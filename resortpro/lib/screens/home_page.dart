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

  /// Ilang guest ang kasama sa presyo (null = walang dagdag na singil bawat tao).
  final int? includedPax;
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
    this.includedPax,
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
      includedPax: json['included_pax'] as int?,
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

  // Malaki ang larawan sa gitna; sumisilip ang nasa kaliwa at kanan.
  // Paikot (loop): napakarami ang "pahina" para laging may susunod; ang larawan ay pahina % bilang.
  static const int _loopStart = 12000; // nahahati sa 1–6, 8, 10, 12…: nagsisimula sa unang larawan
  final PageController _carouselController = PageController(viewportFraction: 0.84, initialPage: _loopStart);
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
  static const double _carouselHeight = 280;
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
  int _carouselPage = 0; // aling larawan (0 hanggang bilang - 1)
  int _carouselVirtual = _loopStart; // aktuwal na pahina sa PageView
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

  /// I-restart ang auto-slide (pagkatapos mag-swipe ang user).
  void _restartCarouselTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) => _autoSlide());
  }

  /// Larawan [index] ng carousel (galing sa admin Gallery, o default kung wala).
  ImageProvider _galleryImage(int index) {
    if (_gallery.isNotEmpty) return NetworkImage('${_gallery[index]['image_url']}');
    return AssetImage(_resortImages[index % _resortImages.length]);
  }

  String _galleryCaption(int index) =>
      _gallery.isNotEmpty ? '${_gallery[index]['caption'] ?? ''}'.trim() : '';

  /// Isang card sa carousel: larawan, pamagat sa itaas, napipindot para palakihin.
  Widget _galleryCard(int index) {
    final caption = _galleryCaption(index);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 10))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Material(
            color: const Color(0xFFE6EBF0),
            child: InkWell(
              onTap: () => _openGalleryViewer(index),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image(
                    image: _galleryImage(index),
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                    errorBuilder: (context, error, stack) =>
                        Image.asset(_resortImages[index % _resortImages.length], fit: BoxFit.cover),
                  ),
                  if (caption.isNotEmpty) ...[
                    // Madilim sa itaas para mabasa ang pamagat.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [Color(0x99000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      top: 16,
                      child: Text(
                        caption,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          shadows: [Shadow(color: Color(0x80000000), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ],
                  // Maliit na palatandaan na puwedeng palakihin.
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                      child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Buong-screen na tingin sa mga larawan (swipe, pinch para mag-zoom).
  void _openGalleryViewer(int start) {
    _carouselTimer?.cancel();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => _GalleryViewer(
              count: _carouselCount,
              initial: start,
              image: _galleryImage,
              caption: _galleryCaption,
            ),
          ),
        )
        .then((_) {
      if (mounted) _restartCarouselTimer();
    });
  }

  void _autoSlide() {
    final count = _carouselCount;
    if (count < 2 || !_carouselController.hasClients || _selectedIndex != 0) return;
    // Laging pasulong: mula sa huling larawan, diretso sa una (walang pabalik na slide).
    _carouselController.animateToPage(
      _carouselVirtual + 1,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  /// Bumalik sa unang larawan (hal. nagbago ang bilang ng larawan).
  void _resetCarousel() {
    final count = _carouselCount;
    if (count == 0) return;
    final target = count < 2 ? 0 : _loopStart - _loopStart % count;
    _carouselVirtual = target;
    _carouselPage = 0;
    if (_carouselController.hasClients) _carouselController.jumpToPage(target);
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
      _resetCarousel();
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
    // Pindot ulit sa Home habang nasa Home: bumalik sa pinakataas.
    if (index == 0 && _selectedIndex == 0) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
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

  Widget _sectionTitle(String text, {Key? key, String? subtitle, Widget? trailing}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, _titleGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.ink,
                  ),
                ),
                if (subtitle != null)
                  Text(subtitle, style: const TextStyle(fontSize: 12.5, color: AppColors.muted)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  /// Pill na kapareho ng itsura ng mga tab sa admin.
  Widget _pill(String label, bool selected, VoidCallback onTap, {IconData? icon}) {
    return Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.ink : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: selected ? Colors.white : AppColors.muted),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : AppColors.text,
                  )),
            ],
          ),
        ),
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
        FocusManager.instance.primaryFocus?.unfocus();
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

            // WELCOME BANNER
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: AppColors.ink,
                  boxShadow: floatShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _greeting(),
                                style: const TextStyle(color: AppColors.inkText, fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$firstName!',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Image.asset('assets/images/aryana_logo.png', width: 58, height: 58),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      "Ready for your next stay at Aryana's Guests House?",
                      style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13.5, height: 1.35),
                    ),
                    const SizedBox(height: 16),
                    // QUICK ACTIONS
                    Row(
                      children: [
                        for (final (i, a) in <(IconData, String, VoidCallback)>[
                          (Icons.event_available_rounded, 'Book', () => _scrollToPackages()),
                          (Icons.chat_bubble_outline_rounded, 'Chat', _openChat),
                          (Icons.map_outlined, 'Map', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResortMapPage()))),
                        ].indexed) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: Material(
                              color: i == 0 ? AppColors.primary : AppColors.inkRaised,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: i == 0 ? AppColors.primary : AppColors.inkLine),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: a.$3,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Column(
                                    children: [
                                      a.$2 == 'Chat'
                                          // Badge: mga sagot ng resort na hindi pa nababasa
                                          ? ListenableBuilder(
                                              listenable: _notifications,
                                              builder: (context, _) => Badge(
                                                isLabelVisible: _unreadChat > 0,
                                                label: Text('$_unreadChat'),
                                                child: Icon(a.$1, color: Colors.white, size: 22),
                                              ),
                                            )
                                          : Icon(a.$1, color: Colors.white, size: 22),
                                      const SizedBox(height: 6),
                                      Text(a.$2,
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: _sectionGap),

            // GALLERY CAROUSEL (galing sa Gallery ng admin; default photos kung wala pa)
            _sectionTitle('Gallery', subtitle: 'A peek at the resort'),
            SizedBox(
              height: _carouselHeight,
              // Kapag ini-swipe ng user, i-restart ang auto-slide para hindi biglang lumipat.
              child: NotificationListener<ScrollStartNotification>(
                onNotification: (n) {
                  if (n.dragDetails != null) _restartCarouselTimer();
                  return false;
                },
                child: PageView.builder(
                  controller: _carouselController,
                  // Walang dulo kapag 2 o higit pa ang larawan (paikot).
                  itemCount: _carouselCount < 2 ? _carouselCount : null,
                  onPageChanged: (i) => setState(() {
                    _carouselVirtual = i;
                    _carouselPage = i % _carouselCount;
                  }),
                  itemBuilder: (context, index) => AnimatedBuilder(
                    animation: _carouselController,
                    builder: (context, child) {
                      // Lumiliit ang mga larawan sa gilid; buo ang nasa gitna.
                      var page = _carouselVirtual.toDouble();
                      if (_carouselController.hasClients && _carouselController.position.haveDimensions) {
                        page = _carouselController.page ?? page;
                      }
                      final t = (page - index).abs().clamp(0.0, 1.0);
                      return Transform.scale(scale: 1 - t * 0.12, child: child);
                    },
                    child: _galleryCard(index % _carouselCount),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _carouselCount; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _carouselPage ? 22 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: i == _carouselPage ? AppColors.primary : const Color(0xFFD5DCE3),
                      borderRadius: BorderRadius.circular(6),
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
            _sectionTitle('Our Packages', key: _packagesKey, subtitle: 'Tap a package to see what is included'),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: SearchField(
                controller: _packageSearch,
                hint: 'Search packages or inclusions',
                onChanged: (v) => setState(() => _packageQuery = v),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
              child: Row(
                children: [
                  for (final e in const {
                    'all': 'All',
                    'packages': 'Resort',
                    'hall': 'Function Hall',
                  }.entries) ...[
                    _pill(e.value, _packageFilter == e.key, () => setState(() => _packageFilter = e.key)),
                    const SizedBox(width: 8),
                  ],
                  PopupMenuButton<String>(
                    initialValue: _packageSort,
                    position: PopupMenuPosition.under,
                    onSelected: (v) => setState(() => _packageSort = v),
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'default', child: Text('Default Order')),
                      PopupMenuItem(value: 'low', child: Text('Price: Low to High')),
                      PopupMenuItem(value: 'high', child: Text('Price: High to Low')),
                    ],
                    child: IgnorePointer(
                      child: _pill(
                        switch (_packageSort) {
                          'low' => 'Price: Low to High',
                          'high' => 'Price: High to Low',
                          _ => 'Sort',
                        },
                        _packageSort != 'default',
                        () {},
                        icon: Icons.swap_vert_rounded,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

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
              _sectionTitle('Function Hall', subtitle: 'For catered events and celebrations'),
              ...otherPackages.map((pkg) => _buildPackageCard(pkg)),
            ],

            // Iisang paalala para sa lahat ng package
            if (shown.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(_pagePadding, 8, _pagePadding, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.primary.withValues(alpha: 0.06),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.mic_external_on_outlined, size: 18, color: AppColors.primary),
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

  /// Pangalan ng package. Function Hall: "Function Hall" sa itaas at ang oras
  /// (Day Tour / Night Tour / Overnight (22 Hours)) sa ilalim, pare-pareho ang ayos.
  Widget _packageTitle(Package pkg) {
    const titleStyle = TextStyle(fontFamily: 'Poppins', fontSize: 16.5, fontWeight: FontWeight.w700, color: AppColors.ink);
    final m = RegExp(r'^Function Hall\s*\((.+)\)$').firstMatch(pkg.name.trim());
    if (m == null) return Text(pkg.name, style: titleStyle);
    final variant = m.group(1)!.replaceFirst(RegExp(r'^Overnight\s+22 Hours$'), 'Overnight (22 Hours)');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Function Hall', style: titleStyle),
        Text(
          variant,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
        ),
      ],
    );
  }

  /// Kulay at icon ayon sa oras (pareho sa admin).
  static ({Color color, IconData icon}) _slotOf(Package pkg) {
    final n = pkg.name.toLowerCase();
    if (n.contains('overnight') || n.contains('22')) return (color: const Color(0xFF0F766E), icon: Icons.bedtime_rounded);
    if (n.contains('night')) return (color: const Color(0xFF6366F1), icon: Icons.nights_stay_rounded);
    return (color: const Color(0xFFF59E0B), icon: Icons.wb_sunny_rounded);
  }

  Widget _metaChip(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.subtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.muted),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.text)),
          ],
        ),
      );

  Widget _buildPackageCard(Package pkg) {
    final isHall = pkg.name.startsWith('Function Hall');
    final slot = _slotOf(pkg);
    // Ang "for catering only" ay ipinapakita bilang note (hindi kasama sa Additional).
    final additional = isHall
        ? pkg.additional.where((a) => !RegExp(r'catering\s+only', caseSensitive: false).hasMatch(a)).toList()
        : pkg.additional;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _pagePadding, vertical: _cardGap / 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 12, offset: Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 4, color: slot.color),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: slot.color.withValues(alpha: 0.12),
                ),
                child: Icon(isHall ? Icons.celebration_outlined : slot.icon, color: slot.color, size: 22),
              ),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _packageTitle(pkg)),
                  const SizedBox(width: 8),
                  Text(
                    pkg.formattedPrice,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _metaChip(Icons.schedule_rounded, pkg.formattedDuration),
                    _metaChip(Icons.groups_outlined, pkg.formattedCapacity),
                  ],
                ),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 14),
                if (isHall) ...[
                  const _HallCateringNote(),
                  const SizedBox(height: 14),
                ],
                _detailHeading('Inclusions'),
                ...pkg.inclusions.map((item) => _buildDetailItem(item)),
                if (additional.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _detailHeading('Additional'),
                  ...additional.map((item) => _buildDetailItem(item, extra: true)),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _handleBookNow(pkg),
                    icon: const Icon(Icons.event_available_rounded),
                    label: const Text('Book Now', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailHeading(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted),
          ),
        ),
      );

  Widget _buildDetailItem(String text, {bool extra = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _itemGap),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              extra ? Icons.add_circle_outline_rounded : Icons.check_circle_rounded,
              size: 16,
              color: extra ? AppColors.muted : AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 18) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Lumiliit nang kusa ang heading para hindi maputol ang pangalan.
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_tabTitles[_selectedIndex], maxLines: 1),
        ),
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

/// Paalala sa Function Hall: para sa event na may catering, pero walang catering ang resort.
class _HallCateringNote extends StatelessWidget {
  const _HallCateringNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5D08A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.restaurant_outlined, color: Color(0xFFB7791F), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Note: ', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(
                    text: 'The function hall is for events with catering only. '
                        'Catering is not included and is not offered by the resort, '
                        'so please arrange your own caterer.',
                  ),
                ],
              ),
              style: TextStyle(color: Color(0xFF7A4B0B), height: 1.4, fontSize: 13.5),
            ),
          ),
        ],
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

/// Buong-screen na gallery: swipe pakaliwa/pakanan, pinch para mag-zoom.
class _GalleryViewer extends StatefulWidget {
  const _GalleryViewer({required this.count, required this.initial, required this.image, required this.caption});

  final int count;
  final int initial;
  final ImageProvider Function(int) image;
  final String Function(int) caption;

  @override
  State<_GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<_GalleryViewer> {
  late final _controller = PageController(initialPage: widget.initial);
  late int _page = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final caption = widget.caption(_page);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_page + 1} / ${widget.count}', style: const TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.count,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Image(
                  image: widget.image(i),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) => progress == null
                      ? child
                      : const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorBuilder: (context, error, stack) =>
                      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
          if (caption.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
