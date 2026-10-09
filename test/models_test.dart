import 'package:flutter_test/flutter_test.dart';
import 'package:novo_ifood/models/order.dart';
import 'package:novo_ifood/models/product.dart';

/// Confere as conversões dos modelos: SQLite (toMap/fromMap) e API (toJson/fromJson).
void main() {
  final product = Product(
    id: 'x-salada',
    establishmentId: 'campus-principal',
    name: 'X-Salada',
    description: 'Hambúrguer e salada',
    price: 1800,
    categoryId: 'Lanches',
    active: true,
    available: true,
    stockQuantity: 7,
    createdAt: DateTime(2026, 10, 1, 12),
  );

  test('Product.toMap/fromMap usa colunas do SQLite e 0/1 para booleanos', () {
    final map = product.toMap();
    expect(map['nome'], 'X-Salada');
    expect(map['preco_centavos'], 1800);
    expect(map['ativo'], 1);
    expect(map['sincronizado'], 0);
    final restored = Product.fromMap(map);
    expect(restored.name, product.name);
    expect(restored.stockQuantity, 7);
    expect(restored.synchronized, isFalse);
  });

  test('Product.toJson/fromJson usa as chaves da API e marca como sincronizado',
      () {
    final json = product.toJson();
    expect(json['preco'], 1800);
    expect(json.containsKey('sincronizado'), isFalse);
    final restored = Product.fromJson(json);
    expect(restored.id, 'x-salada');
    expect(restored.synchronized, isTrue);
    expect(restored.onServer, isTrue);
  });

  test('Product.fromJson recusa JSON sem campos obrigatórios', () {
    expect(() => Product.fromJson({'id': 'a', 'nome': 'Sem preço'}),
        throwsFormatException);
    expect(() => Product.fromJson({'preco': 100}), throwsFormatException);
  });

  test('Order converte itens para JSON e de volta', () {
    final order = Order(
      id: 'pedido-1',
      establishmentId: 'campus-principal',
      items: const [
        OrderItem(
            productId: 'salgado',
            name: 'Salgado',
            quantity: 2,
            unitPrice: 900,
            subtotal: 1800),
      ],
      totalAmount: 1800,
      status: OrderStatus.preparing,
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 1),
    );
    final restored = Order.fromJson(order.toJson());
    expect(restored.items.single.quantity, 2);
    expect(restored.status, OrderStatus.preparing);
    expect(Order.fromMap(order.toMap(), order.items).totalAmount, 1800);
    expect(() => orderStatusFromCode('DESCONHECIDO'), throwsFormatException);
  });
}
