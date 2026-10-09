import 'package:flutter_test/flutter_test.dart';
import 'package:novo_ifood/database/app_database.dart';
import 'package:novo_ifood/models/order.dart';
import 'package:novo_ifood/models/product.dart';
import 'package:novo_ifood/repositories/order_repository.dart';
import 'package:novo_ifood/repositories/product_repository.dart';

import 'helpers.dart';

/// Testa o CRUD local no SQLite (apostila de Persistência, seções 7 a 11).
void main() {
  late AppDatabase database;
  late ProductRepository products;
  late OrderRepository orders;

  setUp(() {
    database = createTestDatabase();
    products = ProductRepository(database: database);
    orders = OrderRepository(database: database);
  });

  tearDown(() => database.fechar());

  test('onCreate cria as tabelas e o cardápio inicial pendente', () async {
    final list = await products.listar();
    expect(list, hasLength(5));
    expect(list.every((product) => !product.synchronized), isTrue);
    expect(await products.contarPendentes(), 5);
  });

  test('inserir, listar, atualizar, atualizarEstoque e excluir', () async {
    final novo = Product(
      id: 'pastel',
      establishmentId: AppDatabase.establishmentId,
      name: 'Pastel',
      description: 'Pastel de queijo',
      price: 700,
      categoryId: 'Salgados',
      active: true,
      available: true,
      stockQuantity: 10,
      createdAt: DateTime.now(),
    );
    await products.inserir(novo); // INSERT
    expect((await products.listar()).map((p) => p.id), contains('pastel'));

    await products.atualizar(novo.copyWith(price: 750)); // UPDATE
    expect((await products.buscarPorId('pastel'))!.price, 750);

    await products.atualizarEstoque('pastel', 0); // UPDATE parcial
    final semEstoque = await products.buscarPorId('pastel');
    expect(semEstoque!.stockQuantity, 0);
    expect(semEstoque.available, isFalse);

    // Nunca enviado à API: a exclusão apaga a linha imediatamente (DELETE).
    await products.excluir('pastel');
    expect(await products.buscarPorId('pastel'), isNull);
  });

  test('exclusão de item já enviado fica pendente até o DELETE da API',
      () async {
    final salgado = (await products.buscarPorId('salgado'))!;
    await products.marcarSincronizado('salgado', salgado.updatedAt);
    expect((await products.buscarPorId('salgado'))!.onServer, isTrue);

    await products.excluir('salgado');
    final marcado = await products.buscarPorId('salgado');
    expect(marcado!.deleted, isTrue);
    expect(marcado.synchronized, isFalse);
    expect((await products.listar()).map((p) => p.id), isNot(contains('salgado')));
  });

  test('marcarSincronizado ignora versão antiga (alterada durante o envio)',
      () async {
    final antes = (await products.buscarPorId('trident'))!;
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await products.atualizarEstoque('trident', 39);
    await products.marcarSincronizado('trident', antes.updatedAt);
    expect((await products.buscarPorId('trident'))!.synchronized, isFalse);
  });

  test('criarPedido calcula pelo preço do banco e baixa o estoque', () async {
    final result = await orders.criarPedido(itens: const [
      OrderLine(productId: 'salgado', quantity: 2),
      OrderLine(productId: 'refrigerante', quantity: 1),
    ]);
    expect(result.totalAmount, 2 * 900 + 600);
    expect((await products.buscarPorId('salgado'))!.stockQuantity, 28);

    final pedido = (await orders.listar()).single;
    expect(pedido.items, hasLength(2));
    expect(pedido.status, OrderStatus.preparing);
    expect(pedido.synchronized, isFalse);
  });

  test('estoque insuficiente não grava nada (transação)', () async {
    await expectLater(
      orders.criarPedido(itens: const [
        OrderLine(productId: 'salgado', quantity: 1),
        OrderLine(productId: 'x-salada', quantity: 99),
      ]),
      throwsA(isA<OrderException>()),
    );
    expect(await orders.listar(), isEmpty);
    expect((await products.buscarPorId('salgado'))!.stockQuantity, 30);
  });

  test('fluxo do pedido: pronto, concluir, excluir; cancelar devolve estoque',
      () async {
    final primeiro = await orders.criarPedido(
        itens: const [OrderLine(productId: 'trident', quantity: 3)]);
    await orders.marcarComoPronto(primeiro.orderId);
    await orders.concluir(primeiro.orderId);
    expect((await orders.buscarPorId(primeiro.orderId))!.status,
        OrderStatus.pickedUp);
    await orders.excluir(primeiro.orderId);
    expect(await orders.buscarPorId(primeiro.orderId), isNull);

    final segundo = await orders.criarPedido(
        itens: const [OrderLine(productId: 'trident', quantity: 5)]);
    expect((await products.buscarPorId('trident'))!.stockQuantity, 32);
    await orders.cancelar(segundo.orderId);
    expect((await products.buscarPorId('trident'))!.stockQuantity, 37);
    // Transição inválida é recusada.
    await expectLater(
        orders.concluir(segundo.orderId), throwsA(isA<OrderException>()));
  });
}
