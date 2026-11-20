import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../constants/api_config.dart';
import 'api_client.dart';

class AccountService {
  static Future<Map<String, dynamic>> deleteAccount() async {
    try {
      final response = await ApiClient.delete(ApiConfig.deleteAccountUrl);
      debugPrint('🗑️ Delete status: ${response.statusCode}');
      debugPrint('🗑️ Delete body: ${response.body}');
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message']?.toString() ?? '',
      };
    } catch (e) {
      debugPrint('❌ Delete account error: $e');
      return {'success': false, 'message': ''};
    }
  }
}