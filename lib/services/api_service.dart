import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/order.dart';
import '../models/product.dart';

/// Falha de comunicação com a API, com mensagem pronta para a interface.
///
/// [statusCode] fica nulo quando nem chegou a existir resposta HTTP
/// (sem internet, servidor desligado, tempo esgotado ou URL inválida).
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// O servidor respondeu 404: o registro não existe lá.
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;
}

/// Resultado do botão "Testar conexão" das configurações.
class ConnectionCheck {
  const ConnectionCheck({
    required this.statusCode,
    required this.productCount,
    required this.elapsed,
  });

  final int statusCode;
  final int productCount;
  final Duration elapsed;
}

/// Concentra toda a comunicação HTTP do aplicativo com a API REST.
///
/// Apostila de HTTP, seção 13 (Model / Service / Screen): as telas nunca chamam
/// `http.get` diretamente; elas usam este serviço, que monta a URL, envia os
/// headers, confere o status, converte o JSON e traduz os erros.
///
/// Recursos da API (padrão REST):
/// - `GET    /produtos`       lista o cardápio
/// - `GET    /produtos/{id}`  busca um produto
/// - `POST   /produtos`       cadastra um produto
/// - `PUT    /produtos/{id}`  atualiza um produto
/// - `DELETE /produtos/{id}`  remove um produto
/// - os mesmos cinco endpoints existem em `/pedidos`.
class ApiService {
  ApiService({required String Function() baseUrl, http.Client? client})
      : _baseUrl = baseUrl,
        _client = client ?? http.Client();

  /// A URL vem das configurações (SharedPreferences) e pode mudar sem reiniciar.
  final String Function() _baseUrl;
  final http.Client _client;

  /// Evita que a tela fique esperando para sempre quando a rede não responde.
  static const Duration timeout = Duration(seconds: 8);

  /// Headers enviados em todas as requisições (apostila de HTTP, seção 16).
  /// Tokens e senhas nunca devem ficar fixos no código-fonte público.
  static const Map<String, String> headers = {
    'Content-Type': 'application/json; charset=UTF-8',
    'Accept': 'application/json',
  };

  /// Endereço base sem a barra final, por exemplo `http://10.0.2.2:3000`.
  String get baseUrl {
    final value = _baseUrl().trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  // ---------------------------------------------------------------------------
  // Produtos
  // ---------------------------------------------------------------------------

  /// GET /produtos — baixa o cardápio salvo no servidor.
  Future<List<Product>> listarProdutos() async {
    final response = await _send('GET', '/produtos', expected: {200});
    return _decodeList(response, Product.fromJson);
  }

  /// GET /produtos/{id} — consulta um único produto (usado pela tela de detalhes).
  Future<Product> buscarProduto(String id) async {
    final response = await _send('GET', '/produtos/${Uri.encodeComponent(id)}',
        expected: {200});
    return _decodeObject(response, Product.fromJson);
  }

  /// POST /produtos — envia um produto novo; a API responde 201 Created.
  Future<Product> criarProduto(Product product) async {
    final response = await _send('POST', '/produtos',
        body: product.toJson(), expected: {200, 201});
    // Exercício 10.1 da apostila: exibir no console o JSON retornado pela API.
    debugPrint('[API] Produto cadastrado. JSON retornado: ${response.body}');
    return _decodeObject(response, Product.fromJson);
  }

  /// PUT /produtos/{id} — substitui o produto pela versão editada no aparelho.
  Future<Product> atualizarProduto(Product product) async {
    final response = await _send(
        'PUT', '/produtos/${Uri.encodeComponent(product.id)}',
        body: product.toJson(), expected: {200});
    return _decodeObject(response, Product.fromJson);
  }

  /// DELETE /produtos/{id} — remove o produto do servidor.
  Future<void> excluirProduto(String id) async {
    await _send('DELETE', '/produtos/${Uri.encodeComponent(id)}',
        expected: {200, 204});
  }

  // ---------------------------------------------------------------------------
  // Pedidos
  // ---------------------------------------------------------------------------

  /// GET /pedidos — baixa os pedidos registrados no servidor.
  Future<List<Order>> listarPedidos() async {
    final response = await _send('GET', '/pedidos', expected: {200});
    return _decodeList(response, Order.fromJson);
  }

  /// GET /pedidos/{id} — consulta um único pedido.
  Future<Order> buscarPedido(String id) async {
    final response = await _send('GET', '/pedidos/${Uri.encodeComponent(id)}',
        expected: {200});
    return _decodeObject(response, Order.fromJson);
  }

  /// POST /pedidos — registra no servidor um pedido criado no aparelho.
  Future<Order> criarPedido(Order order) async {
    final response = await _send('POST', '/pedidos',
        body: order.toJson(), expected: {200, 201});
    debugPrint('[API] Pedido enviado. JSON retornado: ${response.body}');
    return _decodeObject(response, Order.fromJson);
  }

  /// PUT /pedidos/{id} — atualiza o estado do pedido (pronto, retirado, cancelado).
  Future<Order> atualizarPedido(Order order) async {
    final response = await _send(
        'PUT', '/pedidos/${Uri.encodeComponent(order.id)}',
        body: order.toJson(), expected: {200});
    return _decodeObject(response, Order.fromJson);
  }

  /// DELETE /pedidos/{id} — remove o pedido do histórico do servidor.
  Future<void> excluirPedido(String id) async {
    await _send('DELETE', '/pedidos/${Uri.encodeComponent(id)}',
        expected: {200, 204});
  }

  // ---------------------------------------------------------------------------
  // Diagnóstico (apostila de HTTP, seção 17 — como testar e depurar)
  // ---------------------------------------------------------------------------

  /// Faz um GET simples e mede o tempo, para conferir URL, rede e status.
  Future<ConnectionCheck> testarConexao() async {
    final stopwatch = Stopwatch()..start();
    final products = await listarProdutos();
    stopwatch.stop();
    return ConnectionCheck(
      statusCode: 200,
      productCount: products.length,
      elapsed: stopwatch.elapsed,
    );
  }

  // ---------------------------------------------------------------------------
  // Infraestrutura comum
  // ---------------------------------------------------------------------------

  /// Envia a requisição, registra no console e converte falhas em [ApiException].
  ///
  /// Apostila de HTTP, seção 15: trata falta de conexão, URL incorreta,
  /// tempo esgotado e respostas fora do esperado (404, 500...).
  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    required Set<int> expected,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse('$baseUrl$path');
      final supportedScheme = uri.scheme == 'http' || uri.scheme == 'https';
      if (!supportedScheme || uri.host.isEmpty) throw const FormatException();
    } on FormatException {
      throw const ApiException(
          'Endereço da API inválido. Confira em Configurações (ex.: http://10.0.2.2:3000).');
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    debugPrint('[HTTP] → $method $uri');
    if (encodedBody != null) debugPrint('[HTTP]   corpo enviado: $encodedBody');

    final http.Response response;
    try {
      final request = switch (method) {
        'GET' => _client.get(uri, headers: headers),
        'POST' => _client.post(uri, headers: headers, body: encodedBody),
        'PUT' => _client.put(uri, headers: headers, body: encodedBody),
        'DELETE' => _client.delete(uri, headers: headers),
        _ => throw ArgumentError.value(method, 'method'),
      };
      response = await request.timeout(timeout);
    } on TimeoutException {
      debugPrint('[HTTP] ✗ tempo esgotado em $method $uri');
      throw const ApiException(
          'O servidor demorou para responder. Tente novamente.');
    } on http.ClientException catch (error) {
      // Sem internet, servidor desligado ou endereço errado caem aqui.
      debugPrint('[HTTP] ✗ falha de comunicação: ${error.message}');
      throw const ApiException(
          'Sem conexão com a API. Confira a internet e o endereço do servidor.');
    }

    debugPrint('[HTTP] ← ${response.statusCode} $method $uri');
    debugPrint('[HTTP]   corpo recebido: ${response.body}');

    if (!expected.contains(response.statusCode)) {
      throw ApiException(_messageForStatus(response.statusCode),
          statusCode: response.statusCode);
    }
    return response;
  }

  /// Traduz os códigos de status mais comuns (apostila de HTTP, seção 4.3).
  static String _messageForStatus(int statusCode) {
    return switch (statusCode) {
      400 => 'Requisição inválida (HTTP 400).',
      401 => 'Autenticação necessária (HTTP 401).',
      403 => 'Acesso não permitido (HTTP 403).',
      404 => 'Registro não encontrado no servidor (HTTP 404).',
      409 => 'Este registro já existe no servidor (HTTP 409).',
      429 => 'O servidor atingiu o limite de registros (HTTP 429).',
      500 => 'Erro interno no servidor (HTTP 500).',
      >= 500 => 'O servidor está indisponível (HTTP $statusCode).',
      _ => 'Resposta inesperada do servidor (HTTP $statusCode).',
    };
  }

  /// Converte uma resposta que deveria ser uma lista JSON.
  List<T> _decodeList<T>(
      http.Response response, T Function(Map<String, dynamic>) fromJson) {
    final decoded = _decodeBody(response);
    if (decoded is! List) {
      throw const ApiException('A API não devolveu uma lista JSON.');
    }
    return _convert(() => decoded
        .map((item) => fromJson(Map<String, dynamic>.from(item as Map)))
        .toList());
  }

  /// Converte uma resposta que deveria ser um único objeto JSON.
  T _decodeObject<T>(
      http.Response response, T Function(Map<String, dynamic>) fromJson) {
    final decoded = _decodeBody(response);
    if (decoded is! Map) {
      throw const ApiException('A API não devolveu um objeto JSON.');
    }
    return _convert(() => fromJson(Map<String, dynamic>.from(decoded)));
  }

  /// Decodifica os bytes em UTF-8 (acentos) e depois o texto JSON.
  Object? _decodeBody(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ApiException('A API respondeu com um JSON inválido.');
    }
  }

  /// Transforma campos ausentes ou com tipo errado em mensagem compreensível.
  T _convert<T>(T Function() conversion) {
    try {
      return conversion();
    } on FormatException catch (error) {
      throw ApiException('JSON inesperado: ${error.message}');
    } on TypeError {
      throw const ApiException('JSON inesperado: um campo veio com tipo errado.');
    }
  }
}
