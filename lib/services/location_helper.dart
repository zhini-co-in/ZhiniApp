import 'package:geolocator/geolocator.dart';

/// Shared current-GPS helper (5 min cache, so permission popup repeat aagaadhu).
class LocationHelper {
  static Position? _cached;
  static DateTime? _at;

  static Future<Position?> current() async {
    if (_cached != null &&
        _at != null &&
        DateTime.now().difference(_at!) < const Duration(minutes: 5)) {
      return _cached;
    }
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      _cached = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      _at = DateTime.now();
      return _cached;
    } catch (_) {
      return null;
    }
  }
}