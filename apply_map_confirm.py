import re, shutil, os

failed = 0

def patch(path, edits):
    global failed
    if not os.path.exists(path):
        print(f'!! {path} not found (run from the ZhiniApp folder)')
        failed += 1
        return
    src = open(path, encoding='utf-8').read()
    shutil.copyfile(path, path + '.bak6')
    print(f'--- {path}')
    for name, pattern, repl, count in edits:
        found = len(re.findall(pattern, src))
        if found != count:
            print(f'SKIP  {name}  (found {found}, expected {count})')
            failed += 1
            continue
        src = re.sub(pattern, lambda m: repl, src)
        print(f'OK    {name}')
    open(path, 'w', encoding='utf-8').write(src)

# ───────────── map_picker_screen.dart : can start at a given point ─────────────
patch('lib/map_picker_screen.dart', [
    ('constructor + start point',
     r"const MapPickerScreen\(\{super\.key\}\);",
     "// If lat/lng are given the map opens there (typed address / current location).\n"
     "  final double? initialLat;\n"
     "  final double? initialLng;\n\n"
     "  const MapPickerScreen({super.key, this.initialLat, this.initialLng});", 1),
    ('initial centre',
     r"late LatLng _center = _fallback;",
     "late LatLng _center = (widget.initialLat != null && widget.initialLng != null)\n"
     "      ? LatLng(widget.initialLat!, widget.initialLng!)\n"
     "      : _fallback;", 1),
    ('skip GPS when a start point is given',
     r"_scheduleGeocode\(\);\s*_goToMyLocation\(\);\s*\}",
     "_scheduleGeocode();\n    if (widget.initialLat == null) _goToMyLocation();\n  }", 1),
    ('hint text',
     r"Move the map to set your location",
     "Move the map so the pin is on your exact location", 1),
])

# ───────────── address_screen.dart : confirm pin before saving ─────────────
CONFIRM_METHOD = '''// Remembers where the pin was last set (current location / map pick),
  // so the confirm-map opens exactly there.
  double? _pinLat;
  double? _pinLng;
  String _pinKey = '';

  String _addressKey() =>
      '${_addressController.text.trim()}|${_cityController.text.trim()}|${_pincodeController.text.trim()}';

  // Swiggy / Zomato style: before saving, show the map with a pin on the
  // entered address (or current location). User adjusts it and confirms.
  Future<PickedLocation?> _confirmPinOnMap(
      String address, String city, String pincode) async {
    double? lat;
    double? lng;

    if (_pinLat != null && _pinLng != null && _pinKey == _addressKey()) {
      lat = _pinLat;
      lng = _pinLng;
    } else {
      try {
        final found = await locationFromAddress('$address, $city $pincode');
        if (found.isNotEmpty) {
          lat = found.first.latitude;
          lng = found.first.longitude;
        }
      } catch (e) {
        debugPrint('❌ Forward geocode error: $e');
      }
    }

    if (!mounted) return null;
    return Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(initialLat: lat, initialLng: lng),
      ),
    );
  }

  Future<void> _saveAndContinue() async {'''

CONFIRM_CALL = '''setState(() => _isSaving = true);

    // Confirm the exact location with a pin on the map.
    final pin = await _confirmPinOnMap(address, city, pincode);
    if (!mounted) return;
    if (pin == null) {
      setState(() => _isSaving = false);
      return;
    }

    final fullAddress ='''

patch('lib/address_screen.dart', [
    ('pin fields + _confirmPinOnMap',
     r"Future<void> _saveAndContinue\(\) async \{",
     CONFIRM_METHOD, 1),
    ('show map before saving',
     r"setState\(\(\) => _isSaving = true\);\s*final fullAddress =",
     CONFIRM_CALL, 1),
    ('remember pin: current location',
     r"_pincodeController\.text = resolved\.pincode;",
     "_pincodeController.text = resolved.pincode;\n"
     "      _pinLat = position.latitude;\n"
     "      _pinLng = position.longitude;\n"
     "      _pinKey = _addressKey();", 1),
    ('remember pin: pick on map',
     r"_pincodeController\.text = loc\.pincode;",
     "_pincodeController.text = loc.pincode;\n"
     "    _pinLat = loc.lat;\n"
     "    _pinLng = loc.lng;\n"
     "    _pinKey = _addressKey();", 1),
])

print(f'\nDone. {failed} problem(s).  Backups: *.bak6')
