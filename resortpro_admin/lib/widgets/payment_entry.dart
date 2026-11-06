import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_strings.dart';
import '../services/admin_data.dart';
import '../services/reference_format.dart';
import '../theme/app_theme.dart';

/// Detalye ng bayad na tinanggap ng staff (walk-in o Record payment).
class PaymentDetails {
  const PaymentDetails({required this.method, this.reference = '', this.cashReceived});

  /// cash, gcash, o maya
  final String method;

  /// Reference number (para sa GCash at Maya)
  final String reference;

  /// Perang inabot ng guest (para sa cash, para makuha ang sukli)
  final double? cashReceived;

  bool get isCash => method == 'cash';

  double changeFor(double amount) => isCash && cashReceived != null ? cashReceived! - amount : 0;

  /// Translation key ng error, o null kung ayos.
  String? validate(double amount) {
    if (amount <= 0) return null; // walang bayad ngayon: walang kailangang detalye
    if (isCash) {
      if (cashReceived != null && cashReceived! + 0.01 < amount) return 'peCashShort';
      return null;
    }
    if (!RefFormat.of(method).isComplete(reference)) return method == 'maya' ? 'peRefMaya' : 'peRefGcash';
    return null;
  }
}

/// Saan magpapadala ang guest kapag GCash/Maya (e-payment sa resort mismo).
const resortPayName = "Aryana's Guests House";
const resortPayNumber = '0962 882 8792';

/// Paraan ng bayad (Cash / GCash / Maya) + sukli o reference number.
class PaymentEntry extends StatefulWidget {
  const PaymentEntry({super.key, required this.amount, required this.onChanged, this.initialMethod = 'cash'});

  /// Halagang binabayaran ngayon (para makuha ang sukli).
  final double amount;
  final ValueChanged<PaymentDetails> onChanged;
  final String initialMethod;

  @override
  State<PaymentEntry> createState() => _PaymentEntryState();
}

class _PaymentEntryState extends State<PaymentEntry> {
  late String _method = widget.initialMethod;
  final _reference = TextEditingController();
  final _cash = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _reference.dispose();
    _cash.dispose();
    super.dispose();
  }

  PaymentDetails get _details => PaymentDetails(
        method: _method,
        reference: _reference.text.trim(),
        cashReceived: double.tryParse(_cash.text.replaceAll(',', '')),
      );

  void _emit() {
    if (mounted) widget.onChanged(_details);
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;
    final change = details.changeFor(widget.amount);
    final short = details.isCash && details.cashReceived != null && change < -0.01;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          segments: [
            for (final m in const ['cash', 'gcash', 'maya'])
              ButtonSegment(
                value: m,
                icon: Icon(m == 'cash' ? Icons.payments_outlined : Icons.phone_android, size: 18),
                label: Text(methodLabel(m)),
              ),
          ],
          selected: {_method},
          onSelectionChanged: (s) {
            setState(() {
              _method = s.first;
              if (_method != 'cash') _reference.text = RefFormat.of(_method).format(_reference.text);
            });
            _emit();
          },
        ),
        const SizedBox(height: 12),
        if (details.isCash) ...[
          TextField(
            controller: _cash,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: '${tr('peCashReceived')} (${tr('optional')})',
              prefixText: '₱ ',
              helperText: tr('peCashHelp'),
            ),
            onChanged: (_) {
              setState(() {});
              _emit();
            },
          ),
          if (details.cashReceived != null && widget.amount > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: (short ? AppColors.danger : AppColors.success).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (short ? AppColors.danger : AppColors.success).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(short ? Icons.error_outline : Icons.change_circle_outlined,
                      color: short ? AppColors.danger : AppColors.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      short
                          ? tr('peCashShort')
                          : tr('peChange', {'amount': peso(change)}),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: short ? AppColors.danger : AppColors.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ] else ...[
          // E-payment: saan magpapadala ang guest, bago ilagay ang reference number.
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withValues(alpha: 0.25)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.qr_code_2, color: AppColors.info),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('peSendTo', {'method': methodLabel(_method)}),
                        style: const TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                      const SelectableText(
                        '$resortPayNumber · $resortPayName',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      if (widget.amount > 0)
                        Text(
                          tr('peSendAmount', {'amount': peso(widget.amount)}),
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      const SizedBox(height: 2),
                      Text(tr('peSendHelp'), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Kusang may espasyo; hindi lalampas sa bilang ng reference number.
          TextField(
            key: ValueKey('ref-$_method'),
            controller: _reference,
            keyboardType: RefFormat.of(_method).digitsOnly ? TextInputType.number : TextInputType.visiblePassword,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [RefFormat.of(_method).formatter],
            style: const TextStyle(letterSpacing: 1.2, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              labelText: tr('peReference', {'method': methodLabel(_method)}),
              hintText: 'e.g. ${RefFormat.of(_method).example}',
              helperText: tr('peRefCount', {
                'n': RefFormat.of(_method).clean(_reference.text).length,
                'max': RefFormat.of(_method).length,
              }),
              suffixIcon: RefFormat.of(_method).isComplete(_reference.text)
                  ? const Icon(Icons.check_circle, color: AppColors.success)
                  : null,
            ),
            onChanged: (_) {
              setState(() {});
              _emit();
            },
          ),
        ],
      ],
    );
  }
}
