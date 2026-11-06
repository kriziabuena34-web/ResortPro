import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_widgets.dart';
import 'admin_login_page.dart';
import 'modules/analytics_page.dart';
import 'modules/availability_page.dart';
import 'modules/bookings_page.dart';
import 'modules/calendar_page.dart';
import 'modules/checkin_page.dart';
import 'modules/clients_page.dart';
import 'modules/gallery_page.dart';
import 'modules/overview_page.dart';
import 'modules/packages_page.dart';
import 'modules/payments_page.dart';
import 'modules/reports_page.dart';
import 'modules/verifications_page.dart';
import 'notifications_panel.dart';

/// Main admin panel. May sidebar (sa malapad na screen) o drawer
/// (sa phone) papunta sa bawat module.
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final supabase = Supabase.instance.client;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _notifications = NotificationService.instance;

  AdminData? _data;
  bool _isLoading = true;
  String? _error;
  int _index = 0;

  /// Filter na ipapasa sa Bookings module (galing sa reminders).
  String? _bookingFilter;

  // Ang pagkakasunod dito ang index na ginagamit ng onOpenModule.
  // Ang `label` ay translation key (tingnan ang l10n/app_strings.dart).
  static const _modules = [
    (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'navDashboard'),
    (icon: Icons.event_note_outlined, selectedIcon: Icons.event_note, label: 'navBookings'),
    (icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, label: 'navCalendar'),
    (icon: Icons.people_outline, selectedIcon: Icons.people, label: 'navClients'),
    (icon: Icons.verified_user_outlined, selectedIcon: Icons.verified_user, label: 'navVerifications'),
    (icon: Icons.payments_outlined, selectedIcon: Icons.payments, label: 'navPayments'),
    (icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2, label: 'navPackages'),
    (icon: Icons.photo_library_outlined, selectedIcon: Icons.photo_library, label: 'navGallery'),
    (icon: Icons.event_busy_outlined, selectedIcon: Icons.event_busy, label: 'navAvailability'),
    (icon: Icons.summarize_outlined, selectedIcon: Icons.summarize, label: 'navReports'),
    (icon: Icons.insights_outlined, selectedIcon: Icons.insights, label: 'navAnalytics'),
    (icon: Icons.qr_code_scanner_outlined, selectedIcon: Icons.qr_code_scanner, label: 'navCheckin'),
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _notifications.load();
    _notifications.subscribe(_onNewNotification);
  }

  @override
  void dispose() {
    _notifications.unsubscribe();
    super.dispose();
  }

  /// May bagong notification (real-time): i-refresh ang data at magpakita ng toast.
  void _onNewNotification(Map<String, dynamic> n) {
    _fetchData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(notificationIcon(n['type'] as String?), color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notificationTitle(n), style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(notificationBody(n)),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: tr('view'),
          onPressed: () {
            _notifications.markRead(n);
            _openModule(
              notificationModule(n['type'] as String?),
              notificationFilter(n['type'] as String?),
            );
          },
        ),
      ),
    );
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await AdminData.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '$e';
      });
      if (_data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('loadFailedToast', {'e': e}))),
        );
      }
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('logoutQ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('logout'))),
        ],
      ),
    );
    if (ok != true) return;

    await supabase.auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const AdminLoginPage()),
    );
  }

  void _openModule(int index, [String? bookingFilter]) => setState(() {
        _index = index;
        _bookingFilter = bookingFilter;
      });

  int get _pendingCount => _data?.pendingAccounts.length ?? 0;
  int get _toConfirmCount => _data?.bookings.where((b) => b['status'] == 'reserved').length ?? 0;

  int _countFor(int i) => switch (i) {
        1 => _toConfirmCount,
        4 => _pendingCount,
        5 => _data?.pendingPayments.length ?? 0,
        _ => 0,
      };

  Widget _moduleIcon(int i, {required bool selected}) {
    final m = _modules[i];
    final icon = Icon(selected ? m.selectedIcon : m.icon);
    final count = _countFor(i);
    if (count > 0) {
      return Badge(label: Text('$count'), child: icon);
    }
    return icon;
  }

  Widget _bellButton() {
    return ListenableBuilder(
      listenable: _notifications,
      builder: (context, _) {
        final reminders = _data == null ? 0 : remindersFor(_data!).length;
        final unread = _notifications.unreadCount;
        return IconButton(
          tooltip: tr('notifications'),
          onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          icon: Badge(
            isLabelVisible: unread + reminders > 0,
            label: Text(unread > 0 ? '$unread' : '!'),
            child: Icon(unread > 0 ? Icons.notifications_active : Icons.notifications_none),
          ),
        );
      },
    );
  }

  Widget _endDrawer() => NotificationsPanel(data: _data, onOpen: _openModule);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        final extended = constraints.maxWidth >= 1100;

        final actions = <Widget>[
          _bellButton(),
          const LanguageMenuButton(),
          IconButton(
            tooltip: tr('refresh'),
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _isLoading ? null : _fetchData,
          ),
        ];

        if (wide) {
          return Scaffold(
            key: _scaffoldKey,
            endDrawer: _endDrawer(),
            body: Row(
              children: [
                _Sidebar(
                  extended: extended,
                  selected: _index,
                  labels: [for (final m in _modules) tr(m.label)],
                  icons: [for (final m in _modules) m.icon],
                  selectedIcons: [for (final m in _modules) m.selectedIcon],
                  counts: [for (var i = 0; i < _modules.length; i++) _countFor(i)],
                  email: supabase.auth.currentUser?.email ?? '',
                  onSelect: _openModule,
                  onLogout: _logout,
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(title: tr(_modules[_index].label), actions: actions),
                      Expanded(child: AmbientBackground(child: _buildBody())),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(tr(_modules[_index].label)),
            actions: [...actions, const SizedBox(width: 4)],
          ),
          endDrawer: _endDrawer(),
          drawer: Drawer(
            width: 280,
            backgroundColor: AppColors.ink,
            child: _Sidebar(
              extended: true,
              selected: _index,
              labels: [for (final m in _modules) tr(m.label)],
              icons: [for (final m in _modules) m.icon],
              selectedIcons: [for (final m in _modules) m.selectedIcon],
              counts: [for (var i = 0; i < _modules.length; i++) _countFor(i)],
              email: supabase.auth.currentUser?.email ?? '',
              onSelect: (i) {
                Navigator.pop(context);
                _openModule(i);
              },
              onLogout: _logout,
            ),
          ),
          body: AmbientBackground(child: _buildBody()),
          // Bottom navigation (phone): priority modules muna, ang iba ay nasa "More".
          bottomNavigationBar: NavigationBar(
            selectedIndex: _priorityModules.contains(_index)
                ? _priorityModules.indexOf(_index)
                : _priorityModules.length,
            onDestinationSelected: (i) {
              if (i < _priorityModules.length) {
                _openModule(_priorityModules[i]);
              } else {
                _showMoreModules();
              }
            },
            destinations: [
              for (final m in _priorityModules)
                NavigationDestination(
                  icon: _moduleIcon(m, selected: false),
                  selectedIcon: _moduleIcon(m, selected: true),
                  label: tr(_modules[m].label),
                ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: !_priorityModules.contains(_index),
                  smallSize: 8,
                  child: const Icon(Icons.more_horiz),
                ),
                label: tr('navMore'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Mga module na laging nasa bottom bar kapag naka-phone (pinakamadalas gamitin).
  static const _priorityModules = [0, 1, 11, 5]; // Dashboard, Bookings, Check-in/out, Payments

  void _showMoreModules() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _modules.length; i++)
              if (!_priorityModules.contains(i))
                ListTile(
                  leading: _moduleIcon(i, selected: i == _index),
                  title: Text(tr(_modules[i].label)),
                  selected: i == _index,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openModule(i);
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final data = _data;

    if (data == null) {
      if (_isLoading) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 12),
              Text('${tr('loadFailed')}\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _fetchData, child: Text(tr('tryAgain'))),
            ],
          ),
        ),
      );
    }

    final Widget page = switch (_index) {
      0 => OverviewPage(data: data, onOpen: _openModule),
      1 => BookingsPage(
          key: ValueKey('bookings-${_bookingFilter ?? ''}'),
          data: data,
          onChanged: _fetchData,
          initialFilter: _bookingFilter,
        ),
      2 => CalendarPage(data: data),
      3 => ClientsPage(data: data),
      4 => VerificationsPage(data: data, onChanged: _fetchData),
      5 => PaymentsPage(
          key: ValueKey('payments-${_bookingFilter ?? ''}'),
          data: data,
          onChanged: _fetchData,
          showPendingFirst: _bookingFilter == 'pending',
        ),
      6 => PackagesPage(data: data, onChanged: _fetchData),
      7 => const GalleryPage(),
      8 => AvailabilityPage(data: data, onChanged: _fetchData),
      9 => ReportsPage(data: data),
      11 => CheckinPage(data: data, onChanged: _fetchData, onOpenBookings: () => _openModule(1)),
      _ => AnalyticsPage(data: data),
    };

    return Column(
      children: [
        SizedBox(
          height: 2,
          child: _isLoading ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(child: page),
      ],
    );
  }
}


/// Madilim na sidebar na naka-grupo ang mga module.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.extended,
    required this.selected,
    required this.labels,
    required this.icons,
    required this.selectedIcons,
    required this.counts,
    required this.email,
    required this.onSelect,
    required this.onLogout,
  });

  final bool extended;
  final int selected;
  final List<String> labels;
  final List<IconData> icons;
  final List<IconData> selectedIcons;
  final List<int> counts;
  final String email;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  static const _groups = [
    ('navGroupMain', [0, 1, 11, 2]),
    ('navGroupGuests', [3, 4, 5]),
    ('navGroupResort', [6, 7, 8]),
    ('navGroupInsights', [9, 10]),
  ];

  @override
  Widget build(BuildContext context) {
    final initial = email.isEmpty ? 'A' : email[0].toUpperCase();

    return Container(
      width: extended ? 264 : 80,
      decoration: const BoxDecoration(color: AppColors.ink),
      clipBehavior: Clip.hardEdge,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Brand
            Padding(
              padding: EdgeInsets.fromLTRB(extended ? 20 : 0, 22, extended ? 20 : 0, 18),
              child: Row(
                mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF14B8A6), AppColors.primary],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.beach_access_rounded, color: Colors.white, size: 22),
                  ),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ResortPro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            "Aryana's Guests House",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppColors.inkText, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(color: AppColors.inkLine, height: 1),

            // Mga module
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: extended ? 12 : 10, vertical: 8),
                children: [
                  for (final g in _groups) ...[
                    if (extended)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                        child: Text(
                          tr(g.$1).toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF6B8299),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                          ),
                        ),
                      )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        child: Divider(color: AppColors.inkLine, height: 1),
                      ),
                    for (final i in g.$2)
                      _NavItem(
                        extended: extended,
                        selected: i == selected,
                        icon: i == selected ? selectedIcons[i] : icons[i],
                        label: labels[i],
                        count: counts[i],
                        onTap: () => onSelect(i),
                      ),
                  ],
                ],
              ),
            ),

            // Naka-login na admin
            const Divider(color: AppColors.inkLine, height: 1),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: extended ? 16 : 0, vertical: 14),
              child: extended
                  ? Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.accent,
                          child: Text(
                            initial,
                            style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr('adminRole'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.inkText, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: tr('logout'),
                          onPressed: onLogout,
                          icon: const Icon(Icons.logout_rounded, color: AppColors.inkText, size: 20),
                        ),
                      ],
                    )
                  : Center(
                      child: IconButton(
                        tooltip: tr('logout'),
                        onPressed: onLogout,
                        icon: const Icon(Icons.logout_rounded, color: AppColors.inkText),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.extended,
    required this.selected,
    required this.icon,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final bool extended;
  final bool selected;
  final IconData icon;
  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final fg = selected ? Colors.white : (_hover ? Colors.white : AppColors.inkText);
    final bg = selected
        ? AppColors.primary
        : _hover
            ? AppColors.inkRaised
            : Colors.transparent;

    final icon = widget.count > 0 && !widget.extended
        ? Badge(label: Text('${widget.count}'), child: Icon(widget.icon, color: fg, size: 21))
        : Icon(widget.icon, color: fg, size: 21);

    final tile = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.extended ? 12 : 0, vertical: 10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
          child: widget.extended
              ? Row(
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fg,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (widget.count > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected ? Colors.white.withValues(alpha: 0.22) : AppColors.accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${widget.count}',
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                )
              : Center(child: icon),
        ),
      ),
    );

    return widget.extended ? tile : Tooltip(message: widget.label, child: tile);
  }
}

/// Header sa itaas ng bawat module (malapad na screen).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.actions});
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = '${weekdaysTr[now.weekday % 7]}, ${monthNamesTr[now.month - 1]} ${now.day}, ${now.year}';

    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(date, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
