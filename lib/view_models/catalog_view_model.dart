import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';

/// Controla produtos, carregamento e filtro do catálogo fora da View.
class CatalogViewModel extends ChangeNotifier {
  CatalogViewModel({required ProductRepository repository})
      : _repository = repository;

  final ProductRepository _repository;
  List<Product> products = const [];
  String selectedCategory = 'Todos';
  bool loading = true;
  bool failed = false;
  bool _disposed = false;

  /// Lê o SQLite e volta a ler sempre que um repositório gravar algo.
  void start() {
    _repository.changes.addListener(load);
    load();
  }

  /// SELECT dos produtos ativos que aparecem para o cliente.
  Future<void> load() async {
    try {
      final all = await _repository.listar();
      products = all.where((product) => product.active).toList();
      failed = false;
    } catch (_) {
      failed = true;
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  /// Atualiza o filtro sem misturar estado com os controles visuais.
  void selectCategory(String category) {
    selectedCategory = category;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.changes.removeListener(load);
    super.dispose();
  }
}
