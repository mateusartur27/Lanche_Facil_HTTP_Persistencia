import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../models/product.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import 'api_service.dart';
import 'preferences_service.dart';

/// Resumo de uma sincronização completa, exibido na interface.
class SyncResult {
  const SyncResult({
    this.sent = 0,
    this.received = 0,
    this.failed = 0,
    this.error,
  });

  final int sent;
  final int received;
  final int failed;

  /// Preenchido quando nem foi possível falar com a API (ex.: sem internet).
  final String? error;

  bool get success => error == null && failed == 0;

  /// Mensagem curta para SnackBar ou para a tela de configurações.
  String get message {
    if (error != null) return 'Não foi possível sincronizar. $error';
    if (failed > 0) {
      return '$sent alteração(ões) enviada(s) e $failed ainda pendente(s).';
    }
    return 'Sincronizado: $received registro(s) recebido(s) e $sent enviado(s).';
  }
}

/// Resultado de uma tentativa de enviar um único registro logo após salvá-lo.
class SendAttempt {
  const SendAttempt._(this.sent, this.error);

  /// A API confirmou o envio.
  const SendAttempt.sent() : this._(true, null);

  /// Não havia nada pendente para esse registro.
  const SendAttempt.nothingToSend() : this._(false, null);

  /// O envio falhou; o registro continua pendente no SQLite.
  const SendAttempt.failed(String error) : this._(false, error);

  final bool sent;
  final String? error;
}

/// Liga a persistência local (SQLite) à API REST (HTTP).
///
/// Estratégia offline-first da apostila de Persistência (seções 17 a 19):
/// 1. o aplicativo salva primeiro no SQLite;
/// 2. em seguida tenta enviar para a API;
/// 3. se falhar, o registro fica com `sincronizado = 0` (pendente);
/// 4. [sincronizar] baixa os dados do servidor (GET) e reenvia os pendentes
///    com POST (novo), PUT (alterado) ou DELETE (excluído).
class SyncService extends ChangeNotifier {
  SyncService({
    required this.api,
    required this.products,
    required this.orders,
    this.preferences,
  });

  final ApiService api;
  final ProductRepository products;
  final OrderRepository orders;
  final PreferencesService? preferences;

  bool _running = false;
  Future<void> _queue = Future<void>.value();
  SyncResult? _lastResult;

  /// Indica que a sincronização completa está em andamento (mostra o carregamento).
  bool get isRunning => _running;

  /// Resultado da última sincronização completa feita nesta execução.
  SyncResult? get lastResult => _lastResult;

  /// Horário salvo da última sincronização bem-sucedida.
  DateTime? get lastSync => preferences?.lastSync;

  /// Soma produtos e pedidos que ainda aguardam envio.
  Future<int> contarPendentes() async =>
      await products.contarPendentes() + await orders.contarPendentes();

  /// Sincronização completa: GET dos dados remotos e envio dos pendentes.
  Future<SyncResult> sincronizar() async {
    if (_running) {
      return const SyncResult(error: 'Uma sincronização já está em andamento.');
    }
    _running = true;
    notifyListeners();
    try {
      _lastResult = await _exclusive(_synchronize);
      return _lastResult!;
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  /// Envia apenas os registros pendentes, sem baixar nada (usado após um pedido).
  Future<SyncResult> enviarPendentes() => _exclusive(_sendPending);

  /// Após salvar um produto no SQLite, tenta enviá-lo imediatamente à API.
  Future<SendAttempt> tentarEnviarProduto(String id) => _exclusive(() async {
        final product = await products.buscarPorId(id);
        if (product == null || product.synchronized) {
          return const SendAttempt.nothingToSend();
        }
        try {
          await _sendProduct(product);
          return const SendAttempt.sent();
        } on ApiException catch (error) {
          debugPrint('Produto ${product.id} ainda não sincronizado: $error');
          return SendAttempt.failed(error.message);
        }
      });

  /// Após alterar um pedido no SQLite, tenta enviá-lo imediatamente à API.
  Future<SendAttempt> tentarEnviarPedido(String id) => _exclusive(() async {
        final order = await orders.buscarPorId(id);
        if (order == null || order.synchronized) {
          return const SendAttempt.nothingToSend();
        }
        try {
          await _sendOrder(order);
          return const SendAttempt.sent();
        } on ApiException catch (error) {
          debugPrint('Pedido ${order.id} ainda não sincronizado: $error');
          return SendAttempt.failed(error.message);
        }
      });

  /// Executa uma operação por vez para o mesmo registro não ser enviado duas vezes
  /// (ex.: usuário clicando repetidamente enquanto a sincronização roda).
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Etapas da sincronização completa.
  Future<SyncResult> _synchronize() async {
    try {
      // 1. GET: o que existe no servidor passa para o SQLite.
      final remoteProducts = await api.listarProdutos();
      final remoteOrders = await api.listarPedidos();
      var received = await products.salvarDoServidor(remoteProducts);
      received += await orders.salvarDoServidor(remoteOrders);

      // 2. POST / PUT / DELETE: o que mudou no aparelho vai para o servidor.
      final pending = await _sendPending();
      final result = SyncResult(
        sent: pending.sent,
        received: received,
        failed: pending.failed,
      );
      if (result.success) {
        await preferences?.salvarUltimaSincronizacao(DateTime.now());
      }
      return result;
    } on ApiException catch (error) {
      // Sem conexão: os dados continuam seguros no SQLite (modo offline).
      debugPrint('Não foi possível sincronizar: $error');
      return SyncResult(error: error.message);
    } on Exception catch (error) {
      debugPrint('Falha inesperada na sincronização: $error');
      return const SyncResult(error: 'Falha ao gravar os dados no aparelho.');
    }
  }

  /// Envia cada pendente separadamente; uma falha não impede os demais.
  Future<SyncResult> _sendPending() async {
    var sent = 0;
    var failed = 0;
    for (final product in await products.listarPendentes()) {
      try {
        await _sendProduct(product);
        sent++;
      } on ApiException catch (error) {
        failed++;
        debugPrint('Produto ${product.id} ainda não sincronizado: $error');
      }
    }
    for (final order in await orders.listarPendentes()) {
      try {
        await _sendOrder(order);
        sent++;
      } on ApiException catch (error) {
        failed++;
        debugPrint('Pedido ${order.id} ainda não sincronizado: $error');
      }
    }
    return SyncResult(sent: sent, failed: failed);
  }

  /// Escolhe o método HTTP conforme a situação do produto no SQLite.
  Future<void> _sendProduct(Product product) async {
    if (product.deleted) {
      await _ignoreNotFound(() => api.excluirProduto(product.id)); // DELETE
      await products.removerDefinitivamente(product.id);
      return;
    }
    if (product.onServer) {
      try {
        await api.atualizarProduto(product); // PUT
      } on ApiException catch (error) {
        // 404: alguém apagou no servidor; recria o registro com POST.
        if (!error.isNotFound) rethrow;
        await api.criarProduto(product);
      }
    } else {
      await api.criarProduto(product); // POST
    }
    await products.marcarSincronizado(product.id, product.updatedAt);
  }

  /// Escolhe o método HTTP conforme a situação do pedido no SQLite.
  Future<void> _sendOrder(Order order) async {
    if (order.deleted) {
      await _ignoreNotFound(() => api.excluirPedido(order.id)); // DELETE
      await orders.removerDefinitivamente(order.id);
      return;
    }
    if (order.onServer) {
      try {
        await api.atualizarPedido(order); // PUT
      } on ApiException catch (error) {
        if (!error.isNotFound) rethrow;
        await api.criarPedido(order);
      }
    } else {
      await api.criarPedido(order); // POST
    }
    await orders.marcarSincronizado(order.id, order.updatedAt);
  }

  /// Um DELETE que recebe 404 significa que o registro já não existe: objetivo cumprido.
  Future<void> _ignoreNotFound(Future<void> Function() request) async {
    try {
      await request();
    } on ApiException catch (error) {
      if (!error.isNotFound) rethrow;
    }
  }
}
