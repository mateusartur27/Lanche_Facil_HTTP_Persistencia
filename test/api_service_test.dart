import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novo_ifood/models/product.dart';
import 'package:novo_ifood/services/api_service.dart';

import 'helpers.dart';

/// Testa a camada HTTP sem rede real, usando um MockClient.
void main() {
  final product = sampleProducts('campus-principal').first;

  test('GET /produtos converte a lista JSON em objetos Dart', () async {
    final api = FakeRestApi(initial: {
      'produtos': [product.toJson()]
    });
    final service =
        ApiService(baseUrl: () => 'http://api.test/', client: api.client);
    final products = await service.listarProdutos();
    expect(products.single.name, product.name);
    expect(api.log, ['GET /produtos']);
  });

  test('POST envia headers JSON e aceita 201 Created', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(request.body, 201,
          headers: {'content-type': 'application/json'});
    });
    final service = ApiService(baseUrl: () => 'http://api.test', client: client);
    final created = await service.criarProduto(product);
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'http://api.test/produtos');
    expect(captured.headers['Content-Type'], startsWith('application/json'));
    expect(captured.headers['Accept'], 'application/json');
    expect(jsonDecode(captured.body)['nome'], product.name);
    expect(created.id, product.id);
  });

  test('PUT e DELETE usam o id na URL', () async {
    final api = FakeRestApi(initial: {
      'produtos': [product.toJson()]
    });
    final service = ApiService(baseUrl: () => 'http://api.test', client: api.client);
    await service.atualizarProduto(product.copyWith(name: 'Novo nome'));
    await service.excluirProduto(product.id);
    expect(api.log, ['PUT /produtos/${product.id}', 'DELETE /produtos/${product.id}']);
    expect(api.resources['produtos'], isEmpty);
  });

  test('404 vira ApiException com isNotFound', () async {
    final api = FakeRestApi();
    final service = ApiService(baseUrl: () => 'http://api.test', client: api.client);
    await expectLater(
      service.buscarProduto('nao-existe'),
      throwsA(isA<ApiException>()
          .having((e) => e.isNotFound, 'isNotFound', isTrue)
          .having((e) => e.statusCode, 'statusCode', 404)),
    );
  });

  test('500 vira mensagem de erro do servidor', () async {
    final api = FakeRestApi()..forcedStatus = 500;
    final service = ApiService(baseUrl: () => 'http://api.test', client: api.client);
    await expectLater(
      service.listarProdutos(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('500'))),
    );
  });

  test('409 (id duplicado na API do Cloudflare) vira mensagem própria',
      () async {
    final client = MockClient((_) async => http.Response('{}', 409));
    final service = ApiService(baseUrl: () => 'http://api.test', client: client);
    await expectLater(
      service.criarProduto(product),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('já existe'))),
    );
  });

  test('sem conexão vira mensagem amigável', () async {
    final api = FakeRestApi()..offline = true;
    final service = ApiService(baseUrl: () => 'http://api.test', client: api.client);
    await expectLater(
      service.listarProdutos(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('Sem conexão'))
          .having((e) => e.statusCode, 'statusCode', isNull)),
    );
  });

  test('JSON inválido ou incompleto é tratado', () async {
    final broken = MockClient((_) async => http.Response('{"produtos": [', 200));
    final incomplete = MockClient(
        (_) async => http.Response('[{"id": "a", "nome": "Sem preco"}]', 200));
    await expectLater(
      ApiService(baseUrl: () => 'http://api.test', client: broken)
          .listarProdutos(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('JSON inválido'))),
    );
    await expectLater(
      ApiService(baseUrl: () => 'http://api.test', client: incomplete)
          .listarProdutos(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('JSON inesperado'))),
    );
  });

  test('URL incorreta é recusada antes de enviar', () async {
    final service = ApiService(
        baseUrl: () => 'servidor-sem-http', client: FakeRestApi().client);
    await expectLater(
      service.listarProdutos(),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('Endereço da API'))),
    );
  });
}
