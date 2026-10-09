import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/product.dart';

/// Camada de acesso aos produtos gravados no SQLite (CRUD local).
///
/// Apostila de Persistência, seções 8 a 11: inserir (INSERT), listar (SELECT),
/// atualizar (UPDATE) e excluir (DELETE). Cada alteração marca o produto como
/// pendente (`sincronizado = 0`) para o [SyncService] enviá-lo à API depois.
class ProductRepository {
  ProductRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  static const String _table = 'produtos';

  /// Contador observado pelas telas para recarregar quando algo for gravado.
  ValueListenable<int> get changes => _database.changes;

  /// SELECT — devolve os produtos não excluídos em ordem alfabética.
  Future<List<Product>> listar() async {
    final db = await _database.abrir();
    final rows = await db.query(
      _table,
      where: 'excluido = 0',
      orderBy: 'nome COLLATE NOCASE',
    );
    return rows.map(Product.fromMap).toList();
  }

  /// SELECT por chave primária; inclui exclusões pendentes para a sincronização.
  Future<Product?> buscarPorId(String id) async {
    final db = await _database.abrir();
    final rows = await db.query(_table, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Product.fromMap(rows.first);
  }

  /// INSERT — grava um novo produto como pendente de envio para a API.
  Future<void> inserir(Product product) async {
    final db = await _database.abrir();
    await db.insert(
      _table,
      product
          .copyWith(synchronized: false, onServer: false, deleted: false)
          .toMap(),
    );
    _database.notifyChanged();
  }

  /// UPDATE — salva a edição do formulário e marca o produto para reenvio (PUT).
  Future<void> atualizar(Product product) async {
    final db = await _database.abrir();
    final values = product
        .copyWith(updatedAt: DateTime.now(), synchronized: false)
        .toMap()
      // Preserva o que o banco já sabe sobre a existência do registro na API.
      ..remove('no_servidor')
      ..remove('excluido')
      ..remove('criado_em');
    await db.update(_table, values, where: 'id = ?', whereArgs: [product.id]);
    _database.notifyChanged();
  }

  /// UPDATE parcial — altera apenas estoque e disponibilidade.
  Future<void> atualizarEstoque(String id, int quantidade) async {
    if (quantidade < 0) {
      throw ArgumentError.value(quantidade, 'quantidade', 'não pode ser negativa');
    }
    final db = await _database.abrir();
    await db.update(
      _table,
      {
        'estoque': quantidade,
        'disponivel': quantidade > 0 ? 1 : 0,
        'atualizado_em': DateTime.now().toIso8601String(),
        'sincronizado': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    _database.notifyChanged();
  }

  /// DELETE — remove o produto do catálogo.
  ///
  /// Se ele nunca chegou à API, basta apagar a linha. Se já existe no servidor,
  /// a linha fica marcada como `excluido = 1` até o DELETE HTTP ser confirmado.
  Future<void> excluir(String id) async {
    final db = await _database.abrir();
    final product = await buscarPorId(id);
    if (product == null) return;
    if (product.onServer) {
      await db.update(
        _table,
        {
          'excluido': 1,
          'sincronizado': 0,
          'atualizado_em': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    }
    _database.notifyChanged();
  }

  /// Recria o cardápio de demonstração sem duplicar produtos existentes.
  Future<void> inserirExemplos() async {
    final db = await _database.abrir();
    final batch = db.batch();
    for (final product in sampleProducts(AppDatabase.establishmentId)) {
      batch.insert(_table, product.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
    _database.notifyChanged();
  }

  /// Lista tudo o que ainda precisa ser enviado (inclusive exclusões pendentes).
  Future<List<Product>> listarPendentes() async {
    final db = await _database.abrir();
    final rows = await db.query(_table, where: 'sincronizado = 0');
    return rows.map(Product.fromMap).toList();
  }

  /// Conta as alterações pendentes para exibir na interface.
  Future<int> contarPendentes() async {
    final db = await _database.abrir();
    final result =
        await db.rawQuery('SELECT COUNT(*) FROM $_table WHERE sincronizado = 0');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Marca o produto como sincronizado depois da resposta de sucesso da API.
  ///
  /// A condição em `atualizado_em` evita marcar como enviado um produto que foi
  /// alterado de novo enquanto a requisição HTTP ainda estava em andamento.
  Future<void> marcarSincronizado(String id, DateTime versaoEnviada) async {
    final db = await _database.abrir();
    await db.update(
      _table,
      {'sincronizado': 1, 'no_servidor': 1},
      where: 'id = ? AND atualizado_em = ?',
      whereArgs: [id, versaoEnviada.toIso8601String()],
    );
    _database.notifyChanged();
  }

  /// Apaga a linha de vez (usado depois que o DELETE da API foi confirmado).
  Future<void> removerDefinitivamente(String id) async {
    final db = await _database.abrir();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
    _database.notifyChanged();
  }

  /// Grava no SQLite a lista recebida pelo GET /produtos.
  ///
  /// Alterações locais ainda pendentes têm prioridade e não são sobrescritas.
  /// Produtos já sincronizados que sumiram do servidor são removidos do aparelho.
  /// Retorna quantos registros vieram do servidor e foram gravados.
  Future<int> salvarDoServidor(List<Product> remotos) async {
    final db = await _database.abrir();
    var saved = 0;
    await db.transaction((txn) async {
      final localRows = await txn.query(_table);
      final locais = {
        for (final row in localRows) row['id'] as String: Product.fromMap(row),
      };
      final remoteIds = <String>{};
      for (final remoto in remotos) {
        remoteIds.add(remoto.id);
        final local = locais[remoto.id];
        if (local != null && !local.synchronized) {
          // Só registra que o item já existe na API; a próxima etapa usará PUT.
          if (!local.onServer) {
            await txn.update(_table, {'no_servidor': 1},
                where: 'id = ?', whereArgs: [remoto.id]);
          }
          continue;
        }
        await txn.insert(_table, remoto.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        saved++;
      }
      for (final local in locais.values) {
        if (local.synchronized &&
            local.onServer &&
            !remoteIds.contains(local.id)) {
          await txn.delete(_table, where: 'id = ?', whereArgs: [local.id]);
        }
      }
    });
    _database.notifyChanged();
    return saved;
  }
}
