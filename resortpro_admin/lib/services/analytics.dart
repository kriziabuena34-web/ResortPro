import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'admin_data.dart';

/// Mga kuwenta para sa Analytics module.
///
/// Mga depinisyon (para sa documentation / defense):
///  • Occupancy rate  = booked package-days ÷ available package-days
///      - booked package-day: may aktibong booking (hindi cancelled/no-show)
///        ang isang package sa isang araw
///      - available package-days: (bilang ng package × araw sa buwan)
///        bawas ang mga blocked na araw
///  • Cancellation rate = cancelled ÷ lahat ng bookings sa buwan
///  • No-show rate      = no-show ÷ lahat ng bookings sa buwan
///  • Repeat client     = client na may 2 o higit pang aktibong booking
///  • Lead time         = araw mula pag-book (created_at) hanggang stay date
///  • Forecast:
///      - 3-month moving average: F(t+1) = (Y(t) + Y(t−1) + Y(t−2)) ÷ 3
///      - Simple linear regression: Y = a + bX, kung saan X = month index,
///        b = Σ(x−x̄)(y−ȳ) ÷ Σ(x−x̄)², a = ȳ − b·x̄, at R² ang sukat ng fit
class MonthStat {
  MonthStat(this.month);
  final DateTime month; // unang araw ng buwan

  int bookings = 0; // lahat, kasama ang cancelled/no-show
  int active = 0;
  int cancelled = 0;
  int noShow = 0;
  double revenue = 0; // booked value ng aktibong bookings
  double collected = 0; // verified payments na natanggap sa buwan
  int bookedPackageDays = 0;
  int availablePackageDays = 0;

  double get occupancy => availablePackageDays == 0 ? 0 : bookedPackageDays / availablePackageDays;
  double get cancellationRate => bookings == 0 ? 0 : cancelled / bookings;
  double get noShowRate => bookings == 0 ? 0 : noShow / bookings;
}

class RegressionResult {
  RegressionResult(this.intercept, this.slope, this.r2);
  final double intercept;
  final double slope;
  final double r2;

  double predict(double x) => intercept + slope * x;
}

class Analytics {
  Analytics(this.data, {this.months = 12});

  final AdminData data;
  final int months;

  late final DateTime _thisMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// Huling [months] na buwan, kasama ang kasalukuyang buwan.
  late final List<MonthStat> monthly = _buildMonthly();

  List<MonthStat> _buildMonthly() {
    final list = [
      for (var i = months - 1; i >= 0; i--) MonthStat(DateTime(_thisMonth.year, _thisMonth.month - i)),
    ];
    MonthStat? statFor(DateTime d) {
      for (final m in list) {
        if (m.month.year == d.year && m.month.month == d.month) return m;
      }
      return null;
    }

    final pkgCount = data.packages.length;
    for (final m in list) {
      final days = DateUtils.getDaysInMonth(m.month.year, m.month.month);
      var blockedPackageDays = 0;
      for (var day = 1; day <= days; day++) {
        final date = DateTime(m.month.year, m.month.month, day);
        final blocks = data.blocksOn(date);
        if (blocks.any((b) => b['package_id'] == null)) {
          blockedPackageDays += pkgCount;
        } else {
          blockedPackageDays += blocks.map((b) => '${b['package_id']}').toSet().length;
        }
      }
      m.availablePackageDays = math.max(0, pkgCount * days - blockedPackageDays);
    }

    final occupied = <String>{};
    for (final b in data.bookings) {
      final d = bookingDateOf(b);
      if (d == null) continue;
      final m = statFor(d);
      if (m == null) continue;
      m.bookings++;
      final status = b['status'];
      if (status == 'cancelled') {
        m.cancelled++;
      } else if (status == 'no_show') {
        m.noShow++;
      } else {
        m.active++;
        m.revenue += totalOf(b);
        final key = '${b['package_id']}|${dateKey(d)}';
        if (occupied.add(key)) m.bookedPackageDays++;
      }
    }

    for (final b in data.bookings) {
      for (final p in paymentsOf(b)) {
        if (!isVerifiedPayment(p)) continue;
        final d = parseDate(p['created_at']) ?? bookingDateOf(b);
        if (d == null) continue;
        statFor(d)?.collected += asDouble(p['amount']);
      }
    }
    return list;
  }

  // ---- Buod ng huling 12 buwan ----
  int get totalBookings => monthly.fold(0, (s, m) => s + m.bookings);
  int get totalActive => monthly.fold(0, (s, m) => s + m.active);
  double get totalRevenue => monthly.fold(0.0, (s, m) => s + m.revenue);

  double get occupancyRate {
    final booked = monthly.fold(0, (s, m) => s + m.bookedPackageDays);
    final available = monthly.fold(0, (s, m) => s + m.availablePackageDays);
    return available == 0 ? 0 : booked / available;
  }

  double get cancellationRate {
    final c = monthly.fold(0, (s, m) => s + m.cancelled);
    return totalBookings == 0 ? 0 : c / totalBookings;
  }

  double get noShowRate {
    final n = monthly.fold(0, (s, m) => s + m.noShow);
    return totalBookings == 0 ? 0 : n / totalBookings;
  }

  double get averageBookingValue => totalActive == 0 ? 0 : totalRevenue / totalActive;

  /// Average na araw mula pag-book hanggang stay.
  double get averageLeadTimeDays {
    final leads = <int>[];
    for (final b in data.activeBookings) {
      final created = parseDate(b['created_at']);
      final stay = bookingDateOf(b);
      if (created == null || stay == null) continue;
      final days = stay.difference(DateUtils.dateOnly(created)).inDays;
      if (days >= 0) leads.add(days);
    }
    return leads.isEmpty ? 0 : leads.reduce((a, b) => a + b) / leads.length;
  }

  /// Bilang ng aktibong booking bawat araw ng linggo (index 0 = Lunes).
  List<int> get bookingsByWeekday {
    final counts = List<int>.filled(7, 0);
    for (final b in data.activeBookings) {
      final d = bookingDateOf(b);
      if (d != null) counts[d.weekday - 1]++;
    }
    return counts;
  }

  /// (bagong clients, repeat clients) ayon sa bilang ng aktibong booking.
  ({int newClients, int repeatClients}) get clientLoyalty {
    final counts = <String, int>{};
    for (final b in data.activeBookings) {
      final id = b['client_id'] != null
          ? '${b['client_id']}'
          : 'guest:${'${b['guest_name'] ?? ''}'.trim().toLowerCase()}|${b['guest_phone'] ?? ''}';
      if (id == 'guest:|') continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final repeat = counts.values.where((c) => c >= 2).length;
    return (newClients: counts.length - repeat, repeatClients: repeat);
  }

  /// Bilang ng aktibong booking ayon sa source (online, walk_in, phone).
  Map<String, int> get bookingsBySource {
    final m = <String, int>{};
    for (final b in data.activeBookings) {
      final s = bookingSourceOf(b);
      m[s] = (m[s] ?? 0) + 1;
    }
    return m;
  }

  // ---- Forecast ----

  static List<double> movingAverageForecast(List<double> values, int horizon, {int window = 3}) {
    final series = [...values];
    final out = <double>[];
    for (var i = 0; i < horizon; i++) {
      final w = math.min(window, series.length);
      if (w == 0) {
        out.add(0);
        series.add(0);
        continue;
      }
      final avg = series.sublist(series.length - w).reduce((a, b) => a + b) / w;
      out.add(avg);
      series.add(avg);
    }
    return out;
  }

  static RegressionResult linearRegression(List<double> y) {
    final n = y.length;
    if (n < 2) return RegressionResult(n == 1 ? y.first : 0, 0, 0);
    final xs = [for (var i = 0; i < n; i++) i.toDouble()];
    final xMean = xs.reduce((a, b) => a + b) / n;
    final yMean = y.reduce((a, b) => a + b) / n;
    var sxy = 0.0, sxx = 0.0, sst = 0.0;
    for (var i = 0; i < n; i++) {
      sxy += (xs[i] - xMean) * (y[i] - yMean);
      sxx += (xs[i] - xMean) * (xs[i] - xMean);
      sst += (y[i] - yMean) * (y[i] - yMean);
    }
    final slope = sxx == 0 ? 0.0 : sxy / sxx;
    final intercept = yMean - slope * xMean;
    var sse = 0.0;
    for (var i = 0; i < n; i++) {
      final e = y[i] - (intercept + slope * xs[i]);
      sse += e * e;
    }
    final r2 = sst == 0 ? 0.0 : 1 - sse / sst;
    return RegressionResult(intercept, slope, r2);
  }

  /// Mga buwan sa hinaharap para sa forecast.
  List<DateTime> futureMonths(int horizon) => [
        for (var i = 1; i <= horizon; i++) DateTime(_thisMonth.year, _thisMonth.month + i),
      ];

  /// Mga aktibong booking sa mga susunod na buwan na naka-book na (para ikumpara sa forecast).
  List<double> alreadyBooked(int horizon, {required bool revenue}) {
    final months = futureMonths(horizon);
    return [
      for (final m in months)
        data.activeBookings
            .where((b) {
              final d = bookingDateOf(b);
              return d != null && d.year == m.year && d.month == m.month;
            })
            .fold<double>(0, (s, b) => s + (revenue ? totalOf(b) : 1)),
    ];
  }
}
