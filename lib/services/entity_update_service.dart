import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/api_config.dart';
import 'api_client.dart';

class EntityUpdateService {
  /// Backend needs homeId always. Only the fields you pass get updated.
  static Future<Map<String, dynamic>> update({
    required String? homeId,
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
    String? modelNumber,
    String? serialNumber,
    String? purchasedShopName,
    String? shopWarranty,
  }) async {
    if (homeId == null || homeId.isEmpty) {
      return {'success': false, 'message': 'homeId is required'};
    }

    final body = <String, dynamic>{
      'homeId': homeId,
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
      'modelNumber': ?modelNumber,
      'serialNumber': ?serialNumber,
      'purchasedShopName': ?purchasedShopName,
      'shopWarranty': ?shopWarranty,
    };

    try {
      final http.Response response =
          await ApiClient.put(ApiConfig.updateEntityUrl, body: body);

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