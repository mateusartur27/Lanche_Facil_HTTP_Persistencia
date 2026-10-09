import 'package:flutter/material.dart';

/// Exibe as informações institucionais e a autoria do projeto acadêmico.
Future<void> showAboutApplicationDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.storefront_rounded, size: 42),
      title: const Text('Sobre o Lanche Fácil'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplicativo de pedidos antecipados criado para reduzir filas e '
              'agilizar o atendimento na lanchonete da Faculdade FANS.',
            ),
            SizedBox(height: 12),
            Text(
              'Versão acadêmica: dados salvos no aparelho (SQLite e '
              'SharedPreferences) e sincronizados com uma API REST via HTTP.',
            ),
            SizedBox(height: 20),
            Text(
              'Desenvolvido por',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Rafael Araújo Nascimento'),
            Text('Mateus Artur Santos'),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
