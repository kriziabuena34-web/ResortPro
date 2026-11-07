import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_strings.dart';
import '../theme/app_theme.dart';
import 'admin_data.dart';

/// Laman ng resibo ng bayad na tinanggap sa resort.
class PaymentReceipt {
  const PaymentReceipt({
    required this.paymentId,
    required this.date,
    required this.guest,
    required this.packageName,
    required this.bookingDate,
    required this.source,
    required this.amount,
    required this.method,
    required this.totalAmount,
    required this.paidSoFar,
    required this.staff,
    this.reference = '',
    this.cashReceived,
    this.claimCode,
    this.checkinCode,
  });

  final Object paymentId;
  final DateTime date;
  final String guest;
  final String packageName;
  final DateTime? bookingDate;
  final String source;
  final double amount;
  final String method;
  final String reference;
  final double? cashReceived;
  final double totalAmount;
  final double paidSoFar; // kasama na ang bayad na ito
  final String staff;

  /// Code para ma-link ng guest ang booking sa account niya sa app (kapag walang account).
  final String? claimCode;

  /// QR para sa check-in / check-out sa resort.
  final String? checkinCode;

  /// Hal. 7K3QM-4XPA2
  String? get checkinCodeLabel {
    final c = checkinCode?.trim() ?? '';
    if (c.isEmpty) return null;
    return c.length == 10 ? '${c.substring(0, 5)}-${c.substring(5)}' : c;
  }

  /// Hal. K7QM-4XPA
  String? get claimCodeLabel {
    final c = claimCode?.trim() ?? '';
    if (c.isEmpty) return null;
    return c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
  }

  double get balance => (totalAmount - paidSoFar).clamp(0, double.infinity).toDouble();
  double? get change => method == 'cash' && cashReceived != null ? cashReceived! - amount : null;

  /// Hal. AGH-20261105-00042
  String get number {
    final d = date;
    final ymd = '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
    final id = '$paymentId'.padLeft(5, '0');
    return 'AGH-$ymd-${id.length > 8 ? id.substring(id.length - 8) : id}';
  }

  String get _dateTime {
    final d = date;
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${formatDate(d)}, $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// Mga linya ng resibo: (label, value, naka-bold?)
  List<(String, String, bool)> get lines => [
        (tr('rcGuest'), guest.toUpperCase(), false),
        (tr('rcPackage'), packageName, false),
        if (bookingDate != null) (tr('rcBookingDate'), formatDate(bookingDate), false),
        (tr('rcSource'), sourceLabel(source), false),
        (tr('rcTotal'), peso(totalAmount), false),
        (tr('rcAmountPaid'), peso(amount), true),
        (tr('rcMethod'), methodLabel(method), false),
        if (reference.isNotEmpty) (tr('rcReference'), reference, false),
        if (cashReceived != null) (tr('peCashReceived'), peso(cashReceived!), false),
        if (change != null) (tr('rcChange'), peso(change! < 0 ? 0 : change!), false),
        (tr('rcBalance'), balance <= 0.01 ? tr('rcFullyPaid') : peso(balance), true),
        (tr('rcReceivedBy'), staff, false),
      ];

  Future<Uint8List> pdfBytes() async {
    final doc = pw.Document();
    String p(String s) => s.replaceAll('₱', 'PHP '); // walang ₱ sa default na PDF font
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(14),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text("ARYANA'S GUESTS HOUSE",
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.Text('Brgy. Maulawin, Tramo St., Pagsanjan, Laguna',
                textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
            pw.Text('0962 882 8792 · aryanasguesthouse06@gmail.com',
                textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7.5)),
            pw.SizedBox(height: 8),
            pw.Text(p(tr('rcTitle')).toUpperCase(),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text('${tr('rcNo')} $number', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
            pw.Text(_dateTime, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
            pw.Divider(thickness: 0.6),
            for (final l in lines)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 1.6),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(flex: 4, child: pw.Text(p(l.$1), style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Expanded(
                      flex: 6,
                      child: pw.Text(
                        p(l.$2),
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(fontSize: l.$3 ? 10 : 8.5, fontWeight: l.$3 ? pw.FontWeight.bold : null),
                      ),
                    ),
                  ],
                ),
              ),
            pw.Divider(thickness: 0.6),
            if (checkinCodeLabel != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(p(tr('rcCheckinTitle')),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: checkinCode!,
                  width: 80,
                  height: 80,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(checkinCodeLabel!,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
              pw.Text(p(tr('rcCheckinHint')), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
              pw.Divider(thickness: 0.6),
            ],
            if (claimCodeLabel != null) ...[
              pw.SizedBox(height: 4),
              pw.Text(p(tr('rcClaimTitle')),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              pw.Text(claimCodeLabel!,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
              pw.Text(p(tr('rcClaimHint')), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
              pw.Divider(thickness: 0.6),
            ],
            pw.SizedBox(height: 4),
            pw.Text(p(tr('rcThanks')), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8.5)),
            pw.SizedBox(height: 2),
            pw.Text(p(tr('rcNote')), textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  Future<void> printReceipt() => Printing.layoutPdf(name: 'Receipt $number', onLayout: (_) => pdfBytes());

  Future<void> download() async {
    await FileSaver.instance.saveFile(
      name: 'Receipt_$number',
      bytes: await pdfBytes(),
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }
}

/// Ipakita ang resibo pagkatapos ma-save ang bayad (may Print at Download PDF).
Future<void> showPaymentReceipt(BuildContext context, PaymentReceipt r) {
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.receipt_long, color: AppColors.primary, size: 36),
      title: Text(tr('rcSavedTitle')),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "ARYANA'S GUESTS HOUSE",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
                ),
                const SizedBox(height: 2),
                Text(
                  '${tr('rcTitle')} · ${r.number}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: AppColors.muted),
                ),
                Text(r._dateTime, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                const Divider(height: 22),
                for (final l in r.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Text(l.$1, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        ),
                        Expanded(
                          flex: 6,
                          child: Text(
                            l.$2,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: l.$3 ? FontWeight.w800 : FontWeight.w600,
                              fontSize: l.$3 ? 15 : 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (r.checkinCodeLabel != null) ...[
                  const Divider(height: 22),
                  Row(
                    children: [
                      const Icon(Icons.qr_code_2, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('rcCheckinTitle'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                      SelectableText(r.checkinCodeLabel!,
                          style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                    ],
                  ),
                ],
                if (r.claimCodeLabel != null) ...[
                  const Divider(height: 22),
                  Text(
                    tr('rcClaimTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SelectableText(
                      r.claimCodeLabel!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr('rcClaimHint'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
        OutlinedButton.icon(
          onPressed: () => r.download(),
          icon: const Icon(Icons.download_outlined),
          label: Text(tr('rcDownload')),
        ),
        FilledButton.icon(
          onPressed: () => r.printReceipt(),
          icon: const Icon(Icons.print_outlined),
          label: Text(tr('rcPrint')),
        ),
      ],
    ),
  );
}

/// Para sa walk-in na walang bayad pa: ipakita ang code para ma-link ng guest sa app.
Future<void> showClaimCodeDialog(BuildContext context, String code) {
  final label = code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;
  return showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.confirmation_number_outlined, color: AppColors.primary, size: 36),
      title: Text(tr('rcClaimTitle')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SelectableText(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 3, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(tr('rcClaimHint'), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ],
      ),
      actions: [
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('rcClose'))),
      ],
    ),
  );
}
