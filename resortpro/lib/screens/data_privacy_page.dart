import 'package:flutter/material.dart';

class DataPrivacyPage extends StatelessWidget {
  const DataPrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Data Privacy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ResortPro Terms & Data Privacy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'In compliance with the Data Privacy Act of 2012 (Republic Act No. 10173)',
              style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 24),

            _sectionTitle('1. Introduction'),
            _sectionBody(
              'ResortPro ("the App") is committed to protecting your personal data in accordance '
                  'with the Data Privacy Act of 2012 (RA 10173) and its Implementing Rules and '
                  'Regulations, as enforced by the National Privacy Commission (NPC). By using this '
                  'App and continuing with Google Sign-In, you acknowledge and consent to the '
                  'collection, use, and processing of your personal data as described below.',
            ),
            const SizedBox(height: 16),

            _sectionTitle('2. Information We Collect'),
            _sectionBody('We collect the following categories of personal data:'),
            const SizedBox(height: 10),
            _bulletList([
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
            ]),
            const SizedBox(height: 6),

            _sectionTitle('3. Purpose of Collection'),
            _sectionBody('Your personal data is collected and processed solely for the following purposes:'),
            const SizedBox(height: 10),
            _bulletList([
              'To verify your identity and confirm that you are the rightful owner of your account.',
              'To process and manage your resort bookings and reservations.',
              'To facilitate payment tracking and issue accurate booking receipts.',
              'To allow resort staff (admin) to communicate with you regarding your reservation.',
              'To comply with legal and regulatory requirements, where applicable.',
            ]),
            const SizedBox(height: 6),

            _sectionTitle('4. Storage and Security'),
            _sectionBody(
              'Your data is stored securely using Supabase, a cloud database provider that '
                  'implements encryption and access-control policies. Your government ID photo is '
                  'stored in a private, access-restricted file storage system and is visible only to '
                  'you and authorized resort administrators for verification purposes. We implement '
                  'reasonable organizational, physical, and technical measures to protect your data '
                  'against unauthorized access, alteration, disclosure, or destruction.',
            ),
            const SizedBox(height: 16),

            _sectionTitle('5. Data Sharing'),
            _sectionBody(
              'We do not sell, rent, or trade your personal data to third parties. Your '
                  'information is only accessible to authorized resort administrators for the sole '
                  'purpose of verifying your identity and processing your bookings.',
            ),
            const SizedBox(height: 16),

            _sectionTitle('6. Your Rights as a Data Subject'),
            _sectionBody('Under the Data Privacy Act of 2012, you have the right to:'),
            const SizedBox(height: 10),
            _bulletList([
              'Be informed that your personal data will be, are being, or have been processed.',
              'Access your personal data upon request.',
              'Dispute and request correction of any inaccurate data.',
              'Object to the processing of your data, subject to legal and contractual restrictions.',
              'Request the deletion or blocking of your data, where applicable.',
              'Be informed of any breach that may compromise your data.',
            ]),
            const SizedBox(height: 6),

            _sectionTitle('7. Data Retention'),
            _sectionBody(
              'Your personal data will be retained only for as long as necessary to fulfill the '
                  'purposes stated in these terms, or as required by applicable law, after which it '
                  'will be securely disposed of or anonymized.',
            ),
            const SizedBox(height: 16),

            _sectionTitle('8. Consent'),
            _sectionBody(
              'By tapping "Continue with Google" and proceeding to use this App, you confirm that '
                  'you have read, understood, and voluntarily agree to the collection and processing '
                  'of your personal data as described in these terms.',
            ),

            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'For concerns regarding your personal data, you may contact the resort directly, '
                    'or the National Privacy Commission (NPC) at privacy.gov.ph.',
                style: TextStyle(fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _sectionBody(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, height: 1.5),
    );
  }

  Widget _bulletList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('•  ', style: TextStyle(fontSize: 14, height: 1.5)),
              Expanded(
                child: Text(
                  item,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      )
          .toList(),
    );
  }
}
