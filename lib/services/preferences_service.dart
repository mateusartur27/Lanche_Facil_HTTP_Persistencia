import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guarda preferências simples do aparelho com SharedPreferences.
///
/// Apostila de Persistência, seção 6: SharedPreferences é indicado para valores
/// pequenos (chave → valor). Aqui ficam o tema, o endereço da API, o carrinho
/// e o horário da última sincronização. Dados estruturados ficam no SQLite.
class PreferencesService {
  PreferencesService(this._prefs);

  /// Carrega o arquivo de preferências antes de abrir a interface.
  static Future<PreferencesService> carregar() async =>
      PreferencesService(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const String themeKey = 'tema';
  static const String apiUrlKey = 'api_url';
  static const String cartKey = 'carrinho';
  static const String lastSyncKey = 'ultima_sincronizacao';

  // ---------------------------------------------------------------------------
  // Tema (equivalente ao exemplo "temaEscuro" da apostila).
  // ---------------------------------------------------------------------------

  /// getString() recupera o valor; `??` define o padrão quando ainda não existe.
  ThemeMode get themeMode => switch (_prefs.getString(themeKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  /// setString() grava o valor e ele continua salvo depois de fechar o app.
  Future<void> salvarTema(ThemeMode mode) =>
      _prefs.setString(themeKey, mode.name);

  // ---------------------------------------------------------------------------
  // Endereço da API REST.
  // ---------------------------------------------------------------------------

  /// Endereço usado quando a pessoa ainda não configurou outro.
  ///
  /// No emulador Android, `10.0.2.2` aponta para o computador que roda a API.
  /// No navegador e no computador, a API local responde em `localhost`.
  static String get defaultApiUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  /// Endereço atual da API (salvo ou padrão).
  String get apiUrl => _prefs.getString(apiUrlKey) ?? defaultApiUrl;

  /// Salva um novo endereço; texto vazio volta ao padrão.
  Future<void> salvarApiUrl(String url) {
    final value = url.trim();
    return value.isEmpty
        ? _prefs.remove(apiUrlKey)
        : _prefs.setString(apiUrlKey, value);
  }

  // ---------------------------------------------------------------------------
  // Carrinho — mapa simples {idDoProduto: quantidade} convertido em JSON.
  // ---------------------------------------------------------------------------

  /// Recupera o carrinho salvo; um valor corrompido é ignorado com segurança.
  Map<String, int> carregarCarrinho() {
    final raw = _prefs.getString(cartKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((id, quantity) => MapEntry(id, (quantity as num).toInt()));
    } catch (_) {
      return {};
    }
  }

  /// Salva o carrinho a cada alteração para ele sobreviver ao fechamento do app.
  Future<void> salvarCarrinho(Map<String, int> quantities) => quantities.isEmpty
      ? _prefs.remove(cartKey)
      : _prefs.setString(cartKey, jsonEncode(quantities));

  // ---------------------------------------------------------------------------
  // Última sincronização com a API.
  // ---------------------------------------------------------------------------

  /// Horário da última sincronização concluída, se houver.
  DateTime? get lastSync =>
      DateTime.tryParse(_prefs.getString(lastSyncKey) ?? '');

  /// Registra o horário em que a sincronização terminou com sucesso.
  Future<void> salvarUltimaSincronizacao(DateTime moment) =>
      _prefs.setString(lastSyncKey, moment.toIso8601String());
}
