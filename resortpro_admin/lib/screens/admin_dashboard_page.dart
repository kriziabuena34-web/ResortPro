import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/admin_widgets.dart';
import '../services/app_router.dart';
import 'modules/analytics_page.dart';
import 'modules/expenses_page.dart';
import 'modules/terms_page.dart';
import 'modules/payment_accounts_page.dart';
import 'modules/availability_page.dart';
import 'modules/bookings_page.dart';
import 'modules/calendar_page.dart';
import 'modules/checkin_page.dart';
import 'modules/clients_page.dart';
import 'modules/gallery_page.dart';
import 'modules/messages_page.dart';
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
  String? _focusBookingId;

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
    (icon: Icons.forum_outlined, selectedIcon: Icons.forum, label: 'navMessages'),
    (icon: Icons.receipt_long_outlined, selectedIcon: Icons.receipt_long, label: 'navExpenses'),
    (icon: Icons.gavel_outlined, selectedIcon: Icons.gavel, label: 'navTerms'),
    (icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet, label: 'navPayAccounts'),
  ];

  /// Bahagi ng URL ng bawat module (kapareho ang pagkakasunod ng [_modules]).
  static const _slugs = [
    'dashboard', 'bookings', 'calendar', 'clients', 'verifications', 'payments', 'packages',
    'gallery', 'availability', 'reports', 'analytics', 'checkin', 'messages', 'expenses', 'terms', 'payment-accounts',
  ];

  static int _indexOfPath(String path) {
    final slug = path.replaceAll('/', '');
    final i = _slugs.indexOf(slug);
    return i < 0 ? 0 : i;
  }

  /// Kapag pinindot ang back/forward ng browser: lumipat sa module sa URL.
  void _onPathChanged() {
    final i = _indexOfPath(adminPath.value);
    if (i != _index && mounted) {
      setState(() {
        _index = i;
        _bookingFilter = null;
        _focusBookingId = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _index = _indexOfPath(adminPath.value);
    adminPath.addListener(_onPathChanged);
    if (!_slugs.contains(adminPath.value.replaceAll('/', ''))) {
      WidgetsBinding.instance.addPostFrameCallback((_) => adminPath.value = '/${_slugs[_index]}');
    }
    _fetchData();
    _notifications.load();
    _notifications.subscribe(_onNewNotification);
  }

  @override
  void dispose() {
    adminPath.removeListener(_onPathChanged);
    _notifications.unsubscribe();
    super.dispose();
  }

  /// May bagong notification (real-time): i-refresh ang data at magpakita ng toast.
  void _onNewNotification(Map<String, dynamic> n) {
    _fetchData();
    if (!mounted) return;
    // Nasa Messages na: doon na makikita ang bagong mensahe (walang toast).
    if (n['type'] == 'chat_message' && _index == 12) return;
    // Lalabas sa itaas (kanan kapag malapad ang screen) para hindi matakpan ang mga button sa ibaba.
    final size = MediaQuery.of(context).size;
    final wide = size.width > 700;
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final type = n['type'] as String?;
    final color = notificationColor(type);
    void open() {
      messenger.hideCurrentSnackBar();
      _notifications.markRead(n);
      _openModule(notificationModule(type), notificationOpenFilter(n));
    }

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        dismissDirection: DismissDirection.up,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: wide ? EdgeInsets.only(left: size.width - 436, right: 20, bottom: size.height - 200) : null,
        content: Material(
          color: Colors.white,
          elevation: 10,
          shadowColor: const Color(0x33000000),
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: open,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: color, width: 4)),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(11)),
                    child: Icon(notificationIcon(type), color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titleCase(notificationTitle(n)),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.text)),
                        const SizedBox(height: 2),
                        Text(notificationBody(n),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.35)),
                        const SizedBox(height: 6),
                        Text(tr('ntTapToView'),
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: messenger.hideCurrentSnackBar,
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Ilagay o palitan ang sariling pangalan ng naka-login na admin.
  Future<void> _editMyName() async {
    final current = (staffNameOf(supabase.auth.currentUser?.id) ?? '').split(' ');
    final first = TextEditingController(text: current.length > 1 ? current.sublist(0, current.length - 1).join(' ') : current.first);
    final last = TextEditingController(text: current.length > 1 ? current.last : '');
    // Posisyon: pinipili na lang (hindi na tina-type).
    const positions = ['Owner', 'Assistant / Caretaker', 'Staff'];
    final savedTitle = (currentStaffTitle() ?? '').trim();
    String? position = savedTitle.isEmpty ? null : savedTitle;
    String? error;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(tr('yourNameTitle')),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(tr('yourNameHelp'), style: const TextStyle(color: AppColors.muted)),
                const SizedBox(height: 14),
                TextField(
                  controller: first,
                  maxLength: 50,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('firstName')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: last,
                  maxLength: 50,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: tr('lastName')),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: position,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('staffPosition')),
                  items: [
                    for (final p in [...positions, if (position != null && !positions.contains(position)) position!])
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: (v) => setLocal(() => position = v),
                ),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Text(error!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
            FilledButton(
              onPressed: () async {
                if (first.text.trim().isEmpty || last.text.trim().isEmpty) {
                  setLocal(() => error = tr('nameRequired'));
                  return;
                }
                if (position == null) {
                  setLocal(() => error = tr('positionRequired'));
                  return;
                }
                try {
                  await saveMyStaffName(first.text, last.text, title: position);
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (e) {
                  setLocal(() => error = tr('failed', {'e': e}));
                }
              },
              child: Text(tr('save')),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    last.dispose();
    if (saved == true && mounted) {
      showToast(context, tr('nameSaved'));
      setState(() {});
    }
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
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFFECACA), width: 6),
                    ),
                    child: const Icon(Icons.logout_rounded, color: AppColors.danger, size: 24),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('logoutQ'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  tr('logoutMsg', {'name': staffNameOf(supabase.auth.currentUser?.id) ?? 'Admin'}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.4),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(tr('cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          backgroundColor: AppColors.danger,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: Text(tr('logout')),
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
    if (ok != true) return;

    await supabase.auth.signOut();
    adminPath.value = '/dashboard';
    adminSignedIn.value = false;
  }

  void _openModule(int index, [String? bookingFilter, String? focusBookingId]) {
    setState(() {
      _index = index;
      _bookingFilter = bookingFilter;
      _focusBookingId = focusBookingId;
    });
    // Bagong entry sa history ng browser (para gumana ang ← at →).
    adminPath.value = '/${_slugs[index]}';
  }

  int get _pendingCount => _data?.pendingAccounts.length ?? 0;
  int get _toConfirmCount => _data?.bookings.where((b) => b['status'] == 'reserved').length ?? 0;

  int _countFor(int i) => switch (i) {
        1 => _toConfirmCount,
        4 => _pendingCount,
        5 => (_data?.pendingPayments.length ?? 0) + (_data?.pendingRefunds.length ?? 0),
        12 => _data?.unreadChats ?? 0,
        _ => 0,
      };

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
            // Bilang ng hindi pa nababasa + mga kailangang asikasuhin (Needs Attention).
            isLabelVisible: unread + reminders > 0,
            label: Text('${unread + reminders}'),
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

        final actions = <Widget>[
          _bellButton(),
          const LanguageMenuButton(),
          const SizedBox(width: 4),
        ];

        if (wide) {
          return Scaffold(
            key: _scaffoldKey,
            endDrawer: _endDrawer(),
            body: Stack(
              children: [
                Row(
                  children: [
                    const SizedBox(width: _HoverSidebar.collapsedWidth),
                    Expanded(
                      child: Column(
                        children: [
                          _TopBar(title: titleCase(tr(_modules[_index].label)), actions: actions),
                          Expanded(child: AmbientBackground(child: _buildBody())),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _HoverSidebar(
                    builder: (expanded) => _Sidebar(
                  extended: expanded,
                  selected: _index,
                  labels: [for (final m in _modules) titleCase(tr(m.label))],
                  icons: [for (final m in _modules) m.icon],
                  selectedIcons: [for (final m in _modules) m.selectedIcon],
                  counts: [for (var i = 0; i < _modules.length; i++) _countFor(i)],
                  email: supabase.auth.currentUser?.email ?? '',
                  staffName: staffNameOf(supabase.auth.currentUser?.id),
                  staffTitle: currentStaffTitle(),
                  onEditName: _editMyName,
                  onSelect: _openModule,
                  onLogout: _logout,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            title: Text(titleCase(tr(_modules[_index].label))),
            actions: [...actions, const SizedBox(width: 4)],
          ),
          endDrawer: _endDrawer(),
          drawer: Drawer(
            width: 280,
            backgroundColor: AppColors.ink,
            child: _Sidebar(
              extended: true,
              selected: _index,
              labels: [for (final m in _modules) titleCase(tr(m.label))],
              icons: [for (final m in _modules) m.icon],
              selectedIcons: [for (final m in _modules) m.selectedIcon],
              counts: [for (var i = 0; i < _modules.length; i++) _countFor(i)],
              email: supabase.auth.currentUser?.email ?? '',
              staffName: staffNameOf(supabase.auth.currentUser?.id),
              staffTitle: currentStaffTitle(),
              onEditName: () {
                Navigator.pop(context);
                _editMyName();
              },
              onSelect: (i) {
                Navigator.pop(context);
                _openModule(i);
              },
              onLogout: _logout,
            ),
          ),
          body: AmbientBackground(child: _buildBody()),
        );
      },
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
          onOpenPayments: (id) => _openModule(5, 'pending', id),
          onOpenCheckin: (id) => _openModule(11, null, id),
        ),
      2 => CalendarPage(data: data),
      3 => ClientsPage(data: data),
      4 => VerificationsPage(data: data, onChanged: _fetchData),
      5 => PaymentsPage(
          key: ValueKey('payments-${_bookingFilter ?? ''}-${_focusBookingId ?? ''}'),
          data: data,
          onChanged: _fetchData,
          showPendingFirst: _bookingFilter == 'pending',
          initialTab: _bookingFilter == 'refunds' ? 'refunds' : null,
          focusBookingId: _focusBookingId,
        ),
      6 => PackagesPage(data: data, onChanged: _fetchData),
      7 => const GalleryPage(),
      8 => AvailabilityPage(data: data, onChanged: _fetchData),
      9 => ReportsPage(data: data),
      11 => CheckinPage(
          key: ValueKey('checkin-${_focusBookingId ?? ''}'),
          data: data,
          onChanged: _fetchData,
          onOpenBookings: () => _openModule(1),
          focusBookingId: _focusBookingId,
        ),
      12 => MessagesPage(
          key: ValueKey('messages-${_bookingFilter ?? ''}'),
          onUnreadChanged: _fetchData,
          initialClientId: (_bookingFilter ?? '').startsWith('chat:') ? _bookingFilter!.substring(5) : null,
        ),
      13 => ExpensesPage(data: data, onChanged: _fetchData),
      14 => const TermsPage(),
      15 => const PaymentAccountsPage(),
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
    this.staffName,
    this.staffTitle,
    this.onEditName,
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
  final String? staffName;
  final String? staffTitle;
  final VoidCallback? onEditName;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  static const _groups = [
    ('navGroupMain', [0, 1, 11, 2]),
    ('navGroupGuests', [3, 12, 4, 5]),
    ('navGroupResort', [6, 7, 8, 14, 15]),
    ('navGroupInsights', [9, 10, 13]),
  ];

  @override
  Widget build(BuildContext context) {
    final shown = staffName ?? email;
    final initial = shown.isEmpty ? 'A' : shown[0].toUpperCase();

    return Container(
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
                  Image.asset('assets/images/aryana_logo.png', width: 44, height: 44, filterQuality: FilterQuality.medium),
                  if (extended) ...[
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ResortPro',
                            style: TextStyle(
                              fontFamily: 'Poppins',
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
                          backgroundColor: const Color(0xFF2B4C6B),
                          child: Text(
                            initial,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: onEditName,
                            borderRadius: BorderRadius.circular(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  staffName ?? tr('setYourName'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: staffName == null ? const Color(0xFF7DD3FC) : Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  staffTitle ?? tr('adminRole'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.inkText, fontSize: 12),
                                ),
                              ],
                            ),
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

/// Sidebar na makitid (icons lang) at lumalapad kapag itinapat ang cursor.
/// Lumalabas ito sa ibabaw ng page, kaya hindi gumagalaw ang laman.
class _HoverSidebar extends StatefulWidget {
  const _HoverSidebar({required this.builder});

  static const collapsedWidth = 80.0;
  static const expandedWidth = 264.0;

  final Widget Function(bool expanded) builder;

  @override
  State<_HoverSidebar> createState() => _HoverSidebarState();
}

class _HoverSidebarState extends State<_HoverSidebar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        width: _hover ? _HoverSidebar.expandedWidth : _HoverSidebar.collapsedWidth,
        decoration: BoxDecoration(
          boxShadow: _hover
              ? const [BoxShadow(color: Color(0x40000000), blurRadius: 28, offset: Offset(8, 0))]
              : const [],
        ),
        child: LayoutBuilder(
          // Ipakita lang ang mga label kapag sapat na ang lapad (iwas overflow habang nag-a-animate).
          builder: (context, c) => widget.builder(c.maxWidth >= 220),
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
                          color: selected ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${widget.count}',
                          style: TextStyle(
                            color: Colors.white,
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
                    fontFamily: 'Poppins',
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    height: 1.15,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 13, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      date,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
