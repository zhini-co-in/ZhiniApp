// lib/service_tab.dart
//
// "Service" screen — ticket list (with invoice-style billing popup, same
// design as MyTicketsScreen) + a "quick book" grid for common service
// categories. Also lets the customer cancel a still-open ticket with a
// reason (bottom sheet, quick-reason chips + custom text).

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'constants/api_config.dart';
import 'theme/app_theme.dart';
import 'widgets/service_provider_card.dart';

// ---------------------------------------------------------------------
// ADD THIS to lib/constants/api_config.dart (if not already present):
//
//   static String cancelTicketUrl() => '$baseUrl/cancel-ticket';
//
// ---------------------------------------------------------------------

class ServiceTab extends StatefulWidget {
  final String mobileNumber;
  final String address;
  final String pincode;
  final String name;

  const ServiceTab({
    super.key,
    required this.mobileNumber,
    required this.address,
    required this.pincode,
    this.name = '',
  });

  @override
  State<ServiceTab> createState() => _ServiceTabState();
}

class _ServiceTabState extends State<ServiceTab> {
  static const List<Map<String, dynamic>> _quickBookCategories = [
    {'label': 'Electrician', 'type': 'electrician', 'icon': Icons.electrical_services_rounded},
    {'label': 'Plumber', 'type': 'plumber', 'icon': Icons.plumbing_rounded},
    {'label': 'AC Service', 'type': 'AC service', 'icon': Icons.ac_unit_rounded},
    {'label': 'Appliance repair', 'type': 'appliance repair', 'icon': Icons.build_rounded},
  ];

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  String _selectedFilter = 'all'; // 'all', 'open', 'in_progress', 'completed', 'cancelled'
  final Map<String, int> _quickBookCounts = {};

  static const List<Map<String, String>> _filterOptions = [
    {'key': 'all', 'label': 'All'},
    {'key': 'open', 'label': 'Open'},
    {'key': 'in_progress', 'label': 'In Progress'},
    {'key': 'completed', 'label': 'Completed'},
    {'key': 'cancelled', 'label': 'Cancelled'},
  ];

  static const double _defaultGstPercent = 18;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _prefetchQuickBookCounts();
  }

  // ---------------------------------------------------------------------
  // LOCATION HELPER
  // ---------------------------------------------------------------------
  Future<String> _buildGpsLocationQuery() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return '';

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return '';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      return '&latitude=${position.latitude}&longitude=${position.longitude}';
    } catch (e) {
      debugPrint('❌ Location fetch error (service tab): $e');
      return '';
    }
  }

  // ---------------------------------------------------------------------
  // FETCH TICKETS
  // ---------------------------------------------------------------------
  Future<void> _fetchTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plainMobile = ApiConfig.stripCountryCode(widget.mobileNumber);
      final response = await http.get(
        Uri.parse(ApiConfig.customerBillingUrl(plainMobile)),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );

      debugPrint('🎫 Service tickets status: ${response.statusCode}');
      debugPrint('🎫 Service tickets body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final rawData = data['data'];
          final List rawList = rawData is List ? rawData : (rawData == null ? [] : [rawData]);
          final tickets = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          if (mounted) {
            setState(() {
              _tickets = tickets;
              _loading = false;
            });
          }
          return;
        }
        if (mounted) {
          setState(() {
            _error = data['message']?.toString() ?? 'Could not load tickets.';
            _loading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _error = 'Could not load tickets (${response.statusCode}).';
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Service tickets fetch error: $e');
      if (mounted) {
        setState(() {
          _error = 'Network error. Pull down to retry.';
          _loading = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------
  // CANCEL TICKET — calls PUT {baseUrl}/cancel-ticket with a reason.
  // ---------------------------------------------------------------------
  Future<void> _cancelTicket(String ticketId, String reason) async {
    try {
      final response = await http.put(
        Uri.parse(ApiConfig.cancelTicketUrl()),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'ticketId': ticketId,
          'customerMobile': ApiConfig.stripCountryCode(widget.mobileNumber),
          'reason': reason,
        }),
      );

      debugPrint('🚫 Cancel ticket status: ${response.statusCode}');
      debugPrint('🚫 Cancel ticket body: ${response.body}');

      final data = response.statusCode == 200 ? jsonDecode(response.body) : null;
      final ok = data != null && data['success'] == true;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Ticket cancelled successfully.'
              : (data?['message']?.toString() ?? 'Could not cancel ticket (${response.statusCode}).')),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );

      if (ok) _fetchTickets(); // refresh list to reflect new status
    } catch (e) {
      debugPrint('❌ Cancel ticket error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Network error. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _prefetchQuickBookCounts() async {
    final locationQuery = await _buildGpsLocationQuery();

    final futures = _quickBookCategories.map((cat) async {
      final type = cat['type'] as String;
      try {
        final response = await http.post(
          Uri.parse(
            '${ApiConfig.homeServicesUrl}'
            '?serviceType=${Uri.encodeQueryComponent(type)}'
            '&pincode=${widget.pincode}'
            '$locationQuery',
          ),
          headers: {'ngrok-skip-browser-warning': 'true'},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true && data['data'] != null) {
            final raw = data['data'];
            final list = raw is List ? raw : [raw];
            if (mounted) setState(() => _quickBookCounts[type] = list.length);
          }
        }
      } catch (_) {}
    });
    await Future.wait(futures);
  }

  // -----------------------------------------------------------------------
  // Defensive extraction helpers
  // -----------------------------------------------------------------------
  String _statusOf(Map<String, dynamic> t) =>
      (t['status'] ?? t['billing']?['status'])?.toString().trim().toLowerCase() ?? 'unknown';

  String _statusBucket(String status) {
    switch (status) {
      case 'completed':
      case 'closed':
      case 'resolved':
        return 'completed';
      case 'in_progress':
      case 'in progress':
      case 'assigned':
      case 'accepted':
        return 'in_progress';
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return 'cancelled';
      case 'new':
      case 'open':
      case 'pending':
        return 'open';
      default:
        return 'unknown';
    }
  }

  List<Map<String, dynamic>> get _filteredTickets {
    if (_selectedFilter == 'all') return _tickets;
    return _tickets.where((t) => _statusBucket(_statusOf(t)) == _selectedFilter).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
      case 'closed':
      case 'resolved':
      case 'paid':
        return AppColors.success;
      case 'in_progress':
      case 'in progress':
      case 'assigned':
      case 'accepted':
        return AppColors.primary;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return AppColors.danger;
      case 'new':
      case 'open':
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.textMuted;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
      case 'closed':
      case 'resolved':
      case 'paid':
        return Icons.check_circle_rounded;
      case 'in_progress':
      case 'in progress':
      case 'assigned':
      case 'accepted':
        return Icons.build_circle_rounded;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return Icons.cancel_rounded;
      case 'new':
      case 'open':
      case 'pending':
        return Icons.hourglass_top_rounded;
      default:
        return Icons.help_outline_rounded;
    }
  }

  String _statusLabel(String status) {
    if (status.isEmpty || status == 'unknown') return 'Status unknown';
    return status
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String? _assignedName(Map<String, dynamic> t) {
    final assigned = t['assignedTo'];
    if (assigned == null) return null;
    if (assigned is Map) return assigned['name']?.toString();
    final s = assigned.toString().trim();
    return s.isEmpty ? null : s;
  }

  String _serviceLabel(Map<String, dynamic> t) {
    final sd = t['serviceDetails'];
    if (sd is Map) {
      final product = sd['product']?.toString();
      final brand = sd['brand']?.toString();
      if (product != null && product.isNotEmpty) {
        return (brand != null && brand.isNotEmpty && brand.toUpperCase() != 'N/A')
            ? '$brand $product'
            : product;
      }
      final desc = sd['description']?.toString();
      if (desc != null && desc.isNotEmpty) return desc;
    }
    final billingProduct = t['billing'] is Map ? t['billing']['productName']?.toString() : null;
    if (billingProduct != null && billingProduct.isNotEmpty) return billingProduct;
    return 'Service request';
  }

  String? _formattedDate(Map<String, dynamic> t) {
    final raw = t['updatedAt']?.toString();
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  num? _asNum(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    return num.tryParse(raw.toString());
  }

  // -----------------------------------------------------------------------
  // Bill computation
  // -----------------------------------------------------------------------
  _BillBreakdown _billFor(Map<String, dynamic> t) {
    final billing = t['billing'];
    if (billing is! Map) return _BillBreakdown.empty();

    final laborCharge = _asNum(billing['laborCharge'] ?? billing['labourCharge']) ?? 0;
    final partsCost = _asNum(billing['partsCost']);

    final partsUsed = billing['partsUsed'];
    final partLines = <_BillLine>[];
    if (partsUsed is List) {
      for (final p in partsUsed) {
        if (p is Map) {
          final name = p['name']?.toString() ?? p['partName']?.toString() ?? 'Part';
          final cost = _asNum(p['cost'] ?? p['amount'] ?? p['price']);
          if (cost != null) partLines.add(_BillLine(name, cost));
        }
      }
    }
    final partsSubtotal = partLines.isNotEmpty
        ? partLines.fold<num>(0, (sum, l) => sum + l.amount)
        : (partsCost ?? 0);

    if (partLines.isEmpty && partsSubtotal > 0) {
      final count = partsUsed is List ? partsUsed.length : 0;
      partLines.add(_BillLine(count > 0 ? 'Parts ($count)' : 'Parts', partsSubtotal));
    }

    final lines = <_BillLine>[
      if (laborCharge > 0) _BillLine('Labour Charge', laborCharge),
      ...partLines,
    ];

    final subtotal = laborCharge + partsSubtotal;

    final explicitGstAmount = _asNum(billing['gstAmount'] ?? billing['gst']);
    final gstPercent = _asNum(billing['gstPercent']) ?? _defaultGstPercent;
    final gstAmount = explicitGstAmount ?? (subtotal * gstPercent / 100);

    final backendTotal = _asNum(billing['totalAmount'] ?? billing['total'] ?? billing['amount']);
    final total = backendTotal ?? (subtotal + gstAmount);

    return _BillBreakdown(
      lines: lines,
      subtotal: subtotal,
      gstPercent: gstPercent,
      gstAmount: gstAmount,
      total: total,
      productName: billing['productName']?.toString(),
      notes: billing['notes']?.toString(),
      warrantyDays: billing['warrantyDays'],
    );
  }

  // -----------------------------------------------------------------------
  // Bill / invoice popup
  // -----------------------------------------------------------------------
  void _showBill(BuildContext context, Map<String, dynamic> t) {
    final bill = _billFor(t);
    final ticketId = t['ticketId']?.toString();
    final date = _formattedDate(t);
    String money(num v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Invoice',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                          if (ticketId != null && ticketId.isNotEmpty)
                            Text('#$ticketId', style: AppText.caption),
                        ],
                      ),
                    ),
                    if (date != null) Text(date, style: AppText.caption),
                  ],
                ),
                if (bill.productName != null && bill.productName!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(bill.productName!,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),
                _dashedDivider(),
                const SizedBox(height: 12),
                if (bill.lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text('No itemized breakdown available.', style: AppText.caption),
                  ),
                ...bill.lines.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.label,
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                          ),
                          Text(money(l.amount),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                        ],
                      ),
                    )),
                const SizedBox(height: 6),
                _dashedDivider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('Subtotal', style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                    const Spacer(),
                    Text(money(bill.subtotal), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('GST (${bill.gstPercent % 1 == 0 ? bill.gstPercent.toStringAsFixed(0) : bill.gstPercent}%)',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                    const Spacer(),
                    Text(money(bill.gstAmount), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                  ],
                ),
                const SizedBox(height: 12),
                _dashedDivider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Total',
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(money(bill.total),
                        style: const TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (bill.warrantyDays != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.verified_user_outlined, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text('${bill.warrantyDays} days warranty on this service', style: AppText.caption),
                      ),
                    ],
                  ),
                ],
                if (bill.notes != null && bill.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(bill.notes!, style: AppText.caption),
                ],
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close', style: TextStyle(color: AppColors.primary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashedDivider() {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 5.0;
          const dashSpace = 4.0;
          final count = (constraints.maxWidth / (dashWidth + dashSpace)).floor();
          return Row(
            children: List.generate(
              count,
              (_) => Padding(
                padding: const EdgeInsets.only(right: dashSpace),
                child: Container(width: dashWidth, height: 1, color: AppColors.borderSubtle),
              ),
            ),
          );
        },
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Cancel ticket sheet — bottom sheet with quick-reason chips + custom text.
  // -----------------------------------------------------------------------
  void _showCancelDialog(BuildContext context, Map<String, dynamic> t) {
    final ticketId = t['ticketId']?.toString();
    if (ticketId == null || ticketId.isEmpty) return;

    final reasonController = TextEditingController();
    const quickReasons = [
      'Found a local technician',
      'Changed my mind',
      'Price too high',
      'Taking too long',
    ];
    String? selectedQuickReason;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ---- Drag handle ----
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: AppColors.borderSubtle,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                // ---- Header ----
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cancel this ticket?',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                          Text('Ticket #$ticketId', style: AppText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ---- Quick reason chips ----
                const Text('Quick reasons',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: quickReasons.map((r) {
                    final isSelected = selectedQuickReason == r;
                    return GestureDetector(
                      onTap: () {
                        setSheetState(() {
                          selectedQuickReason = isSelected ? null : r;
                          reasonController.text = isSelected ? '' : r;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.danger.withValues(alpha: 0.12) : AppColors.scaffoldBg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? AppColors.danger : AppColors.borderSubtle,
                          ),
                        ),
                        child: Text(r,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? AppColors.danger : AppColors.textSecondary,
                            )),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // ---- Custom reason field ----
                const Text('Or type your own reason',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  onChanged: (_) => setSheetState(() => selectedQuickReason = null),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: "Tell us why you're cancelling...",
                    hintStyle: AppText.faintCaption,
                    filled: true,
                    fillColor: AppColors.scaffoldBg,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.borderSubtle),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.borderSubtle),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('Your assigned technician will be notified once cancelled.',
                          style: AppText.caption),
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // ---- Actions ----
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Keep ticket', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Please add a reason to cancel.')),
                            );
                            return;
                          }
                          Navigator.of(ctx).pop();
                          _cancelTicket(ticketId, reason);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Confirm cancel', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -----------------------------------------------------------------------
  // Quick Book helpers (unchanged from before)
  // -----------------------------------------------------------------------
  Future<void> _callNumber(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: phone));
    } catch (_) {}
  }

  Future<void> _openMapDirections(String? address) async {
    if (address == null || address.isEmpty) return;
    final query = Uri.encodeComponent(address);
    try {
      await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=$query'), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _openQuickBookSheet(Map<String, dynamic> category) {
    final type = category['type'] as String;
    final label = category['label'] as String;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.cardBg,
      isScrollControlled: true,
      shape: AppDecor.sheetShape,
      builder: (sheetContext) {
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _fetchProvidersFor(type),
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final providers = snapshot.data ?? [];
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppText.dialogTitle),
                  const SizedBox(height: 4),
                  Text('Near pincode ${widget.pincode}', style: AppText.caption),
                  const SizedBox(height: 16),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                    )
                  else if (providers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('No service providers found nearby.', style: AppText.faintCaption),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: providers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final s = providers[i];
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
                            onCall: (phone != null && phone.isNotEmpty && phone != 'N/A') ? () => _callNumber(phone) : null,
                            onDirections: (address != null && address.isNotEmpty && address != 'Address not available')
                                ? () => _openMapDirections(address)
                                : null,
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchProvidersFor(String serviceType) async {
    try {
      final locationQuery = await _buildGpsLocationQuery();

      final response = await http.post(
        Uri.parse(
          '${ApiConfig.homeServicesUrl}'
          '?serviceType=${Uri.encodeQueryComponent(serviceType)}'
          '&pincode=${widget.pincode}'
          '$locationQuery',
        ),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final raw = data['data'];
          final list = raw is List ? raw : [raw];
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('❌ Quick book fetch error: $e');
    }
    return [];
  }

  // -----------------------------------------------------------------
  // BUILD
  // -----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffoldBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: _buildHeader(),
            ),
            const SizedBox(height: 12),
            _filterChipsRow(),
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.cardBg,
                onRefresh: _fetchTickets,
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        children: [
                          if (_error != null) ...[
                            const SizedBox(height: 40),
                            const Icon(Icons.wifi_off_rounded, color: AppColors.textFaint, size: 36),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: AppText.caption),
                            const SizedBox(height: 40),
                          ] else if (_filteredTickets.isEmpty) ...[
                            const SizedBox(height: 30),
                            const Icon(Icons.receipt_long_rounded, color: AppColors.textFaint, size: 36),
                            const SizedBox(height: 12),
                            Text(
                              _tickets.isEmpty
                                  ? 'No tickets yet.\nBook a repair from any appliance to see it here.'
                                  : 'No tickets match this filter.',
                              textAlign: TextAlign.center,
                              style: AppText.faintCaption,
                            ),
                            const SizedBox(height: 30),
                          ] else ...[
                            ..._filteredTickets.map((t) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _ticketCard(t),
                                )),
                          ],
                          const SizedBox(height: 12),
                          _sectionHeader('⚡ QUICK BOOK'),
                          const SizedBox(height: 10),
                          _buildQuickBookGrid(),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final city = widget.address.split(',').first.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Service', style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('$city · ${_tickets.length} ticket${_tickets.length == 1 ? '' : 's'}', style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChipsRow() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _filterOptions.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = _filterOptions[index];
          final isSelected = _selectedFilter == option['key'];
          return ChoiceChip(
            label: Text(option['label']!),
            selected: isSelected,
            onSelected: (_) => setState(() => _selectedFilter = option['key']!),
            backgroundColor: AppColors.cardBg,
            selectedColor: AppColors.primary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
              color: isSelected ? AppColors.primary : AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
            side: BorderSide(color: isSelected ? AppColors.primary : AppColors.borderSubtle),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            showCheckmark: false,
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8));
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final status = _statusOf(t);
    final color = _statusColor(status);
    final ticketId = t['ticketId']?.toString();
    final assigned = _assignedName(t);
    final serviceLabel = _serviceLabel(t);
    final date = _formattedDate(t);
    final bill = _billFor(t);
    final hasBill = t['billing'] is Map;
    final isCancellable = _statusBucket(status) == 'open' || _statusBucket(status) == 'in_progress';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderSubtle),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      serviceLabel,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (ticketId != null && ticketId.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('Ticket #$ticketId', style: AppText.caption),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(status), size: 13, color: color),
                    const SizedBox(width: 5),
                    Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
          if (assigned != null || date != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (assigned != null) ...[
                  const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Flexible(child: Text(assigned, style: AppText.caption, overflow: TextOverflow.ellipsis)),
                ],
                if (assigned != null && date != null) const SizedBox(width: 14),
                if (date != null) ...[
                  const Icon(Icons.event_rounded, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Text(date, style: AppText.caption),
                ],
              ],
            ),
          ],

          // ---- Bottom action row: bill total (left) + cancel pill (right) ----
          if (hasBill || isCancellable) ...[
            const SizedBox(height: 12),
            Divider(color: AppColors.borderSubtle, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                if (hasBill)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showBill(context, t),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Total',
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 5),
                          const Icon(Icons.receipt_long_rounded, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            '₹${bill.total.toStringAsFixed(bill.total % 1 == 0 ? 0 : 2)}',
                            style: const TextStyle(
                                color: AppColors.primary, fontSize: 14.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (isCancellable)
                  GestureDetector(
                    onTap: () => _showCancelDialog(context, t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.close_rounded, size: 13, color: AppColors.danger),
                          SizedBox(width: 4),
                          Text('Cancel',
                              style: TextStyle(
                                  color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickBookGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemCount: _quickBookCategories.length,
      itemBuilder: (context, i) {
        final cat = _quickBookCategories[i];
        final type = cat['type'] as String;
        final count = _quickBookCounts[type];
        return InkWell(
          onTap: () => _openQuickBookSheet(cat),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: AppDecor.flatCard(radius: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
                  child: Icon(cat['icon'] as IconData, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat['label'] as String,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(count == null ? '...' : '$count available now',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Small value types for bill computation.
// ---------------------------------------------------------------------------
class _BillLine {
  final String label;
  final num amount;
  const _BillLine(this.label, this.amount);
}

class _BillBreakdown {
  final List<_BillLine> lines;
  final num subtotal;
  final num gstPercent;
  final num gstAmount;
  final num total;
  final String? productName;
  final String? notes;
  final dynamic warrantyDays;

  const _BillBreakdown({
    required this.lines,
    required this.subtotal,
    required this.gstPercent,
    required this.gstAmount,
    required this.total,
    this.productName,
    this.notes,
    this.warrantyDays,
  });

  factory _BillBreakdown.empty() => const _BillBreakdown(
        lines: [],
        subtotal: 0,
        gstPercent: 0,
        gstAmount: 0,
        total: 0,
      );
}