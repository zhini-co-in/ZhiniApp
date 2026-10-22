// lib/service_category_sheet.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';
import 'widgets/service_provider_card.dart';

/// Bottom sheet listing nearby providers for one service category.
class ServiceCategorySheet extends StatefulWidget {
  final String label;
  final Future<List<Map<String, dynamic>>> Function() fetchServices;

  const ServiceCategorySheet({
    super.key,
    required this.label,
    required this.fetchServices,
  });

  @override
  State<ServiceCategorySheet> createState() => _ServiceCategorySheetState();
}

class _ServiceCategorySheetState extends State<ServiceCategorySheet> {
  static const int _pageSize = 5;
  static const int _maxResults = 20;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = [];
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 0;
    });

    final results = await widget.fetchServices();

    if (!mounted) return;
    setState(() {
      _services = results.take(_maxResults).toList();
      _loading = false;
      if (_services.isEmpty) {
        _error = 'Could not find services near your current location.';
      }
    });
  }

  int get _totalPages =>
      (_services.length / _pageSize).ceil().clamp(1, (_maxResults / _pageSize).ceil());

  List<Map<String, dynamic>> get _pageItems {
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, _services.length);
    return start < end ? _services.sublist(start, end) : [];
  }

  Future<void> _callNumber(String phone) async {
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (e) {
      debugPrint('Call launch error: $e');
    }
  }

  Future<void> _openMapDirections(String address) async {
    final query = Uri.encodeComponent(address);
    try {
      await launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Directions launch error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(widget.label, style: AppText.dialogTitle)),
              InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text('Near your current location', style: AppText.faintCaption),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(_error!, style: AppText.faintCaption),
            )
          else ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _pageItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = _pageItems[i];
                  final phone = s['phone']?.toString();
                  final address = s['address']?.toString();
                  final ratingRaw = s['rating'];
                  final rating = ratingRaw != null && ratingRaw.toString() != 'N/A'
                      ? double.tryParse(ratingRaw.toString())
                      : null;
                  return ServiceProviderCard(
                    name: s['name']?.toString() ?? 'Not available',
                    address: address,
                    phone: phone,
                    rating: rating,
                    onCall: (phone != null && phone.isNotEmpty && phone != 'N/A')
                        ? () => _callNumber(phone)
                        : null,
                    onDirections: (address != null &&
                            address.isNotEmpty &&
                            address != 'Address not available')
                        ? () => _openMapDirections(address)
                        : null,
                  );
                },
              ),
            ),
            if (_services.length > _pageSize) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _page > 0 ? () => setState(() => _page--) : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Previous'),
                  ),
                  Text('Page ${_page + 1} of $_totalPages', style: AppText.caption),
                  TextButton.icon(
                    onPressed: _page < _totalPages - 1 ? () => setState(() => _page++) : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}