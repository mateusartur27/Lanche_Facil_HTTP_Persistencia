import 'package:flutter/material.dart';

/// Exibe um seletor compacto por cliques; a tela decide quando atualizar o carrinho.
class QuantityInput extends StatelessWidget {
  const QuantityInput(
      {required this.value,
      required this.maximum,
      required this.onChanged,
      this.enabled = true,
      super.key});
  final int value;
  final int maximum;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  /// Mantém alvos de toque confortáveis e impede valores fora do estoque e da API.
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Mantém os sinais visíveis nos limites, sem a transparência padrão do botão desativado.
    final buttonStyle = IconButton.styleFrom(
      foregroundColor: colors.onSurface,
      disabledForegroundColor: colors.onSurfaceVariant,
      backgroundColor: colors.surfaceContainerHighest,
      disabledBackgroundColor: colors.surfaceContainerHighest,
      side: BorderSide(color: colors.outline),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quantidade'),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              key: const Key('quantity-decrease'),
              tooltip: 'Diminuir quantidade',
              style: buttonStyle,
              onPressed:
                  enabled && value > 1 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Semantics(
              liveRegion: true,
              label: 'Quantidade selecionada: $value',
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('$value',
                      style: Theme.of(context).textTheme.titleMedium)),
            ),
            IconButton(
              key: const Key('quantity-increase'),
              tooltip: 'Aumentar quantidade',
              style: buttonStyle,
              onPressed: enabled && value < maximum && value < 99
                  ? () => onChanged(value + 1)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
        ),
      ]),
    );
  }
}
