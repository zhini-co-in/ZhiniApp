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
  bool removeWarrantyCard;

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
    this.removeWarrantyCard = false,
  })  : extraPhotos = extraPhotos ?? [],
        removedExtraUrls = removedExtraUrls ?? [];
}

class _PhotoItem {
  final String? url;
  final File? file;
  const _PhotoItem({this.url, this.file});
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
  bool _cardRemoved = false; // existing warranty card deleted (applied on save)
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

    final info = await extractCardInfo(file);
    if (!mounted) return;

    setState(() {
      _scanningCard = false;
      final found = <String>[];

      // warranty period: always updated from the card
      if (info.warranty != null) {
        _warranty.text = info.warranty!;
        found.add('warranty');
      }

      // other fields: only fill if the user hasn't typed anything
      void fill(TextEditingController c, String? v, String label) {
        if (v == null || v.isEmpty) return;
        if (c.text.trim().isEmpty) {
          c.text = v;
          found.add(label);
        }
      }

      fill(_shop, info.shop, 'purchased from');
      fill(_shopWarranty, info.shopWarranty, 'shop warranty');
      fill(_model, info.model, 'model no');
      fill(_serial, info.serial, 'serial no');

      if (found.isNotEmpty) {
        _cardMsg = 'Detected: ${found.join(', ')}. Please verify.';
        _cardMsgOk = true;
      } else {
        _cardMsg = 'Could not read details. Please enter them manually.';
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
      removeWarrantyCard: _card == null && _cardRemoved,
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
          colors: [
            Color(0xFF4BA3F0),
            Color(0xFF7EC0F8),
            Color(0xFFB8DFFC),
            Color(0xFFEAF6FF),
            Color(0xFFF5F8FF),
          ],
          stops: [0, 0.12, 0.25, 0.37, 0.5]);

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

  Widget _header(IconData icon, String title, {Widget? trailing}) => Row(
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
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      );

  Widget _pillBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      color: color, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
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

  // ── Warranty card + extra photos (same look as details screen) ──
  Color get _purple => AppColors.lightPurple;

  Widget _fileRow({
    required IconData fallbackIcon,
    required Color color,
    required Widget? thumb,
    required String title,
    required String subtitle,
    required bool enabled,
    required VoidCallback onView,
    required VoidCallback onDelete,
  }) {
    Widget act(IconData i, Color c, VoidCallback f) => IconButton(
          onPressed: enabled ? f : null,
          icon: Icon(i,
              size: 22,
              color: enabled ? c : AppColors.textMuted.withValues(alpha: 0.4)),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          visualDensity: VisualDensity.compact,
        );

    final placeholder = Icon(fallbackIcon, color: color, size: 22);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.cardBgAlt,
        border: Border.all(color: AppColors.borderSubtle),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: enabled ? onView : null,
            child: Container(
              width: 48,
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: thumb ?? Center(child: placeholder),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
              ],
            ),
          ),
          act(Icons.visibility_outlined, AppColors.primary, onView),
          act(Icons.delete_outline_rounded, AppColors.textPrimary, onDelete),
        ],
      ),
    );
  }

  Widget _imgOf(_PhotoItem it) => it.url != null
      ? Image.network(it.url!,
          fit: BoxFit.cover,
          cacheWidth: 200,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, color: AppColors.textMuted))
      : Image.file(it.file!, fit: BoxFit.cover, cacheWidth: 200);

  // Swipe viewer. If deletable, a delete icon removes the current photo
  // (staged until "Save Changes").
  void _openViewer(List<_PhotoItem> source, int start,
      {bool deletable = true}) {
    final items = List<_PhotoItem>.from(source);
    final controller = PageController(initialPage: start);
    var current = start;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatefulBuilder(
          builder: (ctx, setS) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              title: items.length > 1
                  ? Text('${current + 1} / ${items.length}',
                      style: const TextStyle(fontSize: 16))
                  : null,
              actions: [
                if (deletable)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () {
                      final it = items[current];
                      setState(() {
                        if (it.url != null) {
                          _existingUrls.remove(it.url);
                          _removedUrls.add(it.url!);
                        } else {
                          _extras.remove(it.file);
                        }
                      });
                      items.removeAt(current);
                      if (items.isEmpty) {
                        Navigator.pop(ctx);
                        return;
                      }
                      setS(() {
                        if (current >= items.length) current = items.length - 1;
                      });
                    },
                  ),
              ],
            ),
            body: PageView.builder(
              controller: controller,
              itemCount: items.length,
              onPageChanged: (i) => setS(() => current = i),
              itemBuilder: (_, i) {
                final it = items[i];
                return InteractiveViewer(
                  child: Center(
                    child: it.url != null
                        ? Image.network(it.url!, fit: BoxFit.contain)
                        : Image.file(it.file!, fit: BoxFit.contain),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _photosCard() {
    final total = _existingUrls.length + _extras.length;
    final canAdd = total < _maxExtra;
    final hasExistingCard = !_cardRemoved &&
        widget.existingWarrantyUrl != null &&
        widget.existingWarrantyUrl!.isNotEmpty;
    final hasCard = _card != null || hasExistingCard;

    final photoItems = <_PhotoItem>[
      for (final u in _existingUrls) _PhotoItem(url: u),
      for (final f in _extras) _PhotoItem(file: f),
    ];

    // ---------- warranty card thumb ----------
    Widget? cardThumb;
    if (_scanningCard) {
      cardThumb = Center(
        child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
      );
    } else if (_card != null) {
      cardThumb = Image.file(_card!, fit: BoxFit.cover, cacheWidth: 200);
    } else if (hasExistingCard) {
      cardThumb = Image.network(widget.existingWarrantyUrl!,
          fit: BoxFit.cover,
          cacheWidth: 200,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.broken_image_outlined, color: AppColors.textMuted));
    }

    final cardSubtitle = _scanningCard
        ? 'Reading details...'
        : _card != null
            ? 'New image'
            : hasExistingCard
                ? '1 image'
                : 'Not added';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ===== Warranty Card card =====
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(
                Icons.verified_outlined,
                'Warranty Card',
                trailing: _scanningCard
                    ? null
                    : hasCard
                        ? _pillBtn(Icons.edit_outlined, 'Replace', _purple,
                            _pickCard)
                        : _pillBtn(Icons.add_a_photo_outlined, 'Upload',
                            AppColors.primary, _pickCard),
              ),
              const SizedBox(height: 12),
              _fileRow(
                fallbackIcon: Icons.verified_outlined,
                color: AppColors.danger,
                thumb: cardThumb,
                title: 'Warranty Card',
                subtitle: cardSubtitle,
                enabled: hasCard && !_scanningCard,
                onView: () => _openViewer([
                  _card != null
                      ? _PhotoItem(file: _card)
                      : _PhotoItem(url: widget.existingWarrantyUrl),
                ], 0, deletable: false),
                onDelete: () => setState(() {
                  _card = null;
                  _cardMsg = null;
                  if (widget.existingWarrantyUrl != null &&
                      widget.existingWarrantyUrl!.isNotEmpty) {
                    _cardRemoved = true;
                  }
                }),
              ),
              if (_cardMsg != null) ...[
                const SizedBox(height: 6),
                Text(_cardMsg!,
                    style: TextStyle(
                        color: _cardMsgOk
                            ? AppColors.success
                            : AppColors.textMuted,
                        fontSize: 12)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ===== Extra Photos card =====
        _box(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(
                Icons.photo_library_outlined,
                'Extra Photos ($total)',
                trailing: canAdd
                    ? _pillBtn(Icons.add_a_photo_outlined, 'Upload',
                        AppColors.primary, _pickExtras)
                    : null,
              ),
              const SizedBox(height: 12),
              if (total == 0)
                Text('No photos added',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 14))
              else
                _fileRow(
                  fallbackIcon: Icons.photo_library_outlined,
                  color: _purple,
                  thumb: _imgOf(photoItems.first),
                  title: 'Device Photos ($total)',
                  subtitle: '$total image${total > 1 ? 's' : ''}',
                  enabled: true,
                  onView: () => _openViewer(photoItems, 0),
                  onDelete: () => setState(() {
                    _removedUrls.addAll(_existingUrls);
                    _existingUrls.clear();
                    _extras.clear();
                  }),
                ),
            ],
          ),
        ),
      ],
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
                    child:
                        Center(child: Image.network(u, fit: BoxFit.contain))),
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
class WarrantyCardInfo {
  final String? warranty;
  final String? shop;
  final String? shopWarranty;
  final String? model;
  final String? serial;
  const WarrantyCardInfo({
    this.warranty,
    this.shop,
    this.shopWarranty,
    this.model,
    this.serial,
  });
}

Future<WarrantyCardInfo> extractCardInfo(File file) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFile(file));
    debugPrint('🧾 OCR text: ${result.text}');
    return parseCardInfo(result.text);
  } catch (e) {
    debugPrint('❌ OCR error: $e');
    return const WarrantyCardInfo();
  } finally {
    recognizer.close();
  }
}

// kept so older callers still compile
Future<String?> extractWarrantyFromCard(File file) async =>
    (await extractCardInfo(file)).warranty;

const _periodUnit = r'(years?|yrs?|months?|mths?|days?)';

String _normPeriod(int n, String u) {
  final word =
      u.startsWith('y') ? 'year' : u.startsWith('m') ? 'month' : 'day';
  return '$n $word${n > 1 ? 's' : ''}';
}

// Lines that are only a label (used to detect a block of labels)
final _labelLine = RegExp(
  r'^(customer\s*name|product\s*name|product\s*description|model(\s*(no|number|num|name))?|serial\s*(no|number|num)|bill\s*(no|number|date)|invoice\s*(no|number|date)|purchase\s*date|date\s*of\s*purchase|warranty\s*period|contact\s*(no|number)|phone|name|address|order\s*(no|number)|dealer(\s*name)?|shop(\s*name)?|seller|retailer|purchased\s*from|sold\s*by)\.?\s*:?$',
  caseSensitive: false,
);

String _cleanVal(String s) =>
    s.replaceAll(RegExp(r'^[\s:\-#.]+'), '').replaceAll(RegExp(r'[\s,;:]+$'), '').trim();

String? _periodFrom(String s) {
  final m = RegExp(r'(\d{1,3})\s*-?\s*' + _periodUnit, caseSensitive: false)
      .firstMatch(s);
  if (m == null) return null;
  final n = int.tryParse(m.group(1)!);
  if (n == null || n <= 0) return null;
  return _normPeriod(n, m.group(2)!.toLowerCase());
}

// Finds the value for a label: same line ("Label : value"),
// or the matching position in the values block, or the next line.
String? _valueFor(List<String> lines, RegExp label,
    {bool needDigit = false}) {
  bool ok(String v) =>
      v.length >= 2 &&
      v.length <= 40 &&
      (!needDigit || RegExp(r'\d').hasMatch(v));

  for (var i = 0; i < lines.length; i++) {
    final m = label.firstMatch(lines[i]);
    if (m == null) continue;

    // 1) same line
    final same = _cleanVal(m.namedGroup('v') ?? '');
    if (ok(same)) return same;

    // 2) label block -> value at same position after the block
    var s = i, e = i;
    while (s > 0 && _labelLine.hasMatch(lines[s - 1])) {
      s--;
    }
    while (e < lines.length - 1 && _labelLine.hasMatch(lines[e + 1])) {
      e++;
    }
    final idx = e + 1 + (i - s);
    if (idx < lines.length && !_labelLine.hasMatch(lines[idx])) {
      final v = _cleanVal(lines[idx]);
      if (ok(v)) return v;
    }
  }
  return null;
}

WarrantyCardInfo parseCardInfo(String raw) {
  final lines = raw
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  final flat = lines.join(' ').toLowerCase();

  // ---- main warranty ----
  String? warranty;
  final wp = _valueFor(
      lines, RegExp(r'^warranty\s*period\b(?<v>.*)$', caseSensitive: false));
  if (wp != null) warranty = _periodFrom(wp);
  if (warranty == null) {
    for (final p in <String>[
      r'(?:warranty|guarantee)[^0-9]{0,40}(\d{1,3})\s*-?\s*' + _periodUnit,
      r'(\d{1,3})\s*-?\s*' +
          _periodUnit +
          r'(?:\s+[a-z]+){0,3}\s+(?:warranty|guarantee)',
    ]) {
      final m = RegExp(p).firstMatch(flat);
      if (m == null) continue;
      final n = int.tryParse(m.group(1)!);
      if (n == null || n <= 0) continue;
      warranty = _normPeriod(n, m.group(2)!);
      break;
    }
  }

  // ---- shop warranty ----
  String? shopWarranty;
  final sw = _valueFor(
      lines,
      RegExp(r'^(?:shop|dealer|seller|store)\s*warranty\b(?<v>.*)$',
          caseSensitive: false));
  if (sw != null) shopWarranty = _periodFrom(sw);

  // ---- purchased from ----
  var shop = _valueFor(
      lines,
      RegExp(
          r'^(?:purchased\s*from|bought\s*from|sold\s*by|dealer(?:\s*name)?|shop(?:\s*name)?|seller|retailer)(?!\s*warranty)\b(?<v>.*)$',
          caseSensitive: false));
  // fallback: company line like "Zhini Technologies Pvt. Ltd."
  shop ??= () {
    final re = RegExp(
        r'(pvt\.?\s*ltd|private\s*limited|\bltd\b|traders|enterprises|stores?\b|electronics|agencies)',
        caseSensitive: false);
    for (final l in lines) {
      if (re.hasMatch(l) && l.length <= 50) return _cleanVal(l);
    }
    return null;
  }();

  // ---- model number ----
  final model = _valueFor(
      lines,
      RegExp(r'^model\s*(?:no|number|num)?\.?\s*[:#\-]?(?<v>.*)$',
          caseSensitive: false),
      needDigit: true);

  // ---- serial number ----
  final serial = _valueFor(
      lines,
      RegExp(
          r'^(?:serial\s*(?:no|number|num)?|s\/n|sr\.?\s*no)\.?\s*[:#\-]?(?<v>.*)$',
          caseSensitive: false),
      needDigit: true);

  return WarrantyCardInfo(
    warranty: warranty,
    shop: shop,
    shopWarranty: shopWarranty,
    model: model,
    serial: serial,
  );
}

// kept so older callers still compile
String? parseWarrantyPeriod(String raw) => parseCardInfo(raw).warranty;