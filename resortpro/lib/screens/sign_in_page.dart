import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'info_pages.dart';
import '../theme/app_theme.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, this.openAccountPicker = false});

  /// True kapag galing sa "Switch Account": kusang ipapakita ang Google account picker.
  final bool openAccountPicker;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final supabase = Supabase.instance.client;
  bool _isSigningIn = false;

  // Web Client ID from Google Cloud Console (used for Supabase verification)
  static const String _webClientId =
      '426104695342-3mvl1ng19qbdhqj5fgnaeeo8flp20omo.apps.googleusercontent.com';

  // Google Sign-In should be initialized only once per app run.
  static bool _googleInitialized = false;

  // ---------- EASY SETTINGS ----------
  // Laki ng logo (bilog)
  static const double _logoSize = 160;
  // Dilim ng background: mas mababa = mas maliwanag
  static const double _gradientTopAlpha = 0.10;
  static const double _gradientBottomAlpha = 0.85;
  // -----------------------------------

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: _webClientId);
    _googleInitialized = true;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  String _friendlyGoogleError(GoogleSignInException e) {
    final text = e.toString().toLowerCase();

    if (text.contains('reauth')) {
      return 'Google could not verify this account. '
          'Details: ${e.description ?? e.toString()}';
    }
    if (text.contains('no credentials')) {
      return 'No Google account found on this device. Add one in your '
          'device settings, then try again.';
    }
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return 'Sign-in was cancelled or blocked. Details: '
          '${e.description ?? 'none'}';
    }
    return 'Sign-in failed: $e';
  }

  @override
  void initState() {
    super.initState();
    if (widget.openAccountPicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleGoogleSignIn());
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isSigningIn = true);

    try {
      await _ensureGoogleInitialized();
      final googleSignIn = GoogleSignIn.instance;

      final account = await googleSignIn.authenticate();
      final googleAuth = account.authentication;

      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw Exception('No ID token received from Google.');
      }

      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    } on GoogleSignInException catch (e) {
      // Isinara lang ang account picker (pinindot sa labas o Back): walang error na ipapakita.
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      _showMessage(_friendlyGoogleError(e));
    } catch (e) {
      _showMessage('Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _isSigningIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // BACKGROUND: tubig ng pool na may anino ng palm
          Image.asset(
            'assets/images/login_bg.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => const ColoredBox(color: AppColors.ink),
          ),

          // GRADIENT OVERLAY (para mabasa ang text)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.45, 1],
                colors: [
                  AppColors.ink.withValues(alpha: _gradientTopAlpha),
                  AppColors.ink.withValues(alpha: 0.15),
                  AppColors.ink.withValues(alpha: _gradientBottomAlpha),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // TOP: LOGO + APP NAME
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // LOGO (transparent ang paligid; walang puting bilog)
                          Container(
                            width: _logoSize,
                            height: _logoSize,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Color(0x55000000), blurRadius: 28, offset: Offset(0, 12)),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/aryana_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Icon(Icons.hotel, color: AppColors.primary, size: 64),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'ResortPro',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 34,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              shadows: [Shadow(color: Color(0x88000000), blurRadius: 12)],
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Your booking companion',
                            style: TextStyle(
                              color: AppColors.accent,
                              fontSize: 15,
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                              shadows: [Shadow(color: Color(0x88000000), blurRadius: 10)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // BOTTOM: WELCOME CARD (dark glass)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
                  decoration: BoxDecoration(
                    color: AppColors.ink.withValues(alpha: 0.38),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Welcome!',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Sign in to book your stay at Aryana's Guests House.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // SIGN-IN BUTTON
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: _isSigningIn ? null : _handleGoogleSignIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: _isSigningIn
                              ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                              : const Icon(Icons.login),
                          label: Text(
                            _isSigningIn
                                ? 'Signing in...'
                                : 'Continue with Google',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const TermsPage(initialTab: 1),
                            ),
                          );
                        },
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            children: [
                              const TextSpan(
                                text: 'By continuing, you agree to our ',
                              ),
                              TextSpan(
                                text: 'Terms & Data Privacy',
                                style: TextStyle(
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF5EEAD4),
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                    ),
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
