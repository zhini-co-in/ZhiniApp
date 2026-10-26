import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'theme/app_theme.dart';
import 'constants/api_config.dart';
import 'services/api_client.dart';

class EditProviderProfileScreen extends StatefulWidget {
  final String mobileNumber;
  final Map<String, dynamic> initialData; // GET endpoint irundha adhula vara data

  const EditProviderProfileScreen({
    super.key,
    required this.mobileNumber,
    this.initialData = const {},
  });

  @override
  State<EditProviderProfileScreen> createState() =>
      _EditProviderProfileScreenState();
}

class _EditProviderProfileScreenState extends State<EditProviderProfileScreen> {
  final _name = TextEditingController();
  final _shopName = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _pincode = TextEditingController();
  final _servicePincodes = TextEditingController();
  final _operatingHours = TextEditingController();
  final _gst = TextEditingController();
  final _upi = TextEditingController();

  static const _allCategories = [
    'Plumbing', 'Electrician', 'AC Service', 'Home Appliances',
    'Carpenter', 'Painting',
  ];
  final Set<String> _categories = {};
  bool _isAvailable = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    _name.text = d['name']?.toString() ?? '';
    _shopName.text = d['shopName']?.toString() ?? '';
    _email.text = d['email']?.toString() ?? '';
    _address.text = d['address']?.toString() ?? '';
    _pincode.text = d['pincode']?.toString() ?? '';
    _operatingHours.text = d['operatingHours']?.toString() ?? '';
    _gst.text = d['gstNumber']?.toString() ?? '';
    _upi.text = d['upiId']?.toString() ?? '';
    _servicePincodes.text =
        (d['servicePincodes'] as List?)?.join(', ') ?? '';
    _categories.addAll(((d['categories'] as List?) ?? []).map((e) => e.toString()));
    _isAvailable = d['isAvailable'] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final c in [_name, _shopName, _email, _address, _pincode,
      _servicePincodes, _operatingHours, _gst, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return _snack('Name venum');
    if (_pincode.text.trim().isNotEmpty && _pincode.text.trim().length != 6) {
      return _snack('Valid 6-digit pincode kudu');
    }

    final mobile = ApiConfig.stripCountryCode(widget.mobileNumber);
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'isAvailable': _isAvailable,
      if (_shopName.text.trim().isNotEmpty) 'shopName': _shopName.text.trim(),
      if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
      if (_address.text.trim().isNotEmpty) 'address': _address.text.trim(),
      if (_pincode.text.trim().isNotEmpty) 'pincode': _pincode.text.trim(),
      if (_operatingHours.text.trim().isNotEmpty)
        'operatingHours': _operatingHours.text.trim(),
      if (_gst.text.trim().isNotEmpty) 'gstNumber': _gst.text.trim(),
      if (_upi.text.trim().isNotEmpty) 'upiId': _upi.text.trim(),
      if (_servicePincodes.text.trim().isNotEmpty)
        'servicePincodes': _servicePincodes.text
            .split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      if (_categories.isNotEmpty) 'categories': _categories.toList(),
    };

    setState(() => _saving = true);
    try {
      final headers = Map<String, String>.from(await ApiClient.authHeaders())
        ..['Content-Type'] = 'application/json'
        ..['x-user-phone'] = mobile;

      final res = await http.put(
        Uri.parse(ApiConfig.updateProviderUrl),
        headers: headers,
        body: jsonEncode({...body, 'mobile': mobile}),
      );

      debugPrint('✏️ Update provider: ${res.statusCode} ${res.body}');
      if (!mounted) return;

      final json = jsonDecode(res.body);
      if (res.statusCode == 200 && json['success'] == true) {
        _snack('Profile updated');
        Navigator.pop(context, Map<String, dynamic>.from(json['data'] ?? body));
      } else {
        _snack(json['message']?.toString() ?? 'Update failed');
      }
    } catch (e) {
      debugPrint('⚠️ Update error: $e');
      if (mounted) _snack('Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primaryBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.primary, width: 2),
        ),
      );

  Widget _field(String label, TextEditingController c, String hint,
      {TextInputType? type, int maxLines = 1, int? maxLength,
       TextCapitalization cap = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 8),
          TextField(
            controller: c,
            keyboardType: type,
            maxLines: maxLines,
            maxLength: maxLength,
            textCapitalization: cap,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: _dec(hint).copyWith(counterText: ''),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      appBar: AppBar(
        backgroundColor: AppColors.scaffoldBg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textSecondary),
        title: Text('Edit profile',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 18)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Full name', _name, 'Your name'),
              _field('Shop name', _shopName, 'e.g. Ravi Services'),
              _field('Email', _email, 'you@example.com',
                  type: TextInputType.emailAddress),
              _field('Address', _address, 'City / service area', maxLines: 2),
              _field('Pincode', _pincode, 'e.g. 620001',
                  type: TextInputType.number, maxLength: 6),
              _field('Service pincodes (comma separated)', _servicePincodes,
                  'e.g. 620001, 620002'),
              _field('Operating hours', _operatingHours, 'e.g. 9 AM - 7 PM'),
              _field('GSTIN', _gst, 'e.g. 22AAAAA0000A1Z5',
                  cap: TextCapitalization.characters),
              _field('UPI ID', _upi, 'e.g. name@upi'),
              Text('Categories',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allCategories.map((c) {
                  final on = _categories.contains(c);
                  return FilterChip(
                    label: Text(c),
                    selected: on,
                    selectedColor: AppColors.primary,
                    backgroundColor: AppColors.cardBg,
                    labelStyle: TextStyle(
                        color: on ? AppColors.onPrimary : AppColors.textSecondary),
                    onSelected: (v) => setState(
                        () => v ? _categories.add(c) : _categories.remove(c)),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Available for jobs',
                    style: TextStyle(color: AppColors.textPrimary)),
                value: _isAvailable,
                activeTrackColor: AppColors.primary,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _saving
                      ? SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.onPrimary, strokeWidth: 2))
                      : Text('Save changes',
                          style: TextStyle(
                              color: AppColors.onPrimary, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}