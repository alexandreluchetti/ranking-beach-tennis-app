import 'package:dio/dio.dart';

/// A failed backend call with a message ready to be shown to the user (pt-BR).
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode, this.details});

  final String message;

  /// Stable business code sent by the backend (e.g. `INVALID_SCORE`), if any.
  final String? code;
  final int? statusCode;

  /// The full error body, for codes that carry extra data.
  final Map<String, dynamic>? details;

  bool get isNetworkError => statusCode == null;

  static const _generic = 'Não foi possível concluir a operação. Tente novamente.';
  static const _offline = 'Sem conexão com o servidor. Verifique sua internet.';
  static const _session = 'Sua sessão expirou. Entre novamente.';

  /// The backend answers errors as RFC 9457 problem details with a pt-BR
  /// `detail` and a stable `code`.
  factory ApiException.fromDio(DioException error) {
    final response = error.response;
    if (response == null) {
      return const ApiException(_offline);
    }
    final data = response.data;
    final body = data is Map<String, dynamic> ? data : null;
    final status = response.statusCode;
    final detail = body?['detail'] as String?;
    return ApiException(
      detail ?? (status == 401 ? _session : _generic),
      code: body?['code'] as String?,
      statusCode: status,
      details: body,
    );
  }

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}
