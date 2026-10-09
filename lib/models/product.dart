/// Representa um produto pertencente ao catálogo de um estabelecimento.
///
/// O mesmo modelo possui duas conversões, uma para cada apostila:
/// - `toMap`/`fromMap`: linha da tabela `produtos` do SQLite (persistência local);
/// - `toJson`/`fromJson`: corpo JSON enviado e recebido pela API REST (HTTP).
class Product {
  final String id;
  final String establishmentId;
  final String name;
  final String description;

  /// Preço atual em centavos para evitar erros de arredondamento.
  final int price;
  final String categoryId;
  final bool active;
  final bool available;

  /// Quantidade disponível; zero impede novas inclusões no carrinho.
  final int stockQuantity;
  final String? imageUrl;

  /// Guarda a preferência visual: imagem inteira ou preenchimento com corte.
  final String imageFit;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// `true` quando a cópia local é igual à do servidor; `false` = alteração pendente de envio.
  final bool synchronized;

  /// Indica se o registro já existe na API: define se a sincronização usa POST ou PUT.
  final bool onServer;

  /// Exclusão feita sem internet e que ainda aguarda o DELETE na API.
  final bool deleted;

  /// Cria um produto com seu estado administrativo e sua disponibilidade.
  Product({
    required this.id,
    required this.establishmentId,
    required this.name,
    required this.description,
    required this.price,
    required this.categoryId,
    required this.active,
    required this.available,
    this.stockQuantity = 0,
    this.imageUrl,
    this.imageFit = 'contain',
    required this.createdAt,
    DateTime? updatedAt,
    this.synchronized = false,
    this.onServer = false,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? createdAt;

  // ---------------------------------------------------------------------------
  // SQLite (apostila de Persistência, seção 7 — Model com toMap/fromMap)
  // ---------------------------------------------------------------------------

  /// Converte o produto para uma linha da tabela `produtos`.
  /// O SQLite não possui tipo booleano, por isso usamos 1 (verdadeiro) e 0 (falso).
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'estabelecimento_id': establishmentId,
      'nome': name,
      'descricao': description,
      'preco_centavos': price,
      'categoria': categoryId,
      'ativo': active ? 1 : 0,
      'disponivel': available ? 1 : 0,
      'estoque': stockQuantity,
      'imagem_url': imageUrl,
      'ajuste_imagem': imageFit,
      'criado_em': createdAt.toIso8601String(),
      'atualizado_em': updatedAt.toIso8601String(),
      'sincronizado': synchronized ? 1 : 0,
      'no_servidor': onServer ? 1 : 0,
      'excluido': deleted ? 1 : 0,
    };
  }

  /// Reconstrói o produto a partir de uma linha lida do SQLite.
  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      establishmentId: map['estabelecimento_id'] as String,
      name: map['nome'] as String,
      description: map['descricao'] as String,
      price: map['preco_centavos'] as int,
      categoryId: map['categoria'] as String,
      active: map['ativo'] == 1,
      available: map['disponivel'] == 1,
      stockQuantity: map['estoque'] as int,
      imageUrl: map['imagem_url'] as String?,
      imageFit: map['ajuste_imagem'] == 'cover' ? 'cover' : 'contain',
      createdAt: DateTime.parse(map['criado_em'] as String),
      updatedAt: DateTime.parse(map['atualizado_em'] as String),
      synchronized: map['sincronizado'] == 1,
      onServer: map['no_servidor'] == 1,
      deleted: map['excluido'] == 1,
    );
  }

  // ---------------------------------------------------------------------------
  // API REST (apostila de HTTP, seção 8 — JSON ↔ objeto Dart)
  // ---------------------------------------------------------------------------

  /// Monta o corpo JSON enviado nas requisições POST e PUT.
  /// Os campos de controle local (sincronizado, excluido...) não vão para o servidor.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'estabelecimentoId': establishmentId,
      'nome': name,
      'descricao': description,
      'preco': price,
      'categoria': categoryId,
      'ativo': active,
      'disponivel': available,
      'estoque': stockQuantity,
      'imagemUrl': imageUrl,
      'ajusteImagem': imageFit,
      'criadoEm': createdAt.toIso8601String(),
      'atualizadoEm': updatedAt.toIso8601String(),
    };
  }

  /// Converte o JSON recebido da API em um produto Dart.
  ///
  /// Campos obrigatórios ausentes ou com tipo errado geram [FormatException],
  /// tratada pelo ApiService como "JSON inesperado" (apostila de HTTP, seção 15).
  factory Product.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Product(
      id: _requiredString(json, 'id'),
      establishmentId: json['estabelecimentoId'] as String? ?? 'campus-principal',
      name: _requiredString(json, 'nome'),
      description: json['descricao'] as String? ?? '',
      price: _requiredInt(json, 'preco'),
      categoryId: json['categoria'] as String? ?? 'Outros',
      active: json['ativo'] as bool? ?? true,
      available: json['disponivel'] as bool? ?? true,
      stockQuantity: (json['estoque'] as num?)?.toInt() ?? 0,
      imageUrl: json['imagemUrl'] as String?,
      imageFit: json['ajusteImagem'] == 'cover' ? 'cover' : 'contain',
      createdAt: DateTime.tryParse(json['criadoEm'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['atualizadoEm'] as String? ?? '') ?? now,
      // Um registro vindo da API já está igual ao servidor.
      synchronized: true,
      onServer: true,
    );
  }

  /// Retorna uma cópia com alterações administrativas, operacionais ou de sincronização.
  Product copyWith({
    String? id,
    String? name,
    String? description,
    int? price,
    String? categoryId,
    bool? active,
    bool? available,
    int? stockQuantity,
    String? imageUrl,
    String? imageFit,
    DateTime? updatedAt,
    bool? synchronized,
    bool? onServer,
    bool? deleted,
  }) {
    return Product(
      id: id ?? this.id,
      establishmentId: establishmentId,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      active: active ?? this.active,
      available: available ?? this.available,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      imageUrl: imageUrl ?? this.imageUrl,
      imageFit: imageFit ?? this.imageFit,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      synchronized: synchronized ?? this.synchronized,
      onServer: onServer ?? this.onServer,
      deleted: deleted ?? this.deleted,
    );
  }
}

/// Lê um texto obrigatório do JSON e explica qual campo veio errado.
String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value;
  // Alguns servidores (ex.: json-server) podem gerar IDs numéricos.
  if (key == 'id' && value is num) return value.toString();
  throw FormatException('Campo "$key" ausente ou inválido no JSON do produto.');
}

/// Lê um número inteiro obrigatório do JSON (aceita 900 ou 900.0).
int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Campo "$key" ausente ou inválido no JSON do produto.');
}

/// Fornece dados coerentes para a primeira demonstração do catálogo e do cálculo.
List<Product> sampleProducts(String establishmentId) {
  final now = DateTime(2026, 8, 16);
  return [
    Product(
        id: 'salgado',
        establishmentId: establishmentId,
        name: 'Salgado assado',
        description:
            'Opções de frango, presunto e queijo conforme disponibilidade.',
        price: 900,
        categoryId: 'Salgados',
        active: true,
        available: true,
        stockQuantity: 30,
        createdAt: now),
    Product(
        id: 'refrigerante',
        establishmentId: establishmentId,
        name: 'Refrigerante lata',
        description: 'Lata de 350 ml servida gelada.',
        price: 600,
        categoryId: 'Bebidas',
        active: true,
        available: true,
        stockQuantity: 24,
        createdAt: now),
    Product(
        id: 'trident',
        establishmentId: establishmentId,
        name: 'Trident',
        description: 'Goma de mascar em sabores variados.',
        price: 350,
        categoryId: 'Conveniência',
        active: true,
        available: true,
        stockQuantity: 40,
        createdAt: now),
    Product(
        id: 'x-salada',
        establishmentId: establishmentId,
        name: 'X-Salada especial',
        description: 'Hambúrguer, queijo, salada fresca e molho da casa.',
        price: 1800,
        categoryId: 'Lanches',
        active: true,
        available: true,
        stockQuantity: 15,
        createdAt: now),
    Product(
        id: 'cachorro-quente',
        establishmentId: establishmentId,
        name: 'Cachorro-quente',
        description:
            'Pão, salsicha, molho, milho, batata palha e complementos.',
        price: 1400,
        categoryId: 'Lanches',
        active: true,
        available: true,
        stockQuantity: 18,
        createdAt: now),
  ];
}
