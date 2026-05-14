import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

const _kakaoRestApiKey = String.fromEnvironment('KAKAO_REST_API_KEY');
const _redirectUri = 'https://love-app-4e2ac.web.app';
const _fsBase = 'https://firestore.googleapis.com/v1/projects/love-app-4e2ac/databases/(default)/documents';

class KakaoService {
  static String? pendingCode;

  static String getAuthUrl() =>
      'https://kauth.kakao.com/oauth/authorize'
      '?client_id=$_kakaoRestApiKey'
      '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
      '&response_type=code'
      '&scope=talk_message';

  static Future<String?> _idToken() async {
    try {
      return await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {
      return null;
    }
  }

  static Future<bool> exchangeAndSave(String code) async {
    try {
      final res = await http.post(
        Uri.parse('https://kauth.kakao.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=authorization_code'
            '&client_id=$_kakaoRestApiKey'
            '&redirect_uri=${Uri.encodeComponent(_redirectUri)}'
            '&code=$code',
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 21600;
      if (accessToken == null || refreshToken == null) return false;
      await _saveTokens(null, accessToken, refreshToken, expiresIn);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _saveTokens(
      String? uid, String accessToken, String refreshToken, int expiresIn) async {
    final token = await _idToken();
    if (token == null) return;
    final targetUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (targetUid == null) return;
    final expiresAt = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
    await http.patch(
      Uri.parse('$_fsBase/users/$targetUid'
          '?updateMask.fieldPaths=kakaoAccessToken'
          '&updateMask.fieldPaths=kakaoRefreshToken'
          '&updateMask.fieldPaths=kakaoExpiresAt'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'fields': {
          'kakaoAccessToken': {'stringValue': accessToken},
          'kakaoRefreshToken': {'stringValue': refreshToken},
          'kakaoExpiresAt': {'integerValue': '$expiresAt'},
        }
      }),
    );
  }

  static Future<bool> isConnected() async {
    try {
      final token = await _idToken();
      if (token == null) return false;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;
      final res = await http.get(
        Uri.parse('$_fsBase/users/$uid'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>? ?? {};
        final rtMap = fields['kakaoRefreshToken'] as Map<String, dynamic>?;
        final rt = rtMap?['stringValue'] as String?;
        return rt != null && rt.isNotEmpty;
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> notifyPartner(String message) async {
    try {
      final token = await _idToken();
      if (token == null) return false;
      final currentUid = FirebaseAuth.instance.currentUser?.uid;

      final res = await http.get(
        Uri.parse('$_fsBase/users'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode != 200) return false;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final docs = (data['documents'] as List?) ?? [];

      for (final doc in docs) {
        final d = doc as Map<String, dynamic>;
        final uid = (d['name'] as String).split('/').last;
        if (uid == currentUid) continue;

        final fields = d['fields'] as Map<String, dynamic>? ?? {};
        var accessToken = (fields['kakaoAccessToken'] as Map<String, dynamic>?)?['stringValue'] as String?;
        final refreshToken = (fields['kakaoRefreshToken'] as Map<String, dynamic>?)?['stringValue'] as String?;
        final expiresAtStr = (fields['kakaoExpiresAt'] as Map<String, dynamic>?)?['integerValue'] as String?;
        final expiresAt = expiresAtStr != null ? int.tryParse(expiresAtStr) : null;

        if (refreshToken == null) continue;

        if (accessToken == null ||
            (expiresAt != null &&
                DateTime.now().millisecondsSinceEpoch > expiresAt - 60000)) {
          accessToken = await _refreshAndUpdate(uid, refreshToken, token);
        }
        if (accessToken == null) continue;

        return await _sendMessage(accessToken, message);
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> _refreshAndUpdate(
      String uid, String refreshToken, String idToken) async {
    try {
      final res = await http.post(
        Uri.parse('https://kauth.kakao.com/oauth/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token'
            '&client_id=$_kakaoRestApiKey'
            '&refresh_token=$refreshToken',
      );
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final newAccess = data['access_token'] as String?;
      final newRefresh = data['refresh_token'] as String?;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 21600;
      if (newAccess == null) return null;

      final expiresAt = DateTime.now().millisecondsSinceEpoch + expiresIn * 1000;
      final body = <String, dynamic>{
        'kakaoAccessToken': {'stringValue': newAccess},
        'kakaoExpiresAt': {'integerValue': '$expiresAt'},
      };
      var mask = '?updateMask.fieldPaths=kakaoAccessToken&updateMask.fieldPaths=kakaoExpiresAt';
      if (newRefresh != null) {
        body['kakaoRefreshToken'] = {'stringValue': newRefresh};
        mask += '&updateMask.fieldPaths=kakaoRefreshToken';
      }
      await http.patch(
        Uri.parse('$_fsBase/users/$uid$mask'),
        headers: {'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json'},
        body: jsonEncode({'fields': body}),
      );
      return newAccess;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _sendMessage(String accessToken, String message) async {
    try {
      final templateObject = jsonEncode({
        'object_type': 'text',
        'text': message,
        'link': {
          'web_url': _redirectUri,
          'mobile_web_url': _redirectUri,
        },
        'button_title': '앱 열기',
      });
      final res = await http.post(
        Uri.parse('https://kapi.kakao.com/v2/api/talk/memo/default/send'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: 'template_object=${Uri.encodeComponent(templateObject)}',
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
