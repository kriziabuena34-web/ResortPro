import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../l10n/app_strings.dart';
import 'admin_data.dart';

enum ReportType { dailySales, monthlySales, bookings, collections }

/// Isang report na handang ipakita, i-export sa PDF/Excel, o i-print.
class ReportTable {
  ReportTable({
    required this.title,
    required this.subtitle,
    required this.headers,
    required this.rows,
    this.totals,
    this.numericColumns = const {},
  });

  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<Object>> rows;
  final List<Object>? totals;

  /// Mga column na numero (naka-right align at walang ₱ sa Excel).
  final Set<int> numericColumns;
}

/// Gumagawa ng mga report mula sa AdminData.
class ReportBuilder {
  ReportBuilder(this.data);
  final AdminData data;

  static const _resortName = "Aryana's Guests House";

  ReportTable build(ReportType type, DateTimeRange range) {
    switch (type) {
      case ReportType.dailySales:
        return _sales(range, monthly: false);
      case ReportType.monthlySales:
        return _sales(range, monthly: true);
      case ReportType.bookings:
        return _bookings(range);
      case ReportType.collections:
        return _collections(range);
    }
  }

  String _rangeText(DateTimeRange r) => '${formatDate(r.start)} – ${formatDate(r.end)}';

  bool _inRange(DateTime? d, DateTimeRange r) {
    if (d == null) return false;
    final day = DateUtils.dateOnly(d);
    return !day.isBefore(DateUtils.dateOnly(r.start)) && !day.isAfter(DateUtils.dateOnly(r.end));
  }

  Iterable<({Map<String, dynamic> payment, Map<String, dynamic> booking})> _verifiedPayments() sync* {
    for (final b in data.bookings) {
      for (final p in paymentsOf(b)) {
        if (isVerifiedPayment(p)) yield (payment: p, booking: b);
      }
    }
  }

  DateTime? _paymentDate(Map<String, dynamic> p, Map<String, dynamic> b) =>
      parseDate(p['created_at']) ?? bookingDateOf(b);

  // ---- Sales (daily o monthly) ----
  ReportTable _sales(DateTimeRange range, {required bool monthly}) {
    String keyOf(DateTime d) => monthly
        ? '${d.year}-${d.month.toString().padLeft(2, '0')}'
        : dateKey(d);
    String labelOf(String key) {
      final parts = key.split('-').map(int.parse).toList();
      return monthly
          ? '${monthNames[parts[1] - 1]} ${parts[0]}'
          : formatDate(DateTime(parts[0], parts[1], parts[2]));
    }

    final bookings = <String, int>{};
    final booked = <String, double>{};
    final cancelled = <String, int>{};
    final collected = <String, double>{};
    final guests = <String, int>{};

    for (final b in data.bookings) {
      final d = bookingDateOf(b);
      if (!_inRange(d, range)) continue;
      final k = keyOf(d!);
      if (isInactive(b)) {
        cancelled[k] = (cancelled[k] ?? 0) + 1;
      } else {
        bookings[k] = (bookings[k] ?? 0) + 1;
        booked[k] = (booked[k] ?? 0) + totalOf(b);
        guests[k] = (guests[k] ?? 0) + guestsOf(b);
      }
    }
    for (final e in _verifiedPayments()) {
      final d = _paymentDate(e.payment, e.booking);
      if (!_inRange(d, range)) continue;
      final k = keyOf(d!);
      collected[k] = (collected[k] ?? 0) + asDouble(e.payment['amount']);
    }

    final keys = {...bookings.keys, ...cancelled.keys, ...collected.keys}.toList()..sort();
    final rows = [
      for (final k in keys)
        <Object>[
          labelOf(k),
          bookings[k] ?? 0,
          guests[k] ?? 0,
          cancelled[k] ?? 0,
          booked[k] ?? 0.0,
          collected[k] ?? 0.0,
        ],
    ];
    double sum(Map<String, double> m) => m.values.fold(0.0, (s, v) => s + v);
    int count(Map<String, int> m) => m.values.fold(0, (s, v) => s + v);

    return ReportTable(
      title: monthly ? tr('rpMonthlySales') : tr('rpDailySales'),
      subtitle: '$_resortName · ${_rangeText(range)}',
      headers: [
        monthly ? tr('rpMonth') : tr('fieldDate'),
        tr('bookingsWord'),
        tr('fieldGuests'),
        tr('rpCancelledNoShow'),
        tr('seriesBooked'),
        tr('seriesCollected'),
      ],
      rows: rows,
      totals: [tr('rpTotal'), count(bookings), count(guests), count(cancelled), sum(booked), sum(collected)],
      numericColumns: {1, 2, 3, 4, 5},
    );
  }

  // ---- Listahan ng bookings ----
  ReportTable _bookings(DateTimeRange range) {
    final list = data.bookings.where((b) => _inRange(bookingDateOf(b), range)).toList()
      ..sort((a, b) => bookingDateOf(a)!.compareTo(bookingDateOf(b)!));

    double total = 0, paid = 0, balance = 0;
    final rows = <List<Object>>[];
    for (final b in list) {
      final inactive = isInactive(b);
      final t = totalOf(b), p = paidOf(b), r = inactive ? 0.0 : remainingOf(b);
      if (!inactive) {
        total += t;
        balance += r;
      }
      paid += p;
      rows.add([
        '#${'${b['id']}'.split('-').first.toUpperCase()}',
        formatDate(bookingDateOf(b)),
        packageNameOf(b),
        clientNameOf(b),
        sourceLabel(bookingSourceOf(b)),
        statusLabel(b['status'] as String?),
        guestsOf(b),
        t,
        p,
        r,
      ]);
    }

    return ReportTable(
      title: tr('rpBookingsList'),
      subtitle: '$_resortName · ${_rangeText(range)} · ${tr('rpByStayDate')}',
      headers: [
        tr('bookingRef'),
        tr('fieldDate'),
        tr('navPackages'),
        tr('fieldClient'),
        tr('filterSource'),
        tr('rpStatus'),
        tr('fieldGuests'),
        tr('fieldTotal'),
        tr('fieldPaid'),
        tr('fieldBalance'),
      ],
      rows: rows,
      totals: [tr('rpTotal'), '', '', '', '', '', list.fold<int>(0, (s, b) => s + guestsOf(b)), total, paid, balance],
      numericColumns: {6, 7, 8, 9},
    );
  }

  // ---- Collections ayon sa payment method ----
  ReportTable _collections(DateTimeRange range) {
    final entries = _verifiedPayments()
        .where((e) => _inRange(_paymentDate(e.payment, e.booking), range))
        .toList()
      ..sort((a, b) => _paymentDate(a.payment, a.booking)!.compareTo(_paymentDate(b.payment, b.booking)!));

    final rows = <List<Object>>[];
    final byMethod = <String, double>{};
    double total = 0;
    for (final e in entries) {
      final amount = asDouble(e.payment['amount']);
      final method = '${e.payment['method'] ?? 'other'}';
      byMethod[method] = (byMethod[method] ?? 0) + amount;
      total += amount;
      rows.add([
        formatDate(_paymentDate(e.payment, e.booking)),
        '#${'${e.booking['id']}'.split('-').first.toUpperCase()}',
        clientNameOf(e.booking),
        kindLabel(e.payment['kind'] as String?),
        methodLabel(method),
        '${e.payment['reference_no'] ?? ''}',
        amount,
      ]);
    }

    final summary = byMethod.entries.map((e) => '${methodLabel(e.key)}: ${peso(e.value)}').join('   ');

    return ReportTable(
      title: tr('rpCollections'),
      subtitle: '$_resortName · ${_rangeText(range)}${summary.isEmpty ? '' : '\n$summary'}',
      headers: [
        tr('fieldDate'),
        tr('bookingRef'),
        tr('fieldClient'),
        tr('rpType'),
        tr('paymentMethod'),
        tr('payReference'),
        tr('rpAmount'),
      ],
      rows: rows,
      totals: [tr('rpTotal'), '', '', '', '', '', total],
      numericColumns: {6},
    );
  }

  // -------------------------------------------------------------------------
  // Export
  // -------------------------------------------------------------------------

  static String cellText(Object v, {bool pdf = false}) {
    if (v is double) {
      // Walang ₱ sa PDF dahil hindi ito suportado ng default na font.
      final s = peso(v);
      return pdf ? 'PHP ${s.replaceFirst('₱', '')}' : s;
    }
    return '$v';
  }

  static String fileName(ReportTable t, String ext) {
    final safe = t.title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return '${safe}_${dateKey(DateTime.now())}.$ext';
  }

  static Future<Uint8List> pdfBytes(ReportTable t) async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: t.headers.length > 7 ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          pw.Text(t.title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text(t.subtitle.replaceAll('₱', 'PHP '), style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            'Generated ${formatDateTime(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: t.headers,
            data: [
              for (final r in t.rows) [for (final c in r) cellText(c, pdf: true)],
              if (t.totals != null) [for (final c in t.totals!) cellText(c, pdf: true)],
            ],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF0E7C86)),
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {for (final i in t.numericColumns) i: pw.Alignment.centerRight},
            oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F6F6)),
          ),
          if (t.rows.isEmpty)
            pw.Padding(padding: const pw.EdgeInsets.only(top: 12), child: pw.Text('No data for this period.')),
        ],
      ),
    );
    return doc.save();
  }

  static Uint8List excelBytes(ReportTable t) {
    final excel = xl.Excel.createExcel();
    excel.rename('Sheet1', 'Report');
    final sheet = excel['Report'];

    xl.CellValue toCell(Object v) {
      if (v is int) return xl.IntCellValue(v);
      if (v is double) return xl.DoubleCellValue(v);
      return xl.TextCellValue('$v');
    }

    sheet.appendRow([xl.TextCellValue(t.title)]);
    for (final line in t.subtitle.split('\n')) {
      sheet.appendRow([xl.TextCellValue(line)]);
    }
    sheet.appendRow([]);
    sheet.appendRow([for (final h in t.headers) xl.TextCellValue(h)]);
    for (final r in t.rows) {
      sheet.appendRow([for (final c in r) toCell(c)]);
    }
    if (t.totals != null) sheet.appendRow([for (final c in t.totals!) toCell(c)]);

    for (var i = 0; i < t.headers.length; i++) {
      sheet.setColumnWidth(i, i == 0 ? 18 : 16);
    }
    return Uint8List.fromList(excel.encode() ?? const <int>[]);
  }

  static Future<void> downloadPdf(ReportTable t) async {
    final bytes = await pdfBytes(t);
    await FileSaver.instance.saveFile(
      name: fileName(t, 'pdf').replaceAll('.pdf', ''),
      bytes: bytes,
      fileExtension: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  static Future<void> downloadExcel(ReportTable t) async {
    await FileSaver.instance.saveFile(
      name: fileName(t, 'xlsx').replaceAll('.xlsx', ''),
      bytes: excelBytes(t),
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  static Future<void> printReport(ReportTable t) async {
    await Printing.layoutPdf(name: t.title, onLayout: (_) => pdfBytes(t));
  }
}
