import 'package:flutter_test/flutter_test.dart';
import 'package:novo_ifood/database/app_database.dart';
import 'package:novo_ifood/models/product.dart';
import 'package:novo_ifood/repositories/order_repository.dart';
import 'package:novo_ifood/repositories/product_repository.dart';
import 'package:novo_ifood/services/api_service.dart';
import 'package:novo_ifood/services/sync_service.dart';

import 'helpers.dart';

/// Testa a estratégia offline-first: salvar local → enviar → sincronizar pendentes.
void main() {
  late AppDatabase database;
  late ProductRepository products;
  late OrderRepository orders;
  late FakeRestApi server;
  late SyncService sync;

  setUp(() {
    database = createTestDatabase();
    products = ProductRepository(database: database);
    orders = OrderRepository(database: database);
    // O servidor começa com o mesmo cardápio do api/db.inicial.json.
    server = FakeRestApi(initial: {
      'produtos': [
        for (final p in sampleProducts(AppDatabase.establishmentId)) p.toJson()
      ],
    });
    sync = SyncService(
      api: ApiService(baseUrl: () => 'http://api.test', client: server.client),
      products: products,
      orders: orders,
    );
  });

  tearDown(() => database.fechar());

  test('primeira sincronização baixa (GET) e confirma o cardápio (PUT)',
      () async {
    final result = await sync.sincronizar();
    expect(result.success, isTrue);
    expect(await sync.contarPendentes(), 0);
    expect(server.log.first, 'GET /produtos');
    // Os itens já existiam no servidor: nenhum POST duplicado.
    expect(server.log.where((line) => line.startsWith('POST')), isEmpty);
  });

  test('offline: pedido fica pendente e é enviado quando a API volta',
      () async {
    await sync.sincronizar();
    server.offline = true;

    final pedido = await orders.criarPedido(
        itens: const [OrderLine(productId: 'salgado', quantity: 2)]);
    final tentativa = await sync.tentarEnviarPedido(pedido.orderId);
    expect(tentativa.sent, isFalse);
    expect(tentativa.error, contains('Sem conexão'));
    expect((await sync.sincronizar()).error, isNotNull);
    expect(await sync.contarPendentes(), greaterThan(0));

    server.offline = false;
    final result = await sync.sincronizar();
    expect(result.success, isTrue);
    expect(await sync.contarPendentes(), 0);
    expect(server.resources['pedidos']!.single['id'], pedido.orderId);
    // A baixa de estoque também chegou ao servidor via PUT.
    final salgado = server.resources['produtos']!
        .firstWhere((item) => item['id'] == 'salgado');
    expect(salgado['estoque'], 28);
  });

  test('cadastro novo usa POST, edição usa PUT e exclusão usa DELETE',
      () async {
    await sync.sincronizar();
    server.log.clear();
    final pastel = Product(
      id: 'pastel',
      establishmentId: AppDatabase.establishmentId,
      name: 'Pastel',
      description: 'Pastel de carne',
      price: 800,
      categoryId: 'Salgados',
      active: true,
      available: true,
      stockQuantity: 5,
      createdAt: DateTime.now(),
    );
    await products.inserir(pastel);
    expect((await sync.tentarEnviarProduto('pastel')).sent, isTrue);

    await products.atualizar(pastel.copyWith(price: 850));
    expect((await sync.tentarEnviarProduto('pastel')).sent, isTrue);

    await products.excluir('pastel');
    expect((await sync.tentarEnviarProduto('pastel')).sent, isTrue);

    expect(server.log,
        ['POST /produtos', 'PUT /produtos/pastel', 'DELETE /produtos/pastel']);
    expect(await products.buscarPorId('pastel'), isNull);
  });

  test('produto apagado no servidor some do aparelho na próxima sincronização',
      () async {
    await sync.sincronizar();
    server.resources['produtos']!.removeWhere((item) => item['id'] == 'trident');
    await sync.sincronizar();
    expect(await products.buscarPorId('trident'), isNull);
  });
}
