import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../models/order.dart';
import '../models/product.dart';

/// Resultado devolvido à tela depois de gravar o pedido no SQLite.
class CreateOrderResult {
  const CreateOrderResult({required this.orderId, required this.totalAmount});

  final String orderId;
  final int totalAmount;
}

/// Linha do carrinho enviada ao repositório: apenas produto e quantidade.
/// O preço é sempre lido do banco, nunca confiado à interface.
class OrderLine {
  const OrderLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;
}

/// Falha de regra de negócio com mensagem segura para exibir ao usuário.
class OrderException implements Exception {
  const OrderException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// CRUD local dos pedidos (tabelas `pedidos` e `itens_pedido` do SQLite).
///
/// Mapeamento com a apostila de Persistência:
/// - [criarPedido] → inserir (INSERT, seção 8);
/// - [listar] → listar (SELECT, seção 9);
/// - [marcarComoPronto] e [concluir] → concluir (UPDATE, seção 10);
/// - [excluir] → excluir (DELETE, seção 11).
class OrderRepository {
  OrderRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  static const String _orders = 'pedidos';
  static const String _items = 'itens_pedido';
  static const String _products = 'produtos';

  /// Contador observado pelas telas para recarregar quando algo for gravado.
  ValueListenable<int> get changes => _database.changes;

  /// INSERT — cria o pedido, seus itens e baixa o estoque numa única transação.
  ///
  /// Se qualquer produto estiver indisponível, nada é gravado (tudo ou nada).
  Future<CreateOrderResult> criarPedido({
    required List<OrderLine> itens,
    String observacao = '',
    String establishmentId = AppDatabase.establishmentId,
  }) async {
    if (itens.isEmpty) throw const OrderException('O carrinho está vazio.');
    final db = await _database.abrir();
    final orderId = const Uuid().v4();
    final now = DateTime.now();
    var total = 0;
    await db.transaction((txn) async {
      final orderItems = <OrderItem>[];
      for (final line in itens) {
        if (line.quantity < 1 || line.quantity > 99) {
          throw const OrderException('Cada item aceita de 1 a 99 unidades.');
        }
        final rows = await txn.query(_products,
            where: 'id = ? AND excluido = 0', whereArgs: [line.productId]);
        if (rows.isEmpty) {
          throw const OrderException('Um produto do carrinho não existe mais.');
        }
        final product = Product.fromMap(rows.first);
        if (!product.active ||
            !product.available ||
            product.stockQuantity < line.quantity) {
          throw OrderException('Estoque insuficiente para ${product.name}.');
        }
        orderItems.add(OrderItem(
          productId: product.id,
          name: product.name,
          quantity: line.quantity,
          unitPrice: product.price,
          subtotal: product.price * line.quantity,
        ));
        // A baixa do estoque também precisa ser enviada à API depois.
        final remaining = product.stockQuantity - line.quantity;
        await txn.update(
          _products,
          {
            'estoque': remaining,
            'disponivel': remaining > 0 ? 1 : 0,
            'atualizado_em': now.toIso8601String(),
            'sincronizado': 0,
          },
          where: 'id = ?',
          whereArgs: [product.id],
        );
      }
      total = orderItems.fold(0, (sum, item) => sum + item.subtotal);
      final trimmedNotes = observacao.trim();
      final order = Order(
        id: orderId,
        establishmentId: establishmentId,
        items: orderItems,
        totalAmount: total,
        status: OrderStatus.preparing,
        createdAt: now,
        updatedAt: now,
        notes: trimmedNotes.isEmpty ? null : trimmedNotes,
      );
      await txn.insert(_orders, order.toMap());
      for (final item in orderItems) {
        await txn.insert(_items, item.toMap(orderId));
      }
    });
    _database.notifyChanged();
    return CreateOrderResult(orderId: orderId, totalAmount: total);
  }

  /// SELECT — lista os pedidos do histórico, do mais recente para o mais antigo.
  Future<List<Order>> listar() async {
    final db = await _database.abrir();
    final rows = await db.query(_orders,
        where: 'excluido = 0', orderBy: 'criado_em DESC');
    return Future.wait(rows.map((row) => _withItems(db, row)));
  }

  /// SELECT por chave primária; inclui exclusões pendentes para a sincronização.
  Future<Order?> buscarPorId(String id) async {
    final db = await _database.abrir();
    final rows = await db.query(_orders, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _withItems(db, rows.first);
  }

  /// UPDATE — a loja avisa que o pedido está pronto para retirada.
  Future<void> marcarComoPronto(String id) => _changeStatus(
      id, from: OrderStatus.preparing, to: OrderStatus.awaitingPickup);

  /// UPDATE — "concluir" da apostila: confirma que o cliente retirou o pedido.
  Future<void> concluir(String id) => _changeStatus(id,
      from: OrderStatus.awaitingPickup, to: OrderStatus.pickedUp);

  /// UPDATE — cancela um pedido em andamento e devolve os itens ao estoque.
  Future<void> cancelar(String id) async {
    final db = await _database.abrir();
    await db.transaction((txn) async {
      final order = await _findInTransaction(txn, id);
      if (order.status.isFinal) {
        throw const OrderException('Este pedido já foi finalizado.');
      }
      final now = DateTime.now().toIso8601String();
      for (final item in order.items) {
        // Produtos apagados do catálogo não recebem estoque de volta.
        await txn.rawUpdate(
          'UPDATE $_products SET estoque = estoque + ?, disponivel = 1, '
          'atualizado_em = ?, sincronizado = 0 WHERE id = ? AND excluido = 0',
          [item.quantity, now, item.productId],
        );
      }
      await txn.update(
        _orders,
        {
          'status': OrderStatus.canceled.code,
          'atualizado_em': now,
          'sincronizado': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _database.notifyChanged();
  }

  /// DELETE — remove do histórico um pedido retirado ou cancelado.
  Future<void> excluir(String id) async {
    final db = await _database.abrir();
    final order = await buscarPorId(id);
    if (order == null) return;
    if (!order.status.isFinal) {
      throw const OrderException(
          'Somente pedidos retirados ou cancelados podem ser excluídos.');
    }
    if (order.onServer) {
      // Mantém a linha até o DELETE da API ser confirmado.
      await db.update(
        _orders,
        {
          'excluido': 1,
          'sincronizado': 0,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      // A chave estrangeira com ON DELETE CASCADE apaga os itens junto.
      await db.delete(_orders, where: 'id = ?', whereArgs: [id]);
    }
    _database.notifyChanged();
  }

  /// Lista pedidos com alterações que ainda não chegaram à API.
  Future<List<Order>> listarPendentes() async {
    final db = await _database.abrir();
    final rows = await db.query(_orders, where: 'sincronizado = 0');
    return Future.wait(rows.map((row) => _withItems(db, row)));
  }

  /// Conta os pedidos pendentes para exibir na interface.
  Future<int> contarPendentes() async {
    final db = await _database.abrir();
    final result = await db
        .rawQuery('SELECT COUNT(*) FROM $_orders WHERE sincronizado = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Marca o pedido como sincronizado se ele não mudou durante o envio.
  Future<void> marcarSincronizado(String id, DateTime versaoEnviada) async {
    final db = await _database.abrir();
    await db.update(
      _orders,
      {'sincronizado': 1, 'no_servidor': 1},
      where: 'id = ? AND atualizado_em = ?',
      whereArgs: [id, versaoEnviada.toIso8601String()],
    );
    _database.notifyChanged();
  }

  /// Apaga pedido e itens de vez (depois do DELETE confirmado pela API).
  Future<void> removerDefinitivamente(String id) async {
    final db = await _database.abrir();
    await db.delete(_orders, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Grava no SQLite os pedidos recebidos pelo GET /pedidos.
  ///
  /// Mesma regra dos produtos: pendências locais vencem e registros sincronizados
  /// que não existem mais no servidor são removidos do aparelho.
  Future<int> salvarDoServidor(List<Order> remotos) async {
    final db = await _database.abrir();
    var saved = 0;
    await db.transaction((txn) async {
      final localRows = await txn.query(_orders,
          columns: ['id', 'sincronizado', 'no_servidor']);
      final locais = {for (final row in localRows) row['id'] as String: row};
      final remoteIds = <String>{};
      for (final remoto in remotos) {
        remoteIds.add(remoto.id);
        final local = locais[remoto.id];
        if (local != null && local['sincronizado'] == 0) {
          if (local['no_servidor'] == 0) {
            await txn.update(_orders, {'no_servidor': 1},
                where: 'id = ?', whereArgs: [remoto.id]);
          }
          continue;
        }
        // Substitui cabeçalho e itens para refletir exatamente o servidor.
        await txn.delete(_orders, where: 'id = ?', whereArgs: [remoto.id]);
        await txn.insert(_orders, remoto.toMap());
        for (final item in remoto.items) {
          await txn.insert(_items, item.toMap(remoto.id));
        }
        saved++;
      }
      for (final local in locais.values) {
        if (local['sincronizado'] == 1 &&
            local['no_servidor'] == 1 &&
            !remoteIds.contains(local['id'])) {
          await txn.delete(_orders, where: 'id = ?', whereArgs: [local['id']]);
        }
      }
    });
    _database.notifyChanged();
    return saved;
  }

  /// Valida a transição antes de gravar o novo estado do pedido.
  Future<void> _changeStatus(
    String id, {
    required OrderStatus from,
    required OrderStatus to,
  }) async {
    final db = await _database.abrir();
    final order = await buscarPorId(id);
    if (order == null || order.deleted) {
      throw const OrderException('Pedido não encontrado.');
    }
    if (order.status != from) {
      throw const OrderException('Esta ação não vale para o estado atual do pedido.');
    }
    await db.update(
      _orders,
      {
        'status': to.code,
        'atualizado_em': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _database.notifyChanged();
  }

  /// Busca um pedido dentro de uma transação já aberta.
  Future<Order> _findInTransaction(Transaction txn, String id) async {
    final rows = await txn.query(_orders, where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw const OrderException('Pedido não encontrado.');
    return _withItems(txn, rows.first);
  }

  /// Junta a linha de `pedidos` com as linhas de `itens_pedido` correspondentes.
  Future<Order> _withItems(
      DatabaseExecutor executor, Map<String, dynamic> row) async {
    final itemRows = await executor.query(_items,
        where: 'pedido_id = ?', whereArgs: [row['id']], orderBy: 'id');
    return Order.fromMap(row, itemRows.map(OrderItem.fromMap).toList());
  }
}
