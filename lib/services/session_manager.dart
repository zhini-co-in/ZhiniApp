import 'package:hive_ce/hive_ce.dart';

class SessionManager {
  static const _boxName = 'session';

  static const _keyMobile = 'mobileNumber';
  static const _keyAddress = 'address';
  static const _keyPincode = 'pincode';
  static const _keyName = 'name';
  static const _keyHomeId = 'homeId';

  static Box get _box => Hive.box(_boxName);

  static Future<void> saveSession({
    required String mobileNumber,
    required String address,
    required String pincode,
    required String name,
    String? homeId,
  }) async {
    await _box.put(_keyMobile, mobileNumber);
    await _box.put(_keyAddress, address);
    await _box.put(_keyPincode, pincode);
    await _box.put(_keyName, name);
    if (homeId != null) {
      await _box.put(_keyHomeId, homeId);
    }
  }

  static Future<void> updateHomeId(String homeId) async {
    await _box.put(_keyHomeId, homeId);
  }

  static Future<Map<String, String>?> getSession() async {
    final mobile = _box.get(_keyMobile) as String?;
    if (mobile == null) return null;
    return {
      'mobileNumber': mobile,
      'address': (_box.get(_keyAddress) as String?) ?? '',
      'pincode': (_box.get(_keyPincode) as String?) ?? '',
      'name': (_box.get(_keyName) as String?) ?? '',
      'homeId': (_box.get(_keyHomeId) as String?) ?? '',
    };
  }

  static Future<void> clearSession() async {
    await _box.clear();
  }
}