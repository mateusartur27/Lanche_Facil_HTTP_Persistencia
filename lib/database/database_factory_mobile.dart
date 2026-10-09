import 'package:sqflite/sqflite.dart';

/// Android e iOS usam o plugin nativo do sqflite, que grava um arquivo .db no aparelho.
DatabaseFactory platformDatabaseFactory() => databaseFactorySqflitePlugin;
