// lib/service_category_sheet.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme/app_theme.dart';
import 'widgets/service_provider_card.dart';

/// Bottom sheet listing nearby providers for one service category.
/// All providers are shown in ONE scrollable list (no Previous / Next paging).
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
  static const int _maxResults = 20;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    List<Map<String, dynamic>> results = [];
    try {
      results = await widget.fetchServices().timeout(const Duration(seconds: 45));
    } catch (e) {
      debugPrint('❌ Service sheet load error: $e');
    }

    if (!mounted) return;
    setState(() {
      _services = results.take(_maxResults).toList();
      _loading = false;
      if (_services.isEmpty) {
        _error = 'Could not find services near your current location.';
      }
    });
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
          else
            // All providers in one list, scroll to see more.
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _services.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final s = _services[i];
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
        ],
      ),
    );
  }
}