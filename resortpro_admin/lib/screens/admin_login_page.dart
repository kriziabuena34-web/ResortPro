import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../widgets/admin_widgets.dart';
import 'admin_dashboard_page.dart';

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

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboardPage()),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final form = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('welcomeBack'),
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            tr('loginSubtitle'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: tr('email'),
              prefixIcon: const Icon(Icons.mail_outline),
            ),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: tr('password'),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _showPassword ? tr('hidePassword') : tr('showPassword'),
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
            obscureText: !_showPassword,
            onSubmitted: (_) => _isLoading ? null : _login(),
          ),
          if (_errorKey != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr(_errorKey!, {'e': _errorDetail ?? ''}),
                      style: TextStyle(color: theme.colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('login'), style: const TextStyle(fontSize: 16)),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final formPane = Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!wide) ...[
                        const _BrandMark(size: 64),
                        const SizedBox(height: 12),
                        Text(
                          'ResortPro Admin',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 28),
                      ],
                      form,
                    ],
                  ),
                ),
              ),
              const Positioned(top: 12, right: 12, child: SafeArea(child: LanguageMenuButton())),
            ],
          );

          if (!wide) return formPane;

          return Row(
            children: [
              Expanded(child: _BrandPanel(theme: theme)),
              Expanded(child: formPane),
            ],
          );
        },
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 56, this.light = false});
  final double size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: light ? Colors.white.withValues(alpha: 0.18) : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        Icons.beach_access_rounded,
        size: size * 0.55,
        color: light ? Colors.white : scheme.primary,
      ),
    );
  }
}

/// Kaliwang panel ng login sa malapad na screen.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const white = Colors.white;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1B2B), Color(0xFF0E4D5A), Color(0xFF0F766E)],
        ),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              _BrandMark(size: 48, light: true),
              SizedBox(width: 12),
              Text(
                'ResortPro Admin',
                style: TextStyle(color: white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const Spacer(),
          Text(
            tr('brandHeadline'),
            style: theme.textTheme.displaySmall?.copyWith(
              color: white,
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('brandSub'),
            style: theme.textTheme.titleMedium?.copyWith(color: white.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 32),
          for (final f in const [
            (Icons.insights, 'brandFeature1'),
            (Icons.notifications_active_outlined, 'brandFeature2'),
            (Icons.photo_library_outlined, 'brandFeature3'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(f.$1, color: white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(tr(f.$2), style: const TextStyle(color: white, fontSize: 15)),
                  ),
                ],
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }
}
