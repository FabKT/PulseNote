import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/subscription_tier.dart';
import 'api_auth.dart';

class EntitlementSnapshot {
  final SubscriptionTier tier;
  final int creditsRemaining;
  final DateTime? creditsResetAt;
  final DateTime? subscriptionExpiresAt;

  const EntitlementSnapshot({
    required this.tier,
    required this.creditsRemaining,
    this.creditsResetAt,
    this.subscriptionExpiresAt,
  });

  factory EntitlementSnapshot.fromJson(Map<String, dynamic> json) {
    final tierName = json['tier'] as String? ?? 'free';
    return EntitlementSnapshot(
      tier: SubscriptionTier.values.firstWhere(
        (value) => value.name == tierName,
        orElse: () => SubscriptionTier.free,
      ),
      creditsRemaining: (json['creditsRemaining'] as num?)?.toInt() ?? 0,
      creditsResetAt:
          DateTime.tryParse(json['creditsResetAt'] as String? ?? ''),
      subscriptionExpiresAt:
          DateTime.tryParse(json['subscriptionExpiresAt'] as String? ?? ''),
    );
  }
}

class EntitlementService {
  EntitlementService._();

  static Future<EntitlementSnapshot> fetch() => _request(
        method: 'GET',
        path: '/me/entitlements',
      );

  static Future<EntitlementSnapshot> verifyPurchase({
    required String productId,
    required String purchaseToken,
  }) =>
      _request(
        method: 'POST',
        path: '/billing/verify',
        body: {
          'productId': productId,
          'purchaseToken': purchaseToken,
        },
      );

  static Future<EntitlementSnapshot> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    if (!ApiConfig.isConfigured) {
      throw Exception('Backend de production non configuré.');
    }
    final uri = Uri.parse('${ApiConfig.backendBaseUrl}$path');
    final headers = await ApiAuth.headers(
      extra: body == null ? null : {'content-type': 'application/json'},
    );
    final response = method == 'POST'
        ? await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 45))
        : await http
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 45));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Vérification des droits impossible.';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        if (payload['error'] is String) message = payload['error'] as String;
      } catch (_) {}
      throw Exception(message);
    }
    return EntitlementSnapshot.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }
}
