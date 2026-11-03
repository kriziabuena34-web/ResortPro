import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../utils/format.dart';

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
      ref.length >= 6 && _image != null
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final number = _method == 'gcash' ? gcashNumber : mayaNumber;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'gcash', label: Text('GCash'), icon: Icon(Icons.phone_android)),
            ButtonSegment(value: 'maya', label: Text('Maya'), icon: Icon(Icons.account_balance_wallet)),
          ],
          selected: {_method},
          onSelectionChanged: (s) {
            setState(() => _method = s.first);
            _emit();
          },
        ),
        const SizedBox(height: 12),

        // Instructions
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Send ${peso(widget.amount)} to:',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_method == 'gcash' ? 'GCash' : 'Maya'}: $number\n$paymentAccountName',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copy number',
                    icon: const Icon(Icons.copy),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: number));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Number copied.')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'After paying, enter the reference number and upload a screenshot of the receipt. '
                'The resort will verify your payment before confirming your booking.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        TextField(
          controller: _reference,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Reference number',
            hintText: 'e.g. 1012 345 678901',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _emit(),
        ),
        const SizedBox(height: 12),

        if (_image == null)
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload receipt screenshot'),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(_image!, height: 200, fit: BoxFit.contain),
              ),
              TextButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Change screenshot'),
              ),
            ],
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.kind == 'downpayment' ? 'Send downpayment proof' : 'Pay remaining balance',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text('Amount: ${peso(widget.balance)}'),
            const SizedBox(height: 16),
            PaymentProofForm(
              amount: widget.balance,
              onChanged: (p) => setState(() => _proof = p),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _proof == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('SUBMIT PAYMENT PROOF'),
              ),
            ),
            if (_proof == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Enter the reference number (at least 6 digits) and upload a screenshot.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
