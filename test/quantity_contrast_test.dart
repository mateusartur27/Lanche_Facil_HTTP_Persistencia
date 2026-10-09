import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novo_ifood/config/theme.dart';
import 'package:novo_ifood/widgets/quantity_input.dart';

/// Verifica a cor efetivamente renderizada do sinal desativado, além da responsividade.
void main() {
  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    for (final width in [320.0, 768.0, 1440.0]) {
      testWidgets('menos visível em ${theme.brightness} e $width',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(MaterialApp(
            theme: theme,
            home: Scaffold(
              body: QuantityInput(value: 1, maximum: 5, onChanged: (_) {}),
            )));
        final button = find.byKey(const Key('quantity-decrease'));
        expect(tester.widget<IconButton>(button).onPressed, isNull);
        final icon = find.descendant(of: button, matching: find.byType(Icon));
        final context = tester.element(icon);
        final foreground = IconTheme.of(context).color!;
        final background = Material.of(context).color!;
        final first = foreground.computeLuminance();
        final second = background.computeLuminance();
        final contrast = first > second
            ? (first + .05) / (second + .05)
            : (second + .05) / (first + .05);
        expect(foreground.a, 1);
        expect(contrast, greaterThanOrEqualTo(3));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
