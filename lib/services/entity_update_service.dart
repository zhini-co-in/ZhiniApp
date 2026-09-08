// lib/services/entity_update_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/api_config.dart';

class EntityUpdateService {
  /// Backend-ல எந்த field(s) குடுக்கிறீங்களோ, அது மட்டும் update ஆகும்.
  /// homeId → address/pincode/name/mobile, deviceId → product/brand, roomId → roomName.
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
    if (homeId == null) {
  return {'success': false, 'message': 'homeId mandatory'};
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
      final response = await http.put( // route POST ஆ இருந்தா இதை மாத்துங்க
        Uri.parse(ApiConfig.updateEntityUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message']?.toString() ?? 'Updated',
          'recordsUpdated': data['recordsUpdated'],
        };
      }
      return {
  'success': false,
  'message': data['message']?.toString() ?? data['error']?.toString() ?? 'Update failed',
};
    } catch (e) {
      return {'success': false, 'message': 'Network error: $e'};
    }
  }
}