import re, shutil, os

path = 'lib/address_screen.dart'
if not os.path.exists(path):
    raise SystemExit(f'{path} not found (run from the ZhiniApp folder)')
if not os.path.exists('lib/map_picker_screen.dart'):
    raise SystemExit('lib/map_picker_screen.dart not found. Create it first (the map picker file).')

src = open(path, encoding='utf-8').read()
shutil.copyfile(path, path + '.bak5')
failed = 0

def edit(name, pattern, repl, count=1):
    global src, failed
    found = len(re.findall(pattern, src))
    if found != count:
        print(f'SKIP  {name}  (found {found}, expected {count})')
        failed += 1
        return
    src = re.sub(pattern, lambda m: repl.replace('<<G1>>', m.group(1) if m.groups() else ''), src)
    print(f'OK    {name}')

edit('import map picker', r"import 'main_shell\.dart';",
     "import 'main_shell.dart';\nimport 'map_picker_screen.dart';")

PICK_METHOD = '''// "Pick on map" — Swiggy/Zomato style pin, then autofill the form.
  Future<void> _pickOnMap() async {
    final loc = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(builder: (_) => const MapPickerScreen()),
    );
    if (loc == null || !mounted) return;

    String street = loc.address;
    String city = '';
    try {
      final list = await placemarkFromCoordinates(loc.lat, loc.lng);
      if (list.isNotEmpty) {
        final p = list.first;
        city = p.locality ?? p.subAdministrativeArea ?? '';
        final bits = [p.name, p.street, p.subLocality]
            .where((e) => e != null && e.isNotEmpty)
            .toSet()
            .join(', ');
        if (bits.isNotEmpty) street = bits;
      }
    } catch (e) {
      debugPrint('❌ Map reverse geocode error: $e');
    }

    _addressController.text = street;
    _cityController.text = city;
    _pincodeController.text = loc.pincode;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Location set from map. Add your flat / landmark and review.')),
    );
  }

  Future<void> _saveAndContinue() async {'''
edit('add _pickOnMap method', r"Future<void> _saveAndContinue\(\) async \{", PICK_METHOD)

BUTTON = '''const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: anyActionInProgress ? null : _pickOnMap,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.map_outlined,
                          size: 18, color: AppColors.primary),
                      label: const Text('Pick on map',
                          style: TextStyle(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.center,'''
edit('add "Pick on map" button',
     r"const SizedBox\(height: 12\),\s*Align\(\s*alignment: Alignment\.center,", BUTTON)

open(path, 'w', encoding='utf-8').write(src)
print(f'\nDone. {failed} problem(s). Backup: {path}.bak5')
