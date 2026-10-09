import 'package:sqflite/sqflite.dart' show DatabaseFactory;
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// No navegador, o mesmo SQLite roda em WebAssembly (web/sqlite3.wasm) e grava no IndexedDB.
/// Assim o aplicativo também mantém os dados ao fechar e abrir a aba.
/// A variante sem web worker evita depender de SharedWorker no navegador.
DatabaseFactory platformDatabaseFactory() => databaseFactoryFfiWebNoWebWorker;
