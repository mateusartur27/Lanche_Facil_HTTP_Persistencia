import 'package:flutter/material.dart';

import '../config/app_dependencies.dart';
import '../models/order.dart';
import '../view_models/operation_feedback.dart';
import '../view_models/orders_view_model.dart';
import '../widgets/sync_status.dart';

/// Histórico de pedidos lido do SQLite, com ações que também vão para a API.
///
/// Cada ação grava primeiro no aparelho (UPDATE/DELETE no SQLite) e depois
/// tenta o envio HTTP correspondente (PUT/DELETE em /pedidos).
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

/// Liga o ciclo de vida da View ao ViewModel responsável pela consulta.
class _OrdersScreenState extends State<OrdersScreen> {
  late final OrdersViewModel _viewModel;
  _OrderFilter _selectedFilter = _OrderFilter.active;

  AppDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _viewModel = OrdersViewModel(repository: _deps.orders, sync: _deps.sync)
      ..start();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// Monta uma página responsiva que funciona em celular e monitores amplos.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar com a API',
            onPressed: () => synchronizeWithFeedback(context, _deps.sync),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => synchronizeWithFeedback(context, _deps.sync),
        child: AnimatedBuilder(
          animation: _viewModel,
          builder: (context, _) {
            if (_viewModel.failed) {
              return const _Message(
                icon: Icons.storage_outlined,
                text: 'Não foi possível ler os pedidos salvos no aparelho.',
              );
            }
            if (_viewModel.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = _viewModel.orders
                .where((order) => _selectedFilter.accepts(order.status))
                .toList(growable: false);
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.isEmpty ? 3 : orders.length + 2,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    if (index == 0) {
                      return SyncStatusBanner(
                        sync: _deps.sync,
                        changes: _deps.database.changes,
                        onSynchronize: () =>
                            synchronizeWithFeedback(context, _deps.sync),
                      );
                    }
                    if (index == 1) {
                      return _OrderFilters(
                        selected: _selectedFilter,
                        onSelected: (filter) =>
                            setState(() => _selectedFilter = filter),
                      );
                    }
                    if (orders.isEmpty) {
                      return const _Message(
                        icon: Icons.filter_alt_off_outlined,
                        text: 'Nenhum pedido encontrado neste filtro.',
                      );
                    }
                    final order = orders[index - 2];
                    return _OrderCard(
                      order: order,
                      processing: _viewModel.isProcessing(order.id),
                      onMarkReady: () => _run(_viewModel.markReady(order)),
                      onConfirmPickup: () =>
                          _run(_viewModel.confirmPickup(order)),
                      onCancel: () => _confirmCancellation(order),
                      onDelete: () => _confirmDeletion(order),
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Aguarda a ação do ViewModel e mostra o resultado em um SnackBar.
  Future<void> _run(Future<OperationFeedback> action) async {
    final feedback = await action;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(feedback.message)));
  }

  /// Pede confirmação antes de cancelar e devolver os itens ao estoque.
  Future<void> _confirmCancellation(Order order) async {
    final confirmed = await _confirm(
      title: 'Cancelar pedido?',
      message: 'Os produtos voltarão ao estoque.',
      action: 'Cancelar pedido',
    );
    if (confirmed) await _run(_viewModel.cancel(order));
  }

  /// Pede confirmação antes de apagar o pedido do aparelho e do servidor.
  Future<void> _confirmDeletion(Order order) async {
    final confirmed = await _confirm(
      title: 'Excluir do histórico?',
      message:
          'O pedido será apagado do aparelho (SQLite) e do servidor (DELETE).',
      action: 'Excluir',
    );
    if (confirmed) await _run(_viewModel.delete(order));
  }

  /// Diálogo simples de confirmação reutilizado pelas ações destrutivas.
  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return confirmed == true && mounted;
  }
}

/// Apresenta dados históricos do pedido e as ações permitidas no estado atual.
class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.processing,
    required this.onMarkReady,
    required this.onConfirmPickup,
    required this.onCancel,
    required this.onDelete,
  });

  final Order order;
  final bool processing;
  final VoidCallback onMarkReady;
  final VoidCallback onConfirmPickup;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  /// Converte o estado técnico em uma mensagem simples.
  String get _statusLabel => switch (order.status) {
        OrderStatus.preparing => 'Em preparação',
        OrderStatus.awaitingPickup => 'Pronto para retirada',
        OrderStatus.pickedUp => 'Retirado',
        OrderStatus.canceled => 'Cancelado',
      };

  /// Escolhe uma cor visual para o estado do pedido.
  Color _statusColor(BuildContext context) => switch (order.status) {
        OrderStatus.awaitingPickup => Colors.green,
        OrderStatus.canceled => Theme.of(context).colorScheme.error,
        OrderStatus.pickedUp => Colors.blueGrey,
        _ => Theme.of(context).colorScheme.primary,
      };

  /// Formata valores armazenados em centavos no padrão brasileiro.
  String _money(int cents) =>
      'R\$ ${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('order-${order.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Pedido ${order.id.substring(0, 8).toUpperCase()}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Chip(
                  avatar: Icon(Icons.circle,
                      size: 10, color: _statusColor(context)),
                  label: Text(_statusLabel),
                ),
                SyncChip(synchronized: order.synchronized),
              ],
            ),
            Text('Criado em ${formatDateTime(order.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall),
            const Divider(),
            for (final item in order.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    '${item.quantity}x ${item.name} · ${_money(item.subtotal)}'),
              ),
            if (order.notes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 4),
              Text('Observação geral: ${order.notes}'),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${_money(order.totalAmount)}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (order.status == OrderStatus.preparing)
                  FilledButton.icon(
                    key: Key('mark-ready-${order.id}'),
                    onPressed: processing ? null : onMarkReady,
                    icon: const Icon(Icons.room_service_outlined),
                    label: const Text('Marcar como pronto'),
                  ),
                if (order.status == OrderStatus.awaitingPickup)
                  FilledButton.icon(
                    key: Key('confirm-pickup-${order.id}'),
                    onPressed: processing ? null : onConfirmPickup,
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Confirmar retirada'),
                  ),
                if (!order.status.isFinal)
                  OutlinedButton.icon(
                    key: Key('cancel-order-${order.id}'),
                    onPressed: processing ? null : onCancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancelar pedido'),
                  ),
                if (order.status.isFinal)
                  OutlinedButton.icon(
                    key: Key('delete-order-${order.id}'),
                    onPressed: processing ? null : onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Excluir do histórico'),
                  ),
                if (processing)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Define filtros visuais sem alterar os estados gravados no banco.
enum _OrderFilter {
  active('Em andamento'),
  preparing('Em preparo'),
  ready('Prontos'),
  pickedUp('Retirados'),
  canceled('Cancelados'),
  all('Todos');

  const _OrderFilter(this.label);
  final String label;

  /// Agrupa estados relacionados para localizar rapidamente cada pedido.
  bool accepts(OrderStatus status) => switch (this) {
        _OrderFilter.active => !status.isFinal,
        _OrderFilter.preparing => status == OrderStatus.preparing,
        _OrderFilter.ready => status == OrderStatus.awaitingPickup,
        _OrderFilter.pickedUp => status == OrderStatus.pickedUp,
        _OrderFilter.canceled => status == OrderStatus.canceled,
        _OrderFilter.all => true,
      };
}

/// Apresenta filtros roláveis para manter o uso confortável em celulares estreitos.
class _OrderFilters extends StatelessWidget {
  const _OrderFilters({required this.selected, required this.onSelected});

  final _OrderFilter selected;
  final ValueChanged<_OrderFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _OrderFilter.values) ...[
            ChoiceChip(
              label: Text(filter.label),
              selected: selected == filter,
              onSelected: (_) => onSelected(filter),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// Centraliza mensagens de lista vazia e falhas de consulta.
class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
