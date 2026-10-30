// lib/service_tab.dart
//
// "Service" screen — ticket list (with invoice-style billing popup, same
// design as MyTicketsScreen) + a "quick book" grid for common service
// categories. Also lets the customer cancel a still-open ticket with a
// reason (bottom sheet, quick-reason chips + custom text).
//
// Quick book uses the shared HomeServices (same as Home tab) — pincode only.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'constants/app_strings.dart';
import 'constants/api_config.dart';
import 'theme/app_theme.dart';
import 'services/api_client.dart';
import 'services/home_services.dart';
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
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  String _selectedFilter = 'all'; // 'all', 'open', 'in_progress', 'completed', 'cancelled'
  final Map<String, int> _quickBookCounts = {};

  static const List<Map<String, String>> _filterOptions = [
    {'key': 'all', 'label': AppStrings.filterAll},
    {'key': 'open', 'label': AppStrings.filterOpen},
    {'key': 'in_progress', 'label': AppStrings.filterInProgress},
    {'key': 'completed', 'label': AppStrings.filterCompleted},
    {'key': 'cancelled', 'label': AppStrings.filterCancelled},
  ];

  static const double _defaultGstPercent = 18;

  @override
  void initState() {
    super.initState();
    _fetchTickets();
    _prefetchQuickBookCounts();
  }

  @override
  void didUpdateWidget(covariant ServiceTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pincode != widget.pincode) {
      setState(() => _quickBookCounts.clear());
      _prefetchQuickBookCounts();
    }
  }

  // ---------------------------------------------------------------------
  // QUICK BOOK COUNTS (shared HomeServices, pincode only)
  // ---------------------------------------------------------------------
  void _prefetchQuickBookCounts() {
    HomeServices.prefetchCounts(widget.pincode, (type, count) {
      if (mounted) setState(() => _quickBookCounts[type] = count);
    });
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
      final response = await ApiClient.get(ApiConfig.customerBillingUrl(plainMobile));

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
            _error = data['message']?.toString() ?? AppStrings.couldNotLoadTickets;
            _loading = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _error = AppStrings.couldNotLoadTicketsCode(response.statusCode);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Service tickets fetch error: $e');
      if (mounted) {
        setState(() {
          _error = AppStrings.networkErrorPullRetry;
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
      final response = await ApiClient.put(ApiConfig.cancelTicketUrl(), body: {
        'ticketId': ticketId,
        'customerMobile': ApiConfig.stripCountryCode(widget.mobileNumber),
        'reason': reason,
      });

      debugPrint('🚫 Cancel ticket status: ${response.statusCode}');
      debugPrint('🚫 Cancel ticket body: ${response.body}');

      final data = response.statusCode == 200 ? jsonDecode(response.body) : null;
      final ok = data != null && data['success'] == true;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? AppStrings.ticketCancelledOk
              : (data?['message']?.toString() ?? AppStrings.couldNotCancelTicket(response.statusCode))),
          backgroundColor: ok ? AppColors.success : AppColors.danger,
        ),
      );

      if (ok) _fetchTickets(); // refresh list to reflect new status
    } catch (e) {
      debugPrint('❌ Cancel ticket error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.networkErrorPleaseRetry),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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
    if (status.isEmpty || status == 'unknown') return AppStrings.statusUnknown;
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
    return AppStrings.serviceRequest;
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
      if (laborCharge > 0) _BillLine(AppStrings.labourCharge, laborCharge),
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
                      child: Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppStrings.invoice,
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
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),
                _dashedDivider(),
                const SizedBox(height: 12),
                if (bill.lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: Text(AppStrings.noItemizedBreakdown, style: AppText.caption),
                  ),
                ...bill.lines.map((l) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(l.label,
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                          ),
                          Text(money(l.amount),
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                        ],
                      ),
                    )),
                const SizedBox(height: 6),
                _dashedDivider(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(AppStrings.subtotal, style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                    const Spacer(),
                    Text(money(bill.subtotal), style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(AppStrings.gstLabel((bill.gstPercent % 1 == 0 ? bill.gstPercent.toStringAsFixed(0) : bill.gstPercent).toString()),
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                    const Spacer(),
                    Text(money(bill.gstAmount), style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
                  ],
                ),
                const SizedBox(height: 12),
                _dashedDivider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(AppStrings.total,
                        style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(money(bill.total),
                        style: TextStyle(color: AppColors.primary, fontSize: 17, fontWeight: FontWeight.w800)),
                  ],
                ),
                if (bill.warrantyDays != null) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, size: 13, color: AppColors.textMuted),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(AppStrings.warrantyOnService(bill.warrantyDays), style: AppText.caption),
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
                    child: Text(AppStrings.close, style: TextStyle(color: AppColors.primary)),
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
    const quickReasons = AppStrings.quickReasonList;
    String? selectedQuickReason;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: BoxDecoration(
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
                      child: Icon(Icons.cancel_rounded, color: AppColors.danger, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppStrings.cancelThisTicket,
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                          Text(AppStrings.ticketNumber(ticketId), style: AppText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ---- Quick reason chips ----
                Text(AppStrings.quickReasons,
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
                Text(AppStrings.orTypeYourOwnReason,
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  onChanged: (_) => setSheetState(() => selectedQuickReason = null),
                  style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: AppStrings.tellUsWhy,
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
                      borderSide: BorderSide(color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(AppStrings.technicianWillBeNotified,
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
                          side: BorderSide(color: AppColors.borderSubtle),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(AppStrings.keepTicket, style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text(AppStrings.pleaseAddReason)),
                            );
                            return;
                          }
                          Navigator.of(ctx).pop();
                          _cancelTicket(ticketId, reason);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.danger,
                          foregroundColor: AppColors.textPrimary,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text(AppStrings.confirmCancel, style: TextStyle(fontWeight: FontWeight.w600)),
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
                    ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        children: [
                          if (_error != null) ...[
                            const SizedBox(height: 40),
                            Icon(Icons.wifi_off_rounded, color: AppColors.textFaint, size: 36),
                            const SizedBox(height: 12),
                            Text(_error!, textAlign: TextAlign.center, style: AppText.caption),
                            const SizedBox(height: 40),
                          ] else if (_filteredTickets.isEmpty) ...[
                            const SizedBox(height: 30),
                            Icon(Icons.receipt_long_rounded, color: AppColors.textFaint, size: 36),
                            const SizedBox(height: 12),
                            Text(
                              _tickets.isEmpty
                                  ? AppStrings.noTicketsYet
                                  : AppStrings.noTicketsMatchFilter,
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
                          _sectionHeader(AppStrings.quickBook),
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
              Text(AppStrings.service, style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(AppStrings.ticketsSummary(city, _tickets.length), style: AppText.caption),
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
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = _filterOptions[index];
          final isSelected = _selectedFilter == option['key'];
          return InkWell(
            onTap: () => setState(() => _selectedFilter = option['key']!),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : AppColors.cardBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? AppColors.primary : AppColors.borderMuted),
              ),
              child: Text(
                option['label']!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.onPrimary : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(title, style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8));
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
                      style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    if (ticketId != null && ticketId.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(AppStrings.ticketNumber(ticketId), style: AppText.caption),
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
                  Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textMuted),
                  const SizedBox(width: 5),
                  Flexible(child: Text(assigned, style: AppText.caption, overflow: TextOverflow.ellipsis)),
                ],
                if (assigned != null && date != null) const SizedBox(width: 14),
                if (date != null) ...[
                  Icon(Icons.event_rounded, size: 14, color: AppColors.textMuted),
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
                          Text(AppStrings.total,
                              style: TextStyle(
                                  color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 5),
                          Icon(Icons.receipt_long_rounded, size: 14, color: AppColors.textMuted),
                          const SizedBox(width: 6),
                          Text(
                            '₹${bill.total.toStringAsFixed(bill.total % 1 == 0 ? 0 : 2)}',
                            style: TextStyle(
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
                        children: [
                          Icon(Icons.close_rounded, size: 13, color: AppColors.danger),
                          SizedBox(width: 4),
                          Text(AppStrings.cancel,
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

  // ---------------------------------------------------------------------
  // QUICK BOOK GRID — same categories + same sheet as Home tab.
  // ---------------------------------------------------------------------
  Widget _buildQuickBookGrid() {
    final categories = HomeServices.categories;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.2,
      ),
      itemCount: categories.length,
      itemBuilder: (context, i) {
        final cat = categories[i];
        final type = cat['type'] as String;
        final count = _quickBookCounts[type];
        final color = cat['color'] as Color;
        return InkWell(
          onTap: () => HomeServices.openSheet(context, cat, widget.pincode),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: AppDecor.flatCard(radius: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(cat['icon'] as IconData, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(cat['label'] as String,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(count == null ? '...' : AppStrings.availableNow(count),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.success, fontSize: 10.5, fontWeight: FontWeight.w600)),
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