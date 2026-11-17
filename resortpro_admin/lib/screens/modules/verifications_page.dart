import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Account verification: tingnan ang ID ng client at i-verify o i-reject.
class VerificationsPage extends StatefulWidget {
  const VerificationsPage({super.key, required this.data, required this.onChanged});

  final AdminData data;
  final Future<void> Function() onChanged;

  @override
  State<VerificationsPage> createState() => _VerificationsPageState();
}

class _VerificationsPageState extends State<VerificationsPage> {
  final supabase = Supabase.instance.client;

  // Naka-cache ang signed URL para hindi paulit-ulit kinukuha tuwing mag-rebuild.
  final Map<String, Future<String?>> _imageUrlCache = {};
  final Set<String> _busy = {};
  final Set<String> _revealed = {};
  final _searchController = TextEditingController();
  String _query = '';
  String _tab = 'pending';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _askRejectReason(Map<String, dynamic> account) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('rejectQ')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('rejectMsg', {'name': _displayName(account)})),
              const SizedBox(height: 16),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final key in const ['reasonBlurry', 'reasonMismatch', 'reasonExpired'])
                    ActionChip(
                      label: Text(tr(key)),
                      onPressed: () => controller.text = tr(key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 2,
                decoration: InputDecoration(labelText: tr('reasonForClient')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('back'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(tr('reject')),
          ),
        ],
      ),
    );
  }

  Future<String?> _getIdImageUrl(String? path) {
    if (path == null || path.isEmpty) return Future.value(null);
    return _imageUrlCache.putIfAbsent(path, () async {
      try {
        return await supabase.storage
            .from('government-ids')
            .createSignedUrl(path, 3600); // valid for 1 hour
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> _verifyAccount(Map<String, dynamic> account, String newStatus) async {
    final id = '${account['id']}';

    String? reason;
    if (newStatus == 'rejected') {
      reason = await _askRejectReason(account);
      if (reason == null) return;
    }
    if (!mounted) return;

    setState(() => _busy.add(id));
    try {
      await supabase
          .from('profiles')
          .update({'verification_status': newStatus})
          .eq('id', id);

      await NotificationService.notifyClient(
        id,
        newStatus == 'verified' ? 'account_verified' : 'account_rejected',
        {if (reason != null && reason.isNotEmpty) 'reason': reason},
        refId: id,
      );

      if (!mounted) return;
      showToast(
        context,
        tr(newStatus == 'verified' ? 'accountVerified' : 'accountRejected'),
      );
      await widget.onChanged();
    } catch (e) {
      if (!mounted) return;
      showToast(context, tr('failed', {'e': e}));
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  String _displayName(Map<String, dynamic> a) {
    final display = a['google_display_name'];
    if (display != null && '$display'.trim().isNotEmpty) return '$display';
    return '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim();
  }

  String _legalName(Map<String, dynamic> a) {
    final suffix = a['suffix'];
    final parts = [
      '${a['last_name'] ?? ''},',
      '${a['first_name'] ?? ''}',
      '${a['middle_name'] ?? ''}',
      if (suffix != null && suffix != 'N/A') '$suffix',
    ];
    return parts.where((p) => p.trim().isNotEmpty && p != ',').join(' ');
  }

  static const _caps = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.muted);

  String? _photoOf(Map<String, dynamic> a) {
    for (final k in ['avatar_url', 'google_avatar_url']) {
      final v = '${a[k] ?? ''}'.trim();
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  static int _ageOf(DateTime birth) {
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) age--;
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final clients = widget.data.clients;
    final pending = widget.data.pendingAccounts;
    final verified = clients.where((c) => c['verification_status'] == 'verified').length;
    final rejected = clients.where((c) => c['verification_status'] == 'rejected').length;

    final q = _query.trim().toLowerCase();
    final shown = clients.where((c) {
      if (_tab != 'all' && c['verification_status'] != _tab) return false;
      if (q.isEmpty) return true;
      return _displayName(c).toLowerCase().contains(q) ||
          _legalName(c).toLowerCase().contains(q) ||
          '${c['username'] ?? ''}'.toLowerCase().contains(q) ||
          '${c['phone'] ?? ''}'.contains(q) ||
          '${c['government_id_type'] ?? ''}'.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        // Pinakamatagal nang naghihintay ang nauuna.
        final da = parseDate(a['created_at']), db = parseDate(b['created_at']);
        if (da == null || db == null) return 0;
        return _tab == 'pending' ? da.compareTo(db) : db.compareTo(da);
      });

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: pageInsets(context),
            children: [
              Text(tr('vfSubtitle'), style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 14),
              _overviewCard(
                wide: constraints.maxWidth >= 700,
                pending: pending.length,
                verified: verified,
                rejected: rejected,
                total: clients.length,
              ),
              const SizedBox(height: 18),
              AppCard(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth >= 900 ? 360 : double.infinity,
                        child: SearchBox(
                          controller: _searchController,
                          hint: tr('searchClientsHint'),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      CountTabs<String>(
                        value: _tab,
                        onChanged: (v) => setState(() => _tab = v),
                        items: [
                          (value: 'pending', label: verificationLabel('pending'), count: pending.length),
                          (value: 'verified', label: verificationLabel('verified'), count: verified),
                          (value: 'rejected', label: verificationLabel('rejected'), count: rejected),
                          (value: 'all', label: tr('filterAll'), count: clients.length),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (shown.isEmpty)
                AppCard(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: EmptyState(
                      icon: Icons.task_alt,
                      message: _tab == 'pending' && q.isEmpty ? tr('noPending') : tr('noClientsMatch'),
                    ),
                  ),
                )
              else
                CardGrid(
                  columns: constraints.maxWidth >= 1100 ? 2 : 1,
                  children: [
                    for (final account in shown) _buildAccountCard(account),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Buod
  // ---------------------------------------------------------------------------

  Widget _overviewCard({
    required bool wide,
    required int pending,
    required int verified,
    required int rejected,
    required int total,
  }) {
    final rate = total == 0 ? 0 : (verified * 100 / total).round();
    final tiles = [
      _tile(tr('vfKPending'), tr('vfKPendingSub'), '$pending', const Color(0xFFFACC15), Icons.hourglass_top_rounded,
          () => setState(() => _tab = 'pending')),
      _tile(tr('vfKVerified'), tr('vfKVerifiedSub'), '$verified', const Color(0xFF4ADE80), Icons.verified_rounded,
          () => setState(() => _tab = 'verified')),
      _tile(tr('vfKRejected'), tr('vfKRejectedSub'), '$rejected', const Color(0xFFF87171), Icons.block_rounded,
          () => setState(() => _tab = 'rejected')),
      _tile(tr('vfKRate'), tr('vfKRateSub', {'n': total}), '$rate%', Colors.white, Icons.pie_chart_outline_rounded,
          () => setState(() => _tab = 'all')),
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
              const Icon(Icons.verified_user_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('vfOverview'),
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

  Widget _tile(String label, String sub, String value, Color valueColor, IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.inkRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.inkLine),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: AppColors.inkText, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
                  ),
                  Icon(icon, size: 16, color: const Color(0xFF7F93A6)),
                ],
              ),
              const SizedBox(height: 2),
              Text(sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF7F93A6), fontSize: 10.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card ng bawat account
  // ---------------------------------------------------------------------------

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppColors.muted),
            const SizedBox(width: 9),
            SizedBox(width: 96, child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(value.isEmpty ? tr('notSet') : value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: value.isEmpty ? AppColors.muted : AppColors.text,
                  )),
            ),
          ],
        ),
      );

  Widget _idImage(Map<String, dynamic> account, {required bool hidden, required double height}) {
    final id = '${account['id']}';
    Widget frame(Widget child) => Container(
          height: height,
          decoration: BoxDecoration(
            color: AppColors.subtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        );

    if (hidden) {
      return frame(
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppColors.muted),
              const SizedBox(height: 6),
              Text(tr('vfIdHidden'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => setState(() => _revealed.add(id)),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: Text(tr('showId')),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<String?>(
      future: _getIdImageUrl(account['id_image_path'] as String?),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return frame(const Center(child: CircularProgressIndicator()));
        }
        final url = snapshot.data;
        if (url == null) {
          return frame(
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.image_not_supported_outlined, color: AppColors.danger),
                  const SizedBox(height: 6),
                  Text(tr('noIdImage'), style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                ],
              ),
            ),
          );
        }
        return frame(
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => showDialog(
                context: context,
                builder: (context) => Dialog(
                  clipBehavior: Clip.antiAlias,
                  child: InteractiveViewer(child: Image.network(url)),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        Center(child: Text(tr('idLoadFail'), style: const TextStyle(color: AppColors.muted))),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xB3000000), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.zoom_in_rounded, size: 15, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(tr('vfZoom'),
                              style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final id = '${account['id']}';
    final busy = _busy.contains(id);
    final status = '${account['verification_status'] ?? 'unverified'}';
    final statusColor = verificationColor(status);
    final pending = status == 'pending';
    final name = _displayName(account);
    final username = '${account['username'] ?? ''}'.trim();
    final photo = _photoOf(account);
    final birth = parseDate(account['birth_date']);
    final joined = parseDate(account['created_at']);
    final hidden = !pending && !_revealed.contains(id);

    final info = [
      _infoRow(Icons.badge_outlined, tr('legalName'), _legalName(account)),
      _infoRow(Icons.phone_outlined, tr('fieldPhone'), '${account['phone'] ?? ''}'.trim()),
      _infoRow(Icons.cake_outlined, tr('birthDate'),
          birth == null ? '' : '${formatDate(birth)}  ·  ${tr('clAge', {'n': _ageOf(birth)})}'),
      _infoRow(Icons.credit_card_outlined, tr('idType'), '${account['government_id_type'] ?? ''}'.trim()),
    ];
    final infoBox = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < info.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            info[i],
          ],
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: pending ? const Color(0xFFFFFBEB) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pending ? const Color(0xFFF5C451) : AppColors.border, width: pending ? 1.5 : 1),
        boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  foregroundImage: photo == null ? null : NetworkImage(photo),
                  child: Text(
                    (username.isNotEmpty ? username : name).isEmpty
                        ? '?'
                        : (username.isNotEmpty ? username : name)[0].toUpperCase(),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username.isNotEmpty ? username : (name.isEmpty ? tr('noName') : name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                      ),
                      Text(
                        joined == null ? '' : tr('vfSignedUp', {'d': formatDate(joined)}),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.30)),
                  ),
                  child: Text(verificationLabel(status),
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, c) {
                if (c.maxWidth >= 520) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 230,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('vfIdPhoto').toUpperCase(), style: _caps),
                            const SizedBox(height: 8),
                            _idImage(account, hidden: hidden, height: 170),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(tr('clPersonalInfo').toUpperCase(), style: _caps),
                            const SizedBox(height: 8),
                            infoBox,
                          ],
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('clPersonalInfo').toUpperCase(), style: _caps),
                    const SizedBox(height: 8),
                    infoBox,
                    const SizedBox(height: 16),
                    Text(tr('vfIdPhoto').toUpperCase(), style: _caps),
                    const SizedBox(height: 8),
                    _idImage(account, hidden: hidden, height: 200),
                  ],
                );
              },
            ),
          ),
            ],
          ),
          // Actions
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: pending ? const Color(0xFFF5C451) : AppColors.border)),
            ),
            child: Row(
              children: [
                if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const Spacer(),
                if (status != 'rejected')
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => _verifyAccount(account, 'rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: BorderSide(color: AppColors.danger.withValues(alpha: 0.5)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: Text(status == 'verified' ? tr('revoke') : tr('reject')),
                  ),
                if (status != 'rejected' && status != 'verified') const SizedBox(width: 10),
                if (status != 'verified')
                  FilledButton.icon(
                    onPressed: busy ? null : () => _verifyAccount(account, 'verified'),
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E9E5B)),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(tr('verify')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
