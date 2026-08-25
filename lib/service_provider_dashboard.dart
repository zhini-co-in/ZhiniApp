import 'package:flutter/material.dart';
import 'login_screen.dart';
import 'service_ticket_card.dart';
import 'service_provider_scan_tab.dart';
import 'services/ticket_service.dart';
import 'constants/api_config.dart';
import '../manual_ticket_create_screen.dart';

// ===========================================================================
// SHELL — Home / Jobs / Scan / Customers / Profile
// ===========================================================================
class ServiceProviderDashboard extends StatefulWidget {
  final String name;
  final String mobileNumber;

  const ServiceProviderDashboard({
    super.key,
    required this.name,
    required this.mobileNumber,
  });

  @override
  State<ServiceProviderDashboard> createState() =>
      _ServiceProviderDashboardState();
}

class _ServiceProviderDashboardState extends State<ServiceProviderDashboard> {
  int _tabIndex = 0; // 0 Home, 1 Jobs, 2 Scan, 3 Customers, 4 Profile
  bool _isAvailable = false;

  // TODO: replace with real values from your backend.
  final double _todayEarnings = 1840;
  final double _weekEarnings = 9200;
  final double _monthEarnings = 34000;
  final double _rating = 4.8;
  final String _category = 'AC & Refrigeration';

  void _toggleAvailability(bool value) {
    setState(() => _isAvailable = value);

    // TODO: call your backend here to persist availability status, e.g.
    // http.patch(Uri.parse('${ApiConfig.baseUrl}/api/service-providers/availability'),
    //   body: {'mobile': widget.mobileNumber, 'available': value.toString()});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF16294A),
        content: Text(
          value ? 'You are now available' : 'You are now unavailable',
          style: const TextStyle(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F2038),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Logout', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerMobile = ApiConfig.stripCountryCode(widget.mobileNumber);

    final tabs = [
      _HomeTab(
        name: widget.name,
        mobileNumber: widget.mobileNumber,
        rating: _rating,
        category: _category,
        isAvailable: _isAvailable,
        onAvailabilityChanged: _toggleAvailability,
        todayEarnings: _todayEarnings,
        weekEarnings: _weekEarnings,
        monthEarnings: _monthEarnings,
      ),
      _JobsTab(
        providerMobile: providerMobile,
        isActive: _tabIndex == 1,
      ),
      // Only mounted while this tab is actually selected — it opens the
      // camera on init, so we don't want it alive in the background.
      _tabIndex == 2 ? const ServiceProviderScanTab() : const SizedBox.shrink(),
      const _CustomersTab(),
      _ProfileTab(
        name: widget.name,
        mobileNumber: widget.mobileNumber,
        rating: _rating,
        category: _category,
        onLogout: _logout,
      ),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1628),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0A1628), Color(0xFF0F2038)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: IndexedStack(index: _tabIndex, children: tabs),
          ),
        ),
        bottomNavigationBar: _BottomNavBar(
          currentIndex: _tabIndex,
          onTap: (i) => setState(() => _tabIndex = i),
        ),
      ),
    );
  }
}

// ===========================================================================
// HOME TAB — profile header, availability card, stats, new requests
// ===========================================================================
class _HomeTab extends StatelessWidget {
  final String name;
  final String mobileNumber;   // ✅ ADD THIS FIELD
  final double rating;
  final String category;
  final bool isAvailable;
  final ValueChanged<bool> onAvailabilityChanged;
  final double todayEarnings;
  final double weekEarnings;
  final double monthEarnings;

  const _HomeTab({
    required this.name,
    required this.mobileNumber,   // ✅ ADD THIS
    required this.rating,
    required this.category,
    required this.isAvailable,
    required this.onAvailabilityChanged,
    required this.todayEarnings,
    required this.weekEarnings,
    required this.monthEarnings,
  });

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  String _fmtMoney(double v) {
    // Simple ₹ formatting with k-suffix for thousands, e.g. 34000 -> 34k
    if (v >= 1000) {
      final k = v / 1000;
      final s = k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1);
      return '₹${s}k';
    }
    return '₹${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- Profile row ----
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: Text(
                  _initials,
                  style: const TextStyle(
                      color: Colors.blue, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 15),
                        const SizedBox(width: 2),
                        Text(
                          '$rating · $category',
                          style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: Colors.greenAccent, size: 13),
                    SizedBox(width: 4),
                    Text('Verified',
                        style: TextStyle(
                            color: Colors.greenAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ---- Availability card ----
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0F2038),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAvailable ? 'Available' : 'Unavailable',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isAvailable ? 'Receiving new jobs' : 'Turn on to get new jobs',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isAvailable,
                  onChanged: onAvailabilityChanged,
                  activeThumbColor: Colors.white,
                  activeTrackColor: Colors.blue,
                  inactiveThumbColor: Colors.white70,
                  inactiveTrackColor: Colors.white24,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ---- Stats row ----
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Today', value: _fmtMoney(todayEarnings))),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'Week', value: _fmtMoney(weekEarnings))),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(label: 'Month', value: _fmtMoney(monthEarnings))),
            ],
          ),

          const SizedBox(height: 24),

          // ---- New requests ----
          if (isAvailable) ...[
            const Text(
              'New request',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          IncomingTicketsSection(
            isAvailable: isAvailable,
            providerMobile: ApiConfig.stripCountryCode(mobileNumber),   // 🔄 sampleTickets-ku badhila idhu
          ),

          if (!isAvailable) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: const Color(0xFF0F2038),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Icon(Icons.power_settings_new_rounded,
                      color: Colors.white.withValues(alpha: 0.2), size: 32),
                  const SizedBox(height: 10),
                  const Text('You are offline',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                  const SizedBox(height: 2),
                  const Text('Turn on availability to get started',
                      style: TextStyle(color: Colors.white24, fontSize: 11)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2038),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: Colors.blue, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
        ],
      ),
    );
  }
}

// ===========================================================================
// JOBS TAB — real tickets from backend, with All / Active / Completed filter
// ===========================================================================
class _JobsTab extends StatefulWidget {
  final String providerMobile;
  final bool isActive;

  const _JobsTab({required this.providerMobile, required this.isActive});

  @override
  State<_JobsTab> createState() => _JobsTabState();
}

enum _JobFilter { all, active, completed }

class _JobsTabState extends State<_JobsTab> {
  _JobFilter _filter = _JobFilter.all;
  List<ServiceTicket> _tickets = [];
  bool _loading = true;
  String? _error;

  static const _activeStatuses = {'ACCEPTED', 'IN_PROGRESS', 'WAITING_FOR_PARTS'};

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  @override
  void didUpdateWidget(covariant _JobsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Refresh every time the provider switches into this tab, so a job
    // just marked complete elsewhere (e.g. from Home) shows up here too.
    if (!oldWidget.isActive && widget.isActive) {
      _loadJobs();
    }
  }

  Future<void> _loadJobs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = await TicketService.fetchProviderTickets(widget.providerMobile);
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
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

  List<ServiceTicket> get _activeTickets =>
      _tickets.where((t) => _activeStatuses.contains(t.status)).toList();

  List<ServiceTicket> get _completedTickets =>
      _tickets.where((t) => t.status == 'COMPLETED').toList();

  List<ServiceTicket> get _visibleTickets {
    switch (_filter) {
      case _JobFilter.all:
        return [..._activeTickets, ..._completedTickets];
      case _JobFilter.active:
        return _activeTickets;
      case _JobFilter.completed:
        return _completedTickets;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My jobs',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${_activeTickets.length} active · ${_completedTickets.length} completed',
              style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
          const SizedBox(height: 16),
          SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () async {
              final created = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => ManualTicketCreateScreen(providerMobile: widget.providerMobile),
                ),
              );
              if (created == true) _loadJobs(); // refresh list after creating
            },
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Create Ticket', style: TextStyle(color: Colors.white)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ),
        const SizedBox(height: 16),

          // Filter chips
          Row(
            children: [
              _FilterChipButton(
                label: 'All',
                selected: _filter == _JobFilter.all,
                onTap: () => setState(() => _filter = _JobFilter.all),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Active',
                selected: _filter == _JobFilter.active,
                onTap: () => setState(() => _filter = _JobFilter.active),
              ),
              const SizedBox(width: 8),
              _FilterChipButton(
                label: 'Completed',
                selected: _filter == _JobFilter.completed,
                onTap: () => setState(() => _filter = _JobFilter.completed),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 28),
            const SizedBox(height: 8),
            const Text('Couldn\'t load jobs', style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _loadJobs,
              child: const Text('Retry', style: TextStyle(color: Colors.blue)),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: Colors.blue,
      backgroundColor: const Color(0xFF0F2038),
      onRefresh: _loadJobs,
      child: _visibleTickets.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),
                Icon(Icons.work_off_rounded, color: Colors.white.withValues(alpha: 0.15), size: 40),
                const SizedBox(height: 12),
                const Center(
                  child: Text('No jobs here yet', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ),
              ],
            )
          : ListView.separated(
              physics: const BouncingScrollPhysics(),
              itemCount: _visibleTickets.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final ticket = _visibleTickets[index];
                return _JobHistoryCard(
                  title: ticket.appliance,
                  statusLabel: _statusLabel(ticket.status),
                  statusColor: _statusColor(ticket.status),
                  subtitle: ticket.issue.isNotEmpty ? ticket.issue : ticket.customerName,
                  location: ticket.address,
                );
              },
            ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ACCEPTED':
        return 'Accepted';
      case 'IN_PROGRESS':
        return 'In Progress';
      case 'WAITING_FOR_PARTS':
        return 'Waiting for Parts';
      case 'COMPLETED':
        return 'Done';
      default:
        return status;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ACCEPTED':
        return Colors.blue;
      case 'IN_PROGRESS':
        return Colors.orangeAccent;
      case 'WAITING_FOR_PARTS':
        return Colors.amber;
      case 'COMPLETED':
        return Colors.greenAccent;
      default:
        return Colors.white38;
    }
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChipButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.blue : const Color(0xFF0F2038),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? Colors.blue : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white60,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _JobHistoryCard extends StatelessWidget {
  final String title;
  final String statusLabel;
  final Color statusColor;
  final String subtitle;
  final String location;

  const _JobHistoryCard({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.subtitle,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2038),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                ),
                child: Text(statusLabel,
                    style: TextStyle(
                        color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          if (location.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(location, style: const TextStyle(color: Colors.white38, fontSize: 11.5)),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// CUSTOMERS TAB — placeholder
// ===========================================================================
class _CustomersTab extends StatelessWidget {
  const _CustomersTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.people_alt_rounded, color: Colors.white.withValues(alpha: 0.2), size: 48),
          const SizedBox(height: 14),
          const Text('Your customers will show up here',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
        ],
      ),
    );
  }
}

// ===========================================================================
// PROFILE TAB
// ===========================================================================
class _ProfileTab extends StatelessWidget {
  final String name;
  final String mobileNumber;
  final double rating;
  final String category;
  final VoidCallback onLogout;

  const _ProfileTab({
    required this.name,
    required this.mobileNumber,
    required this.rating,
    required this.category,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: Colors.blue, size: 32),
                ),
                const SizedBox(height: 12),
                Text(name,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(mobileNumber, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                const SizedBox(height: 4),
                Text('★ $rating · $category',
                    style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _ProfileMenuTile(icon: Icons.edit_outlined, label: 'Edit profile', onTap: () {}),
          _ProfileMenuTile(icon: Icons.receipt_long_outlined, label: 'Payouts & earnings', onTap: () {}),
          _ProfileMenuTile(icon: Icons.support_agent_outlined, label: 'Help & support', onTap: () {}),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLogout,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.redAccent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 18),
              label: const Text('Log out', style: TextStyle(color: Colors.redAccent)),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileMenuTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: Colors.white60, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14)),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// BOTTOM NAV BAR — Home / Jobs / Scan (center) / Customers / Profile
// ===========================================================================
class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom > 0 ? 8 : 14, top: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F2038),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _NavItem(icon: Icons.home_rounded, label: 'Home', index: 0, currentIndex: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.work_rounded, label: 'Jobs', index: 1, currentIndex: currentIndex, onTap: onTap),
          _ScanNavItem(index: 2, currentIndex: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.people_rounded, label: 'Customers', index: 3, currentIndex: currentIndex, onTap: onTap),
          _NavItem(icon: Icons.person_rounded, label: 'Profile', index: 4, currentIndex: currentIndex, onTap: onTap),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    final color = selected ? Colors.blue : Colors.white38;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _ScanNavItem extends StatelessWidget {
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _ScanNavItem({required this.index, required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = index == currentIndex;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.blue : Colors.blue.withValues(alpha: 0.85),
          boxShadow: [
            BoxShadow(color: Colors.blue.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3)),
          ],
        ),
        child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
      ),
    );
  }
}