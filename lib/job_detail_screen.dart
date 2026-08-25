import 'package:flutter/material.dart';
import 'service_ticket_card.dart';
import 'services/ticket_service.dart';
import 'billing_screen.dart';
import 'utils/whatsapp_share.dart';        // 👈 ADD
import 'utils/manual_ticket_store.dart';

// ===========================================================================
// LOCAL (UI-ONLY) STAGE MODEL
// ===========================================================================
//
// Backend / Wekan board only understands these statuses:
//   NEW, ACCEPTED, REJECTED, IN_PROGRESS, WAITING_FOR_PARTS, COMPLETED
//
// The richer flow the provider sees (Reached → Service here / Taking
// product → handover time → Work in progress / Waiting for parts) is
// tracked entirely on-device as a `_LocalStage`. Only when a stage maps
// to a real backend status do we call TicketService.updateTicketStatus.
//
// ⚠️ Because "reached", "on-site vs product-taken", and handoverTime are
// NOT persisted to the backend, they reset to a sane default if the app
// is killed and reopened mid-job (see _resumeLocalStageFromBackend()).
// If you later add columns for these on the backend, wire them in at
// the marked TODOs below.
//
//   LocalStage           │ Backend call
//   ──────────────────────────────────────
//   accepted              │ (none — already ACCEPTED)
//   reached                │ (none — local only)
//   onSite                  │ IN_PROGRESS
//   productTaken             │ IN_PROGRESS
//   productInProgress          │ IN_PROGRESS
//   waitingForParts              │ WAITING_FOR_PARTS
//   completed                     │ COMPLETED

enum LocalStage {
  accepted,
  reached,
  onSite,
  productTaken,
  productInProgress,
  waitingForParts,
  completed,
}

class _BackendStatus {
  static const accepted = 'ACCEPTED';
  static const inProgress = 'IN_PROGRESS';
  static const waitingForParts = 'WAITING_FOR_PARTS';
  static const completed = 'COMPLETED';
}

extension on LocalStage {
  String? get backendStatus {
    switch (this) {
      case LocalStage.onSite:
      case LocalStage.productTaken:
      case LocalStage.productInProgress:
        return _BackendStatus.inProgress;
      case LocalStage.waitingForParts:
        return _BackendStatus.waitingForParts;
      case LocalStage.completed:
        return _BackendStatus.completed;
      case LocalStage.reached:
        return null;   // 🔄 'REACHED' -> null — local only, WhatsApp trigger வேற வழியில பண்ணணும்
      case LocalStage.accepted:
        return null;
    }
  }

  /// Which of the 4 timeline dots this stage lights up (0-3).
  int get timelineIndex {
    switch (this) {
      case LocalStage.accepted:
        return 0;
      case LocalStage.reached:
        return 1;
      case LocalStage.onSite:
      case LocalStage.productTaken:
      case LocalStage.productInProgress:
      case LocalStage.waitingForParts:
        return 2;
      case LocalStage.completed:
        return 3;
    }
  }
}

class JobDetailScreen extends StatefulWidget {
  final ServiceTicket ticket;
  const JobDetailScreen({super.key, required this.ticket});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late LocalStage _stage;
  DateTime? _handoverTime;
  bool _updating = false;

  static const _bg = Color(0xFF0A1628);
  static const _card = Color(0xFF0F2038);
  static const _accent = Color(0xFF2E7DFF);
  static const _amber = Color(0xFFFFB020);
  static const _green = Color(0xFF35D48A);

  @override
  void initState() {
    super.initState();
    _stage = _resumeLocalStageFromBackend(widget.ticket.status);
  }

  /// Best-effort guess of where the provider left off, based only on
  /// the coarse backend status (since finer detail isn't persisted).
  LocalStage _resumeLocalStageFromBackend(String backendStatus) {
    switch (backendStatus.toUpperCase()) {
      case _BackendStatus.inProgress:
        // Could be on-site or product-taken — default to a generic
        // "working" screen rather than re-asking Reached.
        return LocalStage.productInProgress;
      case _BackendStatus.waitingForParts:
        return LocalStage.waitingForParts;
      case _BackendStatus.completed:
        return LocalStage.completed;
      default:
        return LocalStage.accepted;
    }
  }

Future<void> _goToStage(LocalStage newStage, {DateTime? handoverTime}) async {
    if (_updating) return;
    final backendStatus = newStage.backendStatus;

    // Local-only transition (Reached) — no network call needed.
    if (backendStatus == null) {
      setState(() {
        _stage = newStage;
        if (handoverTime != null) _handoverTime = handoverTime;
      });
      if (newStage == LocalStage.reached) {
        await _maybeSendWhatsApp(newStage);   // 👈 ADD
      }
      return;
    }

    setState(() => _updating = true);
    final previousStage = _stage;
    setState(() {
      _stage = newStage;
      if (handoverTime != null) _handoverTime = handoverTime;
    });

    try {
      await TicketService.updateTicketStatus(
        ticketId: widget.ticket.id,
        newStatus: backendStatus,
      );
      await _maybeSendWhatsApp(newStage);   // 👈 ADD — status update success ஆனதும்
      if (newStage == LocalStage.completed && mounted) {
        Navigator.pop(context, 'COMPLETED');
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _stage = previousStage); // rollback
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: _card,
            content: Text('Could not update status. Try again.',
                style: TextStyle(color: Colors.white)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
Future<void> _maybeSendWhatsApp(LocalStage stage) async {
    final isManual = await ManualTicketStore.isManual(widget.ticket.id);
    if (!isManual) return;
    if (widget.ticket.customerPhone.isEmpty) return;

    String? message;
    switch (stage) {
      case LocalStage.reached:
        message = "Hi ${widget.ticket.customerName}, your technician has *reached* "
            "your location for Ticket ${widget.ticket.id}. 🚗";
        break;
      case LocalStage.onSite:                              // 👈 ADD
        message = "Hi ${widget.ticket.customerName}, your technician is now "
            "*servicing* your ${widget.ticket.appliance} on-site (Ticket ${widget.ticket.id}). 🔧";
        break;
      case LocalStage.productTaken:                         // 👈 ADD
        message = "Hi ${widget.ticket.customerName}, your ${widget.ticket.appliance} has been "
            "*picked up* for repair (Ticket ${widget.ticket.id}). We'll keep you updated. 📦";
        break;
      case LocalStage.waitingForParts:
        message = "Hi ${widget.ticket.customerName}, your service (Ticket ${widget.ticket.id}) "
            "is currently *waiting for spare parts*. ⏳ We'll update you once work resumes.";
        break;
      case LocalStage.completed:
        message = "Hi ${widget.ticket.customerName}, your service (Ticket ${widget.ticket.id}) "
            "has been marked *completed* ✅. Thank you for using our service!\n\n"
            "📲 Install our app to track this appliance, view service history, "
            "and book future repairs faster: <APP_DOWNLOAD_LINK>";
        break;
      default:
        return;   // productInProgress (toggle chip) — no separate message, same as productTaken flow
    }

    await shareViaWhatsApp(phone: widget.ticket.customerPhone, message: message);
  }

  Future<void> _pickHandoverTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent, surface: _card),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: _accent, surface: _card),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    final combined = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await _goToStage(LocalStage.productTaken, handoverTime: combined);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(widget.ticket.customerName,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildTicketSummary(),
            _buildTimeline(),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _buildStageContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Ticket summary strip
  // -------------------------------------------------------------------
  Widget _buildTicketSummary() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.build_circle_rounded, color: _accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.ticket.appliance,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(widget.ticket.issue,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white38, size: 14),
              const SizedBox(height: 2),
              Text('${widget.ticket.distanceKm.toStringAsFixed(1)} km',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // 4-stage horizontal timeline: Accepted → Reached → Working → Done
  // -------------------------------------------------------------------
  Widget _buildTimeline() {
    final stage = _stage.timelineIndex;
    final labels = const ['Accepted', 'Reached', 'Working', 'Done'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: List.generate(labels.length * 2 - 1, (i) {
          if (i.isOdd) {
            final leftStage = i ~/ 2;
            final filled = leftStage < stage;
            return Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: filled ? _green : Colors.white12,
              ),
            );
          }
          final dotIndex = i ~/ 2;
          final isDone = dotIndex < stage;
          final isCurrent = dotIndex == stage;
          return Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isCurrent ? 16 : 12,
                height: isCurrent ? 16 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? _green : (isCurrent ? _accent : _card),
                  border: Border.all(
                    color: isDone ? _green : (isCurrent ? _accent : Colors.white24),
                    width: 2,
                  ),
                ),
                child: isDone ? const Icon(Icons.check, size: 8, color: Colors.white) : null,
              ),
              const SizedBox(height: 6),
              Text(
                labels[dotIndex],
                style: TextStyle(
                  color: isCurrent ? Colors.white : Colors.white38,
                  fontSize: 10.5,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Stage-specific content + actions
  // -------------------------------------------------------------------
  Widget _buildStageContent() {
    switch (_stage) {
      case LocalStage.accepted:
        return _actionScreen(
          key: 'accepted',
          icon: Icons.directions_rounded,
          iconColor: _accent,
          title: 'On your way?',
          subtitle: 'Tap once you\'ve reached the customer\'s location.',
          child: _primaryButton(
            'Reached',
            icon: Icons.location_on_rounded,
            onTap: () => _goToStage(LocalStage.reached),
          ),
        );

      case LocalStage.reached:
        return _actionScreen(
          key: 'reached',
          icon: Icons.handshake_rounded,
          iconColor: _accent,
          title: 'How will you handle this?',
          subtitle: 'Choose whether you\'ll fix it on the spot or take the product with you.',
          child: Column(
            children: [
              _optionCard(
                icon: Icons.home_repair_service_rounded,
                color: _green,
                title: 'Service here',
                subtitle: 'Fix the appliance on-site, at the customer\'s place',
                onTap: () => _goToStage(LocalStage.onSite),
              ),
              const SizedBox(height: 12),
              _optionCard(
                icon: Icons.local_shipping_rounded,
                color: _amber,
                title: 'Taking product',
                subtitle: 'Pick it up for repair — set a handover date & time',
                onTap: _pickHandoverTime,
              ),
            ],
          ),
        );

      case LocalStage.onSite:
        return _actionScreen(
          key: 'onsite',
          icon: Icons.build_rounded,
          iconColor: _green,
          title: 'Servicing on-site',
          subtitle: 'Mark this job complete once the repair is done.',
          child: _primaryButton(
            'Complete',
            icon: Icons.check_circle_rounded,
            color: _green,
            onTap: _confirmComplete,
          ),
        );

      case LocalStage.productTaken:
      case LocalStage.productInProgress:
      case LocalStage.waitingForParts:
        return _productTakenScreen(key: 'product');

      case LocalStage.completed:
        return _actionScreen(
          key: 'completed',
          icon: Icons.verified_rounded,
          iconColor: _green,
          title: 'Job completed',
          subtitle: 'Nice work — this job is closed.',
          child: const SizedBox.shrink(),
        );
    }
  }

  Widget _productTakenScreen({required String key}) {
    return Container(
      key: ValueKey(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _iconHeader(
            icon: Icons.inventory_2_rounded,
            iconColor: _amber,
            title: 'Product with you',
            subtitle: 'Track repair progress until it\'s ready for handover.',
          ),
          if (_handoverTime != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_rounded, color: _amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Handover: ${_formatDateTime(_handoverTime!)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                    ),
                  ),
                  TextButton(
                    onPressed: _pickHandoverTime,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Text('Change', style: TextStyle(color: _accent, fontSize: 12)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('Current progress',
              style: TextStyle(color: Colors.white54, fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _toggleChip(
                  label: 'Work in progress',
                  icon: Icons.autorenew_rounded,
                  color: _accent,
                  selected: _stage == LocalStage.productInProgress || _stage == LocalStage.productTaken,
                  onTap: () => _goToStage(LocalStage.productInProgress),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _toggleChip(
                  label: 'Waiting for parts',
                  icon: Icons.hourglass_bottom_rounded,
                  color: _amber,
                  selected: _stage == LocalStage.waitingForParts,
                  onTap: () => _goToStage(LocalStage.waitingForParts),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _primaryButton(
            'Complete',
            icon: Icons.check_circle_rounded,
            color: _green,
            onTap: _confirmComplete,
          ),
        ],
      ),
    );
  }

Future<void> _confirmComplete() async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Mark as complete?', style: TextStyle(color: Colors.white)),
      content: const Text(
        'This will close the job as completed. Make sure the work is fully done.',
        style: TextStyle(color: Colors.white60),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Complete', style: TextStyle(color: _green)),
        ),
      ],
    ),
  );
  if (confirmed != true || !mounted) return;

  // Bill raise + payment collection happens here. BillingScreen itself
  // calls TicketService.addTicketBilling() and updateTicketStatus()
  // and pops with 'COMPLETED' once both succeed.
  final result = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => BillingScreen(
        ticketId: widget.ticket.id,
        ticketMongoId: widget.ticket.mongoId ?? '',
        customerName: widget.ticket.customerName,
        appliance: widget.ticket.appliance,
      ),
    ),
  );

  if (result == 'COMPLETED' && mounted) {
    setState(() => _stage = LocalStage.completed);
    await _maybeSendWhatsApp(LocalStage.completed);
    Navigator.pop(context, 'COMPLETED');
  }
}

  // -------------------------------------------------------------------
  // Reusable pieces
  // -------------------------------------------------------------------
  Widget _actionScreen({
    required String key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      key: ValueKey(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _iconHeader(icon: icon, iconColor: iconColor, title: title, subtitle: subtitle),
          const SizedBox(height: 28),
          child,
        ],
      ),
    );
  }

  Widget _iconHeader({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        const SizedBox(height: 14),
        Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4)),
      ],
    );
  }

  Widget _optionCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _updating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(color: Colors.white54, fontSize: 11.5, height: 1.3)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? color.withValues(alpha: 0.15) : _card,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _updating ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : Colors.white10, width: selected ? 1.4 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? color : Colors.white38, size: 20),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? color : Colors.white54,
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _primaryButton(
    String label, {
    required IconData icon,
    Color color = _accent,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _updating ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: color.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        icon: _updating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Icon(icon, color: Colors.white, size: 18),
        label: Text(label,
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]}, $hour12:$minute $ampm';
  }
}