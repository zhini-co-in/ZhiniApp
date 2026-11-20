// lib/services/appliance_services_loader.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_ce/hive_ce.dart';
import '../constants/api_config.dart';
import 'api_client.dart';

class ApplianceServicesLoader {
  static const _cacheKey = 'applianceServicesTemplate';
  static const int _defaultHomeCount = 4;

  static final ValueNotifier<List<Map<String, dynamic>>> groups =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  static int homeGroupCount = _defaultHomeCount;

  static const Map<String, IconData> _iconMap = {
    'smartphone_rounded': Icons.smartphone_rounded,
    'laptop_mac_rounded': Icons.laptop_mac_rounded,
    'kitchen_rounded': Icons.kitchen_rounded,
    'tv_rounded': Icons.tv_rounded,
    'ac_unit_rounded': Icons.ac_unit_rounded,
    'local_laundry_service_rounded': Icons.local_laundry_service_rounded,
  };

  static Color _hex(String? hex) {
    try {
      return Color(int.parse((hex ?? '#2563EB').replaceFirst('#', '0xFF')));
    } catch (_) {
      return const Color(0xFF2563EB);
    }
  }

  static Future<void> load() async {
    final box = Hive.box('session');

    final cached = box.get(_cacheKey);
    if (cached is String) {
      try {
        _apply(jsonDecode(cached) as Map<String, dynamic>);
      } catch (e) {
        debugPrint('❌ Template cache parse error: $e');
        await box.delete(_cacheKey);
      }
    }

    try {
      final url = '${ApiConfig.templateUrl}/appliance_services';
      debugPrint('🧩 Template URL: $url');
      final res = await ApiClient.get(url);
      debugPrint('🧩 Template status: ${res.statusCode}');
      debugPrint('🧩 Template body: ${res.body}');

      if (res.statusCode == 200) {
        var data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['groups'] == null && data['data'] is Map) {
          data = Map<String, dynamic>.from(data['data'] as Map);
        }
        _apply(data);
        await box.put(_cacheKey, jsonEncode(data));
        debugPrint('🧩 Groups loaded: ${groups.value.length}');
      }
    } catch (e) {
      debugPrint('❌ Template load error: $e');
    }
  }

  static void _apply(Map<String, dynamic> t) {
    final appliances = (t['appliances'] as List? ?? []);
    final labelOf = {
      for (final a in appliances) a['value'].toString(): a['label'].toString(),
    };

    homeGroupCount = (t['home_group_count'] as num?)?.toInt() ??
        (t['homeGroupCount'] as num?)?.toInt() ??
        _defaultHomeCount;

    groups.value = (t['groups'] as List? ?? []).map<Map<String, dynamic>>((g) {
      return {
        'title': g['label'],
        'sub': g['sub'],
        'icon': _iconMap[g['icon']] ?? Icons.devices_other_rounded,
        'color': _hex(g['color']?.toString()),
        'show_on_home': g['show_on_home'] == true,
        'items': ((g['items'] as List?) ?? [])
            .map((v) => labelOf[v.toString()] ?? v.toString())
            .toList(),
      };
    }).toList();
  }
}