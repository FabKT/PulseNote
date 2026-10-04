import 'auth_service.dart';

class ApiAuth {
  ApiAuth._();

  // Le backend n'accepte plus de jeton applicatif partage : seules les
  // sessions Supabase authentifient les appels.
  static Future<Map<String, String>> headers({
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{...?extra};
    final supabaseToken = await AuthService.idToken();
    if (supabaseToken != null && supabaseToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $supabaseToken';
    }
    return headers;
  }
}
