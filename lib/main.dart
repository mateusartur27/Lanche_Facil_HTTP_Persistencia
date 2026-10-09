import 'dart:async';

import 'package:flutter/material.dart';

import 'config/app_dependencies.dart';
import 'config/theme.dart';
import 'screens/home_screen.dart';

/// Inicia a aplicação Flutter e monta o widget principal na tela.
///
/// Não existe mais tela de login: o aplicativo abre direto no cardápio.
Future<void> main() async {
  // Garante que os plugins (SQLite e SharedPreferences) estejam prontos.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ApplicationBootstrap());
}

/// Abre o banco local e as preferências antes de exibir o aplicativo.
class ApplicationBootstrap extends StatefulWidget {
  const ApplicationBootstrap({super.key});

  @override
  State<ApplicationBootstrap> createState() => _ApplicationBootstrapState();
}

/// Mostra carregamento ou erro enquanto o armazenamento local é preparado.
class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  late Future<AppDependencies> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  /// Carrega SharedPreferences + SQLite e dispara a primeira sincronização.
  Future<AppDependencies> _initialize() async {
    final AppDependencies dependencies;
    try {
      dependencies = await AppDependencies.initialize();
    } catch (error, stack) {
      // Registra o motivo no console para facilitar a depuração.
      debugPrint('Falha ao abrir SQLite/SharedPreferences: $error\n$stack');
      rethrow;
    }
    // Aplica o tema salvo antes do primeiro quadro (SharedPreferences).
    AppTheme.mode.value = dependencies.preferences.themeMode;
    // Sincroniza em segundo plano; sem internet o app segue usando o SQLite.
    unawaited(dependencies.sync.sincronizar());
    return dependencies;
  }

  /// Tenta abrir o armazenamento local novamente.
  void _retry() {
    setState(() => _initialization = _initialize());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return LancheFacilApp(dependencies: snapshot.data!);
        }
        return MaterialApp(
          title: 'Lanche Fácil',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: snapshot.hasError
                      ? [
                          const Icon(Icons.storage_outlined, size: 52),
                          const SizedBox(height: 16),
                          const Text(
                            'Não foi possível abrir os dados salvos no aparelho.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          // Detalhe técnico para quem estiver depurando.
                          Text('${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Tentar novamente'),
                          ),
                        ]
                      : const [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Abrindo o Lanche Fácil...'),
                        ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Raiz do aplicativo já com banco, preferências e serviços prontos.
class LancheFacilApp extends StatefulWidget {
  const LancheFacilApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<LancheFacilApp> createState() => _LancheFacilAppState();
}

/// Salva o tema sempre que a pessoa o altera nas configurações.
class _LancheFacilAppState extends State<LancheFacilApp> {
  @override
  void initState() {
    super.initState();
    AppTheme.mode.addListener(_saveTheme);
  }

  @override
  void dispose() {
    AppTheme.mode.removeListener(_saveTheme);
    super.dispose();
  }

  /// SharedPreferences: o tema escolhido continua salvo depois de fechar o app.
  void _saveTheme() =>
      widget.dependencies.preferences.salvarTema(AppTheme.mode.value);

  /// Constrói o aplicativo Material Design exibido no navegador ou celular.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, themeMode, _) => MaterialApp(
        title: 'Lanche Fácil',
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        debugShowCheckedModeBanner: false,
        home: HomeScreen(dependencies: widget.dependencies),
      ),
    );
  }
}
