import 'dart:convert';

import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'api_auth.dart';

class SummaryService {
  Future<String> summarizeText(String text) async {
    if (ApiConfig.isConfigured) {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.backendBaseUrl}/summarize'),
            headers: await ApiAuth.headers(extra: {
              'content-type': 'application/json',
            }),
            body: jsonEncode({'text': text}),
          )
          .timeout(const Duration(minutes: 2));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['summary'] as String? ?? '';
      }
      throw Exception(_errorFromResponse(
        response.body,
        fallback: 'Resume impossible (${response.statusCode}).',
      ));
    }

    await Future.delayed(const Duration(seconds: 1));
    return '**Résumé IA (simulé)**\n\n'
        'Configurez BACKEND_BASE_URL au build pour utiliser le backend réel.';
  }

  String _errorFromResponse(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final details = json['details'];
      if (details is Map<String, dynamic>) {
        final message = details['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final error = json['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    } catch (_) {
      // Keep the fallback below.
    }
    return fallback;
  }
}
