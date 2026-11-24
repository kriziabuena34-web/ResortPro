import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';

/// GCash at Maya ng resort na pinapadalhan ng bayad ng guest.
/// Nakatago sa resort_settings (payment_accounts_setup.sql).
class PaymentAccountsPage extends StatefulWidget {
  const PaymentAccountsPage({super.key});

  @override
  State<PaymentAccountsPage> createState() => _PaymentAccountsPageState();
}

class _AccountForm {
  final number = TextEditingController();
  final name = TextEditingController();
  bool enabled = true;

  void dispose() {
    number.dispose();
    name.dispose();
  }
}

class _PaymentAccountsPageState extends State<PaymentAccountsPage> {
  final _gcash = _AccountForm();
  final _maya = _AccountForm();
  Map<String, dynamic>? _saved;
  DateTime? _updatedAt;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;

  static final _numberPattern = RegExp(r'^09\d{9}$');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gcash.dispose();
    _maya.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _current => {
        'gcash_number': _gcash.number.text.trim(),
        'gcash_name': _gcash.name.text.trim(),
        'gcash_enabled': _gcash.enabled,
        'maya_number': _maya.number.text.trim(),
        'maya_name': _maya.name.text.trim(),
        'maya_enabled': _maya.enabled,
      };

  bool get _changed {
    final s = _saved;
    if (s == null) return false;
    return _current.entries.any((e) => '${s[e.key] ?? ''}' != '${e.value}');
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('resort_settings')
          .select('gcash_number, gcash_name, gcash_enabled, maya_number, maya_name, maya_enabled, '
              'payment_accounts_updated_at')
          .eq('id', 1)
          .single();
      _gcash.number.text = '${row['gcash_number'] ?? ''}';
      _gcash.name.text = '${row['gcash_name'] ?? ''}';
      _gcash.enabled = row['gcash_enabled'] != false;
      _maya.number.text = '${row['maya_number'] ?? ''}';
      _maya.name.text = '${row['maya_name'] ?? ''}';
      _maya.enabled = row['maya_enabled'] != false;
      setState(() {
        _saved = _current;
        _updatedAt = parseDate(row['payment_accounts_updated_at']);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = '$e'.contains('gcash_') ? tr('paNotSetUp') : tr('failed', {'e': e});
      });
    }
  }

  String? _validate() {
    if (!_gcash.enabled && !_maya.enabled) return tr('paNeedOne');
    for (final (label, f) in [('GCash', _gcash), ('Maya', _maya)]) {
      if (!f.enabled) continue;
      if (!_numberPattern.hasMatch(f.number.text.trim())) return tr('paNumberInvalid', {'method': label});
      if (f.name.text.trim().length < 2) return tr('paNameRequired', {'method': label});
    }
    return null;
  }

  Future<void> _save() async {
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? orNull(String v) => v.isEmpty ? null : v;
      final c = _current;
      await Supabase.instance.client.from('resort_settings').update({
        'gcash_number': orNull(c['gcash_number'] as String),
        'gcash_name': orNull(c['gcash_name'] as String),
        'gcash_enabled': c['gcash_enabled'],
        'maya_number': orNull(c['maya_number'] as String),
        'maya_name': orNull(c['maya_name'] as String),
        'maya_enabled': c['maya_enabled'],
        'payment_accounts_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', 1);
      if (!mounted) return;
      setState(() {
        _saved = _current;
        _updatedAt = DateTime.now();
        _saving = false;
      });
      showToast(context, tr('paSaved'));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = tr('failed', {'e': e});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 36, color: AppColors.warning),
              const SizedBox(height: 12),
              Text(_loadError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(tr('tryAgain'))),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: pageInsets(context),
      children: [
        Text(tr('paIntro'), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 760;
          final cards = [
            _accountCard('GCash', Icons.phone_android, const Color(0xFF0B63F6), _gcash),
            _accountCard('Maya', Icons.account_balance_wallet_outlined, const Color(0xFF0E9F6E), _maya),
          ];
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: cards[0]), const SizedBox(width: 16), Expanded(child: cards[1])],
                )
              : Column(children: [cards[0], const SizedBox(height: 16), cards[1]]);
        }),
        const SizedBox(height: 16),
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
              onPressed: !_changed || _saving ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? tr('saving') : tr('save')),
            ),
            if (_changed) Text(tr('tmUnsaved'), style: const TextStyle(color: Color(0xFF92400E), fontSize: 13)),
            if (!_changed && _updatedAt != null)
              Text(tr('tmUpdated', {'date': formatDateTime(_updatedAt)}),
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _accountCard(String label, IconData icon, Color color, _AccountForm f) {
    InputDecoration deco(String text, {String? hint, String? helper}) => InputDecoration(
          labelText: text,
          hintText: hint,
          helperText: helper,
          border: const OutlineInputBorder(),
        );
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                      Text(f.enabled ? tr('paShown') : tr('paHidden'),
                          style: TextStyle(color: f.enabled ? AppColors.success : AppColors.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                Switch(value: f.enabled, onChanged: (v) => setState(() => f.enabled = v)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: f.number,
              enabled: f.enabled,
              keyboardType: TextInputType.phone,
              maxLength: 11,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(tr('paNumber', {'method': label}), hint: '09XX XXX XXXX'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: f.name,
              enabled: f.enabled,
              maxLength: 60,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              textCapitalization: TextCapitalization.words,
              decoration: deco(tr('paName'), helper: tr('paNameHelp', {'method': label})),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            // Ganito ang makikita ng guest sa app.
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: const Color(0xFFE6EDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD3DEEA)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('paPreview'),
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.muted)),
                  const SizedBox(height: 6),
                  Text('$label Number', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text(f.number.text.trim().isEmpty ? '—' : f.number.text.trim(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink)),
                  Text('Account name: ${f.name.text.trim().isEmpty ? '—' : f.name.text.trim()}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
