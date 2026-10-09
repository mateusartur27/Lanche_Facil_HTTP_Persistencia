import 'package:http/http.dart' as http;

import '../database/app_database.dart';
import '../repositories/order_repository.dart';
import '../repositories/product_repository.dart';
import '../services/api_service.dart';
import '../services/preferences_service.dart';
import '../services/sync_service.dart';

/// Reúne as dependências criadas uma única vez e compartilhadas pelas telas.
///
/// Fluxo das camadas:
/// Tela → ViewModel → Repository (SQLite) / SyncService → ApiService (HTTP) → API REST.
class AppDependencies {
  AppDependencies({
    required this.preferences,
    required this.database,
    http.Client? httpClient,
  })  : products = ProductRepository(database: database),
        orders = OrderRepository(database: database) {
    api = ApiService(baseUrl: () => preferences.apiUrl, client: httpClient);
    sync = SyncService(
      api: api,
      products: products,
      orders: orders,
      preferences: preferences,
    );
  }

  final PreferencesService preferences;
  final AppDatabase database;
  final ProductRepository products;
  final OrderRepository orders;
  late final ApiService api;
  late final SyncService sync;

  /// Abre SharedPreferences e o banco SQLite antes de exibir a primeira tela.
  static Future<AppDependencies> initialize() async {
    final preferences = await PreferencesService.carregar();
    final database = AppDatabase.instance;
    await database.abrir();
    return AppDependencies(preferences: preferences, database: database);
  }
}
