import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/envelope.dart';

class ApiClient {
  ApiClient({required this.baseUrl, http.Client? client, Duration? timeout})
    : _client = client ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 5);

  final String baseUrl;
  final http.Client _client;
  final Duration _timeout;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> getJson(String path) async {
    final uri = _uri(path);
    try {
      final res = await _client.get(uri).timeout(_timeout);
      return _handle(res, method: 'GET', path: path);
    } on TimeoutException catch (e) {
      throw ApiException(
        message: 'Timeout after ${_timeout.inSeconds}s',
        statusCode: 0,
        path: 'GET $path',
        rawBody: e.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required Map<String, dynamic> body,
  }) async {
    final uri = _uri(path);
    try {
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      return _handle(res, method: 'POST', path: path);
    } on TimeoutException catch (e) {
      throw ApiException(
        message: 'Timeout after ${_timeout.inSeconds}s',
        statusCode: 0,
        path: 'POST $path',
        rawBody: e.toString(),
      );
    }
  }

  /// Typed envelope (Contract v1)
  Future<Envelope<T>> getEnvelope<T>(
    String path, {
    required FromJson<T> fromJson,
    String expectedContractVersion = '1.0.0',
  }) async {
    final raw = await getJson(path);
    final env = Envelope<T>.fromJson(raw, fromJson: fromJson);

    if (env.meta.contractVersion != expectedContractVersion) {
      throw ApiException(
        message:
            'Unexpected contract_version: ${env.meta.contractVersion} (expected $expectedContractVersion)',
        statusCode: 0,
        path: 'GET $path',
        rawBody: raw.toString(),
      );
    }

    return env;
  }

  Map<String, dynamic> _handle(
    http.Response res, {
    required String method,
    required String path,
  }) {
    final raw = res.body;

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        message: 'HTTP ${res.statusCode} for $method $path',
        statusCode: res.statusCode,
        path: '$method $path',
        rawBody: raw,
      );
    }

    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw ApiException(
        message: 'Expected JSON but got: $contentType',
        statusCode: res.statusCode,
        path: '$method $path',
        rawBody: raw,
      );
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw ApiException(
          message: 'Expected JSON object envelope',
          statusCode: res.statusCode,
          path: '$method $path',
          rawBody: raw,
        );
      }
      return decoded;
    } catch (e) {
      throw ApiException(
        message: 'JSON decode failed',
        statusCode: res.statusCode,
        path: '$method $path',
        rawBody: raw,
      );
    }
  }
}

class ApiException implements Exception {
  ApiException({
    required this.message,
    required this.statusCode,
    required this.path,
    required this.rawBody,
  });

  final String message;
  final int statusCode;
  final String path;
  final String rawBody;

  @override
  String toString() =>
      'ApiException($statusCode $path): $message | body=$rawBody';
}
