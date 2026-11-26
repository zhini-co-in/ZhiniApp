// lib/services/home_services.dart
//
// Single shared place for "Services near you" (Home tab) and "Quick book"
// (Service tab): categories, fetch, counts and the bottom sheet.
// Backend (scrapeHomeServices) needs lat/lng, so ALWAYS coordinates:
//   registered home  -> that home's saved lat/lng
//   unregistered     -> current GPS lat/lng
//
// OFFLINE: every successful fetch is cached in the Hive 'session' box.
//  - Counts: a failed fetch is SKIPPED (never reported as 0), so the last
//    known count stays on screen.
//  - Provider list sheet: falls back to the last cached list.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import '../constants/api_config.dart';
import '../constants/app_strings.dart';
import '../service_category_sheet.dart';
import '../theme/app_theme.dart';
import '../utils/provider_sort.dart';
import 'api_client.dart';

class HomeServices {
  HomeServices._();

  static const List<Map<String, dynamic>> categories = [
    {'label': AppStrings.electrician, 'type': 'electrician', 'icon': Icons.bolt_rounded, 'color': Color(0xFFFF9800)},
    {'label': AppStrings.plumber, 'type': 'plumber', 'icon': Icons.build_rounded, 'color': Color(0xFF1E6BFF)},
    {'label': AppStrings.acService, 'type': 'AC service', 'icon': Icons.ac_unit_rounded, 'color': Color(0xFF2196F3)},
    {'label': AppStrings.carpenter, 'type': 'carpenter', 'icon': Icons.hardware_rounded, 'color': Color(0xFF7C4DFF)},
    {'label': AppStrings.painter, 'type': 'painter', 'icon': Icons.format_paint_rounded, 'color': Color(0xFFE91E63)},
    {'label': AppStrings.pestControl, 'type': 'pest control', 'icon': Icons.pest_control_rounded, 'color': Color(0xFF00A86B)},
  ];

  // ---------------------------------------------------------------------
  // CACHE (Hive 'session' box, opened in main.dart)
  // Key is based on coordinates only (2 decimals ~ 1 km).
  // ---------------------------------------------------------------------
  static String _cacheKey(
      String serviceType, double? latitude, double? longitude) {
    return 'svc:$serviceType:'
        '${latitude?.toStringAsFixed(2)},${longitude?.toStringAsFixed(2)}';
  }

  static void _writeCache(String key, List<Map<String, dynamic>> list) {
    try {
      Hive.box('session').put(key, jsonEncode(list));
    } catch (e) {
      debugPrint('❌ Home services cache write error: $e');
    }
  }

  static List<Map<String, dynamic>>? _readCache(String key) {
    try {
      final raw = Hive.box('session').get(key);
      if (raw is! String) return null;
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('❌ Home services cache read error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // FETCH
  // ---------------------------------------------------------------------

  /// Returns the providers, or **null if the request failed / no coordinates**
  /// (offline, server error, GPS not available). Empty list = "worked, none".
  static Future<List<Map<String, dynamic>>?> fetchOrNull(
    String serviceType,
    String pincode, {
    double? latitude,
    double? longitude,
  }) async {
    final pin = pincode.trim();

    // Backend needs coordinates. No coordinates -> don't call.
    if (latitude == null || longitude == null) return null;

    try {
      var url = '${ApiConfig.homeServicesUrl}'
          '?serviceType=${Uri.encodeQueryComponent(serviceType)}'
          '&latitude=$latitude&longitude=$longitude';
      // pincode is optional extra; backend ignores it if it only uses lat/lng.
      if (pin.isNotEmpty) url += '&pincode=${Uri.encodeQueryComponent(pin)}';

      final response = await ApiClient.post(url);
      debugPrint('🔧 Home services ($serviceType) status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final raw = data['data'];
          final List<dynamic> list =
              raw == null ? <dynamic>[] : (raw is List ? raw : [raw]);
          final sorted = ProviderSort.sort(
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
          _writeCache(_cacheKey(serviceType, latitude, longitude), sorted);
          return sorted;
        }
      }
    } catch (e) {
      debugPrint('❌ Home services fetch error ($serviceType): $e');
    }
    return null; // failed
  }

  /// Providers for [serviceType]. If the request fails, the last cached list
  /// is returned (or [] if there is none).
  static Future<List<Map<String, dynamic>>> fetch(
    String serviceType,
    String pincode, {
    double? latitude,
    double? longitude,
  }) async {
    final fresh = await fetchOrNull(serviceType, pincode,
        latitude: latitude, longitude: longitude);
    if (fresh != null) return fresh;

    return _readCache(_cacheKey(serviceType, latitude, longitude)) ?? [];
  }

  /// Fetches the count for every category; [onCount] is called as each
  /// finishes. A FAILED fetch is skipped, so the old count stays visible.
  static Future<void> prefetchCounts(
    String pincode,
    void Function(String type, int count) onCount, {
    double? latitude,
    double? longitude,
  }) async {
    if (latitude == null || longitude == null) return;
    await Future.wait(categories.map((cat) async {
      final type = cat['type'] as String;
      final list = await fetchOrNull(type, pincode,
          latitude: latitude, longitude: longitude);
      if (list == null) return; // offline / error -> keep last known count
      onCount(type, list.length);
    }));
  }

  /// Same bottom sheet for both tabs.
  static void openSheet(
    BuildContext context,
    Map<String, dynamic> category,
    String pincode, {
    double? latitude,
    double? longitude,
  }) {
    final type = category['type'] as String;
    final label = category['label'] as String;

    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Location edukka mudiyala. GPS on pannunga / location permission kudunga.')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (_) => ServiceCategorySheet(
        label: label,
        fetchServices: () => fetch(type, pincode,
            latitude: latitude, longitude: longitude),
      ),
    );
  }
}