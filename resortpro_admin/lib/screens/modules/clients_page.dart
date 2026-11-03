import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Listahan ng lahat ng client: search, filter by verification status,
/// sort, at history ng bookings ng bawat isa.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, required this.data});

  final AdminData data;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

enum _ClientSort { name, mostBookings, topSpender, recent }

class _ClientStats {
  _ClientStats(this.client, this.bookings);

  final Map<String, dynamic> client;
  final List<Map<String, dynamic>> bookings;

  late final int bookingCount = bookings.where((b) => !isInactive(b)).length;
  late final double totalPaid = bookings.fold<double>(0, (s, b) => s + paidOf(b));
  late final double balance =
      bookings.where((b) => !isInactive(b)).fold<double>(0, (s, b) => s + remainingOf(b));
  late final DateTime? lastBooking = bookings
      .map(bookingDateOf)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (m, d) => m == null || d.isAfter(m) ? d : m);

  String get name {
    final display = client['google_display_name'];
    if (display != null && '$display'.trim().isNotEmpty) return '$display';
    final full = '${client['first_name'] ?? ''} ${client['last_name'] ?? ''}'.trim();
    return full.isEmpty ? tr('noName') : full;
  }

  String get status => '${client['verification_status'] ?? 'unverified'}';
}

class _ClientsPageState extends State<ClientsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
  bool _withBalance = false;
  _ClientSort _sort = _ClientSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final c in widget.data.clients)
        _ClientStats(c, widget.data.bookingsOfClient('${c['id']}')),
    ];

    final q = _query.trim().toLowerCase();
    final list = all.where((c) {
      if (_status != 'all' && c.status != _status) return false;
      if (_withBalance && c.balance <= 0) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          '${c.client['phone'] ?? ''}'.contains(q) ||
          '${c.client['first_name'] ?? ''} ${c.client['last_name'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _ClientSort.name:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case _ClientSort.mostBookings:
        list.sort((a, b) => b.bookingCount.compareTo(a.bookingCount));
      case _ClientSort.topSpender:
        list.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
      case _ClientSort.recent:
        list.sort((a, b) {
          final da = a.lastBooking, db = b.lastBooking;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da);
        });
    }

    int countOf(String s) => s == 'all' ? all.length : all.where((c) => c.status == s).length;
    const statuses = ['verified', 'pending', 'rejected', 'unverified'];

    return Column(
      children: [
        FloatingToolbar(
          children: [
            SearchBox(
              controller: _searchController,
              hint: tr('searchClientsHint'),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
        ChipRow(
          children: [
            ChoiceChip(
              label: Text('${tr('filterAll')} (${countOf('all')})'),
              selected: _status == 'all',
              onSelected: (_) => setState(() => _status = 'all'),
            ),
            for (final s in statuses)
              if (countOf(s) > 0)
                ChoiceChip(
                  label: Text('${verificationLabel(s)} (${countOf(s)})'),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
            FilterChip(
              label: Text(tr('filterWithBalance')),
              selected: _withBalance,
              onSelected: (v) => setState(() => _withBalance = v),
            ),
            SortMenu<_ClientSort>(
              value: _sort,
              options: {
                _ClientSort.name: tr('sortName'),
                _ClientSort.mostBookings: tr('sortMostBookings'),
                _ClientSort.topSpender: tr('sortTopSpender'),
                _ClientSort.recent: tr('sortRecentBooking'),
              },
              onChanged: (v) => setState(() => _sort = v),
            ),
          ],
        ),
          ],
        ),
        ResultCount(
          shown: list.length,
          total: all.length,
          onClear: () {
            _searchController.clear();
            setState(() {
              _query = '';
              _status = 'all';
              _withBalance = false;
            });
          },
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(icon: Icons.people_outline, message: tr('noClientsMatch'))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1200
                        ? 3
                        : constraints.maxWidth >= 760
                            ? 2
                            : 1;
                    return SingleChildScrollView(
                      padding: pageInsets(context).copyWith(top: 8),
                      child: CardGrid(
                        columns: columns,
                        children: [
                          for (final c in list) _clientCard(c),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _clientCard(_ClientStats c) {
    final theme = Theme.of(context);
    final color = verificationColor(c.status);
    return AppCard(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showClient(c),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      c.name.isEmpty ? '?' : c.name[0].toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${c.client['phone'] ?? tr('notSet')}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      verificationLabel(c.status),
                      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  _mini(theme, '${c.bookingCount}', tr('bookingsWord')),
                  _mini(theme, pesoCompact(c.totalPaid), tr('fieldPaid')),
                  _mini(
                    theme,
                    c.balance > 0 ? pesoCompact(c.balance) : '—',
                    tr('fieldBalance'),
                    color: c.balance > 0 ? AppColors.warning : null,
                  ),
                ],
              ),
              if (c.lastBooking != null) ...[
                const SizedBox(height: 8),
                Text(
                  tr('lastBooking', {'date': formatDate(c.lastBooking)}),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(ThemeData theme, String value, String label, {Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
          ),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  void _showClient(_ClientStats c) {
    final bookings = [...c.bookings]
      ..sort((a, b) {
        final da = bookingDateOf(a), db = bookingDateOf(b);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(c.name),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InfoRow(tr('statVerified'), verificationLabel(c.status)),
                InfoRow(tr('fieldPhone'), '${c.client['phone'] ?? tr('notSet')}'),
                InfoRow(tr('birthDate'), formatDate(parseDate(c.client['birth_date']))),
                InfoRow(tr('idType'), '${c.client['government_id_type'] ?? tr('notSet')}'),
                InfoRow(tr('fieldPaid'), peso(c.totalPaid)),
                InfoRow(tr('fieldBalance'), peso(c.balance)),
                const Divider(height: 24),
                Text(
                  tr('bookingHistory'),
                  style: Theme.of(dialogContext).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                if (bookings.isEmpty) Text(tr('noBookingsYet')),
                for (final b in bookings)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(packageNameOf(b)),
                    subtitle: Text(
                      '${formatDate(bookingDateOf(b))} · ${peso(totalOf(b))}',
                    ),
                    trailing: StatusChip(status: b['status'] as String?),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('close')),
          ),
        ],
      ),
    );
  }
}
