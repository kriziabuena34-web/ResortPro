import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notifications.dart';

/// Buong pag-sign out: itigil ang notifications, i-sign out sa Google
/// (para makapili ulit ng account), at sa Supabase.
Future<void> signOutCompletely() async {
  await UserNotifications.instance.stop();
  try {
    await GoogleSignIn.instance.signOut();
  } catch (_) {
    // ignore if Google has nothing to sign out of
  }
  try {
    await Supabase.instance.client.auth.signOut();
  } catch (_) {
    // Hal. burado na ang account sa server: linisin na lang ang session sa phone.
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
  }
}
