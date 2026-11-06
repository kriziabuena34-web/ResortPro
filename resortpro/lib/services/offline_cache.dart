import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Walang internet ba ang dahilan ng error?
bool isOfflineError(Object e) {
  if (e is SocketException || e is TimeoutException || e is HandshakeException) return true;
  final t = '$e';
  return t.contains('SocketException') ||
      t.contains('Failed host lookup') ||
      t.contains('ClientException') ||
      t.contains('Connection refused') ||
      t.contains('Connection closed') ||
      t.contains('Network is unreachable') ||
      t.contains('Connection timed out');
}

/// Mabilis na tingin kung may internet (ilang segundo lang ang hinihintay).
Future<bool> hasInternet() async {
  try {
    final host = Uri.parse(supabaseUrl).host;
    final r = await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
    return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Ipakita agad na walang internet (snackbar).
void showOfflineSnack(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('No internet connection. Please turn on Wi-Fi or mobile data and try again.'),
        duration: Duration(seconds: 3),
      ),
    );
}

/// Maikling mensahe na maiintindihan ng guest (hindi teknikal).
String friendlyError(Object e, {String action = 'load this'}) {
  if (isOfflineError(e)) {
    return 'No internet connection. Please turn on Wi-Fi or mobile data and try again.';
  }
  return 'Something went wrong while trying to $action. Please try again.';
}

/// Naka-save na kopya ng huling nakuhang data, para may maipakita kahit offline.
class OfflineCache {
  OfflineCache._();

  static String _key(String name, {bool perUser = true}) {
    final uid = perUser ? Supabase.instance.client.auth.currentUser?.id ?? 'guest' : 'all';
    return 'offline_cache:$uid:$name';
  }

  static Future<void> save(String name, Object? data, {bool perUser = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key(name, perUser: perUser),
        jsonEncode({'savedAt': DateTime.now().toIso8601String(), 'data': data}),
      );
    } catch (_) {}
  }

  /// Ibinabalik ang naka-save na data at kung kailan ito na-save (null kung wala).
  static Future<({dynamic data, DateTime savedAt})?> load(String name, {bool perUser = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(name, perUser: perUser));
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (data: j['data'], savedAt: DateTime.parse(j['savedAt'] as String));
    } catch (_) {
      return null;
    }
  }
}

/// Banner na nagsasabing offline at naka-save na impormasyon ang ipinapakita.
class OfflineNotice extends StatelessWidget {
  const OfflineNotice({super.key, required this.savedAt, this.onRetry, this.margin});

  final DateTime savedAt;
  final VoidCallback? onRetry;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final h = savedAt.hour % 12 == 0 ? 12 : savedAt.hour % 12;
    final m = savedAt.minute.toString().padLeft(2, '0');
    final when = '${formatDate(savedAt)}, $h:$m ${savedAt.hour >= 12 ? 'PM' : 'AM'}';
    return Container(
      margin: margin ?? const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "You're offline. Showing info saved on $when.",
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Buong-screen na mensahe kapag walang internet at walang naka-save na data.
class OfflineEmpty extends StatelessWidget {
  const OfflineEmpty({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = message.startsWith('No internet');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (offline ? AppColors.warning : AppColors.danger).withValues(alpha: 0.10),
              ),
              child: Icon(
                offline ? Icons.wifi_off_rounded : Icons.error_outline,
                size: 34,
                color: offline ? AppColors.warning : AppColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              offline ? "You're offline" : 'Something went wrong',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
