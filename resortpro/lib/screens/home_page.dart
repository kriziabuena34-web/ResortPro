import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notifications.dart';
import '../services/offline_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/notification_banner.dart';
import '../widgets/ui_kit.dart';
import 'account_page.dart';
import 'booking_page.dart';
import 'chat_page.dart';
import 'my_booking_page.dart';
import 'info_pages.dart';
import 'my_receipt_list_page.dart';
import 'notifications_page.dart';
import 'resort_map_page.dart';
import 'sign_in_page.dart';
import '../services/session.dart';

// PACKAGE MODEL

class Package {
  final int id;
  final String name;
  final double price;
  final String? startTime;
  final String? endTime;
  final int? minPax;
  final int? maxPax;
  final List<String> inclusions;
  final List<String> additional;

  Package({
    required this.id,
    required this.name,
    required this.price,
    this.startTime,
    this.endTime,
    this.minPax,
    this.maxPax,
    required this.inclusions,
    required this.additional,
  });

  factory Package.fromJson(Map<String, dynamic> json) {
    return Package(
      id: json['id'] as int,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      startTime: json['start_time'] as String?,
      endTime: json['end_time'] as String?,
      minPax: json['min_pax'] as int?,
      maxPax: json['max_pax'] as int?,
      inclusions: List<String>.from(json['inclusions'] ?? []),
      additional: List<String>.from(json['additional'] ?? []),
    );
  }

  String get formattedPrice =>
      '₱${price.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
      )}';

  String get formattedDuration {
    if (startTime == null || endTime == null) return 'Contact us for schedule';
    return '${_formatTime(startTime!)} - ${_formatTime(endTime!)}';
  }

  String _formatTime(String time) {
    // time comes back like "07:00:00"
    final parts = time.split(':');
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:$minute $period';
  }

  String get formattedCapacity {
    if (minPax == null || maxPax == null) return 'Contact us for capacity';
    return '$minPax-$maxPax pax';
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final PageController _carouselController = PageController();
  final ScrollController _scrollController = ScrollController();
  final supabase = Supabase.instance.client;

  /// Para sa "Book a stay" button: dito mag-i-scroll (Package Offered).
  final _packagesKey = GlobalKey();

  // ---------- EASY SETTINGS (SPACING) ----------
  // Left/right margin shared by every section on the page
  static const double _pagePadding = 16;
  // Space above the first item and below the last item
  static const double _topSpace = 16;
  static const double _bottomSpace = 32;
  // Space between big sections (Resort Info, Packages, Contact...)
  static const double _sectionGap = 28;
  // Space between a section title and its content
  static const double _titleGap = 12;
  // Vertical space between package cards (each card gets half on top/bottom)
  static const double _cardGap = 12;
  // Space between lines inside an expanded package card
  static const double _itemGap = 6;
  // Carousel height
  static const double _carouselHeight = 230;
  // ---------------------------------------------

  final List<String> _resortImages = [
    'assets/images/pic1.jpg',
    'assets/images/pic2.jpg',
    'assets/images/pic3.jpg',
    'assets/images/pic4.jpg',
  ];

  List<Package> _packages = [];
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _offlineSavedAt; // kapag offline: kailan na-save ang ipinapakitang packages

  // Gallery photos mula sa admin (kapag wala, gagamitin ang _resortImages).
  List<Map<String, dynamic>> _gallery = [];
  int _carouselPage = 0;
  Timer? _carouselTimer;

  // Search at filter ng packages
  final _packageSearch = TextEditingController();
  String _packageQuery = '';
  String _packageFilter = 'all'; // all, packages, hall
  String _packageSort = 'default'; // default, low, high

  // Bottom navigation (priority): Home, Bookings, Receipts, Account.
  // Ang iba (Help, Terms, About, Sign out) ay nasa "More" sa tabi ng bell.
  static const _tabTitles = ["Aryana's Guests House", 'My Bookings', 'My Receipts', 'Account'];

  final _notifications = UserNotifications.instance;

  /// Username ng account (makikita sa "Hi, ...!"). Null kapag wala pa.
  String? _username;

  @override
  void initState() {
    super.initState();
    _notifications.latest.addListener(_onRealtimeNotification);
    _fetchPackages();
    _fetchGallery();
    _fetchUsername();
    _startNotifications();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) => _autoSlide());
  }

  Future<void> _startNotifications() async {
    // Kapag pinindot ang phone notification, buksan ang Notifications.
    LocalNotifier.onTap = (_) {
      if (mounted) _openNotifications();
    };
    if (await LocalNotifier.launchedFromNotification() && mounted) {
      _openNotifications();
    }
    await _notifications.start();
  }

  void _autoSlide() {
    final count = _carouselCount;
    if (count < 2 || !_carouselController.hasClients || _selectedIndex != 0) return;
    _carouselController.animateToPage(
      (_carouselPage + 1) % count,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  int get _carouselCount => _gallery.isNotEmpty ? _gallery.length : _resortImages.length;

  Future<void> _fetchGallery() async {
    try {
      final rows = await supabase
          .from('gallery_images')
          .select()
          .eq('show_on_landing', true)
          .order('sort_order')
          .order('id');
      if (!mounted) return;
      setState(() => _gallery = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      // Walang gallery table pa: mananatili ang default na photos.
    }
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _packageSearch.dispose();
    LocalNotifier.onTap = null;
    _carouselController.dispose();
    _scrollController.dispose();
    _notifications.latest.removeListener(_onRealtimeNotification);
    super.dispose();
  }

  /// Realtime: may bagong notification habang bukas ang app → in-app banner.
  void _onRealtimeNotification() {
    final n = _notifications.latest.value;
    if (n == null || !mounted) return;
    final isChat = n['type'] == 'chat_message';
    // Bukas na ang chat: doon na makikita ang mensahe, walang banner.
    if (isChat && ChatPage.isOpen) return;
    InAppNotificationBanner.show(context, n, onOpen: isChat ? _openChat : _openNotifications);
  }

  /// Bubukas ang Chat sa resort; pagbalik, i-refresh ang notifications (nabasa na ang mga sagot).
  Future<void> _openChat() async {
    await Navigator.push(context, MaterialPageRoute(builder: (context) => const ChatPage()));
    if (mounted) _notifications.load();
  }

  /// Ilang sagot ng resort ang hindi pa nababasa (para sa badge ng Chat).
  int get _unreadChat =>
      _notifications.items.where((n) => n['type'] == 'chat_message' && n['is_read'] != true).length;

  // FETCH PACKAGES FROM SUPABASE

  Future<void> _fetchPackages() async {
    try {
      final data = await supabase
          .from('packages')
          .select()
          .order('id', ascending: true);

      final list = List<Map<String, dynamic>>.from(data as List);
      // I-save para may maipakita kahit walang internet.
      OfflineCache.save('packages', list, perUser: false);
      if (!mounted) return;
      setState(() {
        _packages = list.map(Package.fromJson).toList();
        _errorMessage = null;
        _offlineSavedAt = null;
        _isLoading = false;
      });
    } catch (e) {
      final cached = isOfflineError(e) ? await OfflineCache.load('packages', perUser: false) : null;
      if (!mounted) return;
      setState(() {
        if (cached != null) {
          _packages = [
            for (final j in cached.data as List) Package.fromJson(Map<String, dynamic>.from(j as Map)),
          ];
          _offlineSavedAt = cached.savedAt;
          _errorMessage = null;
        } else {
          _errorMessage = friendlyError(e, action: 'load the packages');
        }
        _isLoading = false;
      });
    }
  }

  /// Bubukas ang Notifications (galing sa bell icon sa itaas o sa phone notification).
  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationsPage()),
    );
  }

  /// Kunin ang username (naka-save din para gumana offline).
  Future<void> _fetchUsername() async {
    final cached = await OfflineCache.load('username');
    if (cached != null && mounted && _username == null) {
      final c = '${cached.data ?? ''}'.trim();
      if (c.isNotEmpty) setState(() => _username = c);
    }
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;
      final p = await supabase.from('profiles').select('username').eq('id', uid).maybeSingle();
      final u = '${p?['username'] ?? ''}'.trim();
      await OfflineCache.save('username', u);
      if (mounted) setState(() => _username = u.isEmpty ? null : u);
    } catch (_) {}
  }

  void _onNavigationItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    // Pagbalik sa Home: kunin ulit ang username (baka pinalitan sa Account).
    if (index == 0) _fetchUsername();
  }

  // "MORE" SHEET: mga item na hindi kasya sa bottom navigation

  void _showMoreSheet() {
    void open(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (context) => page));
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Help and Support'),
              onTap: () => open(const HelpSupportPage()),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms & Conditions'),
              onTap: () => open(const TermsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () => open(const AboutUsPage()),
            ),
            ListTile(
              leading: const Icon(Icons.switch_account_outlined),
              title: const Text('Switch Account'),
              onTap: () {
                Navigator.pop(sheetContext);
                _switchAccount();
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Sign Out', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                _confirmSignOut();
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// Mag-sign out tapos ipakita agad ang Google account picker para pumili ng ibang account.
  Future<void> _switchAccount() async {
    await signOutCompletely();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SignInPage(openAccountPicker: true)),
      (route) => false,
    );
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to book or view your bookings.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Sign Out')),
        ],
      ),
    );
    if (ok != true) return;
    await signOutCompletely();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const SignInPage()),
      (route) => false,
    );
  }

  // BOOK NOW VERIFICATION CHECK

  Future<void> _handleBookNow(Package pkg) async {
    // Kailangan ng internet sa pag-book: sabihin agad kapag offline.
    if (!await hasInternet()) {
      if (mounted) showOfflineSnack(context);
      return;
    }
    try {
      final userId = supabase.auth.currentUser!.id;
      final profile = await supabase
          .from('profiles')
          .select('verification_status')
          .eq('id', userId)
          .single();

      final status = profile['verification_status'];

      if (status != 'verified') {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Account Not Verified'),
              content: Text(
                status == 'pending'
                    ? 'Your account is still under review. Please wait for admin approval before booking.'
                    : 'Please verify your account first before booking. Go to the Account tab to get started.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BookingPage(package: pkg),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e, action: 'check your account'))),
        );
      }
    }
  }

  // MAIN PAGE CONTENT

  Widget _buildCurrentPage() {
    switch (_selectedIndex) {
      case 1:
        return const MyBookingPage(embedded: true);

      case 2:
        return const MyReceiptListPage(embedded: true);

      case 3:
        return const AccountPage();

      case 0:
      default:
        return _buildHomeContent();
    }
  }

  // SECTION TITLE (same margin and gap everywhere)

  Widget _sectionTitle(String text, {Key? key, String? subtitle}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, _titleGap),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF14B8A6), AppColors.primary],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // HOME CONTENT

  Widget _buildHomeContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return OfflineEmpty(
        message: _errorMessage!,
        onRetry: () {
          setState(() => _isLoading = true);
          _fetchPackages();
        },
      );
    }

    // Search, filter, at sort ng packages
    final q = _packageQuery.trim().toLowerCase();
    final shown = _packages.where((p) {
      final isHall = p.name.startsWith('Function Hall');
      if (_packageFilter == 'packages' && isHall) return false;
      if (_packageFilter == 'hall' && !isHall) return false;
      if (q.isEmpty) return true;
      return p.name.toLowerCase().contains(q) ||
          p.inclusions.any((i) => i.toLowerCase().contains(q));
    }).toList();
    if (_packageSort == 'low') shown.sort((a, b) => a.price.compareTo(b.price));
    if (_packageSort == 'high') shown.sort((a, b) => b.price.compareTo(a.price));

    // Split packages: main offers vs Function Hall variants
    final mainPackages =
    shown.where((p) => !p.name.startsWith('Function Hall')).toList();
    final otherPackages =
    shown.where((p) => p.name.startsWith('Function Hall')).toList();

    final user = supabase.auth.currentUser;
    final fullName = '${user?.userMetadata?['full_name'] ?? ''}'.trim();
    final firstName = _username ?? (fullName.isEmpty ? 'Guest' : fullName.split(' ').first);

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_fetchPackages(), _fetchGallery(), _fetchUsername()]);
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: _topSpace),

            if (_offlineSavedAt != null)
              OfflineNotice(
                savedAt: _offlineSavedAt!,
                margin: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, 12),
                onRetry: () {
                  setState(() => _isLoading = true);
                  _fetchPackages();
                },
              ),

            // WELCOME BANNER (katulad ng dashboard ng admin)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.ink, Color(0xFF0E4D5A), AppColors.primary],
                  ),
                  boxShadow: floatShadow,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hi, $firstName!',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            "Ready for your next stay at Aryana's Guests House?",
                            style: TextStyle(color: Color(0xFFCFE3E6), fontSize: 13.5, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.beach_access_rounded, color: Colors.white, size: 28),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),

            // QUICK ACTIONS (neumorphic)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Row(
                children: [
                  for (final (i, a) in <(IconData, String, VoidCallback)>[
                    (Icons.event_available, 'Book', () => _scrollToPackages()),
                    (Icons.chat_bubble_outline, 'Chat', _openChat),
                    (Icons.map_outlined, 'Map', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResortMapPage()))),
                  ].indexed) ...[
                    if (i > 0) const SizedBox(width: 12),
                    Expanded(
                      child: NeuCard(
                        radius: 18,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        onTap: a.$3,
                        child: Column(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
                                boxShadow: const [
                                  BoxShadow(color: Color(0x400F766E), blurRadius: 10, offset: Offset(0, 4)),
                                ],
                              ),
                              child: a.$2 == 'Chat'
                                  // Badge: mga sagot ng resort na hindi pa nababasa
                                  ? ListenableBuilder(
                                      listenable: _notifications,
                                      builder: (context, _) => Badge(
                                        isLabelVisible: _unreadChat > 0,
                                        label: Text('$_unreadChat'),
                                        child: Icon(a.$1, color: Colors.white, size: 21),
                                      ),
                                    )
                                  : Icon(a.$1, color: Colors.white, size: 21),
                            ),
                            const SizedBox(height: 8),
                            Text(a.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: _sectionGap),

            // GALLERY CAROUSEL (galing sa Gallery ng admin; default photos kung wala pa)
            _sectionTitle('GALLERY', subtitle: 'A peek at the resort'),
            SizedBox(
              height: _carouselHeight,
              child: PageView.builder(
                controller: _carouselController,
                itemCount: _carouselCount,
                onPageChanged: (i) => setState(() => _carouselPage = i),
                itemBuilder: (context, index) {
                  final fromGallery = _gallery.isNotEmpty;
                  final caption = fromGallery ? '${_gallery[index]['caption'] ?? ''}'.trim() : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
                    child: DecoratedBox(
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), boxShadow: floatShadow),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (fromGallery)
                              Image.network(
                                '${_gallery[index]['image_url']}',
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) => progress == null
                                    ? child
                                    : Container(
                                        color: const Color(0xFFE6EBF0),
                                        alignment: Alignment.center,
                                        child: const CircularProgressIndicator(),
                                      ),
                                errorBuilder: (context, error, stack) => Image.asset(
                                  _resortImages[index % _resortImages.length],
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              Image.asset(_resortImages[index], fit: BoxFit.cover),
                            if (caption.isNotEmpty)
                              Positioned(
                                left: 12,
                                right: 12,
                                bottom: 12,
                                child: GlassPanel(
                                  radius: 14,
                                  opacity: 0.55,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Text(
                                    caption,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _carouselCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _carouselPage ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _carouselPage ? AppColors.primary : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: _sectionGap),

            // ABOUT THE RESORT (maikli; ang buong detalye ay nasa About Us)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: _HomeLinkCard(
                icon: Icons.spa_outlined,
                title: "About Aryana's Guests House",
                subtitle: 'Private pool, rooms, and a function hall in Pagsanjan',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutUsPage())),
              ),
            ),

            const SizedBox(height: _sectionGap),

            // PACKAGE OFFERED
            _sectionTitle('PACKAGE OFFERED', key: _packagesKey, subtitle: 'Tap a package to see inclusions'),

            // Glass toolbar: search + filters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: GlassPanel(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchField(
                      controller: _packageSearch,
                      hint: 'Search packages or inclusions',
                      onChanged: (v) => setState(() => _packageQuery = v),
                    ),
                    const SizedBox(height: 6),
                    FilterChipsRow(
                      padding: 0,
                      children: [
                        for (final e in const {
                          'all': 'All',
                          'packages': 'Packages',
                          'hall': 'Function Hall',
                        }.entries)
                          ChoiceChip(
                            label: Text(e.value),
                            selected: _packageFilter == e.key,
                            onSelected: (_) => setState(() => _packageFilter = e.key),
                          ),
                        PopupMenuButton<String>(
                          initialValue: _packageSort,
                          onSelected: (v) => setState(() => _packageSort = v),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'default', child: Text('Default order')),
                            PopupMenuItem(value: 'low', child: Text('Price: low to high')),
                            PopupMenuItem(value: 'high', child: Text('Price: high to low')),
                          ],
                          child: Chip(
                            avatar: const Icon(Icons.sort, size: 18),
                            label: Text(switch (_packageSort) {
                              'low' => 'Price: low to high',
                              'high' => 'Price: high to low',
                              _ => 'Sort',
                            }),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            if (shown.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: _pagePadding, vertical: 24),
                child: Center(
                  child: Text('No packages match your search.', style: TextStyle(color: AppColors.muted)),
                ),
              ),

            ...mainPackages.map((pkg) => _buildPackageCard(pkg)),

            // OTHER OFFERED
            if (otherPackages.isNotEmpty) ...[
              const SizedBox(height: _sectionGap),
              _sectionTitle('OTHER OFFERED', subtitle: 'Function hall for events'),
              ...otherPackages.map((pkg) => _buildPackageCard(pkg)),
            ],

            // Iisang paalala para sa lahat ng package
            if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFFFF7E8),
                    border: Border.all(color: const Color(0xFFF5D9A8)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.mic_external_on_outlined, size: 18, color: AppColors.warning),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Videoke and speakers are only allowed from 7:00 AM to 10:00 PM. '
                          'See Terms & Conditions in More for all resort rules.',
                          style: TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: _sectionGap),

            // NEED HELP? (ang contact details ay nasa Help and Support)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: _HomeLinkCard(
                icon: Icons.support_agent,
                title: 'Need help or have questions?',
                subtitle: 'Call, text, or email the resort',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportPage())),
              ),
            ),

            const SizedBox(height: _bottomSpace),
          ],
        ),
      ),
    );
  }

  void _scrollToPackages() {
    final ctx = _packagesKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.02,
    );
  }

  // PACKAGE CARD

  Widget _buildPackageCard(Package pkg) {
    return AppCard(
      margin: const EdgeInsets.symmetric(
        horizontal: _pagePadding,
        vertical: _cardGap / 2,
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
          ),
          child: Icon(
            pkg.name.startsWith('Function Hall') ? Icons.celebration_outlined : Icons.pool_outlined,
            color: Colors.white,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        title: Text(
          pkg.name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pkg.formattedPrice,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 6),
              Text('Duration: ${pkg.formattedDuration}'),
              const SizedBox(height: 4),
              Text('Capacity: ${pkg.formattedCapacity}'),
            ],
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16,
        ),
        children: [
          const Divider(),
          const SizedBox(height: 10),

          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'INCLUSIONS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),

          const SizedBox(height: 8),

          ...pkg.inclusions.map((item) => _buildDetailItem(item)),

          const SizedBox(height: 14),

          if (pkg.additional.isNotEmpty) ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ADDITIONAL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),

            const SizedBox(height: 8),

            ...pkg.additional.map((item) => _buildDetailItem(item)),

            const SizedBox(height: 14),
          ],

          const SizedBox(height: 4),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: () => _handleBookNow(pkg),
              icon: const Icon(Icons.event_available),
              label: const Text('BOOK NOW'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _itemGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 14, height: 1.4)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tabTitles[_selectedIndex]),
        actions: [
          ListenableBuilder(
            listenable: _notifications,
            builder: (context, _) => IconButton(
              tooltip: 'Notifications',
              onPressed: _openNotifications,
              icon: Badge(
                isLabelVisible: _notifications.unreadCount > 0,
                label: Text('${_notifications.unreadCount}'),
                child: const Icon(Icons.notifications_outlined),
              ),
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: _showMoreSheet,
            icon: const Icon(Icons.more_vert),
          ),
          const SizedBox(width: 4),
        ],
      ),

      body: AmbientBackground(child: _buildCurrentPage()),

      // BOTTOM NAVIGATION: priority items muna; ang iba ay nasa "More".
      bottomNavigationBar: ListenableBuilder(
        listenable: _notifications,
        builder: (context, _) {
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onNavigationItemTapped,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.calendar_month_outlined),
                selectedIcon: Icon(Icons.calendar_month),
                label: 'Bookings',
              ),
              const NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Receipts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account',
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Maikling card na may icon at arrow, papunta sa ibang page.
class _HomeLinkCard extends StatelessWidget {
  const _HomeLinkCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                gradient: const LinearGradient(colors: [Color(0xFF14B8A6), AppColors.primary]),
              ),
              child: Icon(icon, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
