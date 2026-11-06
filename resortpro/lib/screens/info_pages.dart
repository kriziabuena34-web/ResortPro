import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'data_privacy_page.dart';
import 'resort_map_page.dart';

// ===========================================================================
// Contact details ng resort (iisang lugar para pare-pareho sa lahat ng page)
// ===========================================================================

const resortName = "Aryana's Guests House";
const resortEmail = 'aryanasguesthouse06@gmail.com';
const resortPhone = '09628828792';
const resortFacebook = "Aryana's Guests House";

// ===========================================================================
// POOL AGREEMENT — Terms and Conditions
// ===========================================================================

const resortTerms = <String>[
  'Payment of 50% must be made at the time of booking, and the balance must be paid upon arrival.',
  'There must be adult supervision at all private rentals. Strictly NO Diving.',
  'There will be no food, drinks, or pets on the pool premises.',
  'Guests will be responsible for any damage that may occur during the time they rent the facility.',
  "The management is not liable for any accidents that will occur during the guest's stay.",
  'Guests are responsible for confirming or canceling their reservations at least 5 days before the booking date.',
  'If the guests fail to cancel the reservation within 5 days, they will no longer get the 50% reservation fee.',
  'Guests can only refund half of the 50% reservation fee if they cancel within 5 days before the event.',
  'For extensions, guests will be charged ₱500 per hour.',
  'Guests are obliged to make an effort to keep the surroundings clean. Guests should refrain from throwing '
      'rubbish anywhere other than the strategically located trash bins. Don\'t leave any trash.',
  'If the guest exceeds 20 pax, there will be an additional payment of ₱100 per head.',
  "Aryana's Guest House will not be responsible for any lost belongings or personal items of the customer.",
  'The videoke and speaker are strictly until 10 PM. Exceeding the time limit will result in a ₱1,500 penalty.',
];

/// Ang numbered na listahan ng terms (ginagamit sa Terms page at sa payment).
class TermsList extends StatelessWidget {
  const TermsList({super.key, this.fontSize = 14});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < resortTerms.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF7F5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(resortTerms[i], style: TextStyle(fontSize: fontSize, height: 1.45)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ipinapakita ang buong Terms and Conditions pagkapindot ng Submit.
/// Babalik ng `true` kapag binasa hanggang dulo at pinindot ang "I have read and agree".
Future<bool> showTermsAgreement(BuildContext context) async {
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _ReadTermsSheet(),
  );
  return agreed == true;
}

/// Bottom sheet ng buong terms. Naka-disable ang "I have read and agree"
/// hangga't hindi naka-scroll sa pinakadulo.
class _ReadTermsSheet extends StatefulWidget {
  const _ReadTermsSheet();

  @override
  State<_ReadTermsSheet> createState() => _ReadTermsSheetState();
}

class _ReadTermsSheetState extends State<_ReadTermsSheet> {
  final _scroll = ScrollController();
  bool _reachedEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_check);
    // Kung kasya na sa screen (walang i-scroll), ituring nang nabasa.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (!_scroll.hasClients || _reachedEnd) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) setState(() => _reachedEnd = true);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              "ARYANA'S GUEST HOUSE\nPOOL AGREEMENT",
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, height: 1.3),
            ),
          ),
          const Text(
            'TERMS AND CONDITIONS',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, letterSpacing: 0.8, fontSize: 12),
          ),
          const Divider(height: 24),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: const TermsList(),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_reachedEnd)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.keyboard_double_arrow_down, size: 18, color: AppColors.warning),
                        SizedBox(width: 6),
                        Text(
                          'Scroll to the end to continue',
                          style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: _reachedEnd ? () => Navigator.pop(context, true) : null,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('I have read and agree'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Mga page
// ===========================================================================

class _InfoScaffold extends StatelessWidget {
  const _InfoScaffold({required this.title, required this.icon, required this.subtitle, required this.children});

  final String title;
  final IconData icon;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AmbientBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
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
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(color: Color(0xFFCFE3E6), fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.icon});
  final String title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: AppColors.primary, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Terms & Conditions
// ---------------------------------------------------------------------------

class TermsPage extends StatelessWidget {
  const TermsPage({super.key, this.initialTab = 0});

  /// 0 = Pool Agreement, 1 = Data Privacy
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Terms & Conditions'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.pool_outlined, size: 20), text: 'Pool Agreement'),
              Tab(icon: Icon(Icons.privacy_tip_outlined, size: 20), text: 'Data Privacy'),
            ],
          ),
        ),
        body: const AmbientBackground(
          child: TabBarView(
            children: [
              _TermsTab(
                title: "$resortName · Pool Agreement",
                icon: Icons.pool_outlined,
                child: TermsList(),
              ),
              _TermsTab(
                title: 'ResortPro · Data Privacy',
                icon: Icons.privacy_tip_outlined,
                child: DataPrivacyContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TermsTab extends StatelessWidget {
  const _TermsTab({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [_Section(title: title, icon: icon, child: child)],
    );
  }
}

// ---------------------------------------------------------------------------
// About Us
// ---------------------------------------------------------------------------

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _InfoScaffold(
      title: 'About Us',
      icon: Icons.beach_access_rounded,
      subtitle: 'Your private pool getaway in Pagsanjan, Laguna',
      children: [
        const _Section(
          title: 'Who we are',
          icon: Icons.spa_outlined,
          child: Text(
            "$resortName is a private resort in Brgy. Maulawin, Pagsanjan, Laguna. We offer a "
            'relaxing place for families, friends, and groups to enjoy a private pool, comfortable '
            'rooms, and spaces for celebrations and gatherings.',
            style: TextStyle(fontSize: 14.5, height: 1.55),
          ),
        ),
        const _Section(
          title: 'What we offer',
          icon: Icons.local_offer_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Bullet(icon: Icons.pool_outlined, text: 'Private pool rentals for day and overnight stays'),
              _Bullet(icon: Icons.bed_outlined, text: 'Comfortable rooms and inclusions per package'),
              _Bullet(icon: Icons.celebration_outlined, text: 'Function hall for birthdays, reunions, and other events'),
              _Bullet(icon: Icons.mic_external_on_outlined, text: 'Videoke and speakers (until 10 PM)'),
            ],
          ),
        ),
        const _Section(
          title: 'Book with the ResortPro app',
          icon: Icons.phone_iphone_outlined,
          child: Text(
            'Check available dates, book your package, pay the 50% downpayment through GCash or Maya, '
            'and get notified once your booking is confirmed — all in one app.',
            style: TextStyle(fontSize: 14.5, height: 1.55),
          ),
        ),
        _Section(
          title: 'Find us',
          icon: Icons.location_on_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(resortAddress, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ResortMapPage()),
                ),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Open Resort Map'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HelpSupportPage()),
                ),
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Contact us in Help and Support'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Help and Support
// ---------------------------------------------------------------------------

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  static const _faqs = [
    (
      'How do I book a stay?',
      'Go to Home, choose a package, and tap BOOK NOW. Pick your date, enter the number of guests, '
          'then pay the 50% downpayment and upload your payment screenshot.',
    ),
    (
      'Why do I need to verify my account?',
      'For the safety of our guests, your account must be verified before booking. Go to Account → '
          'Verify Account and upload a valid government ID. The resort will review it.',
    ),
    (
      'How do I pay?',
      'Send the 50% downpayment through GCash or Maya to the number shown on the booking page, then '
          'enter the reference number and upload a screenshot of your receipt. The balance is paid upon arrival.',
    ),
    (
      'When is my booking confirmed?',
      'After the resort verifies your payment. You will get a notification, and the status in '
          'Bookings will change to Confirmed.',
    ),
    (
      'Can I cancel or move my booking?',
      'Please confirm or cancel at least 5 days before your booking date. If you cancel within 5 days '
          'before the event, only half of the 50% reservation fee can be refunded. See Terms & Conditions.',
    ),
    (
      'Can I extend my stay?',
      'Yes, extensions are charged ₱500 per hour, subject to availability. There is a 10-minute grace period '
          'after your package end time. Please ask the staff on-site.',
    ),
    (
      'How many guests are allowed?',
      'Each package shows its capacity. If you exceed 20 pax, there is an additional ₱100 per head.',
    ),
  ];

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the app.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InfoScaffold(
      title: 'Help and Support',
      icon: Icons.support_agent_outlined,
      subtitle: "We're here to help with your booking",
      children: [
        // Mabilis na contact (neumorphic)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Expanded(
                child: _ContactAction(
                  icon: Icons.call_outlined,
                  label: 'Call',
                  onTap: () => _launch(context, Uri(scheme: 'tel', path: resortPhone)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ContactAction(
                  icon: Icons.sms_outlined,
                  label: 'Text',
                  onTap: () => _launch(context, Uri(scheme: 'sms', path: resortPhone)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ContactAction(
                  icon: Icons.mail_outline,
                  label: 'Email',
                  onTap: () => _launch(
                    context,
                    Uri(scheme: 'mailto', path: resortEmail, query: 'subject=ResortPro booking inquiry'),
                  ),
                ),
              ),
            ],
          ),
        ),
        _Section(
          title: 'Frequently asked questions',
          icon: Icons.help_outline,
          child: Column(
            children: [
              for (final f in _faqs)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    shape: const Border(),
                    collapsedShape: const Border(),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    title: Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(f.$2, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.muted)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const _ContactCard(),
      ],
    );
  }
}

class _ContactAction extends StatelessWidget {
  const _ContactAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NeuCard(
      radius: 18,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: onTap,
      child: Column(
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
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    return const _Section(
      title: 'Contact us',
      icon: Icons.contact_phone_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Bullet(icon: Icons.phone_outlined, text: resortPhone),
          _Bullet(icon: Icons.mail_outline, text: resortEmail),
          _Bullet(icon: Icons.facebook, text: resortFacebook),
          _Bullet(icon: Icons.location_on_outlined, text: resortAddress),
        ],
      ),
    );
  }
}
