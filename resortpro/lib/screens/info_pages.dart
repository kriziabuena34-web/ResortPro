import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/offline_cache.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
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
  'All bookings are non-refundable unless the guest has a valid reason accepted by the management.',
  'For extensions, guests will be charged ₱500 per hour.',
  'Guests are obliged to make an effort to keep the surroundings clean. Guests should refrain from throwing '
      'rubbish anywhere other than the strategically located trash bins. Don\'t leave any trash.',
  'If the guest exceeds 20 pax, there will be an additional payment of ₱100 per head.',
  "Aryana's Guest House will not be responsible for any lost belongings or personal items of the customer.",
  'The videoke and speaker are strictly until 10 PM. Exceeding the time limit will result in a ₱1,500 penalty.',
];

/// Ang kasalukuyang Pool Agreement. Nagsisimula sa [resortTerms], tapos
/// pinapalitan ng bersyong na-edit ng admin (resort_settings.pool_terms).
final poolTerms = ValueNotifier<List<String>>(resortTerms);

const _poolTermsCacheKey = 'pool_terms';
bool _poolTermsCacheLoaded = false;

/// Kinukuha ang pinakabagong Pool Agreement mula sa database. Kapag offline,
/// ginagamit ang huling naka-save na kopya; kapag wala pa, ang [resortTerms].
Future<void> refreshPoolTerms() async {
  if (!_poolTermsCacheLoaded) {
    _poolTermsCacheLoaded = true;
    final cached = await OfflineCache.load(_poolTermsCacheKey, perUser: false);
    final list = _termsFrom(cached?.data);
    if (list != null) poolTerms.value = list;
  }
  try {
    final row = await Supabase.instance.client
        .from('resort_settings')
        .select('pool_terms')
        .eq('id', 1)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));
    final list = _termsFrom(row?['pool_terms']);
    if (list != null) {
      poolTerms.value = list;
      await OfflineCache.save(_poolTermsCacheKey, list, perUser: false);
    }
  } catch (_) {
    // Offline o wala pa ang column: mananatili ang naka-save / default na terms.
  }
}

List<String>? _termsFrom(dynamic v) {
  if (v is! List) return null;
  final list = [for (final t in v) '$t'.trim()]..removeWhere((t) => t.isEmpty);
  return list.isEmpty ? null : list;
}

/// Ang numbered na listahan ng terms (ginagamit sa Terms page at sa payment).
class TermsList extends StatefulWidget {
  const TermsList({super.key, this.fontSize = 14});
  final double fontSize;

  @override
  State<TermsList> createState() => _TermsListState();
}

class _TermsListState extends State<TermsList> {
  @override
  void initState() {
    super.initState();
    refreshPoolTerms();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: poolTerms,
      builder: (context, terms, _) => _list(terms),
    );
  }

  Widget _list(List<String> terms) {
    final fontSize = widget.fontSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < terms.length; i++)
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
                  child: Text(terms[i], style: TextStyle(fontSize: fontSize, height: 1.45)),
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

  /// Hindi na ginagamit (Pool Agreement na lang ang laman ng page; ang Data
  /// Privacy ay nasa sign-in page). Iniwan para hindi masira ang dating tawag.
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: AmbientBackground(
        child: RefreshIndicator(
          onRefresh: refreshPoolTerms,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: const [
              _Section(
                title: "$resortName · Pool Agreement",
                icon: Icons.pool_outlined,
                child: TermsList(),
              ),
            ],
          ),
        ),
      ),
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
      'All bookings are non-refundable unless you have a valid reason. You can cancel in My Bookings any time '
          'before your booking date and request a refund with your reason. If the resort accepts it, you get back '
          'half of the 50% reservation fee. Cancelling on the booking date itself gets no refund. '
          'See Terms & Conditions.',
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

  static const _faqIcons = [
    Icons.event_available_outlined,
    Icons.verified_user_outlined,
    Icons.payments_outlined,
    Icons.task_alt,
    Icons.event_busy_outlined,
    Icons.more_time,
    Icons.groups_outlined,
  ];

  Future<void> _launch(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the app.')));
    }
  }

  static Widget _heading(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.muted)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    void call() => _launch(context, Uri(scheme: 'tel', path: resortPhone));
    void text() => _launch(context, Uri(scheme: 'sms', path: resortPhone));
    void email() => _launch(
          context,
          Uri(scheme: 'mailto', path: resortEmail, query: 'subject=ResortPro booking inquiry'),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Help and Support')),
      body: AmbientBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            // HERO: dark board na may mabilis na contact
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(24),
                boxShadow: floatShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.inkRaised,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.inkLine),
                        ),
                        child: const Icon(Icons.support_agent_outlined, color: Color(0xFF5EEAD4), size: 26),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'How Can We Help?',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Reach the resort or find quick answers below.",
                              style: TextStyle(color: AppColors.inkText, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: _ContactAction(icon: Icons.call_outlined, label: 'Call', onTap: call, primary: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _ContactAction(icon: Icons.sms_outlined, label: 'Text', onTap: text)),
                        const SizedBox(width: 10),
                        Expanded(child: _ContactAction(icon: Icons.mail_outline, label: 'Email', onTap: email)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // FAQ
            _heading('Frequently Asked Questions', 'Tap a question to see the answer'),
            for (var i = 0; i < _faqs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FaqCard(icon: _faqIcons[i % _faqIcons.length], question: _faqs[i].$1, answer: _faqs[i].$2),
              ),
            const SizedBox(height: 16),

            // CONTACT
            _heading('Contact Us', "Aryana's Guests House"),
            AppCard(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    _ContactRow(icon: Icons.phone_outlined, label: 'PHONE', value: resortPhone, onTap: call),
                    const Divider(height: 1, indent: 70),
                    _ContactRow(icon: Icons.mail_outline, label: 'EMAIL', value: resortEmail, onTap: email),
                    const Divider(height: 1, indent: 70),
                    const _ContactRow(icon: Icons.facebook, label: 'FACEBOOK', value: resortFacebook),
                    const Divider(height: 1, indent: 70),
                    _ContactRow(
                      icon: Icons.location_on_outlined,
                      label: 'ADDRESS',
                      value: resortAddress,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResortMapPage())),
                    ),
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

/// Isang tanong sa FAQ na bumubukas kapag pinindot.
class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.icon, required this.question, required this.answer});
  final IconData icon;
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 16, 16),
          iconColor: AppColors.ink,
          collapsedIconColor: AppColors.muted,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE6EDF5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
          title: Text(
            question,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.text),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.subtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(answer, style: const TextStyle(fontSize: 13.5, height: 1.55, color: Color(0xFF334155))),
            ),
          ],
        ),
      ),
    );
  }
}

/// Isang linya ng contact (may icon, label, at value).
class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFE6EDF5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: AppColors.ink),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.35)),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

class _ContactAction extends StatelessWidget {
  const _ContactAction({required this.icon, required this.label, required this.onTap, this.primary = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.primary : AppColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primary ? AppColors.primary : AppColors.inkLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ],
          ),
        ),
      ),
    );
  }
}
