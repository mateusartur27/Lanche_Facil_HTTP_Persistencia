import 'package:flutter/material.dart';

import '../services/sync_service.dart';

/// Formata data e hora no padrão brasileiro sem depender de pacotes extras.
String formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)} às ${two(value.hour)}:${two(value.minute)}';
}

/// Etiqueta que mostra se o registro já está no servidor ou aguarda envio.
class SyncChip extends StatelessWidget {
  const SyncChip({required this.synchronized, super.key});

  final bool synchronized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        synchronized ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
        size: 18,
        color: synchronized ? Colors.green : colors.tertiary,
      ),
      label: Text(synchronized ? 'Sincronizado' : 'Pendente de envio'),
    );
  }
}

/// Faixa com a situação da sincronização: pendências, último envio e botão.
///
/// Recalcula a quantidade de pendências sempre que o SQLite muda ou quando uma
/// sincronização começa/termina.
class SyncStatusBanner extends StatefulWidget {
  const SyncStatusBanner({
    required this.sync,
    required this.changes,
    required this.onSynchronize,
    super.key,
  });

  final SyncService sync;

  /// Contador de alterações do banco (AppDatabase.changes).
  final Listenable changes;
  final VoidCallback onSynchronize;

  @override
  State<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends State<SyncStatusBanner> {
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_refresh);
    widget.sync.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    widget.changes.removeListener(_refresh);
    widget.sync.removeListener(_refresh);
    super.dispose();
  }

  /// Consulta quantos registros ainda têm `sincronizado = 0`.
  Future<void> _refresh() async {
    final pending = await widget.sync.contarPendentes();
    if (mounted) setState(() => _pending = pending);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lastSync = widget.sync.lastSync;
    final lastResult = widget.sync.lastResult;
    final offline = lastResult?.error != null;
    final details = [
      _pending == 0
          ? 'Tudo salvo no aparelho e no servidor.'
          : '$_pending alteração(ões) aguardando envio.',
      if (lastSync != null) 'Última sincronização: ${formatDateTime(lastSync)}.',
      if (offline) 'Modo offline: a API não respondeu.',
    ].join(' ');

    return Container(
      key: const Key('sync-status-banner'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: (offline ? colors.errorContainer : colors.secondaryContainer)
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(offline ? Icons.cloud_off_outlined : Icons.sync_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(details, style: Theme.of(context).textTheme.bodySmall),
          ),
          widget.sync.isRunning
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  key: const Key('sync-now'),
                  onPressed: widget.onSynchronize,
                  child: const Text('Sincronizar'),
                ),
        ],
      ),
    );
  }
}

/// Executa a sincronização completa e mostra o resultado em um SnackBar.
Future<void> synchronizeWithFeedback(
    BuildContext context, SyncService sync) async {
  final result = await sync.sincronizar();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(result.message)));
}
