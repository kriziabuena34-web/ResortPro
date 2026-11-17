import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Listahan ng lahat ng client: buod, search, mga tab ayon sa verification,
/// sort, at history ng bookings ng bawat isa.
class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key, required this.data, this.onMessage, this.onReview});

  final AdminData data;

  /// Bubuksan ang usapan ng client sa Messages.
  final void Function(String clientId)? onMessage;

  /// Pupunta sa Verifications (para sa client na naghihintay ng review).
  final VoidCallback? onReview;

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

enum _ClientSort { name, mostBookings, recent }

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

  String get status => '${client['verification_status'] ?? 'unverified'}';

  static String _part(dynamic v) {
    final t = '${v ?? ''}'.trim();
    return t.toUpperCase() == 'N/A' ? '' : t;
  }

  /// Username ng account (o pangalan sa Google kung wala pa).
  String get username {
    final u = _part(client['username']);
    if (u.isNotEmpty) return u;
    final g = _part(client['google_display_name']);
    return g.isEmpty ? tr('noName') : g;
  }

  /// "KRIZIA RODRIGUEZ BUENA" (first, middle, last, suffix)
  String get fullName {
    final n = [
      _part(client['first_name']),
      _part(client['middle_name']),
      _part(client['last_name']),
      _part(client['suffix']),
    ].where((e) => e.isNotEmpty).join(' ');
    return n.toUpperCase();
  }

  DateTime? get birthDate => parseDate(client['birth_date']);

  DateTime? get joined => parseDate(client['created_at']);

  String? get photo {
    for (final k in ['avatar_url', 'google_avatar_url']) {
      final v = '${client[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }
}

class _ClientsPageState extends State<ClientsPage> {
  final _searchController = TextEditingController();
  String _query = '';
  String _status = 'all';
  _ClientSort _sort = _ClientSort.name;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<_ClientSort, String> get _sortOptions => {
        _ClientSort.name: tr('sortName'),
        _ClientSort.mostBookings: tr('sortMostBookings'),
        _ClientSort.recent: tr('sortRecentBooking'),
      };

  @override
  Widget build(BuildContext context) {
    final all = [
      for (final c in widget.data.clients) _ClientStats(c, widget.data.bookingsOfClient('${c['id']}')),
    ];

    final q = _query.trim().toLowerCase();
    final list = all.where((c) {
      if (_status != 'all' && c.status != _status) return false;
      if (q.isEmpty) return true;
      return c.username.toLowerCase().contains(q) ||
          c.fullName.toLowerCase().contains(q) ||
          '${c.client['phone'] ?? ''}'.contains(q) ||
          '${c.client['google_display_name'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    switch (_sort) {
      case _ClientSort.name:
        list.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
      case _ClientSort.mostBookings:
        list.sort((a, b) => b.bookingCount.compareTo(a.bookingCount));
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('clSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(all, wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            AppCard(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: wide ? 380 : double.infinity,
                          child: SearchBox(
                            controller: _searchController,
                            hint: tr('searchClientsHint'),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                        CountTabs<String>(
                          value: _status,
                          accent: 'pending',
                          onChanged: (v) => setState(() => _status = v),
                          items: [
                            (value: 'all', label: tr('filterAll'), count: countOf('all')),
                            for (final s in const ['verified', 'pending', 'unverified', 'rejected'])
                              if (countOf(s) > 0 || _status == s)
                                (value: s, label: verificationLabel(s), count: countOf(s)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Icon(Icons.tune_rounded, size: 18, color: AppColors.muted),
                        PopupMenuButton<_ClientSort>(
                          tooltip: tr('sortBy'),
                          initialValue: _sort,
                          onSelected: (v) => setState(() => _sort = v),
                          itemBuilder: (context) => [
                            for (final e in _sortOptions.entries)
                              CheckedPopupMenuItem<_ClientSort>(value: e.key, checked: e.key == _sort, child: Text(e.value)),
                          ],
                          child: FilterPill(
                            icon: Icons.swap_vert_rounded,
                            label: _sortOptions[_sort] ?? '',
                            active: _sort != _ClientSort.name,
                            dropdown: true,
                          ),
                        ),
                        if (_status != 'all' || _sort != _ClientSort.name || _query.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _query = '';
                                _status = 'all';
                                _sort = _ClientSort.name;
                              });
                            },
                            icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                            label: Text(tr('bkResetFilters')),
                          ),
                      ],
                    ),
                  ),
                  ResultCount(shown: list.length, total: all.length),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(icon: Icons.people_outline, message: tr('noClientsMatch')),
                    )
                  else ...[
                    if (wide) _tableHeader(),
                    for (var i = 0; i < list.length; i++) ...[
                      if (i > 0 || !wide) const Divider(height: 1),
                      _clientRow(list[i], wide: wide),
                    ],
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Buod
  // ---------------------------------------------------------------------------

  Widget _overviewCard(List<_ClientStats> all, {required bool wide}) {
    final verified = all.where((c) => c.status == 'verified').length;
    final pending = all.where((c) => c.status == 'pending').length;
    final repeat = all.where((c) => c.bookingCount >= 2).length;
    final now = DateTime.now();
    final newThisMonth = all.where((c) => c.joined != null && c.joined!.year == now.year && c.joined!.month == now.month).length;

    final tiles = [
      _tile(tr('clKTotal'), tr('clKTotalSub', {'n': verified}), '${all.length}', Colors.white, Icons.people_outline),
      _tile(tr('clKPending'), tr('clKPendingSub'), '$pending', const Color(0xFFFBBF24), Icons.badge_outlined),
      _tile(tr('clKRepeat'), tr('clKRepeatSub'), '$repeat', const Color(0xFF4ADE80), Icons.favorite_outline),
      _tile(tr('clKNew'), tr('clKNewSub', {'month': '${monthNamesTr[now.month - 1]} ${now.year}'.toUpperCase()}),
          '$newThisMonth', Colors.white, Icons.person_add_alt_1_outlined),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('clOverview'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 0.8, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 14),
          if (wide)
            Row(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: tiles[i]),
                ],
              ],
            )
          else
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: tiles,
            ),
        ],
      ),
    );
  }

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.inkRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inkLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              ),
              Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
            ],
          ),
          const SizedBox(height: 2),
          Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: valueColor, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Table
  // ---------------------------------------------------------------------------

  // Lapad ng bawat column (pareho sa header at sa bawat hanay).
  static const _flex = (client: 5, name: 5, birth: 3, contact: 3, last: 3, status: 3);
  static const _actionWidth = 128.0;
  static const _rowPadding = EdgeInsets.fromLTRB(24, 12, 20, 12);

  /// Isang cell: may puwang sa kanan para hindi magdikit ang mga column.
  Widget _cell(int flex, Widget child) =>
      Expanded(flex: flex, child: Padding(padding: const EdgeInsets.only(right: 16), child: child));

  Widget _tableHeader() {
    Widget h(String t, int flex) => _cell(
          flex,
          Text(t, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
        );
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.subtle,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: _rowPadding,
      child: Row(
        children: [
          h(tr('clColClient'), _flex.client),
          h(tr('clColName'), _flex.name),
          h(tr('clColBirth'), _flex.birth),
          h(tr('clColContact'), _flex.contact),
          h(tr('clColLast'), _flex.last),
          h(tr('clColStatus'), _flex.status),
          SizedBox(
            width: _actionWidth,
            child: Text(tr('bkColAction'),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final color = verificationColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(verificationLabel(status), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
    );
  }

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: 0.4)),
      );

  Widget _avatar(_ClientStats c, {double radius = 18}) {
    final color = verificationColor(c.status);
    final photo = c.photo;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.12),
      foregroundImage: photo == null ? null : NetworkImage(photo),
      child: Text(c.username.isEmpty ? '?' : c.username[0].toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    );
  }

  /// Maliit na parisukat na button sa ACTION column.
  Widget _actionBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required Color fg,
    required Color bg,
    Color? border,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: border ?? bg),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(width: 36, height: 36, child: Icon(icon, size: 18, color: fg)),
        ),
      ),
    );
  }

  Widget _actions(_ClientStats c) {
    final id = '${c.client['id']}';
    final pending = c.status == 'pending';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending && widget.onReview != null) ...[
          _actionBtn(
            icon: Icons.verified_user_outlined,
            tooltip: tr('clActReview'),
            onTap: widget.onReview,
            fg: AppColors.ink,
            bg: const Color(0xFFFACC15),
          ),
          const SizedBox(width: 6),
        ],
        if (widget.onMessage != null) ...[
          _actionBtn(
            icon: Icons.chat_bubble_outline_rounded,
            tooltip: tr('clActMessage'),
            onTap: () => widget.onMessage!(id),
            fg: AppColors.primary,
            bg: AppColors.primary.withValues(alpha: 0.10),
          ),
          const SizedBox(width: 6),
        ],
        _actionBtn(
          icon: Icons.visibility_outlined,
          tooltip: tr('details'),
          onTap: () => _showClient(c),
          fg: AppColors.text,
          bg: Colors.white,
          border: AppColors.border,
        ),
      ],
    );
  }

  Widget _clientRow(_ClientStats c, {required bool wide}) {
    final theme = Theme.of(context);
    final pending = c.status == 'pending';
    final phone = '${c.client['phone'] ?? ''}'.trim();
    final full = c.fullName;
    final birth = c.birthDate;

    final who = Row(
      children: [
        _avatar(c),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.username, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              if (pending || c.bookingCount >= 2) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (pending) _badge(tr('clNeedsReview'), const Color(0xFFFACC15), AppColors.ink),
                    if (c.bookingCount >= 2) _badge(tr('clRepeat'), const Color(0xFFDCFCE7), const Color(0xFF166534)),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final view = _actions(c);
    final decoration = pending
        ? BoxDecoration(color: const Color(0xFFFFFBEB), border: Border.all(color: const Color(0xFFF5C451), width: 1.5))
        : null;
    final muted = theme.textTheme.bodyMedium?.copyWith(color: AppColors.muted);

    if (wide) {
      return Container(
        decoration: decoration,
        child: InkWell(
          onTap: () => _showClient(c),
          child: Padding(
            padding: _rowPadding,
            child: Row(
              children: [
                _cell(_flex.client, who),
                _cell(
                  _flex.name,
                  Text(full.isEmpty ? '—' : full,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                _cell(_flex.birth, Text(birth == null ? '—' : formatDate(birth), style: birth == null ? muted : null)),
                _cell(_flex.contact, Text(phone.isEmpty ? '—' : phone, style: phone.isEmpty ? muted : null)),
                _cell(
                  _flex.last,
                  Text(c.lastBooking == null ? '—' : formatDate(c.lastBooking), style: c.lastBooking == null ? muted : null),
                ),
                _cell(_flex.status, Align(alignment: Alignment.centerLeft, child: _statusPill(c.status))),
                SizedBox(width: _actionWidth, child: Align(alignment: Alignment.centerRight, child: view)),
              ],
            ),
          ),
        ),
      );
    }

    Widget line(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: AppColors.muted),
              const SizedBox(width: 6),
              Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            ],
          ),
        );

    return Container(
      decoration: decoration,
      child: InkWell(
        onTap: () => _showClient(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: who),
                  _statusPill(c.status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        line(Icons.badge_outlined, full.isEmpty ? '—' : full),
                        line(Icons.cake_outlined, birth == null ? '—' : formatDate(birth)),
                        line(Icons.phone_outlined, phone.isEmpty ? '—' : phone),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  view,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Detalye ng client
  // ---------------------------------------------------------------------------

  void _showClient(_ClientStats c) {
    final bookings = [...c.bookings]
      ..sort((a, b) {
        final da = bookingDateOf(a), db = bookingDateOf(b);
        if (da == null || db == null) return 0;
        return db.compareTo(da);
      });

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.subtle,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.muted, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
                ),
              ],
            ),
          ),
        );

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 18),
                decoration: const BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Row(
                  children: [
                    _avatar(c, radius: 26),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.username, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                          if (c.fullName.isNotEmpty)
                            Text(c.fullName, style: const TextStyle(color: AppColors.inkText, fontSize: 12.5)),
                          const SizedBox(height: 4),
                          _statusPill(c.status),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('close'),
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          stat(tr('clColBookings'), '${c.bookingCount}'),
                          const SizedBox(width: 10),
                          stat(tr('clColPaid'), peso(c.totalPaid)),
                          const SizedBox(width: 10),
                          stat(tr('clColBalance'), peso(c.balance), color: c.balance > 0 ? AppColors.warning : null),
                        ],
                      ),
                      const SizedBox(height: 16),
                      InfoRow(tr('clColName'), c.fullName.isEmpty ? tr('notSet') : c.fullName),
                      InfoRow(tr('fieldPhone'), '${c.client['phone'] ?? tr('notSet')}'),
                      InfoRow(tr('birthDate'), formatDate(parseDate(c.client['birth_date']))),
                      InfoRow(tr('idType'), '${c.client['government_id_type'] ?? tr('notSet')}'),
                      if ('${c.client['google_display_name'] ?? ''}'.trim().isNotEmpty)
                        InfoRow(tr('clGoogleName'), '${c.client['google_display_name']}'),
                      const SizedBox(height: 16),
                      Text(tr('bookingHistory').toUpperCase(),
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted)),
                      const SizedBox(height: 8),
                      if (bookings.isEmpty)
                        Text(tr('noBookingsYet'), style: const TextStyle(color: AppColors.muted))
                      else
                        for (final b in bookings)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(packageNameOf(b), style: const TextStyle(fontWeight: FontWeight.w700)),
                                      Text('${formatDate(bookingDateOf(b))} · ${peso(totalOf(b))}',
                                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                StatusChip(status: b['status'] as String?),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              if (widget.onMessage != null || (c.status == 'pending' && widget.onReview != null))
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      if (c.status == 'pending' && widget.onReview != null)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFACC15), foregroundColor: AppColors.ink),
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            widget.onReview!();
                          },
                          icon: const Icon(Icons.verified_user_outlined, size: 18),
                          label: Text(tr('clActReview')),
                        ),
                      if (widget.onMessage != null)
                        FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(dialogContext);
                            widget.onMessage!('${c.client['id']}');
                          },
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: Text(tr('clActMessage')),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
