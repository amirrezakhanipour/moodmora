import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient{required this.baseUrl, http.Client? client} : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Uri _uri(String path) => Uri.parse('\$baseUrl\$path');

  Future<Map<String, dynamic>> getJson(String path) async {
    final res = await _client.get(_uri(path));
    return _handle(res, path);
  }

  Future<Map<String, dynamic>> postJson(String path, {required Map<String, dynamic> body, }) async {
    final res = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return _handle(res, path);
  }

  Map<String, dynamic> _handle(http.Response res, String path) {
    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw ApiException(
        message: 'Expected JSON but got: \$contentType',
        statusCode: res.statusCode,
        path: path,
        rawBody: res.body,
      );
    }
    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        message: 'Expected JSON object envelope',
        statusCode: res.statusCode,
        path: path,
        rawBody: res.body,
      );
    }
    return decoded;
  }
}

class ApiException implements Exception {
  ApiException{required this.message, required this.statusCode, required this.path, required this.rawBody};

  final String message;
  final int statusCode;
  final String path;
  final String rawBody;

  @override
  String toString() =>
      'ApiException(\$statusCode \$path): \$message | body=\$rawBody';
}
