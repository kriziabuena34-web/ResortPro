import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../widgets/admin_widgets.dart';
import '../services/app_router.dart';
import '../theme/app_theme.dart';

class AdminLoginPage extends StatefulWidget {
  const AdminLoginPage({super.key});

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final supabase = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _showPassword = false;

  // Naka-store bilang key + detail para ma-translate ulit kapag nagpalit ng wika.
  String? _errorKey;
  String? _errorDetail;

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorKey = 'loginMissing');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorKey = null;
      _errorDetail = null;
    });

    try {
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final userId = response.user?.id;
      if (userId == null) {
        throw Exception('Login failed.');
      }

      // Check if this user is actually an admin
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .single();

      if (profile['role'] != 'admin') {
        await supabase.auth.signOut();
        setState(() {
          _errorKey = 'notAdmin';
          _isLoading = false;
        });
        return;
      }

      adminSignedIn.value = true;
    } catch (e) {
      // Malinaw na mensahe para sa staff (hindi teknikal na error).
      final t = '$e';
      final String key;
      if (t.contains('invalid_credentials') || t.contains('Invalid login credentials')) {
        key = 'loginWrong';
      } else if (t.contains('email_not_confirmed')) {
        key = 'loginNotConfirmed';
      } else if (t.contains('over_request_rate_limit') || t.contains('429')) {
        key = 'loginTooMany';
      } else if (t.contains('SocketException') ||
          t.contains('Failed host lookup') ||
          t.contains('ClientException') ||
          t.contains('Failed to fetch') ||
          t.contains('XMLHttpRequest')) {
        key = 'loginOffline';
      } else {
        key = 'loginGeneric';
      }
      if (!mounted) return;
      setState(() {
        _errorKey = key;
        _errorDetail = null;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  InputDecoration _field(String label, IconData icon, {Widget? suffix}) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppColors.subtle,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.6)),
      );

  @override
  Widget build(BuildContext context) {
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _BrandMark(size: 76)),
        const SizedBox(height: 18),
        Text(
          tr('welcomeBack'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Poppins', fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        const SizedBox(height: 6),
        Text(
          tr('loginSubtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, height: 1.4),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _emailController,
          decoration: _field(tr('email'), Icons.mail_outline_rounded),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordController,
          decoration: _field(
            tr('password'),
            Icons.lock_outline_rounded,
            suffix: IconButton(
              tooltip: _showPassword ? tr('hidePassword') : tr('showPassword'),
              icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          obscureText: !_showPassword,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _isLoading ? null : _login(),
        ),
        if (_errorKey != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(_errorKey!, {'e': _errorDetail ?? ''}),
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.ink,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _isLoading ? null : _login,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(tr('login'), style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 19),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield_outlined, size: 14, color: AppColors.muted),
            const SizedBox(width: 6),
            Text(tr('loginSecure'), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ],
    );

    final card = Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.fromLTRB(32, 34, 32, 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      child: AutofillGroup(child: form),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 960;
          final formPane = Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: card,
                ),
              ),
              const Positioned(top: 12, right: 12, child: SafeArea(child: LanguageMenuButton())),
            ],
          );

          if (!wide) {
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.asset('assets/images/login_bg.jpg', fit: BoxFit.cover),
                Container(color: const Color(0xCC0B1B2B)),
                formPane,
              ],
            );
          }

          return Row(
            children: [
              const Expanded(flex: 11, child: _BrandPanel()),
              Expanded(flex: 10, child: formPane),
            ],
          );
        },
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/aryana_logo.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Kaliwang panel ng login sa malapad na screen: larawan ng resort.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/images/login_bg.jpg', fit: BoxFit.cover),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x990B1B2B), Color(0x660B1B2B), Color(0xF20B1B2B)],
              stops: [0, 0.45, 1],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  _BrandMark(size: 50),
                  SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ResortPro Admin',
                          style: TextStyle(fontFamily: 'Poppins', color: white, fontSize: 19, fontWeight: FontWeight.w700)),
                      Text("Aryana's Guests House", style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13)),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                tr('brandHeadline'),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: white,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                tr('brandSub'),
                style: TextStyle(color: white.withValues(alpha: 0.85), fontSize: 16, height: 1.45),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final f in const [
                    (Icons.insights_rounded, 'brandFeature1'),
                    (Icons.notifications_active_outlined, 'brandFeature2'),
                    (Icons.photo_library_outlined, 'brandFeature3'),
                  ])
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
                      decoration: BoxDecoration(
                        color: white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: white.withValues(alpha: 0.18)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(f.$1, color: white, size: 18),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(tr(f.$2), style: const TextStyle(color: white, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
