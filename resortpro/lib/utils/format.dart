import 'package:flutter/material.dart';

/// Mga helper para sa pag-format ng pera, petsa, at booking status.

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String peso(num amount) {
  return '₱${amount.toDouble().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      )}';
}

double asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

DateTime? parseDate(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v')?.toLocal();
}

String formatDate(DateTime? d) {
  if (d == null) return '—';
  return '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

String formatDateTime(DateTime? d) {
  if (d == null) return '—';
  var hour = d.hour % 12;
  if (hour == 0) hour = 12;
  final minute = d.minute.toString().padLeft(2, '0');
  return '${formatDate(d)}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String timeAgo(dynamic createdAt) {
  final d = parseDate(createdAt);
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays < 7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
  return formatDate(d);
}

// ---------------------------------------------------------------------------
// Booking status
// ---------------------------------------------------------------------------

String statusLabel(String? status) {
  switch (status) {
    case 'reserved':
      return 'Waiting for confirmation';
    case 'confirmed':
      return 'Confirmed';
    case 'fully_paid':
      return 'Fully paid';
    case 'checked_in':
      return 'Checked in';
    case 'completed':
      return 'Completed';
    case 'no_show':
      return 'No-show';
    case 'cancelled':
      return 'Cancelled';
    default:
      return (status ?? 'Unknown').replaceAll('_', ' ');
  }
}

Color statusColor(String? status) {
  switch (status) {
    case 'reserved':
      return const Color(0xFFE08A00);
    case 'confirmed':
      return const Color(0xFF2F6FED);
    case 'fully_paid':
      return const Color(0xFF238B45);
    case 'checked_in':
      return const Color(0xFF0E9AA7);
    case 'completed':
      return const Color(0xFF6B5BD2);
    case 'no_show':
      return const Color(0xFF8D6E63);
    case 'cancelled':
      return const Color(0xFFD64545);
    default:
      return const Color(0xFF7A7F87);
  }
}

bool isInactiveStatus(String? status) => status == 'cancelled' || status == 'no_show';

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});
  final String? status;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Search box na ginagamit sa mga listahan ng user app.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

/// Pahalang na hanay ng filter chips.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({super.key, required this.children, this.padding = 16});
  final List<Widget> children;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => Center(child: children[i]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payment status (proof of payment)
// ---------------------------------------------------------------------------

/// Verified na bayad lang ang binibilang sa "paid".
bool isVerifiedPayment(Map p) => p['status'] == null || p['status'] == 'verified';

double verifiedPaid(List? payments) => (payments ?? const [])
    .whereType<Map>()
    .where(isVerifiedPayment)
    .fold<double>(0, (s, p) => s + asDouble(p['amount']));

double pendingPaid(List? payments) => (payments ?? const [])
    .whereType<Map>()
    .where((p) => p['status'] == 'pending')
    .fold<double>(0, (s, p) => s + asDouble(p['amount']));

String paymentStatusLabel(String? status) {
  switch (status) {
    case 'pending':
      return 'Waiting for verification';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Verified';
  }
}

Color paymentStatusColor(String? status) {
  switch (status) {
    case 'pending':
      return const Color(0xFFE08A00);
    case 'rejected':
      return const Color(0xFFD64545);
    default:
      return const Color(0xFF238B45);
  }
}
