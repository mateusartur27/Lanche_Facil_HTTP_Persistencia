import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../repositories/product_repository.dart';
import '../services/sync_service.dart';
import 'operation_feedback.dart';

/// Controla a gestão do cardápio: CRUD no SQLite seguido de envio à API.
class ProductManagementViewModel extends ChangeNotifier {
  ProductManagementViewModel({
    required ProductRepository repository,
    required SyncService sync,
  })  : _repository = repository,
        _sync = sync;

  final ProductRepository _repository;
  final SyncService _sync;
  bool _disposed = false;

  List<Product> products = const [];
  bool isLoading = true;
  String? errorMessage;

  /// Carrega a lista e passa a observar alterações gravadas por outras telas.
  void start() {
    _repository.changes.addListener(load);
    load();
  }

  /// SELECT no SQLite (inclui produtos inativos, diferente do catálogo do cliente).
  Future<void> load() async {
    try {
      products = await _repository.listar();
      errorMessage = null;
    } catch (_) {
      errorMessage = 'Não foi possível carregar os produtos salvos no aparelho.';
    }
    isLoading = false;
    if (!_disposed) notifyListeners();
  }

  /// Recria o cardápio de demonstração localmente.
  Future<OperationFeedback> createSamples() async {
    try {
      await _repository.inserirExemplos();
    } catch (_) {
      return const OperationFeedback.failure(
          'Não foi possível criar os exemplos.');
    }
    final result = await _sync.enviarPendentes();
    return OperationFeedback(
      success: true,
      message: result.failed == 0
          ? 'Produtos de exemplo criados e enviados ao servidor.'
          : 'Produtos de exemplo criados no aparelho. Envio pendente.',
    );
  }

  /// Cadastra (INSERT + POST) ou edita (UPDATE + PUT) um produto.
  ///
  /// Apostila de Persistência, seção 17: salvar primeiro no SQLite e depois
  /// tentar enviar para a API. Sem internet o produto fica pendente.
  Future<OperationFeedback> saveProduct(Product product) async {
    final isNew = product.id.isEmpty;
    final toSave = isNew ? product.copyWith(id: const Uuid().v4()) : product;
    try {
      if (isNew) {
        await _repository.inserir(toSave);
      } else {
        await _repository.atualizar(toSave);
      }
    } catch (_) {
      return const OperationFeedback.failure(
          'Não foi possível salvar o produto no aparelho.');
    }
    final attempt = await _sync.tentarEnviarProduto(toSave.id);
    return OperationFeedback.afterLocalSave(
        isNew ? 'Produto cadastrado' : 'Alteração salva', attempt);
  }

  /// Atualiza o estoque (UPDATE) e tenta enviar a alteração (PUT).
  Future<OperationFeedback> updateStock(Product product, int quantity) async {
    if (quantity < 0) {
      return const OperationFeedback.failure('O estoque não pode ser negativo.');
    }
    try {
      await _repository.atualizarEstoque(product.id, quantity);
    } catch (_) {
      return const OperationFeedback.failure(
          'Não foi possível atualizar o estoque.');
    }
    final attempt = await _sync.tentarEnviarProduto(product.id);
    return OperationFeedback.afterLocalSave('Estoque atualizado', attempt);
  }

  /// Exclui o produto (DELETE no SQLite) e tenta removê-lo da API (DELETE HTTP).
  Future<OperationFeedback> deleteProduct(Product product) async {
    try {
      await _repository.excluir(product.id);
    } catch (_) {
      return const OperationFeedback.failure(
          'Não foi possível excluir o produto.');
    }
    final attempt = await _sync.tentarEnviarProduto(product.id);
    return OperationFeedback.afterLocalSave('Produto excluído', attempt);
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.changes.removeListener(load);
    super.dispose();
  }
}
