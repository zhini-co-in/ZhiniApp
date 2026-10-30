// lib/services/home_services.dart
//
// Single shared place for "Services near you" (Home tab) and "Quick book"
// (Service tab): categories, pincode-based fetch, counts and the bottom sheet.
// No GPS — only the saved pincode is used.

import 'dart:convert';
import 'package:flutter/material.dart';
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

  /// Providers for [serviceType] near [pincode]. Empty pincode -> empty list.
  static Future<List<Map<String, dynamic>>> fetch(String serviceType, String pincode) async {
    final pin = pincode.trim();
    if (pin.isEmpty) return [];
    try {
      final response = await ApiClient.post(
        '${ApiConfig.homeServicesUrl}'
        '?serviceType=${Uri.encodeQueryComponent(serviceType)}'
        '&pincode=${Uri.encodeQueryComponent(pin)}',
      );
      debugPrint('🔧 Home services ($serviceType) status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final raw = data['data'];
          final List<dynamic> list = raw is List ? raw : [raw];
          return ProviderSort.sort(
            list.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Home services fetch error ($serviceType): $e');
    }
    return [];
  }

  /// Fetches the count for every category; [onCount] is called as each finishes.
  static Future<void> prefetchCounts(
    String pincode,
    void Function(String type, int count) onCount,
  ) async {
    await Future.wait(categories.map((cat) async {
      final type = cat['type'] as String;
      final list = await fetch(type, pincode);
      onCount(type, list.length);
    }));
  }

  /// Same bottom sheet for both tabs.
  static void openSheet(
    BuildContext context,
    Map<String, dynamic> category,
    String pincode,
  ) {
    final type = category['type'] as String;
    final label = category['label'] as String;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (_) => ServiceCategorySheet(
        label: label,
        fetchServices: () => fetch(type, pincode),
      ),
    );
  }
}