import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notifications.dart';
import '../utils/format.dart';
import 'account_page.dart';
import 'booking_page.dart';
import 'my_booking_page.dart';
import 'my_receipt_list_page.dart';
import 'notifications_page.dart';

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
  final ValueNotifier<double> _appBarFade = ValueNotifier<double>(0);
  final supabase = Supabase.instance.client;

  // ---------- EASY SETTINGS (HEADER) ----------
  // Header color when you are at the top of the page
  static const Color _appBarColor = Color(0xFF238B45);
  // Title and icon color at the top (white) and when faded (dark green)
  static const Color _appBarTextColor = Colors.white;
  static const Color _appBarFadedTextColor = Color(0xFF00441B);
  // How far you scroll (in pixels) before the header is fully faded
  static const double _fadeDistance = 150;
  // How solid the header is when fully faded: 1.0 = no fade, lower = lighter
  static const double _appBarFadedAlpha = 0.65;
  // --------------------------------------------

  // ---------- EASY SETTINGS (SPACING) ----------
  // Left/right margin shared by every section on the page
  static const double _pagePadding = 20;
  // Space above the first item and below the last item
  static const double _topSpace = 16;
  static const double _bottomSpace = 32;
  // Space between big sections (Resort Info, Packages, Contact...)
  static const double _sectionGap = 32;
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

  // Gallery photos mula sa admin (kapag wala, gagamitin ang _resortImages).
  List<Map<String, dynamic>> _gallery = [];
  int _carouselPage = 0;
  Timer? _carouselTimer;

  // Search at filter ng packages
  final _packageSearch = TextEditingController();
  String _packageQuery = '';
  String _packageFilter = 'all'; // all, packages, hall
  String _packageSort = 'default'; // default, low, high

  // Bottom navigation: Home, Bookings, Alerts, Account (+ More sheet)
  static const _tabTitles = ["Aryana's Guests House", 'My Bookings', 'Notifications', 'Account'];
  static const _alertsTab = 2;

  final _notifications = UserNotifications.instance;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _fetchPackages();
    _fetchGallery();
    _startNotifications();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) => _autoSlide());
  }

  Future<void> _startNotifications() async {
    // Kapag pinindot ang phone notification, buksan ang Alerts tab.
    LocalNotifier.onTap = (_) {
      if (mounted) _onNavigationItemTapped(_alertsTab);
    };
    if (await LocalNotifier.launchedFromNotification() && mounted) {
      _onNavigationItemTapped(_alertsTab);
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
    _appBarFade.dispose();
    super.dispose();
  }

  // HEADER FADE (0 = at the top, 1 = fully faded)

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final t = (_scrollController.offset / _fadeDistance).clamp(0.0, 1.0).toDouble();
    if (t != _appBarFade.value) {
      _appBarFade.value = t;
    }
  }

  // FETCH PACKAGES FROM SUPABASE

  Future<void> _fetchPackages() async {
    try {
      final data = await supabase
          .from('packages')
          .select()
          .order('id', ascending: true);

      setState(() {
        _packages = (data as List)
            .map((json) => Package.fromJson(json as Map<String, dynamic>))
            .toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load packages: $e';
        _isLoading = false;
      });
    }
  }

  void _onNavigationItemTapped(int index) {
    // "More" (index 4) ay sheet, hindi tab.
    if (index == 4) {
      _showMoreSheet();
      return;
    }
    // Other tabs start at the top, so the header goes back to solid green
    _appBarFade.value = 0;
    setState(() {
      _selectedIndex = index;
    });
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
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Resort Map'),
              onTap: () => open(
                Scaffold(appBar: AppBar(title: const Text('Resort Map')), body: const MapPage()),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('My Receipts'),
              onTap: () => open(const MyReceiptListPage()),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Booking History'),
              onTap: () => open(const MyBookingPage(initialFilter: 'past')),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Help and Support'),
              onTap: () => open(const PlaceholderPage(title: 'Help and Support')),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms & Conditions'),
              onTap: () => open(const PlaceholderPage(title: 'Terms & Conditions')),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () => open(const PlaceholderPage(title: 'About Us')),
            ),
          ],
        ),
      ),
    );
  }

  // BOOK NOW VERIFICATION CHECK

  Future<void> _handleBookNow(Package pkg) async {
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
          SnackBar(content: Text('Error checking account status: $e')),
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
        return const NotificationsPage(embedded: true);

      case 3:
        return const AccountPage();

      case 0:
      default:
        return _buildHomeContent();
    }
  }

  // SECTION TITLE (same margin and gap everywhere)

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_pagePadding, 0, _pagePadding, _titleGap),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() => _isLoading = true);
                  _fetchPackages();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
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

    return SingleChildScrollView(
      controller: _scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: _topSpace),

          // CAROUSEL PHOTO (galing sa Gallery ng admin; default photos kung wala pa)
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
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
                                    color: Colors.grey.shade200,
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
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(14, 28, 14, 28),
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black54],
                                ),
                              ),
                              child: Text(
                                caption,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _carouselCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _carouselPage ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == _carouselPage ? _appBarColor : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),

          const SizedBox(height: _sectionGap),

          // RESORT INFORMATION
          _sectionTitle('RESORT INFORMATION'),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _pagePadding),
            child: Text(
              'Welcome to Aryana\'s Guests House. '
                  'Enjoy a relaxing stay with a comfortable room, '
                  'inclusions, and spaces for your events and gatherings.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: _sectionGap),

          // PACKAGE OFFERED
          _sectionTitle('PACKAGE OFFERED'),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _pagePadding),
            child: SearchField(
              controller: _packageSearch,
              hint: 'Search packages or inclusions',
              onChanged: (v) => setState(() => _packageQuery = v),
            ),
          ),
          const SizedBox(height: 8),
          FilterChipsRow(
            padding: _pagePadding,
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
          const SizedBox(height: 8),

          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: _pagePadding, vertical: 24),
              child: Center(child: Text('No packages match your search.')),
            ),

          ...mainPackages.map((pkg) => _buildPackageCard(pkg)),

          // OTHER OFFERED
          if (otherPackages.isNotEmpty) ...[
            const SizedBox(height: _sectionGap),

            _sectionTitle('OTHER OFFERED'),

            ...otherPackages.map((pkg) => _buildPackageCard(pkg)),
          ],

          const SizedBox(height: _sectionGap),

          // CONTACT US
          _sectionTitle('CONTACT US'),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: _pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gmail: aryanasguesthouse06@gmail.com'),
                SizedBox(height: 10),
                Text("Facebook: Aryana's Guests House"),
                SizedBox(height: 10),
                Text('Contact: 09628828792'),
                SizedBox(height: 10),
                Text(
                  'Location: Brgy. Maulawin Tramo St. Pagsanjan, Laguna',
                ),
              ],
            ),
          ),

          const SizedBox(height: _bottomSpace),
        ],
      ),
    );
  }

  // PACKAGE CARD

  Widget _buildPackageCard(Package pkg) {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: _pagePadding,
        vertical: _cardGap / 2,
      ),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Colors.grey.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
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
                  fontWeight: FontWeight.bold,
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

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade100,
            ),
            child: const Text(
              'Note: Strictly, videoke and speakers are only '
                  'allowed from 7:00 AM to 10:00 PM.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => _handleBookNow(pkg),
              child: const Text('BOOK NOW'),
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

  // SIDE NAVIGATION DRAWER
  // (No Navigator.pop here, so the back arrow on the next page returns
  // to the screen you came from with the drawer still open.)

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            DrawerHeader(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.hotel,
                    size: 50,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'ResortPro',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Aryana's Guests House",
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('My Booking'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyBookingPage()),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: const Text('My Receipt'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const MyReceiptListPage()),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Booking History'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyBookingPage(initialFilter: 'past'),
                  ),
                );
              },
            ),

            ListTile(
              leading: const Icon(Icons.support_agent_outlined),
              title: const Text('Help and Support'),
              onTap: () {
                _showPlaceholderPage('Help and Support');
              },
            ),

            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Terms & Conditions'),
              onTap: () {
                _showPlaceholderPage('Terms & Conditions');
              },
            ),

            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('About Us'),
              onTap: () {
                _showPlaceholderPage('About Us');
              },
            ),
          ],
        ),
      ),
    );
  }

  // TEMPORARY PLACEHOLDER

  void _showPlaceholderPage(String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlaceholderPage(
          title: title,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // GREEN HEADER THAT FADES WHEN YOU SCROLL
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ValueListenableBuilder<double>(
          valueListenable: _appBarFade,
          builder: (context, fade, _) {
            final alpha = 1.0 - (1.0 - _appBarFadedAlpha) * fade;
            final textColor = Color.lerp(
              _appBarTextColor,
              _appBarFadedTextColor,
              fade,
            )!;

            return AppBar(
              backgroundColor: _appBarColor.withValues(alpha: alpha),
              foregroundColor: textColor,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              title: Text(
                _tabTitles[_selectedIndex],
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              actions: [
                ListenableBuilder(
                  listenable: _notifications,
                  builder: (context, _) => IconButton(
                    tooltip: 'Notifications',
                    onPressed: () => _onNavigationItemTapped(_alertsTab),
                    icon: Badge(
                      isLabelVisible: _notifications.unreadCount > 0,
                      label: Text('${_notifications.unreadCount}'),
                      child: const Icon(Icons.notifications_outlined),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),

      drawer: _buildDrawer(),

      body: _buildCurrentPage(),

      // BOTTOM NAVIGATION: priority items muna; ang iba ay nasa "More".
      bottomNavigationBar: ListenableBuilder(
        listenable: _notifications,
        builder: (context, _) {
          final unread = _notifications.unreadCount;
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
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications),
                ),
                label: 'Alerts',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Account',
              ),
              const NavigationDestination(
                icon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          );
        },
      ),
    );
  }
}

// MAP PAGE

class MapPage extends StatelessWidget {
  const MapPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map_outlined,
            size: 80,
          ),
          SizedBox(height: 16),
          Text(
            'Resort Location',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 30),
            child: Text(
              'The resort map and navigation will be added here.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// PLACEHOLDER PAGE

class PlaceholderPage extends StatelessWidget {
  final String title;

  const PlaceholderPage({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Center(
        child: Text(
          '$title page',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}