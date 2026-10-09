import 'package:flutter/material.dart';

/// Mantém as identidades clara e escura em um único lugar para todas as telas.
class AppTheme {
  static const Color blue = Color(0xFF0079BF);
  static const Color green = Color(0xFF5AAC44);
  static const Color darkBlue = Color(0xFF172B4D);

  /// Notifica a raiz quando a pessoa escolhe seguir o aparelho, claro ou escuro.
  // O valor inicial vem do SharedPreferences (main.dart) e cada mudança é salva
  // de novo por LancheFacilApp, mantendo a escolha depois de fechar o app.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// Cria o tema claro inspirado nas cores do frontend Kanban do ME-PAGA.
  static ThemeData get lightTheme => _buildTheme(Brightness.light);

  /// Cria a versão escura preservando contraste, azul de marca e ações verdes.
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  /// Aplica a preferência escolhida nas configurações sem recriar a navegação.
  static void setMode(ThemeMode selectedMode) => mode.value = selectedMode;

  /// Gera os componentes compartilhados e troca apenas as cores dependentes do brilho.
  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scaffoldColor =
        isDark ? const Color(0xFF101720) : const Color(0xFFF4F5F7);
    final surfaceColor = isDark ? const Color(0xFF1C2738) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF344258) : const Color(0xFFD9DEE7);
    final textColor = isDark ? const Color(0xFFF1F5FA) : darkBlue;
    final mutedTextColor =
        isDark ? const Color(0xFFB4C0D0) : const Color(0xFF5E6C84);

    final colorScheme = ColorScheme.fromSeed(
      // O azul gera tons coerentes para controles Material Design 3.
      seedColor: blue,
      brightness: brightness,
    ).copyWith(
      primary: blue,
      secondary: green,
      surface: surfaceColor,
      onSurface: textColor,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldColor,
      textTheme: (isDark ? ThemeData.dark() : ThemeData.light())
          .textTheme
          .apply(bodyColor: textColor, displayColor: textColor),
      cardTheme: CardThemeData(
        color: surfaceColor,
        elevation: isDark ? 0 : 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? BorderSide(color: borderColor) : BorderSide.none,
        ),
        shadowColor: const Color(0x33172B4D),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceColor,
        hintStyle: TextStyle(color: mutedTextColor),
        prefixIconColor: mutedTextColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: blue, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceColor,
        selectedColor: blue,
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: TextStyle(color: textColor, fontWeight: FontWeight.w700),
        secondaryLabelStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? const Color(0xFF263449) : darkBlue,
        contentTextStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
