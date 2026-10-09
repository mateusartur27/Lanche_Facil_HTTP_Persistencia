import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novo_ifood/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Cria um banco SQLite em memória (sem tocar no disco) para cada teste.
AppDatabase createTestDatabase() {
  sqfliteFfiInit();
  return AppDatabase(
    // Sem isolate: as consultas terminam dentro do relógio falso dos testes de widget.
    factory: databaseFactoryFfiNoIsolate,
    path: inMemoryDatabasePath,
  );
}

/// API REST falsa em memória que imita o json-server usado nas aulas.
///
/// Permite testar GET/POST/PUT/DELETE e também simular queda de conexão.
class FakeRestApi {
  FakeRestApi({Map<String, List<Map<String, dynamic>>>? initial}) {
    resources['produtos'] = [...?initial?['produtos']];
    resources['pedidos'] = [...?initial?['pedidos']];
  }

  final Map<String, List<Map<String, dynamic>>> resources = {};

  /// Requisições recebidas, no formato "MÉTODO /caminho".
  final List<String> log = [];

  /// Quando `true`, toda chamada falha como se o servidor estivesse desligado.
  bool offline = false;

  /// Quando diferente de nulo, toda chamada responde com esse status.
  int? forcedStatus;

  /// Cliente HTTP que o ApiService usa nos testes.
  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('Connection refused', request.url);
    final segments = request.url.pathSegments;
    log.add('${request.method} /${segments.join('/')}');
    if (forcedStatus != null) {
      return _json({'erro': 'falha simulada'}, forcedStatus!);
    }
    final list = resources[segments.first];
    if (list == null) return _json({}, 404);
    final id = segments.length > 1 ? segments[1] : null;
    final index = id == null ? -1 : list.indexWhere((item) => item['id'] == id);

    switch (request.method) {
      case 'GET':
        if (id == null) return _json(list, 200);
        return index < 0 ? _json({}, 404) : _json(list[index], 200);
      case 'POST':
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (list.any((item) => item['id'] == body['id'])) {
          return _json({'erro': 'duplicate id'}, 500);
        }
        list.add(body);
        return _json(body, 201);
      case 'PUT':
        if (index < 0) return _json({}, 404);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        list[index] = {...body, 'id': id};
        return _json(list[index], 200);
      case 'DELETE':
        if (index < 0) return _json({}, 404);
        list.removeAt(index);
        return _json({}, 200);
    }
    return _json({}, 405);
  }

  http.Response _json(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}
