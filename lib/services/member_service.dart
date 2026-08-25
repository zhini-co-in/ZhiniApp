// lib/services/member_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:hive_ce/hive_ce.dart';
import '../constants/api_config.dart';
import '../models/home_model.dart';

/// Shared Add/Delete-member calls + single-home Hive refresh, so every
/// screen (HomeTab, ProfileTab, ...) that listens to the 'homes' box
/// updates immediately after a member is added/removed — matches the
/// addMember / deleteMember backend controllers exactly.
class MemberService {
  static Box<HomeModel> get _homeBox => Hive.box<HomeModel>('homes');

  /// POST addMember — homeId, myMobile, newName, newMobile all required
  /// server-side (400 if missing, 400 if self-add, 404 if requester/home
  /// not found, 400 if already a member).
  static Future<Map<String, dynamic>> addMember({
    required String homeId,
    required String myMobile,
    required String newName,
    required String newMobile,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.memberAddUrl),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'homeId': homeId,
          'myMobile': myMobile,
          'newName': newName,
          'newMobile': newMobile,
        }),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message']?.toString() ?? 'Could not add member.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error. Try again.'};
    }
  }

  /// DELETE deleteMember/:homeId — mobile in body. Backend blocks
  /// removing the primary owner (CANNOT_REMOVE_OWNER) — that message
  /// comes straight through, no special handling needed on our side.
  static Future<Map<String, dynamic>> deleteMember({
    required String homeId,
    required String mobile,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse(ApiConfig.memberDeleteUrl(homeId)),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'mobile': mobile}),
      );
      final data = jsonDecode(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'message': data['message']?.toString() ?? 'Could not remove member.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Network error. Try again.'};
    }
  }

  /// Re-fetches just this one home (same &homeId= single-home path the
  /// backend already supports) and patches its members[] back into the
  /// Hive box in place — rooms/address untouched, no full home-list
  /// refresh needed.
  static Future<void> refreshHomeMembers({
    required String homeId,
    required String mobileNumber,
  }) async {
    try {
      final plainMobile = ApiConfig.stripCountryCode(mobileNumber);
      final response = await http.get(
        Uri.parse('${ApiConfig.submissionSearchUrl}?mobile=$plainMobile&homeId=$homeId'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['data'] == null) return;

      final rawData = data['data'];
      final rawHome = (rawData is List ? rawData.first : rawData) as Map;

      final membersRaw = rawHome['members'];
      final members = membersRaw is List
          ? membersRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];

      for (int i = 0; i < _homeBox.length; i++) {
        final model = _homeBox.getAt(i);
        if (model == null) continue;
        final map = model.toMap();
        if (map['id']?.toString() != homeId) continue;

        map['members'] = members;
        await _homeBox.putAt(i, HomeModel.fromMap(map));
        break;
      }
    } catch (e) {
      // Best-effort — snackbar already reported the add/delete result;
      // worst case the list catches up on the next pull-to-refresh.
    }
  }
}