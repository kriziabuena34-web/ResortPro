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
          '${c['phone'] ?? ''}'.contains(q) ||
          '${c['government_id_type'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {

        return RefreshIndicator(
          onRefresh: widget.onChanged,
          child: ListView(
            padding: pageInsets(context),
            children: [
              StatGrid(
                children: [
                  StatCard(
                    icon: Icons.hourglass_top,
                    label: tr('statPending'),
                    value: '${pending.length}',
                    color: AppColors.accent,
                    onTap: () => setState(() => _tab = 'pending'),
                  ),
                  StatCard(
                    icon: Icons.verified,
                    label: tr('statVerified'),
                    value: '$verified',
                    color: AppColors.success,
                    onTap: () => setState(() => _tab = 'verified'),
                  ),
                  StatCard(
                    icon: Icons.block,
                    label: tr('statRejected'),
                    value: '$rejected',
                    color: AppColors.danger,
                    onTap: () => setState(() => _tab = 'rejected'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchBox(
                      controller: _searchController,
                      hint: tr('searchClientsHint'),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final t in const ['pending', 'verified', 'rejected', 'all'])
                          ChoiceChip(
                            label: Text(t == 'all' ? tr('filterAll') : verificationLabel(t)),
                            selected: _tab == t,
                            onSelected: (_) => setState(() => _tab = t),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (shown.isEmpty)
                EmptyState(
                  icon: Icons.task_alt,
                  message: _tab == 'pending' && q.isEmpty ? tr('noPending') : tr('noClientsMatch'),
                )
              else
                CardGrid(
                  columns: constraints.maxWidth >= 900 ? 2 : 1,
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

  Widget _buildAccountCard(Map<String, dynamic> account) {
    final theme = Theme.of(context);
    final id = '${account['id']}';
    final busy = _busy.contains(id);
    final status = '${account['verification_status'] ?? 'unverified'}';
    final statusColor = verificationColor(status);

    return AppCard(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _displayName(account).isEmpty ? tr('noName') : _displayName(account),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    verificationLabel(status),
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            InfoRow(tr('legalName'), _legalName(account)),
            InfoRow(tr('fieldPhone'), '${account['phone'] ?? tr('notSet')}'),
            InfoRow(tr('birthDate'), formatDate(parseDate(account['birth_date']))),
            InfoRow(tr('idType'), '${account['government_id_type'] ?? tr('notSet')}'),
            const SizedBox(height: 12),
            if (status != 'pending' && !_revealed.contains(id))
              TextButton.icon(
                onPressed: () => setState(() => _revealed.add(id)),
                icon: const Icon(Icons.badge_outlined, size: 18),
                label: Text(tr('showId')),
              )
            else ...[
            FutureBuilder<String?>(
              future: _getIdImageUrl(account['id_image_path'] as String?),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final url = snapshot.data;
                if (url == null) {
                  return Text(
                    tr('noIdImage'),
                    style: TextStyle(color: theme.colorScheme.error),
                  );
                }
                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(child: Image.network(url)),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      url,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => SizedBox(
                        height: 60,
                        child: Center(child: Text(tr('idLoadFail'))),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Text(tr('tapToZoom'), style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (status != 'verified')
                FilledButton.icon(
                  onPressed: busy ? null : () => _verifyAccount(account, 'verified'),
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E9E5B)),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(tr('verify')),
                ),
                if (status != 'rejected')
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _verifyAccount(account, 'rejected'),
                  style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(status == 'verified' ? tr('revoke') : tr('reject')),
                ),
                if (busy) ...[
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
