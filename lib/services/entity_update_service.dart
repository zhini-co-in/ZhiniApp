// lib/services/entity_update_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/api_config.dart';
import 'api_client.dart';

class EntityUpdateService {
  /// Backend-ல எந்த field(s) குடுக்கிறீங்களோ, அது மட்டும் update ஆகும்.
  /// homeId → address/pincode/name/mobile, deviceId → product/brand/warranty,
  /// roomId → roomName.
  static Future<Map<String, dynamic>> update({
    String? homeId,
    String? name,
    String? mobile,
    String? deviceId,
    String? roomId,
    String? address,
    String? pincode,
    String? product,
    String? brand,
    String? roomName,
    String? warranty,
  }) async {
    // homeId / deviceId / roomId — onnu aavadhu venum
    if (homeId == null && deviceId == null && roomId == null) {
      return {'success': false, 'message': 'homeId, deviceId or roomId is required'};
    }

    final body = <String, dynamic>{
      'homeId': ?homeId,
      'name': ?name,
      'mobile': ?mobile,
      'deviceId': ?deviceId,
      'roomId': ?roomId,
      'address': ?address,
      'pincode': ?pincode,
      'product': ?product,
      'brand': ?brand,
      'roomName': ?roomName,
      'warranty': ?warranty,
    };

    try {
      // ✅ ApiClient.put → x-auth-token + x-device-id + Content-Type automatic
      final response = await ApiClient.put(ApiConfig.updateEntityUrl, body: body);

      debugPrint('✏️ Update status: ${response.statusCode}');
      debugPrint('✏️ Update body: ${response.body}');

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? 'Updated',
          'recordsUpdated': data['recordsUpdated'],
        };
      }
      return {
        'success': false,
        'message': data['message']?.toString() ??
            data['error']?.toString() ??
            'Update failed (${response.statusCode})',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}