import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../screens/info_pages.dart';
import 'offline_cache.dart';
import '../utils/format.dart';
import '../utils/reference_format.dart';
import '../theme/app_theme.dart';

/// Ang laman ng proof of payment na ipapasa ng client.
class PaymentProof {
  PaymentProof({required this.method, required this.reference, required this.image});
  final String method; // gcash o maya
  final String reference;
  final Uint8List image;
}

/// I-upload ang screenshot at i-record ang bayad bilang "pending"
/// (ang admin ang magve-verify).
Future<void> submitPaymentProof({
  required String bookingId,
  required double amount,
  required String kind, // downpayment o balance
  required PaymentProof proof,
}) async {
  final supabase = Supabase.instance.client;
  final uid = supabase.auth.currentUser!.id;
  final path = '$uid/${bookingId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

  await supabase.storage.from('payment-proofs').uploadBinary(
        path,
        proof.image,
        fileOptions: const FileOptions(upsert: false, contentType: 'image/jpeg'),
      );

  await supabase.from('payments').insert({
    'booking_id': bookingId,
    'amount': amount,
    'method': proof.method,
    'kind': kind,
    'reference_no': proof.reference,
    'proof_path': path,
    'status': 'pending',
  });
}

/// Form para sa paraan ng bayad, reference number, at screenshot.
/// Ginagamit sa booking page at sa "Pay balance".
class PaymentProofForm extends StatefulWidget {
  const PaymentProofForm({super.key, required this.amount, required this.onChanged});

  final double amount;

  /// Tinatawag tuwing may binago; null kapag kulang pa ang laman.
  final ValueChanged<PaymentProof?> onChanged;

  @override
  State<PaymentProofForm> createState() => _PaymentProofFormState();
}

class _PaymentProofFormState extends State<PaymentProofForm> {
  String _method = 'gcash';
  final _reference = TextEditingController();
  Uint8List? _image;

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  void _emit() {
    final ref = _reference.text.trim();
    widget.onChanged(
      RefFormat.of(_method).isComplete(ref) && _image != null
          ? PaymentProof(method: _method, reference: ref, image: _image!)
          : null,
    );
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _image = bytes);
    _emit();
  }

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.muted,
          ),
        ),
      );

  Widget _methodTile(String value, String label, IconData icon) {
    final selected = _method == value;
    return Material(
      color: selected ? AppColors.ink : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: selected ? AppColors.ink : AppColors.border, width: 1.2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          if (selected) return;
          setState(() {
            _method = value;
            // Ayusin ang format ayon sa bagong paraan ng bayad.
            _reference.text = RefFormat.of(_method).format(_reference.text);
          });
          _emit();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? Colors.white : AppColors.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: selected ? Colors.white : AppColors.text,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: selected ? const Color(0xFF5EEAD4) : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final number = _method == 'gcash' ? gcashNumber : mayaNumber;
    final methodName = _method == 'gcash' ? 'GCash' : 'Maya';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1) Paraan ng bayad
        _label('PAYMENT METHOD'),
        Row(
          children: [
            Expanded(child: _methodTile('gcash', 'GCash', Icons.phone_android)),
            const SizedBox(width: 10),
            Expanded(child: _methodTile('maya', 'Maya', Icons.account_balance_wallet_outlined)),
          ],
        ),
        const SizedBox(height: 18),

        // 2) Saan ipapadala
        _label('SEND PAYMENT TO'),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFE6EDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFD3DEEA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$methodName Number',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          number,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: AppColors.ink,
                          ),
                        ),
                        Text(
                          paymentAccountName,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: number));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Number copied.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text('Amount to send', style: TextStyle(fontSize: 13, color: AppColors.muted)),
                    const Spacer(),
                    Text(
                      peso(widget.amount),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.ink),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // 3) Reference number
        _label('REFERENCE NUMBER'),
        // Kusang may espasyo; hindi lalampas sa bilang ng GCash/Maya reference number.
        Builder(builder: (context) {
          final f = RefFormat.of(_method);
          final count = f.clean(_reference.text).length;
          final done = count == f.length;
          return TextField(
            key: ValueKey('ref-$_method'),
            controller: _reference,
            keyboardType: f.digitsOnly ? TextInputType.number : TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [f.formatter],
            style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'e.g. ${f.example}',
              prefixIcon: const Icon(Icons.tag),
              helperText: done
                  ? 'Looks complete.'
                  : '${f.length} ${f.digitsOnly ? 'digits' : 'letters/numbers'} · $count of ${f.length}',
              helperStyle: TextStyle(color: done ? AppColors.success : null),
              suffixIcon: done ? const Icon(Icons.check_circle, color: AppColors.success) : null,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.ink, width: 1.4),
              ),
            ),
            onChanged: (_) {
              setState(() {});
              _emit();
            },
          );
        }),
        const SizedBox(height: 14),

        // 4) Screenshot ng resibo
        _label('RECEIPT SCREENSHOT'),
        if (_image == null)
          Material(
            color: AppColors.subtle,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pickImage,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Column(
                  children: [
                    Icon(Icons.add_photo_alternate_outlined, size: 32, color: AppColors.ink),
                    SizedBox(height: 8),
                    Text('Tap to Upload Screenshot', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    SizedBox(height: 2),
                    Text(
                      'Make sure the amount and reference number are visible',
                      style: TextStyle(fontSize: 12, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_image!, width: 72, height: 96, fit: BoxFit.cover),
                ),
                const SizedBox(width: 14),
                // Nasa ilalim na ang "Change" para hindi maipit ang text sa maliit na screen.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.check_circle, size: 18, color: AppColors.success),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text('Screenshot Added',
                                overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'The resort will check this against your reference number.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted, height: 1.35),
                      ),
                      const SizedBox(height: 2),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _pickImage,
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text('Change screenshot'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Bottom sheet para magbayad ng natitirang balance (o mag-upload ulit
/// kapag na-reject ang naunang proof).
Future<bool> showPayBalanceSheet(
  BuildContext context, {
  required String bookingId,
  required double balance,
  required String kind,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.background,
    builder: (sheetContext) => _PayBalanceSheet(bookingId: bookingId, balance: balance, kind: kind),
  );
  return result ?? false;
}

class _PayBalanceSheet extends StatefulWidget {
  const _PayBalanceSheet({required this.bookingId, required this.balance, required this.kind});
  final String bookingId;
  final double balance;
  final String kind;

  @override
  State<_PayBalanceSheet> createState() => _PayBalanceSheetState();
}

class _PayBalanceSheetState extends State<_PayBalanceSheet> {
  PaymentProof? _proof;
  bool _submitting = false;

  Future<void> _submit() async {
    final proof = _proof;
    if (proof == null) return;
    if (!await hasInternet()) {
      if (mounted) showOfflineSnack(context);
      return;
    }
    if (!mounted) return;
    // Lalabas ang Terms and Conditions bago i-submit ang bayad.
    if (!await showTermsAgreement(context) || !mounted) return;
    setState(() => _submitting = true);
    try {
      await submitPaymentProof(
        bookingId: widget.bookingId,
        amount: widget.balance,
        kind: widget.kind,
        proof: proof,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'upload your payment proof'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDown = widget.kind == 'downpayment';
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: dark board na may halaga
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDown ? 'DOWNPAYMENT' : 'REMAINING BALANCE',
                          style: const TextStyle(
                            color: AppColors.inkText,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          peso(widget.balance),
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 28,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isDown ? 'Send Downpayment Proof' : 'Pay Remaining Balance',
                          style: const TextStyle(color: Color(0xFF99F6E4), fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.inkRaised,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.inkLine),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF5EEAD4), size: 26),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            PaymentProofForm(
              amount: widget.balance,
              onChanged: (p) => setState(() => _proof = p),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  disabledForegroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _proof == null || _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _submitting ? 'Sending…' : 'Submit Payment Proof',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            if (_proof == null)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.info_outline, size: 15, color: AppColors.muted),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Enter the reference number and upload a screenshot to continue.',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
