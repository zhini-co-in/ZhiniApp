import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import '../constants/api_config.dart';

class LogService with WidgetsBindingObserver {
  LogService._();
  static final LogService instance = LogService._();

  // un backend la crashRoutes mount panna path ku match pannu
  static final String _endpoint = '${ApiConfig.baseUrl}/crash/add';

  final List<Map<String, dynamic>> _buffer = [];
  final String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  Timer? _timer;
  bool _sending = false;
  String? mobile;

  static const int _maxBuffer = 200;

  void init() {
    FirebaseCrashlytics.instance
        .setCrashlyticsCollectionEnabled(!kDebugMode);

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message != null) log('info', message);
    };

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      FirebaseCrashlytics.instance.recordFlutterFatalError(details);
      log('fatal', details.exceptionAsString(),
          stack: details.stack?.toString());
      flush();
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      log('fatal', error.toString(), stack: stack.toString());
      flush();
      return true;
    };

    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => flush());

    log('info', 'App opened');
    flush();
  }

  void log(String level, String message, {String? stack}) {
    if (!kDebugMode) FirebaseCrashlytics.instance.log('[$level] $message');
    if (_buffer.length >= _maxBuffer) _buffer.removeAt(0);
    _buffer.add({
      'level': level,
      'message': message,
      if (stack != null) 'stack': stack,
      'time': DateTime.now().toIso8601String(),
    });
  }

  Future<void> flush() async {
    if (_sending || _buffer.isEmpty) return;
    _sending = true;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();

    try {
      final res = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode({
              'data': {
                'sessionId': _sessionId,
                'mobile': mobile,
                'platform': Platform.operatingSystem,
                'osVersion': Platform.operatingSystemVersion,
                'appVersion': '1.0.3',
                'logs': batch,
              }
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 201) _buffer.insertAll(0, batch);
    } catch (_) {
      _buffer.insertAll(0, batch);
    } finally {
      _sending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      flush();
    }
  }
}