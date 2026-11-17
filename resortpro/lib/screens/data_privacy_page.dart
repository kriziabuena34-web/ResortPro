import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';

/// Isang bahagi ng Data Privacy (pamagat, paliwanag, at listahan).
class _PrivacySection {
  const _PrivacySection(this.icon, this.title, this.body, [this.items = const []]);
  final IconData icon;
  final String title;
  final String body;
  final List<String> items;
}

const _sections = <_PrivacySection>[
  _PrivacySection(
    Icons.info_outline,
    'Introduction',
    'ResortPro ("the App") is committed to protecting your personal data in accordance '
        'with the Data Privacy Act of 2012 (RA 10173) and its Implementing Rules and '
        'Regulations, as enforced by the National Privacy Commission (NPC). By using this '
        'App and continuing with Google Sign-In, you acknowledge and consent to the '
        'collection, use, and processing of your personal data as described below.',
  ),
  _PrivacySection(
    Icons.folder_shared_outlined,
    'Information We Collect',
    'We collect the following categories of personal data:',
    [
      'Google Account Information: your name, email address, and profile photo, '
          'obtained through Google Sign-In.',
      'Identity Verification Information: your full legal name, birth date, contact '
          'number, government-issued ID type, and a photo of your government ID, '
          'submitted voluntarily to verify your identity before booking.',
      'Booking Information: your reservation details, including dates, number and age '
          'range of guests, and type of event (if applicable).',
      'Payment Records: the amount, method, and status of payments made toward your '
          'booking. We do not collect or store your actual card, GCash, or Maya account '
          'credentials.',
    ],
  ),
  _PrivacySection(
    Icons.track_changes_outlined,
    'Purpose of Collection',
    'Your personal data is collected and processed solely for the following purposes:',
    [
      'To verify your identity and confirm that you are the rightful owner of your account.',
      'To process and manage your resort bookings and reservations.',
      'To facilitate payment tracking and issue accurate booking receipts.',
      'To allow resort staff (admin) to communicate with you regarding your reservation.',
      'To comply with legal and regulatory requirements, where applicable.',
    ],
  ),
  _PrivacySection(
    Icons.lock_outline,
    'Storage and Security',
    'Your data is stored securely using Supabase, a cloud database provider that '
        'implements encryption and access-control policies. Your government ID photo is '
        'stored in a private, access-restricted file storage system and is visible only to '
        'you and authorized resort administrators for verification purposes. We implement '
        'reasonable organizational, physical, and technical measures to protect your data '
        'against unauthorized access, alteration, disclosure, or destruction.',
  ),
  _PrivacySection(
    Icons.share_outlined,
    'Data Sharing',
    'We do not sell, rent, or trade your personal data to third parties. Your '
        'information is only accessible to authorized resort administrators for the sole '
        'purpose of verifying your identity and processing your bookings.',
  ),
  _PrivacySection(
    Icons.gavel_outlined,
    'Your Rights as a Data Subject',
    'Under the Data Privacy Act of 2012, you have the right to:',
    [
      'Be informed that your personal data will be, are being, or have been processed.',
      'Access your personal data upon request.',
      'Dispute and request correction of any inaccurate data.',
      'Object to the processing of your data, subject to legal and contractual restrictions.',
      'Request the deletion or blocking of your data, where applicable.',
      'Be informed of any breach that may compromise your data.',
    ],
  ),
  _PrivacySection(
    Icons.history_outlined,
    'Data Retention',
    'Your personal data will be retained only for as long as necessary to fulfill the '
        'purposes stated in these terms, or as required by applicable law, after which it '
        'will be securely disposed of or anonymized.',
  ),
  _PrivacySection(
    Icons.handshake_outlined,
    'Consent',
    'By tapping "Continue with Google" and proceeding to use this App, you confirm that '
        'you have read, understood, and voluntarily agree to the collection and processing '
        'of your personal data as described in these terms.',
  ),
];

/// Hiwalay na Data Privacy page (binubuksan mula sa Sign In).
class DataPrivacyPage extends StatelessWidget {
  const DataPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Data Privacy')),
      body: AmbientBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(24),
                boxShadow: floatShadow,
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.inkRaised,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: AppColors.inkLine),
                    ),
                    child: const Icon(Icons.verified_user_outlined, color: Color(0xFF5EEAD4), size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Privacy Matters',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'In compliance with the Data Privacy Act of 2012 (RA 10173)',
                          style: TextStyle(color: AppColors.inkText, fontSize: 13, height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const DataPrivacyContent(showIntro: false),
          ],
        ),
      ),
    );
  }
}

/// Laman ng Data Privacy (RA 10173). Ginagamit sa Data Privacy page at sa
/// tab na "Data Privacy" ng Terms & Conditions.
class DataPrivacyContent extends StatelessWidget {
  const DataPrivacyContent({super.key, this.showIntro = true});

  /// Ipakita ang linya tungkol sa RA 10173 sa itaas.
  final bool showIntro;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showIntro)
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'In compliance with the Data Privacy Act of 2012 (Republic Act No. 10173)',
              style: TextStyle(fontSize: 13, color: AppColors.muted, fontStyle: FontStyle.italic),
            ),
          ),
        for (var i = 0; i < _sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SectionCard(number: i + 1, section: _sections[i]),
          ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE6EDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD3DEEA)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.support_agent_outlined, size: 20, color: AppColors.ink),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'For concerns regarding your personal data, you may contact the resort directly, '
                  'or the National Privacy Commission (NPC) at privacy.gov.ph.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.text),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.number, required this.section});
  final int number;
  final _PrivacySection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFE6EDF5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(section.icon, size: 20, color: AppColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SECTION $number',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.muted,
                      ),
                    ),
                    Text(
                      section.title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(section.body, style: const TextStyle(fontSize: 14, height: 1.55, color: Color(0xFF334155))),
          if (section.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final item in section.items) _bullet(item),
          ],
        ],
      ),
    );
  }

  Widget _bullet(String item) {
    // Naka-bold ang bahagi bago ang ":" (hal. "Booking Information:").
    final colon = item.indexOf(':');
    final hasLabel = colon > 0 && colon < 40;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(fontSize: 13.5, height: 1.5, color: Color(0xFF334155)),
                children: hasLabel
                    ? [
                        TextSpan(
                          text: item.substring(0, colon + 1),
                          style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
                        ),
                        TextSpan(text: item.substring(colon + 1)),
                      ]
                    : [TextSpan(text: item)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
