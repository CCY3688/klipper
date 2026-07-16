import 'dart:convert';

import 'package:dio/dio.dart';

class MoonrakerApiException implements Exception {
  final String message;
  final int? statusCode;
  final int? rpcCode;
  final Object? raw;

  const MoonrakerApiException(
    this.message, {
    this.statusCode,
    this.rpcCode,
    this.raw,
  });

  factory MoonrakerApiException.fromDio(DioException error) {
    final response = error.response;
    final parsed = parseMoonrakerError(
      response?.data,
      fallback: error.message ?? error.toString(),
    );

    return MoonrakerApiException(
      parsed.message,
      statusCode: response?.statusCode,
      rpcCode: parsed.rpcCode,
      raw: response?.data ?? error,
    );
  }

  factory MoonrakerApiException.fromResponse(
    Map<String, dynamic> response, {
    int? statusCode,
  }) {
    final parsed = parseMoonrakerError(response);
    return MoonrakerApiException(
      parsed.message,
      statusCode: statusCode,
      rpcCode: parsed.rpcCode,
      raw: response,
    );
  }

  @override
  String toString() => message;
}

class MoonrakerParsedError {
  final String message;
  final int? rpcCode;

  const MoonrakerParsedError(this.message, {this.rpcCode});
}

MoonrakerParsedError parseMoonrakerError(
  Object? data, {
  String fallback = 'Moonraker request failed',
}) {
  if (data is Map) {
    final map = data.cast<String, dynamic>();
    final error = map['error'];

    if (error is Map) {
      final err = error.cast<String, dynamic>();
      final message = _firstNonEmpty([
        err['message'],
        err['error'],
        err['detail'],
        err['description'],
      ]);
      if (message != null) {
        return MoonrakerParsedError(
          _normalizeErrorMessage(message),
          rpcCode: (err['code'] as num?)?.toInt(),
        );
      }
    }

    if (error is String && error.trim().isNotEmpty) {
      return MoonrakerParsedError(_normalizeErrorMessage(error));
    }

    final message = _firstNonEmpty([
      map['message'],
      map['detail'],
      map['description'],
    ]);
    if (message != null) {
      return MoonrakerParsedError(_normalizeErrorMessage(message));
    }
  }

  if (data is String) {
    final text = data.trim();
    if (text.isNotEmpty) {
      try {
        return parseMoonrakerError(jsonDecode(text), fallback: text);
      } catch (_) {
        return MoonrakerParsedError(_normalizeErrorMessage(text));
      }
    }
  }

  return MoonrakerParsedError(_normalizeErrorMessage(fallback));
}

String? _firstNonEmpty(List<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}

String _normalizeErrorMessage(String message) {
  final stripped = message
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return stripped.isEmpty ? 'Moonraker request failed' : stripped;
}
