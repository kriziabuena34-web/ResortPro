import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';
import 'offline_cache.dart';

/// I-link sa account ang booking na ginawa sa resort (walk-in o tawag),
/// gamit ang 8-character na code na nasa resibo.
/// Ibinabalik ang true kapag na-link.
Future<bool> showClaimBookingDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _ClaimDialog(),
  );
  return ok ?? false;
}

class _ClaimDialog extends StatefulWidget {
  const _ClaimDialog();

  @override
  State<_ClaimDialog> createState() => _ClaimDialogState();
}

class _ClaimDialogState extends State<_ClaimDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String get _clean => _code.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  Future<void> _submit() async {
    if (_clean.length != 8) {
      setState(() => _error = 'The code has 8 letters and numbers (e.g. K7QM-4XPA).');
      return;
    }
    if (!await hasInternet()) {
      if (mounted) setState(() => _error = 'No internet connection. Please connect and try again.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('claim_booking', params: {'p_code': _clean});
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final text = '$e';
      setState(() {
        _busy = false;
        _error = text.contains('INVALID_CODE')
            ? 'Code not found or already used. Please check your receipt.'
            : text.contains('claim_booking')
                ? 'This feature is not set up yet. Please ask the resort to update the system.'
                : friendlyError(e, action: 'add the booking');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // Puwedeng i-scroll kapag nakabukas ang keyboard (iwas sa dilaw-itim na "overflow" strip).
      scrollable: true,
      icon: const Icon(Icons.confirmation_number_outlined, color: AppColors.primary, size: 36),
      title: const Text('Add a booking made at the resort'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Booked at the front desk or by phone? Enter the code printed on your receipt '
            'so the booking and receipt appear in your account.',
            style: TextStyle(color: AppColors.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 3),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(hintText: 'XXXX-XXXX', errorText: _error, errorMaxLines: 3),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add booking'),
        ),
      ],
    );
  }
}
