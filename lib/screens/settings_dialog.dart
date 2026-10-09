import 'package:flutter/material.dart';

import '../config/app_dependencies.dart';
import '../config/theme.dart';
import '../services/api_service.dart';
import '../services/preferences_service.dart';
import '../widgets/sync_status.dart';

/// Abre as configurações: aparência, servidor da API e sincronização.
Future<void> showSettingsDialog(
    BuildContext context, AppDependencies dependencies) {
  return showDialog<void>(
    context: context,
    builder: (_) => SettingsDialog(dependencies: dependencies),
  );
}

/// Reúne as preferências salvas com SharedPreferences e os testes de conexão HTTP.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _apiUrl;
  bool _testing = false;
  String? _connectionMessage;
  String? _syncMessage;

  AppDependencies get _deps => widget.dependencies;

  @override
  void initState() {
    super.initState();
    _apiUrl = TextEditingController(text: _deps.preferences.apiUrl);
  }

  @override
  void dispose() {
    _apiUrl.dispose();
    super.dispose();
  }

  /// Aceita somente endereços HTTP(S) completos, como http://192.168.0.10:3000.
  String? _validateUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    final valid = uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
    return valid ? null : 'Use um endereço como http://192.168.0.10:3000';
  }

  /// Grava o endereço com SharedPreferences; o ApiService passa a usá-lo na hora.
  /// Retorna `false` quando o texto digitado não é um endereço válido.
  Future<bool> _saveUrl({bool restoreDefault = false}) async {
    if (restoreDefault) _apiUrl.text = '';
    final value = _apiUrl.text.trim();
    final error = value.isEmpty ? null : _validateUrl(value);
    if (error != null) {
      setState(() => _connectionMessage = error);
      return false;
    }
    await _deps.preferences.salvarApiUrl(value);
    _apiUrl.text = _deps.preferences.apiUrl;
    setState(() => _connectionMessage = 'Endereço salvo: ${_apiUrl.text}');
    return true;
  }

  /// Faz um GET /produtos e mostra status, quantidade e tempo de resposta.
  Future<void> _testConnection() async {
    if (!await _saveUrl()) return;
    setState(() {
      _testing = true;
      _connectionMessage = 'Testando GET ${_deps.api.baseUrl}/produtos...';
    });
    try {
      final check = await _deps.api.testarConexao();
      _connectionMessage = 'Conectado! HTTP ${check.statusCode} · '
          '${check.productCount} produto(s) no servidor · '
          '${check.elapsed.inMilliseconds} ms';
    } on ApiException catch (error) {
      _connectionMessage = 'Falhou: ${error.message}';
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Executa a sincronização completa e mostra o resumo dentro do diálogo.
  Future<void> _synchronize() async {
    final result = await _deps.sync.sincronizar();
    if (mounted) setState(() => _syncMessage = result.message);
  }

  @override
  Widget build(BuildContext context) {
    final sectionStyle = Theme.of(context)
        .textTheme
        .titleSmall
        ?.copyWith(fontWeight: FontWeight.w800);
    return AlertDialog(
      title: const Text('Configurações'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Aparência', style: sectionStyle),
              const SizedBox(height: 4),
              Text('Salva no aparelho com SharedPreferences.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              ValueListenableBuilder<ThemeMode>(
                valueListenable: AppTheme.mode,
                builder: (context, selectedMode, _) =>
                    SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      icon: Icon(Icons.settings_suggest_outlined),
                      label: Text('Aparelho'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Claro'),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Escuro'),
                    ),
                  ],
                  selected: {selectedMode},
                  onSelectionChanged: (selection) =>
                      AppTheme.setMode(selection.first),
                ),
              ),
              const Divider(height: 32),
              Text('Servidor da API (HTTP)', style: sectionStyle),
              const SizedBox(height: 10),
              TextField(
                key: const Key('api-url-field'),
                controller: _apiUrl,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Endereço base da API',
                  hintText: PreferencesService.cloudApiUrl,
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Padrão: API na nuvem (Cloudflare). Para testar erros, acrescente '
                '/simular/500, /simular/json-invalido ou /simular/lento ao endereço. '
                'API local opcional: http://10.0.2.2:3000 (emulador) ou '
                'http://IP-do-computador:3000 (celular).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const Key('test-connection'),
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_check_rounded),
                    label: const Text('Salvar e testar'),
                  ),
                  TextButton(
                    key: const Key('use-default-api'),
                    onPressed:
                        _testing ? null : () => _saveUrl(restoreDefault: true),
                    child: const Text('Usar padrão (nuvem)'),
                  ),
                ],
              ),
              if (_connectionMessage != null) ...[
                const SizedBox(height: 8),
                Text(_connectionMessage!,
                    key: const Key('connection-message'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
              const Divider(height: 32),
              Text('Sincronização', style: sectionStyle),
              const SizedBox(height: 10),
              SyncStatusBanner(
                sync: _deps.sync,
                changes: _deps.database.changes,
                onSynchronize: _synchronize,
              ),
              if (_syncMessage != null) ...[
                const SizedBox(height: 8),
                Text(_syncMessage!, key: const Key('sync-message')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}
