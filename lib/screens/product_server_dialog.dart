import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_service.dart';

/// Mostra a versão do produto que está no servidor (GET /produtos/{id}).
///
/// Apostila de HTTP, seção 9: o [FutureBuilder] representa os três estados de
/// uma operação assíncrona — carregando, sucesso (hasData) e erro (hasError).
class ProductServerDialog extends StatefulWidget {
  const ProductServerDialog({
    required this.api,
    required this.productId,
    required this.productName,
    super.key,
  });

  final ApiService api;
  final String productId;
  final String productName;

  @override
  State<ProductServerDialog> createState() => _ProductServerDialogState();
}

class _ProductServerDialogState extends State<ProductServerDialog> {
  /// A requisição é criada uma vez no initState, nunca dentro do build().
  late Future<Product> _futureProduct;

  @override
  void initState() {
    super.initState();
    _futureProduct = widget.api.buscarProduto(widget.productId);
  }

  /// Repete o GET quando a pessoa toca em "Tentar novamente".
  void _retry() {
    setState(() {
      _futureProduct = widget.api.buscarProduto(widget.productId);
    });
  }

  /// Formata centavos no padrão brasileiro.
  String _money(int cents) =>
      'R\$ ${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.productName} no servidor'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: FutureBuilder<Product>(
          future: _futureProduct,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final product = snapshot.data!;
              final json =
                  const JsonEncoder.withIndent('  ').convert(product.toJson());
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GET ${widget.api.baseUrl}/produtos/${product.id}',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text('Nome: ${product.name}'),
                    Text('Categoria: ${product.categoryId}'),
                    Text('Preço: ${_money(product.price)}'),
                    Text('Estoque: ${product.stockQuantity} un.'),
                    const SizedBox(height: 12),
                    const Text('JSON recebido:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    SelectableText(
                      json,
                      key: const Key('server-json'),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ],
                ),
              );
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final message = error is ApiException && error.isNotFound
                  ? 'Este produto ainda não existe no servidor (HTTP 404). '
                      'Sincronize para enviá-lo.'
                  : error is ApiException
                      ? error.message
                      : 'Erro: $error';
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 44),
                  const SizedBox(height: 12),
                  Text(message,
                      key: const Key('server-error'),
                      textAlign: TextAlign.center),
                ],
              );
            }
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _retry, child: const Text('Tentar novamente')),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
