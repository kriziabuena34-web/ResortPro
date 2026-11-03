import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'verification_form_page.dart';
import 'sign_in_page.dart';
import '../services/notifications.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      final profile = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _profile = profile;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    // Itigil ang notifications ng account na ito.
    await UserNotifications.instance.stop();
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // ignore if Google has nothing to sign out of
    }
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const SignInPage()),
            (route) => false,
      );
    }
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'verified':
        color = Colors.green;
        label = 'Verified';
        break;
      case 'pending':
        color = Colors.orange;
        label = 'Pending Review';
        break;
      case 'rejected':
        color = Colors.red;
        label = 'Rejected';
        break;
      default:
        color = Colors.grey;
        label = 'Not Verified';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final email = supabase.auth.currentUser?.email ?? '';
    final googleName =
        supabase.auth.currentUser?.userMetadata?['full_name'] ?? email;
    final status = _profile?['verification_status'] ?? 'unverified';

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 20),
                const CircleAvatar(
                  radius: 45,
                  child: Icon(Icons.person, size: 50),
                ),
                const SizedBox(height: 16),
                Text(
                  googleName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  email,
                  style: const TextStyle(color: Colors.lightGreen, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _statusBadge(status),
                const SizedBox(height: 24),

                if (status == 'unverified') ...[
                  const Text(
                    'Verify your account to start booking.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VerificationFormPage(),
                          ),
                        );
                        _fetchProfile();
                      },
                      child: const Text('Verify Account'),
                    ),
                  ),
                ] else if (status == 'pending') ...[
                  const Text(
                    'Your verification is under review. Please check back later.',
                    textAlign: TextAlign.center,
                  ),
                ] else if (status == 'rejected') ...[
                  const Text(
                    'Your verification was rejected. Please submit again with correct details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const VerificationFormPage(),
                          ),
                        );
                        _fetchProfile();
                      },
                      child: const Text('Resubmit Verification'),
                    ),
                  ),
                ] else if (status == 'verified') ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Name: ${_profile?['last_name'] ?? ''}, '
                                '${_profile?['first_name'] ?? ''} '
                                '${_profile?['middle_name'] ?? ''}'
                                '${(_profile?['suffix'] != null && _profile?['suffix'] != 'N/A') ? ' ${_profile?['suffix']}' : ''}',
                          ),
                          const SizedBox(height: 6),
                          Text('Birth date: ${_profile?['birth_date'] ?? 'N/A'}'),
                          const SizedBox(height: 6),
                          Text('Contact: ${_profile?['phone'] ?? 'N/A'}'),
                          const SizedBox(height: 6),
                          Text('ID Type: ${_profile?['government_id_type'] ?? 'N/A'}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.all(20),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
            ),
          ),
        ),
      ],
    );
  }
}