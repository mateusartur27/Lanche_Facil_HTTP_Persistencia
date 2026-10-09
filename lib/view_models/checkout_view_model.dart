import 'package:flutter/foundation.dart';

import '../repositories/order_repository.dart';
import '../services/preferences_service.dart';

/// Controla carrinho, observação geral e criação do pedido fora da interface visual.
///
/// O carrinho é salvo com SharedPreferences a cada alteração; assim ele continua
/// preenchido depois que o aplicativo é fechado e aberto novamente.
class CheckoutViewModel extends ChangeNotifier {
  CheckoutViewModel({
    required OrderRepository repository,
    PreferencesService? preferences,
  })  : _repository = repository,
        _preferences = preferences {
    _quantities.addAll(preferences?.carregarCarrinho() ?? const {});
  }

  final OrderRepository _repository;
  final PreferencesService? _preferences;
  final Map<String, int> _quantities = {};
  final Map<String, int> _prices = {};
  bool isCreatingOrder = false;

  Map<String, int> get quantities => Map.unmodifiable(_quantities);
  int get itemCount => _quantities.values.fold(0, (sum, value) => sum + value);
  int get totalInCents => _quantities.entries.fold(
        0,
        (sum, entry) => sum + (_prices[entry.key] ?? 0) * entry.value,
      );

  /// Inclui a quantidade escolhida sem exceder estoque nem o limite de 99 unidades.
  bool addItem(
      {required String productId,
      required int price,
      required int stock,
      int quantity = 1}) {
    if (quantity < 1) return false;
    final current = _quantities[productId] ?? 0;
    return setQuantity(
        productId: productId,
        price: price,
        stock: stock,
        quantity: current + quantity);
  }

  /// Atualiza diretamente o item; o repositório revalida tudo ao criar o pedido.
  bool setQuantity(
      {required String productId,
      required int price,
      required int stock,
      required int quantity}) {
    if (isCreatingOrder || quantity < 1 || quantity > stock || quantity > 99) {
      return false;
    }
    _quantities[productId] = quantity;
    _prices[productId] = price;
    _persist();
    notifyListeners();
    return true;
  }

  /// Atualiza preços e remove do carrinho produtos que saíram do catálogo.
  ///
  /// Chamado depois que o catálogo é lido do SQLite, inclusive ao abrir o app
  /// com um carrinho salvo nas preferências.
  void synchronizeCatalog({
    required Map<String, int> prices,
    required Map<String, int> stock,
  }) {
    var changed = false;
    for (final id in _quantities.keys.toList()) {
      final available = stock[id] ?? 0;
      if (!prices.containsKey(id) || available <= 0) {
        _quantities.remove(id);
        _prices.remove(id);
        changed = true;
        continue;
      }
      _prices[id] = prices[id]!;
      if (_quantities[id]! > available) {
        _quantities[id] = available;
        changed = true;
      }
    }
    // A tela já está reconstruindo; só salvamos quando algo realmente mudou.
    if (changed) _persist();
  }

  /// Remove completamente um produto e seu preço auxiliar do carrinho.
  void removeItem(String productId) {
    _quantities.remove(productId);
    _prices.remove(productId);
    _persist();
    notifyListeners();
  }

  /// Grava o pedido no SQLite e limpa o carrinho somente após sucesso.
  Future<CreateOrderResult> createOrder({required String orderNotes}) async {
    if (isCreatingOrder) throw StateError('O pedido já está sendo criado.');
    isCreatingOrder = true;
    notifyListeners();
    try {
      final result = await _repository.criarPedido(
        observacao: orderNotes,
        itens: _quantities.entries
            .where((entry) => entry.value > 0)
            .map((entry) =>
                OrderLine(productId: entry.key, quantity: entry.value))
            .toList(),
      );
      _quantities.clear();
      _prices.clear();
      _persist();
      return result;
    } finally {
      isCreatingOrder = false;
      notifyListeners();
    }
  }

  /// SharedPreferences: salva o mapa {produto: quantidade} como JSON.
  void _persist() => _preferences?.salvarCarrinho(Map.of(_quantities));
}
