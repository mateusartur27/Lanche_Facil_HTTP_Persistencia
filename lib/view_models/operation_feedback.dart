import '../services/sync_service.dart';

/// Mensagem devolvida pelos ViewModels para a tela exibir em um SnackBar.
class OperationFeedback {
  const OperationFeedback({required this.success, required this.message});

  /// `false` somente quando nem a gravação local (SQLite) funcionou.
  final bool success;
  final String message;

  /// Combina "salvo no aparelho" com o resultado da tentativa de envio à API.
  factory OperationFeedback.afterLocalSave(String action, SendAttempt attempt) {
    if (attempt.sent) {
      return OperationFeedback(
          success: true, message: '$action. Sincronizado com o servidor.');
    }
    if (attempt.error != null) {
      return OperationFeedback(
        success: true,
        message: '$action no aparelho. Envio pendente: ${attempt.error}',
      );
    }
    return OperationFeedback(success: true, message: '$action.');
  }

  /// Falha ao gravar no SQLite ou regra de negócio recusada.
  const OperationFeedback.failure(this.message) : success = false;
}
