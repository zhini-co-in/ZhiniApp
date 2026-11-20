// lib/services/banner_loader.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import '../constants/api_config.dart';
import 'api_client.dart';

class BannerLoader {
  static const _cacheKey = 'homeBanners';

  // Assets fallback: first install + offline-ku.
  static const List<String> _fallback = [
    'assets/images/banner_ac.png',
    'assets/images/banner_appliance.png',
    'assets/images/banner_fridge.png',
  ];

  // Each item: image path/URL string (http... = network, else asset).
  static final ValueNotifier<List<String>> banners =
      ValueNotifier<List<String>>(_fallback);

  static String? _imageOf(dynamic b) {
    if (b is String) return b.trim().isEmpty ? null : b.trim();
    if (b is! Map) return null;
    for (final k in const ['imageUrl', 'image', 'url', 'src', 'img']) {
      final v = b[k]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  static void _apply(List list) {
    final urls = list.map(_imageOf).whereType<String>().toList();
    if (urls.isNotEmpty) banners.value = urls;
  }

  static Future<void> load() async {
    final box = Hive.box('session');

    final cached = box.get(_cacheKey);
    if (cached is String) {
      try {
        _apply(jsonDecode(cached) as List);
      } catch (e) {
        debugPrint('❌ Banner cache parse error: $e');
        await box.delete(_cacheKey);
      }
    }

    try {
      final res = await ApiClient.get(ApiConfig.bannersUrl);
      debugPrint('🖼️ Banner status: ${res.statusCode}');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data is Map ? data['banners'] : data;
        if (list is List && list.isNotEmpty) {
          _apply(list);
          await box.put(_cacheKey, jsonEncode(list));
          debugPrint('🖼️ Banners loaded: ${banners.value.length}');
        }
      }
    } catch (e) {
      debugPrint('❌ Banner load error: $e');
    }
  }
}