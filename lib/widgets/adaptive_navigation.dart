import 'package:flutter/material.dart';

/// Descreve uma opção exibida no menu lateral.
class AppNavigationItem {
  const AppNavigationItem({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
}

/// Padroniza a navegação lateral responsiva do aplicativo.
///
/// Sem tela de login, o menu não exibe usuário nem a opção "Sair da conta".
class AdaptiveNavigationScaffold extends StatelessWidget {
  const AdaptiveNavigationScaffold({
    required this.body,
    required this.onOpenAbout,
    required this.onOpenSettings,
    this.items = const [],
    this.trailingActions = const [],
    super.key,
  });

  final Widget body;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenSettings;
  final List<AppNavigationItem> items;
  final List<Widget> trailingActions;

  /// Monta uma barra fixa em telas amplas e um Drawer deslizante no celular.
  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    final panel = _NavigationPanel(
      items: items,
      onOpenAbout: onOpenAbout,
      onOpenSettings: onOpenSettings,
      closeDrawerAfterTap: !isDesktop,
    );

    return Scaffold(
      drawer: isDesktop ? null : Drawer(child: SafeArea(child: panel)),
      appBar: isDesktop
          ? null
          : AppBar(
              title: const Text('Lanche Fácil'),
              actions: trailingActions,
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop)
              SizedBox(
                width: 270,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: panel,
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// Renderiza identidade, atalhos e o acesso às configurações.
class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.items,
    required this.onOpenAbout,
    required this.onOpenSettings,
    required this.closeDrawerAfterTap,
  });

  final List<AppNavigationItem> items;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenSettings;
  final bool closeDrawerAfterTap;

  /// Fecha o menu móvel antes de executar a navegação solicitada.
  void _openItem(BuildContext context, VoidCallback callback) {
    if (closeDrawerAfterTap) Navigator.of(context).pop();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Row(
            children: [
              ClipRRect(
                key: const Key('app-brand-icon'),
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/icons/app_icon.png',
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Lanche Fácil',
                        style: TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      'Pedidos sem fila',
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            children: [
              for (final item in items)
                ListTile(
                  leading: Icon(item.icon),
                  title: Text(item.label),
                  trailing: item.badgeCount > 0
                      ? Badge(label: Text('${item.badgeCount}'))
                      : null,
                  onTap: () => _openItem(context, item.onTap),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const Key('open-about-application'),
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Sobre o aplicativo'),
                  onTap: () => _openItem(context, onOpenAbout),
                ),
                ListTile(
                  key: const Key('open-settings'),
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Configurações'),
                  onTap: () => _openItem(context, onOpenSettings),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
