import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/product.dart';
// Escolhe a implementação do SQLite conforme a plataforma (celular ou navegador).
import 'database_factory_mobile.dart'
    if (dart.library.js_interop) 'database_factory_web.dart';

/// Centraliza a abertura do banco SQLite local do aplicativo.
///
/// Apostila de Persistência, seção 7: o banco é criado na primeira chamada de
/// [abrir] e as tabelas são montadas no `onCreate`.
class AppDatabase {
  /// Permite que os testes usem um banco em memória sem tocar no aparelho.
  AppDatabase({DatabaseFactory? factory, String? path})
      : _factory = factory,
        _path = path;

  /// Instância única usada pelo aplicativo em execução.
  static final AppDatabase instance = AppDatabase();

  /// Nome do arquivo gravado na pasta de bancos do aparelho.
  static const String fileName = 'lanche_facil.db';

  /// Estabelecimento usado enquanto o MVP opera com uma única loja.
  static const String establishmentId = 'campus-principal';

  final DatabaseFactory? _factory;
  final String? _path;
  Future<Database>? _opening;

  /// Avisa as telas sempre que um repositório grava algo, para recarregarem a lista.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  /// Abre o banco uma única vez e reaproveita a mesma conexão nas próximas chamadas.
  Future<Database> abrir() => _opening ??= _open();

  /// Incrementa o contador observado pelos ViewModels após INSERT, UPDATE ou DELETE.
  void notifyChanged() => changes.value++;

  /// Fecha a conexão (usado principalmente pelos testes automatizados).
  Future<void> fechar() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }

  /// Monta o caminho do arquivo e cria as tabelas na primeira execução.
  Future<Database> _open() async {
    final factory = _factory ?? platformDatabaseFactory();
    // No navegador não existe pasta de bancos: o nome identifica o banco no IndexedDB.
    final path = _path ??
        (kIsWeb ? fileName : join(await factory.getDatabasesPath(), fileName));
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        // Liga as chaves estrangeiras para apagar os itens junto com o pedido.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _createTables,
      ),
    );
  }

  /// Cria as tabelas do aplicativo e insere o cardápio inicial.
  ///
  /// As colunas `sincronizado`, `no_servidor` e `excluido` controlam o envio para
  /// a API (apostila de Persistência, seção 17): 0 = pendente, 1 = sincronizado.
  static Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE produtos (
        id TEXT PRIMARY KEY,
        estabelecimento_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        descricao TEXT NOT NULL,
        preco_centavos INTEGER NOT NULL,
        categoria TEXT NOT NULL,
        ativo INTEGER NOT NULL,
        disponivel INTEGER NOT NULL,
        estoque INTEGER NOT NULL,
        imagem_url TEXT,
        ajuste_imagem TEXT NOT NULL,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        sincronizado INTEGER NOT NULL,
        no_servidor INTEGER NOT NULL,
        excluido INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE pedidos (
        id TEXT PRIMARY KEY,
        estabelecimento_id TEXT NOT NULL,
        total_centavos INTEGER NOT NULL,
        status TEXT NOT NULL,
        observacao TEXT,
        criado_em TEXT NOT NULL,
        atualizado_em TEXT NOT NULL,
        sincronizado INTEGER NOT NULL,
        no_servidor INTEGER NOT NULL,
        excluido INTEGER NOT NULL
      )
    ''');
    // Cada item guarda nome e preço do momento da compra (histórico preservado).
    await db.execute('''
      CREATE TABLE itens_pedido (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pedido_id TEXT NOT NULL REFERENCES pedidos(id) ON DELETE CASCADE,
        produto_id TEXT NOT NULL,
        nome TEXT NOT NULL,
        quantidade INTEGER NOT NULL,
        preco_unitario INTEGER NOT NULL,
        subtotal INTEGER NOT NULL,
        observacao TEXT
      )
    ''');
    // O cardápio inicial nasce pendente: a primeira sincronização o confere com a API.
    final batch = db.batch();
    for (final product in sampleProducts(establishmentId)) {
      batch.insert('produtos', product.toMap());
    }
    await batch.commit(noResult: true);
  }
}
