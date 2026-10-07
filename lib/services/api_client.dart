import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import '../constants/api_config.dart';
import 'device_id_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class ApiClient {
  ApiClient._();
  static String? mobile;
  /// FCM fail aanaalum home create block aagakoodadhu
static Future<String?> safeFcmToken() async {
  try {
    return await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 8));
  } catch (_) {
    return null;
  }
}

/// MultipartRequest ku (Content-Type multipart thaane set pannum)
static Future<Map<String, String>> authHeaders() async {
  final h = await _headers();
  h.remove('Content-Type');
  return h;
}

  // Last token we successfully synced to the backend for this app run
  static String? _lastSyncedToken;

  /// Logout la call pannu
  static void reset() {
    mobile = null;
    _lastSyncedToken = null;
  }

  static String? _plainPhone() {
    final raw = mobile ?? FirebaseAuth.instance.currentUser?.phoneNumber;
    if (raw == null) return null;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  // Token maarina mattum backend DB la authToken update pannum
  static Future<void> _syncSession(String token) async {
    if (token == _lastSyncedToken) return;
    final phone = _plainPhone();
    if (phone == null) return;
    try {
      final res = await http
          .post(
            Uri.parse(ApiConfig.sessionSyncUrl),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'x-auth-token': token,
              'x-device-id': await DeviceIdService.getDeviceId(),
            },
            body: jsonEncode({'mobile': phone}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) _lastSyncedToken = token;
      // 404 = user innum create aagala (first-time, createHome apparam), ignore
    } catch (_) {
      // network fail: actual call la thirumba try pannum
    }
  }

  static Future<Map<String, String>> _headers({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken(forceRefresh);
    if (token != null) await _syncSession(token);   // 👈 add
    final phone = _plainPhone();
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      'x-device-id': await DeviceIdService.getDeviceId(),
      if (token != null) 'x-auth-token': token,
      if (phone != null) 'x-user-phone': phone,
    };
  }

  static Future<http.Response> _send(
      Future<http.Response> Function(Map<String, String> h) call) async {
    var res = await call(await _headers()).timeout(const Duration(seconds: 30));
    if (res.statusCode == 401 && FirebaseAuth.instance.currentUser != null) {
      res = await call(await _headers(forceRefresh: true))
          .timeout(const Duration(seconds: 30));
    }
    return res;
  }

  static String? _enc(Object? b) => b == null ? null : (b is String ? b : jsonEncode(b));

  static Future<http.Response> get(String url) =>
      _send((h) => http.get(Uri.parse(url), headers: h));
  static Future<http.Response> post(String url, {Object? body}) =>
      _send((h) => http.post(Uri.parse(url), headers: h, body: _enc(body)));
  static Future<http.Response> put(String url, {Object? body}) =>
      _send((h) => http.put(Uri.parse(url), headers: h, body: _enc(body)));
  static Future<http.Response> delete(String url, {Object? body}) =>
      _send((h) => http.delete(Uri.parse(url), headers: h, body: _enc(body)));
}