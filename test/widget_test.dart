import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novo_ifood/config/app_dependencies.dart';
import 'package:novo_ifood/screens/home_screen.dart';
import 'package:novo_ifood/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

/// Testes de interface: o app abre direto no cardápio (sem login) e funciona offline.
void main() {
  late AppDependencies deps;
  late FakeRestApi server;

  /// Deixa o SQLite terminar suas operações reais e desenha os quadros seguintes.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openHome(WidgetTester tester, {double width = 1440}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    SharedPreferences.setMockInitialValues({});
    server = FakeRestApi()..offline = true;
    await tester.runAsync(() async {
      deps = AppDependencies(
        preferences: await PreferencesService.carregar(),
        database: createTestDatabase(),
        httpClient: server.client,
      );
      await deps.database.abrir();
    });
    await tester.pumpWidget(MaterialApp(home: HomeScreen(dependencies: deps)));
    await settle(tester);
  }

  tearDown(() async => deps.database.fechar());

  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets('abre no cardápio sem tela de login em ${width.toInt()} px',
        (tester) async {
      await openHome(tester, width: width);
      expect(find.text('Cardápio de hoje'), findsOneWidget);
      expect(find.text('Salgado assado'), findsOneWidget);
      expect(find.textContaining('Entrar'), findsNothing);
      expect(find.byKey(const Key('sync-status-banner')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('carrinho fica no SharedPreferences e pedido offline vai ao SQLite',
      (tester) async {
    // Largura de celular/tablet: o botão do carrinho fica na AppBar.
    await openHome(tester, width: 768);

    final addButton = find.byKey(const ValueKey('add-to-cart-salgado'));
    await tester.ensureVisible(addButton);
    await tester.pump();
    await tester.tap(addButton);
    await settle(tester);
    expect(deps.preferences.carregarCarrinho(), {'salgado': 1});

    await tester.tap(find.byKey(const Key('open-cart')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirm-order')));
    await settle(tester);

    expect(find.byKey(const Key('order-feedback')), findsOneWidget);
    expect(find.textContaining('no aparelho. Envio pendente'), findsOneWidget);
    expect(deps.preferences.carregarCarrinho(), isEmpty);
    final saved = await tester.runAsync(deps.orders.listar);
    expect(saved!.single.totalAmount, 900);
    expect(saved.single.synchronized, isFalse);
  });
}
