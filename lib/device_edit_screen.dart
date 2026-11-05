// lib/device_edit_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

class DeviceEditData {
  String product;
  String brand;
  String warranty;
  String shop;
  String shopWarranty;
  String model;
  String serial;
  File? warrantyCard;
  List<File> extraPhotos;
  List<String> removedExtraUrls;

  DeviceEditData({
    this.product = '',
    this.brand = '',
    this.warranty = '',
    this.shop = '',
    this.shopWarranty = '',
    this.model = '',
    this.serial = '',
    this.warrantyCard,
    List<File>? extraPhotos,
    List<String>? removedExtraUrls,
  })  : extraPhotos = extraPhotos ?? [],
        removedExtraUrls = removedExtraUrls ?? [];
}

class DeviceEditScreen extends StatefulWidget {
  final String title;
  final DeviceEditData initial;
  final File? photoFile; // scan tab: captured photo
  final String? photoUrl; // saved device: network photo
  final List<String> existingExtraUrls;
  final String building; // unused (kept so old callers still compile)
  final IconData fallbackIcon;
    final bool photosEditable; // false = hide Photos card (backend update API doesn't support files)
  final String? existingWarrantyUrl;

  /// Return null on success, or an error message to show.
  final Future<String?> Function(DeviceEditData data) onSave;

  const DeviceEditScreen({
    super.key,
    this.title = 'Edit Device',
    required this.initial,
    required this.onSave,
    this.photoFile,
    this.photoUrl,
    this.existingExtraUrls = const [],
    this.building = '',
    this.fallbackIcon = Icons.devices_other_rounded,
        this.photosEditable = true,
        this.existingWarrantyUrl,
  });

  @override
  State<DeviceEditScreen> createState() => _DeviceEditScreenState();
}

class _DeviceEditScreenState extends State<DeviceEditScreen> {
  static const int _maxExtra = 10;

  late final TextEditingController _product,
      _brand,
      _warranty,
      _shop,
      _shopWarranty,
      _model,
      _serial;
  File? _card;
  late List<File> _extras;
  late List<String> _existingUrls;
  final List<String> _removedUrls = [];
  bool _scanningCard = false;
  bool _saving = false;
  String? _cardMsg;
  bool _cardMsgOk = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _product = TextEditingController(text: d.product);
    _brand = TextEditingController(text: d.brand);
    _warranty = TextEditingController(text: d.warranty);
    _shop = TextEditingController(text: d.shop);
    _shopWarranty = TextEditingController(text: d.shopWarranty);
    _model = TextEditingController(text: d.model);
    _serial = TextEditingController(text: d.serial);
    _card = d.warrantyCard;
    _extras = List<File>.from(d.extraPhotos);
    _existingUrls = List<String>.from(widget.existingExtraUrls);
  }

  @override
  void dispose() {
    for (final c in [
      _product, _brand, _warranty, _shop, _shopWarranty, _model, _serial
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _pickCard() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1600,
        maxHeight: 1600);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    setState(() {
      _card = file;
      _scanningCard = true;
      _cardMsg = null;
    });
    final period = await extractWarrantyFromCard(file);
    if (!mounted) return;
    setState(() {
      _scanningCard = false;
      if (period != null) {
        _warranty.text = period;
        _cardMsg = 'Warranty detected: $period';
        _cardMsgOk = true;
      } else {
        _cardMsg = 'Could not read warranty period. Please enter it manually.';
        _cardMsgOk = false;
      }
    });
  }

  Future<void> _pickExtras() async {
    final picked = await ImagePicker()
        .pickMultiImage(imageQuality: 70, maxWidth: 1280, maxHeight: 1280);
    if (picked.isEmpty || !mounted) return;
    setState(() {
      for (final x in picked) {
        if (_existingUrls.length + _extras.length < _maxExtra) {
          _extras.add(File(x.path));
        }
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _scanningCard) return;
    if (_product.text.trim().isEmpty) {
      _snack('Device name is required');
      return;
    }
    final data = DeviceEditData(
      product: _product.text.trim(),
      brand: _brand.text.trim(),
      warranty: _warranty.text.trim(),
      shop: _shop.text.trim(),
      shopWarranty: _shopWarranty.text.trim(),
      model: _model.text.trim(),
      serial: _serial.text.trim(),
      warrantyCard: _card,
      extraPhotos: _extras,
      removedExtraUrls: _removedUrls,
    );
    setState(() => _saving = true);
    final err = await widget.onSave(data);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      _snack(err);
      return;
    }
    Navigator.pop(context, data);
  }

  // ── UI helpers ──
  LinearGradient get _bg => ThemeController.isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF16406B), Color(0xFF0F2347), Color(0xFF0A1628)],
          stops: [0, 0.4, 1])
      : const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFD6E8FF), Color(0xFFF1F6FF), Color(0xFFF5F8FF)],
          stops: [0, 0.4, 1]);

  Widget _box({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderSubtle),
        ),
        child: child,
      );

  Widget _header(IconData icon, String title) => Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      );

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
        isDense: true,
        filled: true,
        fillColor: AppColors.cardBgAlt,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderSubtle)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderSubtle)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary)),
      );

  Widget _row(String label, TextEditingController c, {String hint = ''}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label,
                style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: TextField(
              controller: c,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
              decoration: _dec(hint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroImage() {
    Widget img;
    if (widget.photoFile != null) {
      img = Image.file(widget.photoFile!, fit: BoxFit.cover, cacheWidth: 400);
    } else if (widget.photoUrl != null && widget.photoUrl!.isNotEmpty) {
      img = Image.network(widget.photoUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(widget.fallbackIcon, size: 40, color: AppColors.primary));
    } else {
      img = Icon(widget.fallbackIcon, size: 40, color: AppColors.primary);
    }
    return Container(
      width: 100,
      height: 90,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: AppColors.primaryFaint,
          borderRadius: BorderRadius.circular(14)),
      child: Center(child: img),
    );
  }

  Widget _thumb(Widget image, {VoidCallback? onRemove}) => Stack(
        children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(width: 68, height: 68, child: image)),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      );
        Widget _photosCard() {
    final total = _existingUrls.length + _extras.length;
    final canAdd = total < _maxExtra;
    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(Icons.photo_library_outlined, 'Photos'),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _scanningCard ? null : _pickCard,
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primaryBorder)),
            icon: _scanningCard
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.primary))
                : Icon(
                    _card != null
                        ? Icons.check_circle
                        : Icons.add_a_photo_outlined,
                    size: 16,
                    color:
                        _card != null ? AppColors.success : AppColors.primary),
            label: Text(
              _scanningCard
                  ? 'Reading warranty card...'
                  : _card != null
                      ? 'Warranty card added (tap to change)'
                      : 'Upload warranty card',
              style: AppText.linkAction,
            ),
          ),
          if (_cardMsg != null) ...[
            const SizedBox(height: 6),
            Text(_cardMsg!,
                style: TextStyle(
                    color: _cardMsgOk ? AppColors.success : AppColors.textMuted,
                    fontSize: 12)),
          ],
          const SizedBox(height: 14),
          Text('Extra Photos ($total)',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: canAdd ? _pickExtras : null,
            style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.primaryBorder)),
            icon: Icon(Icons.add_photo_alternate_outlined,
                size: 16, color: AppColors.primary),
            label: Text(total == 0 ? 'Add extra photos' : 'Add more',
                style: AppText.linkAction),
          ),
          if (total > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 68,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final u in _existingUrls)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _thumb(
                          Image.network(u,
                              fit: BoxFit.cover,
                              cacheWidth: 200,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined)),
                          onRemove: () => setState(() {
                            _existingUrls.remove(u);
                            _removedUrls.add(u);
                          }),
                        ),
                      ),
                    for (int i = 0; i < _extras.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _thumb(
                          Image.file(_extras[i],
                              fit: BoxFit.cover, cacheWidth: 200),
                          onRemove: () => setState(() => _extras.removeAt(i)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

   Widget _photosViewCard() {
    final card = widget.existingWarrantyUrl;
    final hasCard = card != null && card.isNotEmpty;
    final urls = widget.existingExtraUrls;

    Widget tile(String u) => GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0),
                body: InteractiveViewer(
                    child: Center(child: Image.network(u, fit: BoxFit.contain))),
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _thumb(Image.network(u,
                fit: BoxFit.cover,
                cacheWidth: 200,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image_outlined))),
          ),
        );

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Text(t,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
        );

    return _box(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(Icons.photo_library_outlined, 'Photos'),
          label('Warranty Card'),
          if (hasCard)
                        Row(children: [tile(card)])
          else
            Text('No warranty card added',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          label('Extra Photos (${urls.length})'),
          if (urls.isNotEmpty)
            SizedBox(
              height: 68,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [for (final u in urls) tile(u)]),
              ),
            )
          else
            Text('No extra photos yet',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          const SizedBox(height: 10),
          Text('Photos can be added while scanning a new device.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.notifier,
      builder: (context, _, __) => Scaffold(
        backgroundColor: AppColors.scaffoldBg,
        body: Container(
          decoration: BoxDecoration(gradient: _bg),
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back_rounded,
                          color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(widget.title,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _box(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _heroImage(),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(TextSpan(
                                    text: 'Device Name',
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 13),
                                    children: [
                                      TextSpan(
                                          text: ' *',
                                          style: TextStyle(
                                              color: AppColors.danger))
                                    ],
                                  )),
                                  const SizedBox(height: 6),
                                  TextField(
                                    controller: _product,
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 15),
                                    decoration: _dec('e.g. Air Conditioner'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _box(
                        child: Column(
                          children: [
                            _header(Icons.info_outline_rounded,
                                'Device Information'),
                            const SizedBox(height: 12),
                            _row('Brand', _brand, hint: 'e.g. Daikin'),
                            _row('Warranty', _warranty, hint: 'e.g. 2 years'),
                            _row('Purchased From', _shop,
                                hint: 'Shop / website'),
                            _row('Shop Warranty', _shopWarranty,
                                hint: 'Optional'),
                            _row('Model Number', _model, hint: 'Optional'),
                            _row('Serial Number', _serial, hint: 'Optional'),
                          ],
                        ),
                      ),
                                                                                        const SizedBox(height: 12),
                      widget.photosEditable ? _photosCard() : _photosViewCard(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: BorderSide(color: AppColors.primaryBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text('Cancel',
                            style: TextStyle(
                                color: AppColors.primary, fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: (_saving || _scanningCard) ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.onPrimary))
                            : Text('Save Changes',
                                style: TextStyle(
                                    color: AppColors.onPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Warranty card OCR (shared) ──
Future<String?> extractWarrantyFromCard(File file) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFile(file));
    return parseWarrantyPeriod(result.text);
  } catch (e) {
    debugPrint('❌ OCR error: $e');
    return null;
  } finally {
    recognizer.close();
  }
}

String? parseWarrantyPeriod(String raw) {
  final text = raw.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  const unit = r'(years?|yrs?|months?|mths?|days?)';
  final patterns = <RegExp>[
    RegExp(r'(?:warranty|guarantee)[^0-9]{0,40}(\d{1,3})\s*-?\s*' + unit),
    RegExp(r'(\d{1,3})\s*-?\s*' +
        unit +
        r'(?:\s+[a-z]+){0,3}\s+(?:warranty|guarantee)'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(text);
    if (m == null) continue;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n <= 0) continue;
    final u = m.group(2)!;
    final word =
        u.startsWith('y') ? 'year' : u.startsWith('m') ? 'month' : 'day';
    return '$n $word${n > 1 ? 's' : ''}';
  }
  return null;
}