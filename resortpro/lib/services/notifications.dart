import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import '../config.dart';
import '../utils/format.dart';

// ===========================================================================
// NOTIFICATIONS NG USER APP
//
// 1. Habang bukas ang app   → Supabase Realtime (instant)
// 2. Kahit sarado ang app   → WorkManager background check kada ~15 minuto.
//    Tinitingnan nito sa Supabase kung may bagong notification, tapos
//    ipinapakita bilang phone notification. Walang Firebase na kailangan.
// 3. Stay reminder          → kapag bukas na ang booking, may paalala.
// ===========================================================================

/// Android lang ang may background check at phone notifications.
bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

const _channelId = 'resortpro_updates';
const _channelName = 'Booking updates';
const _backgroundTaskId = 'resortpro-notification-check';
const _backgroundTaskName = 'resortpro_check_notifications';

String _lastIdKey(String userId) => 'last_notified_id_$userId';
String _remindedKey(dynamic bookingId) => 'stay_reminded_$bookingId';

// ---------------------------------------------------------------------------
// Phone notifications (flutter_local_notifications)
// ---------------------------------------------------------------------------

class LocalNotifier {
  LocalNotifier._();

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Tinatawag kapag pinindot ang notification habang bukas ang app.
  static void Function(String? payload)? onTap;

  static Future<void> init() async {
    if (_ready || !_isAndroid) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) => onTap?.call(response.payload),
    );
    _ready = true;
  }

  /// Android 13+: hihingi ng pahintulot na magpakita ng notifications.
  static Future<void> requestPermission() async {
    if (!_isAndroid) return;
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// True kung binuksan ang app dahil pinindot ang isang notification.
  static Future<bool> launchedFromNotification() async {
    if (!_isAndroid) return false;
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isAndroid) return;
    await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Updates about your bookings, payments, and account',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Text ng bawat uri ng notification
// ---------------------------------------------------------------------------

Map<String, dynamic> notificationData(Map<String, dynamic> n) {
  final d = n['data'];
  return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
}

/// 'booking', 'payment', o 'account' (para sa filter).
String notificationCategory(String? type) {
  final t = type ?? '';
  if (t.startsWith('payment')) return 'payment';
  if (t.startsWith('account')) return 'account';
  if (t.startsWith('chat')) return 'chat';
  return 'booking';
}

String notificationTitle(Map<String, dynamic> n) {
  switch (n['type']) {
    case 'booking_confirmed':
      return 'Booking confirmed';
    case 'booking_cancelled':
      return 'Booking cancelled';
    case 'booking_checked_in':
      return 'Welcome! You are checked in';
    case 'booking_completed':
      return 'Thank you for staying with us';
    case 'booking_no_show':
      return 'Missed booking';
    case 'booking_reserved':
      return 'Booking reopened';
    case 'booking_fully_paid':
    case 'payment_complete':
      return 'Booking fully paid';
    case 'payment_received':
    case 'payment_verified':
      return 'Payment verified';
    case 'payment_rejected':
      return 'Payment not accepted';
    case 'payment_refunded':
      return 'Refund sent';
    case 'payment_refund_rejected':
      return 'Refund not approved';
    case 'account_verified':
      return 'Account verified';
    case 'account_rejected':
      return 'Verification declined';
    case 'stay_reminder':
      return 'Your stay is tomorrow';
    case 'chat_message':
      return 'New message from the resort';
    default:
      return 'ResortPro update';
  }
}

/// Pinaiikli ang mahabang dahilan o note mula sa admin para hindi humaba
/// nang sobra ang notification (hal. 200 letra lang, may "…" sa dulo).
String _clip(String text, [int max = 200]) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.length <= max) return t;
  return '${t.substring(0, max).trimRight()}…';
}

String notificationBody(Map<String, dynamic> n) {
  final d = notificationData(n);
  final pkg = d['package'] ?? 'your booking';
  final date = formatDate(parseDate(d['date']));
  final note = _clip('${d['note'] ?? ''}');
  final reason = _clip('${d['reason'] ?? ''}');

  switch (n['type']) {
    case 'booking_confirmed':
      return 'Your $pkg on $date is confirmed. See you!';
    case 'booking_cancelled':
      return 'Your $pkg on $date was cancelled.${note.isEmpty ? '' : ' Reason: $note'}';
    case 'booking_checked_in':
      return 'Enjoy your $pkg. Contact the front desk if you need anything.';
    case 'booking_completed':
      return 'Your $pkg booking is complete. We hope to see you again!';
    case 'booking_no_show':
      return 'You were marked as no-show for $pkg on $date.${note.isEmpty ? '' : ' Note: $note'}';
    case 'booking_reserved':
      return 'Your $pkg on $date is active again and waiting for confirmation.';
    case 'booking_fully_paid':
    case 'payment_complete':
      return 'We received ${peso(asDouble(d['amount']))}. Your $pkg booking is now fully paid.';
    case 'payment_received':
    case 'payment_verified':
      return 'Your payment of ${peso(asDouble(d['amount']))} for $pkg was verified. '
          'Remaining balance: ${peso(asDouble(d['balance']))}.';
    case 'payment_rejected':
      return 'Your payment of ${peso(asDouble(d['amount']))} for $pkg could not be verified'
          '${reason.isEmpty ? '.' : ': $reason.'} Please send a new proof in My Bookings.';
    case 'payment_refunded':
      return 'We sent your refund of ${peso(asDouble(d['amount']))} for $pkg.'
          '${'${d['reference_no'] ?? ''}'.isEmpty ? '' : ' Reference no. ${d['reference_no']}.'}';
    case 'payment_refund_rejected':
      return 'Your refund for $pkg was not approved${reason.isEmpty ? '.' : ': $reason.'}';
    case 'account_verified':
      return 'Your ID has been verified. You can now book packages.';
    case 'account_rejected':
      return '${reason.isEmpty ? 'Your ID could not be verified.' : 'Reason: $reason.'} '
          'Please submit a valid ID again in the Account tab.';
    case 'stay_reminder':
      return '$pkg on $date. We look forward to seeing you!';
    case 'chat_message':
      return '${d['preview'] ?? 'Tap to read the reply.'}';
    default:
      return '';
  }
}

IconData notificationIcon(String? type) {
  switch (notificationCategory(type)) {
    case 'payment':
      return Icons.payments_outlined;
    case 'account':
      return Icons.verified_user_outlined;
    case 'chat':
      return Icons.chat_bubble_outline;
    default:
      return Icons.event_available_outlined;
  }
}

// ---------------------------------------------------------------------------
// In-app notifications (listahan + realtime)
// ---------------------------------------------------------------------------

class UserNotifications extends ChangeNotifier {
  UserNotifications._();
  static final UserNotifications instance = UserNotifications._();

  SupabaseClient get _db => Supabase.instance.client;

  List<Map<String, dynamic>> items = [];
  bool available = true;
  bool loading = false;
  RealtimeChannel? _channel;
  String? _userId;

  int get unreadCount => items.where((n) => n['is_read'] != true).length;

  /// Pinakabagong dumating na notification (realtime). Ginagamit ng in-app banner.
  final ValueNotifier<Map<String, dynamic>?> latest = ValueNotifier(null);

  /// Simulan pagka-login: load, realtime, at background check.
  Future<void> start() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    if (_userId == uid && _channel != null) return;
    _userId = uid;

    await load();
    _subscribe(uid);
    await LocalNotifier.requestPermission();
    await BackgroundCheck.register();
  }

  /// Itigil pag-logout.
  Future<void> stop() async {
    final channel = _channel;
    if (channel != null) {
      await _db.removeChannel(channel);
      _channel = null;
    }
    _userId = null;
    items = [];
    notifyListeners();
    await BackgroundCheck.cancel();
  }

  Future<void> load() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    loading = true;
    notifyListeners();
    try {
      final rows = await _db
          .from('notifications')
          .select()
          .eq('audience', 'client')
          .eq('recipient_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      items = List<Map<String, dynamic>>.from(rows);
      available = true;

      // Ang mga nakita na sa app ay hindi na ipapakita ulit ng background check.
      final maxId = items.fold<int>(0, (m, n) => math.max(m, (n['id'] as num?)?.toInt() ?? 0));
      await _saveLastId(uid, maxId);
    } catch (_) {
      available = false;
    }
    loading = false;
    notifyListeners();
  }

  void _subscribe(String uid) {
    final old = _channel;
    if (old != null) _db.removeChannel(old);

    _channel = _db
        .channel('client-notifications-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: uid,
          ),
          callback: (payload) async {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row['audience'] != 'client') return;
            items = [row, ...items];
            notifyListeners();

            final id = (row['id'] as num?)?.toInt() ?? 0;
            final foreground =
                WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
            if (foreground) {
              // Bukas ang app: in-app banner ang lalabas (hindi na phone notification).
              latest.value = row;
            } else {
              await LocalNotifier.show(
                id: id % 100000,
                title: notificationTitle(row),
                body: notificationBody(row),
                payload: 'notification:$id',
              );
            }
            await _saveLastId(uid, id);
          },
        )
        .subscribe();
  }

  Future<void> markRead(Map<String, dynamic> n) async {
    if (n['is_read'] == true) return;
    n['is_read'] = true;
    notifyListeners();
    try {
      await _db.from('notifications').update({'is_read': true}).eq('id', n['id']);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return;
    for (final n in items) {
      n['is_read'] = true;
    }
    notifyListeners();
    try {
      await _db
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', uid)
          .eq('is_read', false);
    } catch (_) {}
  }

  static Future<void> _saveLastId(String uid, int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final current = prefs.getInt(_lastIdKey(uid)) ?? 0;
    if (id > current) await prefs.setInt(_lastIdKey(uid), id);
  }
}

// ---------------------------------------------------------------------------
// Background check (WorkManager) — gumagana kahit sarado ang app
// ---------------------------------------------------------------------------

/// Entry point ng background task. Kailangang top-level at may @pragma.
@pragma('vm:entry-point')
void notificationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await BackgroundCheck.run();
    } catch (_) {
      // Huwag i-crash ang background task; susubukan ulit sa susunod.
    }
    return true;
  });
}

class BackgroundCheck {
  BackgroundCheck._();

  /// Tawagin sa main() bago runApp.
  static Future<void> initialize() async {
    if (!_isAndroid) return;
    await Workmanager().initialize(notificationCallbackDispatcher);
  }

  static Future<void> register() async {
    if (!_isAndroid) return;
    await Workmanager().registerPeriodicTask(
      _backgroundTaskId,
      _backgroundTaskName,
      // 15 minuto ang pinakamaikling pinapayagan ng Android.
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 1),
      // Tatakbo lang kapag may internet; kapag wala, uulitin agad pagbalik ng signal.
      constraints: Constraints(networkType: NetworkType.connected),
      // Panatilihin ang dating schedule (huwag i-reset tuwing bubuksan ang app).
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );
  }

  static Future<void> cancel() async {
    if (!_isAndroid) return;
    await Workmanager().cancelByUniqueName(_backgroundTaskId);
  }

  /// Ang mismong check: bagong notifications + stay reminder.
  static Future<void> run() async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    } catch (_) {
      // Naka-initialize na (hal. bukas ang app sa parehong isolate).
    }
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;

    final session = client.auth.currentSession;
    if (session != null && session.isExpired) {
      try {
        await client.auth.refreshSession();
      } catch (_) {
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // 1) Bagong notifications mula sa admin
    final lastId = prefs.getInt(_lastIdKey(user.id)) ?? 0;
    final rows = await client
        .from('notifications')
        .select()
        .eq('audience', 'client')
        .eq('recipient_id', user.id)
        .gt('id', lastId)
        .order('id')
        .limit(20);

    var maxId = lastId;
    for (final raw in rows) {
      final n = Map<String, dynamic>.from(raw);
      final id = (n['id'] as num?)?.toInt() ?? 0;
      await LocalNotifier.show(
        id: id % 100000,
        title: notificationTitle(n),
        body: notificationBody(n),
        payload: 'notification:$id',
      );
      maxId = math.max(maxId, id);
    }
    if (maxId > lastId) await prefs.setInt(_lastIdKey(user.id), maxId);

    // 2) Paalala isang araw bago ang stay
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final bookings = await client
        .from('bookings')
        .select('id, booking_date, status, packages(name)')
        .eq('client_id', user.id)
        .eq('booking_date', dateKey(tomorrow));

    for (final raw in bookings) {
      final b = Map<String, dynamic>.from(raw);
      if (isInactiveStatus(b['status'] as String?)) continue;
      if (prefs.getBool(_remindedKey(b['id'])) == true) continue;

      final pkg = b['packages'];
      final reminder = {
        'type': 'stay_reminder',
        'data': {
          'package': pkg is Map ? pkg['name'] : null,
          'date': b['booking_date'],
        },
      };
      await LocalNotifier.show(
        id: 900000 + ('${b['id']}'.hashCode.abs() % 99999),
        title: notificationTitle(reminder),
        body: notificationBody(reminder),
        payload: 'booking:${b['id']}',
      );
      await prefs.setBool(_remindedKey(b['id']), true);
    }
  }
}

// ---------------------------------------------------------------------------
// Battery optimization — maraming phone (Xiaomi, Oppo, Vivo, realme, Infinix)
// ang pumapatay sa background check kapag sinwipe ang app. Hinihiling sa user
// na payagang tumakbo ang ResortPro sa background.
// ---------------------------------------------------------------------------

class BatterySaver {
  BatterySaver._();

  static const _channel = MethodChannel('resortpro/battery');
  static const _askedKey = 'battery_optimization_asked';

  /// True kapag hindi na pinapatay ng battery saver ang app (o hindi Android).
  static Future<bool> isAllowed() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isIgnoring') ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Bubuksan ang prompt ng Android na "Allow app to run in background?".
  static Future<void> request() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('request');
    } catch (_) {}
  }

  /// Isang beses lang ipapakita: paliwanag, tapos ang prompt ng Android.
  static Future<void> askOnce(BuildContext context) async {
    if (!_isAndroid || await isAllowed()) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return;
    await prefs.setBool(_askedKey, true);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: const Text('Get updates even when the app is closed'),
        content: const Text(
          'Some phones stop apps in the background to save battery. Allow ResortPro to run in the '
          'background so you still get booking and payment updates after you close the app.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Allow')),
        ],
      ),
    );
    if (ok == true) await request();
  }
}
