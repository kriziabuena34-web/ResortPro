import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import 'offline_cache.dart';

/// Isang e-wallet account ng resort (GCash o Maya) na pinapadalhan ng bayad.
class PayAccount {
  const PayAccount({required this.number, required this.name, this.enabled = true});
  final String number;
  final String name;
  final bool enabled;

  Map<String, dynamic> toJson() => {'number': number, 'name': name, 'enabled': enabled};

  static PayAccount? fromJson(dynamic j) {
    if (j is! Map) return null;
    final number = '${j['number'] ?? ''}'.trim();
    if (number.isEmpty) return null;
    return PayAccount(
      number: number,
      name: '${j['name'] ?? ''}'.trim(),
      enabled: j['enabled'] != false,
    );
  }
}

/// Mga account ng resort para sa bayad. Galing sa admin (resort_settings);
/// kapag offline o hindi pa naka-setup, ang huling naka-save o ang nasa config.
class PaymentAccounts {
  PaymentAccounts._();

  static const _cacheKey = 'payment_accounts';
  static bool _cacheLoaded = false;

  static final current = ValueNotifier<Map<String, PayAccount>>({
    'gcash': const PayAccount(number: gcashNumber, name: paymentAccountName),
    'maya': const PayAccount(number: mayaNumber, name: paymentAccountName),
  });

  static Future<void> refresh() async {
    if (!_cacheLoaded) {
      _cacheLoaded = true;
      final cached = await OfflineCache.load(_cacheKey, perUser: false);
      final m = _parse(cached?.data);
      if (m != null) current.value = m;
    }
    try {
      final row = await Supabase.instance.client
          .from('resort_settings')
          .select('gcash_number, gcash_name, gcash_enabled, maya_number, maya_name, maya_enabled')
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));
      if (row == null) return;
      final m = _parse({
        'gcash': {'number': row['gcash_number'], 'name': row['gcash_name'], 'enabled': row['gcash_enabled']},
        'maya': {'number': row['maya_number'], 'name': row['maya_name'], 'enabled': row['maya_enabled']},
      });
      if (m == null) return;
      current.value = m;
      await OfflineCache.save(_cacheKey, {for (final e in m.entries) e.key: e.value.toJson()}, perUser: false);
    } catch (_) {
      // Offline o hindi pa na-run ang SQL: mananatili ang naka-save / default.
    }
  }

  static Map<String, PayAccount>? _parse(dynamic data) {
    if (data is! Map) return null;
    final g = PayAccount.fromJson(data['gcash']);
    final m = PayAccount.fromJson(data['maya']);
    if (g == null && m == null) return null;
    return {
      'gcash': g ?? current.value['gcash']!,
      'maya': m ?? current.value['maya']!,
    };
  }
}
