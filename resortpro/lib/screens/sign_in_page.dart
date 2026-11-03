import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_page.dart';
import 'data_privacy_page.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

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
  // Logo opacity: 1.0 = solid, lower = more see-through
  static const double _logoOpacity = 1.0;
  // Logo corner radius: 0 = sharp corners, bigger = rounder
  static const double _logoCornerRadius = 30;
  // Logo size
  static const double _logoWidth = 300;
  static const double _logoHeight = 220;
  // Photo darkness: lower = brighter photo
  static const double _gradientTopAlpha = 0.35;
  static const double _gradientBottomAlpha = 0.75;
  // Welcome card opacity: 1.0 = solid, lower = more see-through
  static const double _cardAlpha = 0.0;
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
          // BACKGROUND PHOTO
          Image.asset(
            'assets/images/pool.jpg',
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: colorScheme.primary),
          ),

          // DARK GRADIENT OVERLAY (keeps the text readable)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: _gradientTopAlpha),
                  Colors.black.withValues(alpha: _gradientBottomAlpha),
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
                          // LOGO (transparent PNG, no frame)
                          ClipRRect(
                            borderRadius:
                            BorderRadius.circular(_logoCornerRadius),
                            child: Opacity(
                              opacity: _logoOpacity,
                              child: Image.asset(
                                'assets/images/backless.png',
                                width: _logoWidth,
                                height: _logoHeight,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) =>
                                const SizedBox(
                                  width: _logoWidth,
                                  height: _logoHeight,
                                  child: Icon(
                                    Icons.hotel,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 1),
                          const Text(
                            'ResortPro',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Your booking companion',
                            style: TextStyle(
                              color: Colors.tealAccent.withValues(alpha: 0.85),
                              fontSize: 16,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // BOTTOM: WELCOME CARD
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: _cardAlpha),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
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
                              builder: (context) => const DataPrivacyPage(),
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
                                  color: colorScheme.primary,
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
