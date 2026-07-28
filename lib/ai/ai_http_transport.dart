import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AiHttpResponse {
  const AiHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract class AiHttpTransport {
  Future<AiHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  });
}

class IoAiHttpTransport implements AiHttpTransport {
  IoAiHttpTransport({this.timeout = const Duration(seconds: 90)});

  final Duration timeout;

  @override
  Future<AiHttpResponse> post(
    Uri uri, {
    required Map<String, String> headers,
    required String body,
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client.postUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      request.write(body);
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      return AiHttpResponse(statusCode: response.statusCode, body: text);
    } on TimeoutException {
      throw const AiRequestTransportException(
        'AI request timed out. Check the endpoint and try again.',
      );
    } on SocketException catch (error) {
      throw AiRequestTransportException(
        'Could not reach the AI endpoint: ${error.message}',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class AiRequestTransportException implements Exception {
  const AiRequestTransportException(this.message);

  final String message;

  @override
  String toString() => message;
}
