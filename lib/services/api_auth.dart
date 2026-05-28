import '../config/api_config.dart';
import 'auth_service.dart';

class ApiAuth {
  ApiAuth._();

  static Future<Map<String, String>> headers({
    Map<String, String>? extra,
  }) async {
    final headers = <String, String>{...?extra};
    final firebaseToken = await AuthService.idToken();
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      headers['authorization'] = 'Bearer $firebaseToken';
      return headers;
    }
    if (ApiConfig.appClientToken.isNotEmpty) {
      headers['x-app-token'] = ApiConfig.appClientToken;
    }
    return headers;
  }
}
