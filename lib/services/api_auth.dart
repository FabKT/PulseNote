import '../config/api_config.dart';
import 'auth_service.dart';

class ApiAuth {
  ApiAuth._();

  static Future<Map<String, String>> headers({
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{...?extra};
    final supabaseToken = await AuthService.idToken();
    if (supabaseToken != null && supabaseToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $supabaseToken';
      return headers;
    }
    if (ApiConfig.appClientToken.isNotEmpty) {
      headers['x-app-token'] = ApiConfig.appClientToken;
    }
    return headers;
  }
}
