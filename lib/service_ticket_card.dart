// lib/service_ticket_card.dart
//
// Incoming appliance-repair "ticket" cards for the Service Provider
// Dashboard. Shown when the provider toggles Availability ON.
// Tickets are fetched live from the backend (wekan-services).

import 'package:flutter/material.dart';
import 'job_detail_screen.dart';
import 'services/ticket_service.dart';
import 'utils/whatsapp_share.dart';
import 'utils/manual_ticket_store.dart';

// ---------------------------------------------------------------------
// MODEL
// ---------------------------------------------------------------------
enum TicketUrgency { high, medium, low }

class ServiceTicket {
  final String id;
  final String? mongoId;
  final String customerName;
  final String customerPhone;   // 👈 ADD
  final String appliance;
  final String issue;
  final String address;
  final double distanceKm;
  final TicketUrgency urgency;
  final DateTime postedAt;
  final String status;
  final String source;          // 👈 ADD — "manual" or "app" etc.

  ServiceTicket({
    required this.id,
    this.mongoId,
    required this.customerName,
    required this.customerPhone,   // 👈 ADD
    required this.appliance,
    required this.issue,
    required this.address,
    required this.distanceKm,
    required this.urgency,
    required this.postedAt,
    this.status = 'NEW',
    this.source = 'app',           // 👈 ADD, default 'app'
  });

  ServiceTicket copyWith({String? status}) {
    return ServiceTicket(
      id: id,
      mongoId: mongoId,
      customerName: customerName,
      customerPhone: customerPhone,   // 👈 ADD
      appliance: appliance,
      issue: issue,
      address: address,
      distanceKm: distanceKm,
      urgency: urgency,
      postedAt: postedAt,
      status: status ?? this.status,
      source: source,                 // 👈 ADD
    );
  }
}

// ---------------------------------------------------------------------
// SECTION WIDGET — "New requests" + "In progress" lists
// ---------------------------------------------------------------------
class IncomingTicketsSection extends StatefulWidget {
  final bool isAvailable;
  final String providerMobile;

  const IncomingTicketsSection({
    super.key,
    required this.isAvailable,
    required this.providerMobile,
  });

  @override
  State<IncomingTicketsSection> createState() => _IncomingTicketsSectionState();
}

class _IncomingTicketsSectionState extends State<IncomingTicketsSection> {
  List<ServiceTicket> _newTickets = [];
  List<ServiceTicket> _acceptedTickets = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.isAvailable) _loadTickets();
  }

  @override
  void didUpdateWidget(covariant IncomingTicketsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isAvailable && widget.isAvailable) {
      _loadTickets();
    }
  }

  Future<void> _loadTickets() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await TicketService.fetchProviderTickets(widget.providerMobile);
      if (!mounted) return;
      setState(() {
        _newTickets = tickets.where((t) => t.status == 'NEW').toList();
        // Anything still "in flight" (accepted, actively being worked,
        // or waiting on parts) stays visible under "In progress" here.
        // COMPLETED / REJECTED tickets drop off this list — they show
        // up in the Jobs tab instead.
        _acceptedTickets = tickets
            .where((t) =>
                t.status == 'ACCEPTED' ||
                t.status == 'IN_PROGRESS' ||
                t.status == 'WAITING_FOR_PARTS')
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

Future<void> _respond(ServiceTicket ticket, bool accepted) async {
    setState(() {
      _newTickets.removeWhere((t) => t.id == ticket.id);
      if (accepted) {
        _acceptedTickets.add(ticket.copyWith(status: 'ACCEPTED'));
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16294A),
        content: Text(
          accepted
              ? 'Accepted ${ticket.customerName}\'s ${ticket.appliance} request ✅'
              : 'Declined ${ticket.customerName}\'s request',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
  await TicketService.respondToTicket(ticketId: ticket.id, accepted: accepted);
  print("🎫 respondToTicket call finished for ${ticket.id}, accepted=$accepted");

  if (accepted) {
    final isManual = await ManualTicketStore.isManual(ticket.id);
    if (isManual) {
      await shareViaWhatsApp(
        phone: ticket.customerPhone,
        message: "Hi ${ticket.customerName}, your ${ticket.appliance} service request "
            "(Ticket ${ticket.id}) has been accepted ✅. We'll be in touch soon!",
      );
    }
  }
} catch (e) {
  debugPrint('⚠️ respondToTicket failed: $e');
}
  }

  Future<void> _startJob(ServiceTicket ticket) async {
    // JobDetailScreen updates the backend status itself as the provider
    // moves through Reached → on-site/product-taken → working/waiting
    // → complete. It only pops a value when the job is fully COMPLETED;
    // any other exit (back button mid-flow) pops null.
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => JobDetailScreen(ticket: ticket)),
    );

    if (!mounted) return;

    if (result == 'COMPLETED') {
      // Job is done — drop it from "In progress" here. It'll now show
      // up under the Jobs tab's Completed filter (fetched from backend).
      setState(() {
        _acceptedTickets.removeWhere((t) => t.id == ticket.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF16294A),
          content: Text(
            '${ticket.customerName}\'s job marked as completed ✅',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      // Provider may have moved it to IN_PROGRESS / WAITING_FOR_PARTS
      // without fully completing — refresh from backend to reflect the
      // real current status instead of guessing locally.
      _loadTickets();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isAvailable) return const SizedBox.shrink();

    if (_loading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2038),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2),
        ),
      );
    }

    if (_error != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2038),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(height: 8),
            const Text('Couldn\'t load requests',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white24, fontSize: 10.5)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loadTickets,
              child: const Text('Retry', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
    }

    if (_newTickets.isEmpty && _acceptedTickets.isEmpty) {
      return _emptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_newTickets.isNotEmpty) ...[
          _ticketList(_newTickets, isInProgress: false),
        ],
        if (_acceptedTickets.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('In progress',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _ticketList(_acceptedTickets, isInProgress: true),
        ],
        if (_newTickets.isEmpty && _acceptedTickets.isNotEmpty) ...[
          const SizedBox(height: 4),
        ],
        if (_newTickets.isEmpty) ...[
          const SizedBox(height: 12),
          _emptyState(),
        ],
      ],
    );
  }

  Widget _ticketList(List<ServiceTicket> list, {required bool isInProgress}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final ticket = list[index];
          return TweenAnimationBuilder<double>(
            key: ValueKey(ticket.id),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(offset: Offset(0, (1 - value) * 12), child: child),
            ),
            child: TicketCard(
              ticket: ticket,
              isInProgress: isInProgress,
              onAccept: () => _respond(ticket, true),
              onReject: () => _respond(ticket, false),
              onStart: () => _startJob(ticket),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2038),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, color: Colors.white.withValues(alpha: 0.2), size: 34),
          const SizedBox(height: 10),
          const Text('No requests right now',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 2),
          const Text('New tickets will show up here',
              style: TextStyle(color: Colors.white24, fontSize: 11)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// TICKET CARD — the unique design (unchanged visually)
// ---------------------------------------------------------------------
class TicketCard extends StatelessWidget {
  final ServiceTicket ticket;
  final bool isInProgress;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onStart;

  const TicketCard({
    super.key,
    required this.ticket,
    this.isInProgress = false,
    required this.onAccept,
    required this.onReject,
    required this.onStart,
  });

  static const Map<String, IconData> _applianceIcons = {
    'fridge': Icons.kitchen_rounded,
    'refrigerator': Icons.kitchen_rounded,
    'washing machine': Icons.local_laundry_service_rounded,
    'ac': Icons.ac_unit_rounded,
    'geyser': Icons.hot_tub_rounded,
    'mixer grinder': Icons.blender_rounded,
    'mixer': Icons.blender_rounded,
    'tv': Icons.tv_rounded,
    'router': Icons.router_rounded,
    'laptop': Icons.laptop_rounded,
  };

  IconData get _icon {
    final key = ticket.appliance.toLowerCase();
    for (final e in _applianceIcons.entries) {
      if (key.contains(e.key)) return e.value;
    }
    return Icons.build_circle_rounded;
  }

  (Color, String) get _urgencyMeta {
    switch (ticket.urgency) {
      case TicketUrgency.high:
        return (Colors.redAccent, 'Urgent');
      case TicketUrgency.medium:
        return (Colors.orangeAccent, 'Moderate');
      case TicketUrgency.low:
        return (Colors.greenAccent, 'Low priority');
    }
  }

  String get _timeAgo {
    final diff = DateTime.now().difference(ticket.postedAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get _statusLabel {
    switch (ticket.status) {
      case 'IN_PROGRESS':
        return 'IN PROGRESS';
      case 'WAITING_FOR_PARTS':
        return 'WAITING FOR PARTS';
      default:
        return 'ACCEPTED';
    }
  }

  Color get _statusColor {
    switch (ticket.status) {
      case 'IN_PROGRESS':
        return Colors.greenAccent;
      case 'WAITING_FOR_PARTS':
        return Colors.amber;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (urgencyColor, urgencyLabel) = _urgencyMeta;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F2038),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: urgencyColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(_icon, color: Colors.blue, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ticket.appliance,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(ticket.customerName,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: urgencyColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: urgencyColor.withValues(alpha: 0.5)),
                              ),
                              child: Text(urgencyLabel,
                                  style: TextStyle(
                                      color: urgencyColor, fontSize: 10, fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 6),
                            Text(_timeAgo, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(ticket.issue,
                        style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.35)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: Colors.white38, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ticket.address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (ticket.distanceKm > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${ticket.distanceKm.toStringAsFixed(1)} km',
                              style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (isInProgress) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: _statusColor.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              _statusLabel,
                              style: TextStyle(
                                  color: _statusColor, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onStart,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
                          label: Text(
                            ticket.status == 'ACCEPTED' ? 'Start' : 'Open job',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _CircleActionButton(icon: Icons.close_rounded, color: Colors.redAccent, onTap: onReject),
                          const SizedBox(width: 12),
                          _CircleActionButton(icon: Icons.check_rounded, color: Colors.blue, onTap: onAccept, filled: true),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Small round icon-only action button used for Accept / Reject.
// ---------------------------------------------------------------------
class _CircleActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  const _CircleActionButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? color : color.withValues(alpha: 0.12),
      shape: CircleBorder(side: BorderSide(color: color.withValues(alpha: filled ? 0 : 0.5))),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: filled ? Colors.white : color),
        ),
      ),
    );
  }
}