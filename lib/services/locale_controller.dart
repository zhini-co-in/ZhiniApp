import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the app's currently selected locale and persists the choice so it
/// survives app restarts.
///
/// Usage:
///   1. Call `await LocaleController.instance.loadSavedLocale();` once in
///      `main()` before `runApp`.
///   2. Wrap your `MaterialApp` in an `AnimatedBuilder` (or
///      `ListenableBuilder`) that listens to `LocaleController.instance`, and
///      pass `locale: LocaleController.instance.locale` to the app.
///   3. Call `await LocaleController.instance.setLocale(Locale('hi'));`
///      whenever the user picks a language — the whole app rebuilds and the
///      choice is saved automatically.
class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const _prefsKey = 'app_locale_code';

  /// The 6 languages this app currently ships translations for.
  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('hi'),
    Locale('ta'),
    Locale('te'),
    Locale('kn'),
    Locale('ml'),
  ];

  /// Native display name for each language code — shown in the picker so
  /// people can find their own language without needing English literacy.
  static const Map<String, String> languageNames = {
    'en': 'English',
    'hi': 'हिन्दी (Hindi)',
    'ta': 'தமிழ் (Tamil)',
    'te': 'తెలుగు (Telugu)',
    'kn': 'ಕನ್ನಡ (Kannada)',
    'ml': 'മലയാളം (Malayalam)',
  };

  Locale _locale = const Locale('en');
  Locale get locale => _locale;

  /// Loads the previously-saved language, if any. Defaults to English
  /// (device locale is intentionally NOT auto-detected here, per product
  /// decision: language is chosen manually from Settings).
  Future<void> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null && supportedLocales.any((l) => l.languageCode == code)) {
      _locale = Locale(code);
      notifyListeners();
    }
  }

Future<void> setLocale(Locale locale) async {
  debugPrint('🌐 setLocale called with: ${locale.languageCode}, current: ${_locale.languageCode}');
  if (_locale == locale) return;
  _locale = locale;
  notifyListeners();
  debugPrint('🌐 notifyListeners called, _locale is now: ${_locale.languageCode}');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_prefsKey, locale.languageCode);
}
}