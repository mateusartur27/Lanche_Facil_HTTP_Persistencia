import 'package:flutter/foundation.dart';

import '../models/order.dart';
import '../repositories/order_repository.dart';
import '../services/sync_service.dart';
import 'operation_feedback.dart';

/// Mantém o estado da tela de pedidos e executa as ações sobre cada pedido.
class OrdersViewModel extends ChangeNotifier {
  OrdersViewModel({
    required OrderRepository repository,
    required SyncService sync,
  })  : _repository = repository,
        _sync = sync;

  final OrderRepository _repository;
  final SyncService _sync;
  final Set<String> _processing = <String>{};
  bool _disposed = false;

  List<Order> orders = const [];
  bool loading = true;
  bool failed = false;

  /// Conta somente pedidos que ainda exigem preparo ou retirada.
  int get activeOrderCount =>
      orders.where((order) => !order.status.isFinal).length;

  /// Indica que um pedido está com uma ação em andamento (bloqueia cliques repetidos).
  bool isProcessing(String orderId) => _processing.contains(orderId);

  /// Lê o histórico e volta a ler sempre que o SQLite mudar.
  void start() {
    _repository.changes.addListener(load);
    load();
  }

  /// SELECT dos pedidos com seus itens.
  Future<void> load() async {
    try {
      orders = await _repository.listar();
      failed = false;
    } catch (_) {
      failed = true;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  /// UPDATE: preparo concluído, pedido aguardando o cliente.
  Future<OperationFeedback> markReady(Order order) => _run(order,
      () => _repository.marcarComoPronto(order.id), 'Pedido marcado como pronto');

  /// UPDATE: "concluir" da apostila — o cliente retirou o pedido.
  Future<OperationFeedback> confirmPickup(Order order) => _run(
      order, () => _repository.concluir(order.id), 'Retirada confirmada');

  /// UPDATE: cancela e devolve os itens ao estoque.
  Future<OperationFeedback> cancel(Order order) => _run(order,
      () => _repository.cancelar(order.id), 'Pedido cancelado e estoque devolvido');

  /// DELETE: remove do histórico um pedido finalizado.
  Future<OperationFeedback> delete(Order order) => _run(
      order, () => _repository.excluir(order.id), 'Pedido excluído do histórico');

  /// Grava no SQLite, tenta sincronizar e devolve a mensagem para a tela.
  Future<OperationFeedback> _run(
    Order order,
    Future<void> Function() action,
    String successMessage,
  ) async {
    if (_processing.contains(order.id)) {
      return const OperationFeedback.failure('Aguarde a ação anterior terminar.');
    }
    _processing.add(order.id);
    notifyListeners();
    try {
      await action();
      final attempt = await _sync.tentarEnviarPedido(order.id);
      // Cancelamentos devolvem estoque: os produtos também precisam ser enviados.
      if (attempt.sent) await _sync.enviarPendentes();
      return OperationFeedback.afterLocalSave(successMessage, attempt);
    } on OrderException catch (error) {
      return OperationFeedback.failure(error.message);
    } catch (_) {
      return const OperationFeedback.failure(
          'Não foi possível concluir esta operação.');
    } finally {
      _processing.remove(order.id);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.changes.removeListener(load);
    super.dispose();
  }
}
