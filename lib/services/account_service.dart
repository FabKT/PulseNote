import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import 'api_auth.dart';

class AccountService {
  AccountService._();

  static Future<void> deleteAccount() async {
    if (!ApiConfig.isConfigured) {
      throw Exception('Le service de suppression de compte est indisponible.');
    }

    final response = await http
        .delete(
          Uri.parse('${ApiConfig.backendBaseUrl}/account'),
          headers: await ApiAuth.headers(),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    var message = 'Suppression du compte impossible (${response.statusCode}).';
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is String && error.trim().isNotEmpty) message = error.trim();
    } catch (_) {}
    throw Exception(message);
  }
}
