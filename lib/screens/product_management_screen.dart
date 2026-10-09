import 'package:flutter/material.dart';

import '../config/app_dependencies.dart';
import '../database/app_database.dart';
import '../models/product.dart';
import '../view_models/operation_feedback.dart';
import '../view_models/product_management_view_model.dart';
import '../widgets/sync_status.dart';
import 'product_server_dialog.dart';

/// CRUD do cardápio: cadastrar, listar, editar, alterar estoque e excluir.
///
/// Cada operação grava no SQLite e em seguida usa HTTP (POST, PUT ou DELETE
/// em /produtos). Sem internet, o produto fica marcado como pendente.
class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<ProductManagementScreen> createState() =>
      _ProductManagementScreenState();
}

/// Conecta a tela ao ViewModel e mantém diálogos e mensagens na camada visual.
class _ProductManagementScreenState extends State<ProductManagementScreen> {
  late final ProductManagementViewModel _viewModel;

  AppDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _viewModel = ProductManagementViewModel(
      repository: _deps.products,
      sync: _deps.sync,
    )..start();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão do cardápio'),
        actions: [
          IconButton(
            tooltip: 'Sincronizar com a API',
            onPressed: () => synchronizeWithFeedback(context, _deps.sync),
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-product'),
        onPressed: () => _openProductForm(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Novo produto'),
      ),
      body: AnimatedBuilder(
        animation: _viewModel,
        builder: (context, _) {
          if (_viewModel.errorMessage != null) {
            return Center(child: Text(_viewModel.errorMessage!));
          }
          if (_viewModel.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = _viewModel.products;
          return RefreshIndicator(
            onRefresh: () => synchronizeWithFeedback(context, _deps.sync),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                  itemCount: products.isEmpty ? 2 : products.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return SyncStatusBanner(
                        sync: _deps.sync,
                        changes: _deps.database.changes,
                        onSynchronize: () =>
                            synchronizeWithFeedback(context, _deps.sync),
                      );
                    }
                    if (products.isEmpty) {
                      return _EmptyCatalog(
                          onCreateSamples: () =>
                              _show(_viewModel.createSamples()));
                    }
                    final product = products[index - 1];
                    return _ProductManagementCard(
                      product: product,
                      onEdit: () => _openProductForm(context, product),
                      onStockChanged: (quantity) =>
                          _show(_viewModel.updateStock(product, quantity),
                              onlyErrors: true),
                      onDelete: () => _confirmDeletion(product),
                      onShowServer: () => _showServerVersion(product),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Exibe o resultado de uma operação; o estoque só avisa quando algo falha.
  Future<void> _show(Future<OperationFeedback> operation,
      {bool onlyErrors = false}) async {
    final feedback = await operation;
    if (!mounted || (onlyErrors && feedback.success)) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(feedback.message)));
  }

  /// Abre o formulário; o próprio formulário aguarda o salvamento e o envio HTTP.
  Future<void> _openProductForm(BuildContext context,
      [Product? product]) async {
    final feedback = await showDialog<OperationFeedback>(
      context: context,
      builder: (_) => _ProductFormDialog(
        product: product,
        onSubmit: _viewModel.saveProduct,
      ),
    );
    if (feedback == null || !mounted) return;
    ScaffoldMessenger.of(this.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(feedback.message, key: const Key('product-feedback')),
        duration: const Duration(seconds: 5),
      ));
  }

  /// Confirma antes de excluir do SQLite e do servidor.
  Future<void> _confirmDeletion(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Excluir ${product.name}?'),
        content: const Text(
            'O produto sai do aparelho (SQLite) e do servidor (DELETE /produtos).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            key: const Key('confirm-delete-product'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _show(_viewModel.deleteProduct(product));
  }

  /// Consulta a API (GET /produtos/{id}) e mostra o JSON recebido.
  Future<void> _showServerVersion(Product product) {
    return showDialog<void>(
      context: context,
      builder: (_) => ProductServerDialog(
        api: _deps.api,
        productId: product.id,
        productName: product.name,
      ),
    );
  }
}

/// Orienta o primeiro cadastro e oferece a criação controlada de exemplos.
class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({required this.onCreateSamples});
  final VoidCallback onCreateSamples;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.inventory_2_outlined, size: 54),
          const SizedBox(height: 14),
          const Text('Nenhum produto cadastrado.', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('create-sample-products'),
            onPressed: onCreateSamples,
            icon: const Icon(Icons.auto_awesome_rounded),
            label: const Text('Criar produtos de exemplo'),
          ),
        ],
      ),
    );
  }
}

/// Apresenta dados do produto, situação de sincronização e ações.
class _ProductManagementCard extends StatelessWidget {
  const _ProductManagementCard({
    required this.product,
    required this.onEdit,
    required this.onStockChanged,
    required this.onDelete,
    required this.onShowServer,
  });
  final Product product;
  final VoidCallback onEdit;
  final ValueChanged<int> onStockChanged;
  final VoidCallback onDelete;
  final VoidCallback onShowServer;

  /// Formata centavos sem realizar operações monetárias em ponto flutuante.
  String get _price =>
      'R\$ ${(product.price ~/ 100)},${(product.price % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    // Limita o cartão em monitores e reduz sua largura em celulares compactos.
    final detailsWidth =
        (MediaQuery.sizeOf(context).width - 64).clamp(220.0, 420.0);
    return Card(
      key: ValueKey('manage-${product.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: detailsWidth,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: product.imageUrl == null || product.imageUrl!.isEmpty
                      ? const Icon(Icons.fastfood_rounded)
                      : ClipOval(
                          child: Image.network(product.imageUrl!,
                              fit: product.imageFit == 'cover'
                                  ? BoxFit.cover
                                  : BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined))),
                ),
                title: Text(product.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                    '${product.categoryId} • $_price\n${product.description}'),
                isThreeLine: true,
              ),
            ),
            Chip(
                label: Text(product.available ? 'Disponível' : 'Indisponível')),
            SyncChip(synchronized: product.synchronized),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                    key: ValueKey('stock-decrease-${product.id}'),
                    onPressed: product.stockQuantity > 0
                        ? () => onStockChanged(product.stockQuantity - 1)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: 'Diminuir estoque'),
                Text('${product.stockQuantity} un.',
                    key: ValueKey('stock-${product.id}'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                    key: ValueKey('stock-increase-${product.id}'),
                    onPressed: () => onStockChanged(product.stockQuantity + 1),
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Aumentar estoque'),
              ],
            ),
            OutlinedButton.icon(
                key: ValueKey('edit-${product.id}'),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar')),
            OutlinedButton.icon(
                key: ValueKey('server-${product.id}'),
                onPressed: onShowServer,
                icon: const Icon(Icons.cloud_outlined),
                label: const Text('Ver no servidor')),
            TextButton.icon(
                key: ValueKey('delete-${product.id}'),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Excluir')),
          ],
        ),
      ),
    );
  }
}

/// Formulário de cadastro/edição.
///
/// Exercício 10.1 da apostila de HTTP: campos de texto + botão "Cadastrar";
/// ao clicar, salva e envia (POST) e mostra mensagem de sucesso ou erro.
/// O botão fica desabilitado durante o envio para evitar cliques repetidos.
class _ProductFormDialog extends StatefulWidget {
  const _ProductFormDialog({required this.onSubmit, this.product});

  final Future<OperationFeedback> Function(Product product) onSubmit;
  final Product? product;

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _stock;
  late final TextEditingController _imageUrl;
  // Usa o mesmo enquadramento na prévia e no catálogo depois do salvamento.
  String _imageFit = 'contain';
  bool _active = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _imageFit = product?.imageFit ?? 'contain';
    _active = product?.active ?? true;
    _name = TextEditingController(text: product?.name);
    _description = TextEditingController(text: product?.description);
    _category = TextEditingController(text: product?.categoryId);
    _price = TextEditingController(
        text: product == null
            ? ''
            : (product.price / 100).toStringAsFixed(2).replaceAll('.', ','));
    _stock = TextEditingController(text: '${product?.stockQuantity ?? 0}');
    _imageUrl = TextEditingController(text: product?.imageUrl);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _category,
      _price,
      _stock,
      _imageUrl
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Converte reais digitados para centavos antes de montar o produto.
  int? _priceInCents() {
    final value = double.tryParse(_price.text.replaceAll(',', '.'));
    return value == null ? null : (value * 100).round();
  }

  /// Valida, salva no SQLite, tenta o envio HTTP e fecha com a mensagem final.
  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final stock = int.parse(_stock.text);
    final imageUrl = _imageUrl.text.trim();
    final product = Product(
      id: widget.product?.id ?? '',
      establishmentId:
          widget.product?.establishmentId ?? AppDatabase.establishmentId,
      name: _name.text.trim(),
      description: _description.text.trim(),
      price: _priceInCents()!,
      categoryId: _category.text.trim(),
      active: _active,
      available: stock > 0,
      stockQuantity: stock,
      imageUrl: imageUrl.isEmpty ? null : imageUrl,
      imageFit: _imageFit,
      createdAt: widget.product?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final feedback = await widget.onSubmit(product);
    if (!mounted) return;
    if (feedback.success) {
      Navigator.of(context).pop(feedback);
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = feedback.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imageUrl.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(_isNew ? 'Novo produto' : 'Editar produto'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                    key: const Key('product-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Informe o nome.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('product-description'),
                    controller: _description,
                    maxLines: 3,
                    decoration:
                        const InputDecoration(labelText: 'Detalhes do produto'),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? 'Informe os detalhes.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('product-category'),
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Informe a categoria.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('product-price'),
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Preço em reais', prefixText: 'R\$ '),
                    validator: (_) => (_priceInCents() ?? 0) <= 0
                        ? 'Informe um preço válido.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    key: const Key('product-stock'),
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Quantidade em estoque'),
                    validator: (value) => (int.tryParse(value ?? '') ?? -1) < 0
                        ? 'Informe zero ou mais.'
                        : null),
                const SizedBox(height: 12),
                TextFormField(
                    controller: _imageUrl,
                    // Atualiza a prévia quando o gerente informa uma URL externa.
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        labelText: 'URL da foto (opcional)',
                        hintText: 'https://...')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Exibir no cardápio'),
                  value: _active,
                  onChanged: _isSubmitting
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                if (hasImage) ...[
                  SwitchListTile(
                    key: const Key('fit-product-image'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mostrar foto inteira'),
                    subtitle: Text(_imageFit == 'contain'
                        ? 'Encaixa sem cortar. Pode deixar espaço nas laterais.'
                        : 'Preenche o card. As bordas da foto podem ser cortadas.'),
                    value: _imageFit == 'contain',
                    onChanged: _isSubmitting
                        ? null
                        : (value) => setState(
                            () => _imageFit = value ? 'contain' : 'cover'),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        _imageUrl.text.trim(),
                        fit:
                            _imageFit == 'cover' ? BoxFit.cover : BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.broken_image_outlined, size: 44),
                        ),
                      ),
                    ),
                  ),
                ],
                if (_isSubmitting) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 6),
                  const Text('Salvando no aparelho e enviando para a API...'),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700)),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            key: const Key('save-product'),
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isNew ? 'Cadastrar' : 'Salvar')),
      ],
    );
  }
}
