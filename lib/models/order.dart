/// Lista os estados permitidos no ciclo de vida de um pedido.
enum OrderStatus {
  preparing,
  awaitingPickup,
  pickedUp,
  canceled,
}

/// Traduz os estados Dart para os textos estáveis gravados no SQLite e na API.
extension OrderStatusCode on OrderStatus {
  /// Retorna o código explícito usado no banco local e no JSON.
  String get code => switch (this) {
        OrderStatus.preparing => 'PREPARING',
        OrderStatus.awaitingPickup => 'AWAITING_PICKUP',
        OrderStatus.pickedUp => 'PICKED_UP',
        OrderStatus.canceled => 'CANCELED',
      };

  /// Indica que o pedido terminou e já pode sair do histórico.
  bool get isFinal =>
      this == OrderStatus.pickedUp || this == OrderStatus.canceled;
}

/// Converte o texto salvo em um estado de pedido conhecido.
OrderStatus orderStatusFromCode(Object? value) {
  return switch (value) {
    'PREPARING' => OrderStatus.preparing,
    'AWAITING_PICKUP' => OrderStatus.awaitingPickup,
    'PICKED_UP' => OrderStatus.pickedUp,
    'CANCELED' => OrderStatus.canceled,
    // Dados desconhecidos são recusados para não exibir um estado errado.
    _ => throw FormatException('Estado de pedido inválido: $value'),
  };
}

/// Representa um pedido e preserva os dados históricos da compra.
///
/// No SQLite o pedido fica na tabela `pedidos` e seus itens em `itens_pedido`.
/// Na API ele trafega como um único JSON com a lista `itens`.
class Order {
  final String id;
  final String establishmentId;
  final List<OrderItem> items;

  /// Valor total em centavos para evitar imprecisão de ponto flutuante.
  final int totalAmount;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  /// `true` quando a cópia local é igual à do servidor; `false` = pendente de envio.
  final bool synchronized;

  /// Indica se o pedido já existe na API (POST na primeira vez, PUT depois).
  final bool onServer;

  /// Exclusão local que ainda aguarda o DELETE na API.
  final bool deleted;

  /// Cria um pedido já calculado e associado ao estabelecimento.
  const Order({
    required this.id,
    required this.establishmentId,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.synchronized = false,
    this.onServer = false,
    this.deleted = false,
  });

  // ---------------------------------------------------------------------------
  // SQLite — tabela `pedidos` (os itens são gravados separadamente).
  // ---------------------------------------------------------------------------

  /// Converte o cabeçalho do pedido para uma linha da tabela `pedidos`.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estabelecimento_id': establishmentId,
      'total_centavos': totalAmount,
      'status': status.code,
      'observacao': notes,
      'criado_em': createdAt.toIso8601String(),
      'atualizado_em': updatedAt.toIso8601String(),
      'sincronizado': synchronized ? 1 : 0,
      'no_servidor': onServer ? 1 : 0,
      'excluido': deleted ? 1 : 0,
    };
  }

  /// Reconstrói o pedido a partir da linha de `pedidos` e dos seus itens.
  factory Order.fromMap(Map<String, dynamic> map, List<OrderItem> items) {
    return Order(
      id: map['id'] as String,
      establishmentId: map['estabelecimento_id'] as String,
      items: items,
      totalAmount: map['total_centavos'] as int,
      status: orderStatusFromCode(map['status']),
      notes: map['observacao'] as String?,
      createdAt: DateTime.parse(map['criado_em'] as String),
      updatedAt: DateTime.parse(map['atualizado_em'] as String),
      synchronized: map['sincronizado'] == 1,
      onServer: map['no_servidor'] == 1,
      deleted: map['excluido'] == 1,
    );
  }

  // ---------------------------------------------------------------------------
  // API REST — JSON único com os itens dentro.
  // ---------------------------------------------------------------------------

  /// Monta o corpo JSON enviado nas requisições POST e PUT de `/pedidos`.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'estabelecimentoId': establishmentId,
      'itens': items.map((item) => item.toJson()).toList(),
      'total': totalAmount,
      'status': status.code,
      'observacao': notes,
      'criadoEm': createdAt.toIso8601String(),
      'atualizadoEm': updatedAt.toIso8601String(),
    };
  }

  /// Converte o JSON recebido da API em um pedido Dart.
  factory Order.fromJson(Map<String, dynamic> json) {
    final rawItems = json['itens'];
    final id = json['id'];
    if (id == null || rawItems is! List || json['total'] is! num) {
      throw const FormatException('JSON de pedido incompleto.');
    }
    final now = DateTime.now();
    return Order(
      id: id.toString(),
      establishmentId: json['estabelecimentoId'] as String? ?? 'campus-principal',
      items: rawItems
          .map((item) => OrderItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      totalAmount: (json['total'] as num).toInt(),
      status: orderStatusFromCode(json['status']),
      notes: json['observacao'] as String?,
      createdAt: DateTime.tryParse(json['criadoEm'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['atualizadoEm'] as String? ?? '') ?? now,
      synchronized: true,
      onServer: true,
    );
  }

  /// Retorna uma cópia com outro estado ou outra situação de sincronização.
  Order copyWith({
    OrderStatus? status,
    DateTime? updatedAt,
    bool? synchronized,
    bool? onServer,
    bool? deleted,
  }) {
    return Order(
      id: id,
      establishmentId: establishmentId,
      items: items,
      totalAmount: totalAmount,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes,
      synchronized: synchronized ?? this.synchronized,
      onServer: onServer ?? this.onServer,
      deleted: deleted ?? this.deleted,
    );
  }
}

/// Preserva a quantidade e o preço aplicado a um produto no momento da compra.
class OrderItem {
  final String productId;
  final String name;
  final int quantity;

  /// Preço unitário histórico em centavos.
  final int unitPrice;

  /// Resultado de quantidade multiplicada pelo preço unitário, em centavos.
  final int subtotal;
  final String? notes;

  /// Cria a fotografia histórica de um item incluído no pedido.
  const OrderItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
    this.notes,
  });

  /// Converte o item para uma linha da tabela `itens_pedido`, ligada ao pedido.
  Map<String, dynamic> toMap(String orderId) {
    return {
      'pedido_id': orderId,
      'produto_id': productId,
      'nome': name,
      'quantidade': quantity,
      'preco_unitario': unitPrice,
      'subtotal': subtotal,
      'observacao': notes,
    };
  }

  /// Reconstrói um item a partir de uma linha da tabela `itens_pedido`.
  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      productId: map['produto_id'] as String,
      name: map['nome'] as String,
      quantity: map['quantidade'] as int,
      unitPrice: map['preco_unitario'] as int,
      subtotal: map['subtotal'] as int,
      notes: map['observacao'] as String?,
    );
  }

  /// Produz o JSON do item dentro do pedido enviado à API.
  Map<String, dynamic> toJson() {
    return {
      'produtoId': productId,
      'nome': name,
      'quantidade': quantity,
      'precoUnitario': unitPrice,
      'subtotal': subtotal,
      'observacao': notes,
    };
  }

  /// Converte um item recebido da API, recusando campos obrigatórios ausentes.
  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final quantity = json['quantidade'];
    final unitPrice = json['precoUnitario'];
    if (json['produtoId'] is! String ||
        json['nome'] is! String ||
        quantity is! num ||
        unitPrice is! num) {
      throw const FormatException('JSON de item do pedido incompleto.');
    }
    return OrderItem(
      productId: json['produtoId'] as String,
      name: json['nome'] as String,
      quantity: quantity.toInt(),
      unitPrice: unitPrice.toInt(),
      subtotal: (json['subtotal'] as num?)?.toInt() ??
          quantity.toInt() * unitPrice.toInt(),
      notes: json['observacao'] as String?,
    );
  }
}
