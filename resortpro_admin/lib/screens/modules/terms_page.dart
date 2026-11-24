import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';

/// Pool Agreement ng resort (Terms & Conditions na makikita ng guest sa app).
/// Nakatago sa resort_settings.pool_terms (terms_setup.sql).
class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  static const maxTerms = 40;
  static const maxTermLength = 300;

  List<String> _terms = [];
  List<String> _saved = [];
  DateTime? _updatedAt;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _changed => _terms.join('\n') != _saved.join('\n');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await Supabase.instance.client
          .from('resort_settings')
          .select('pool_terms, pool_terms_updated_at')
          .eq('id', 1)
          .single();
      final list = [for (final t in (row['pool_terms'] as List? ?? const [])) '$t'];
      setState(() {
        _terms = [...list];
        _saved = [...list];
        _updatedAt = parseDate(row['pool_terms_updated_at']);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '$e'.contains('pool_terms') ? tr('tmNotSetUp') : tr('failed', {'e': e});
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await Supabase.instance.client
          .from('resort_settings')
          .update({'pool_terms': _terms, 'pool_terms_updated_at': now})
          .eq('id', 1);
      if (!mounted) return;
      setState(() {
        _saved = [..._terms];
        _updatedAt = DateTime.now();
        _saving = false;
      });
      showToast(context, tr('tmSaved'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showToast(context, tr('failed', {'e': e}));
    }
  }

  Future<void> _edit({int? index}) async {
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _TermDialog(initial: index == null ? '' : _terms[index], maxLength: maxTermLength),
    );
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      if (index == null) {
        _terms.add(text.trim());
      } else {
        _terms[index] = text.trim();
      }
    });
  }

  Future<void> _delete(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('tmDeleteQ')),
        content: Text(_terms[index]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(tr('cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok == true) setState(() => _terms.removeAt(index));
  }

  void _move(int index, int by) {
    final to = index + by;
    if (to < 0 || to >= _terms.length) return;
    setState(() {
      final t = _terms.removeAt(index);
      _terms.insert(to, t);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, size: 36, color: AppColors.warning),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(tr('tryAgain'))),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: pageInsets(context),
      children: [
        Text(tr('tmIntro'), style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        AppCard(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 18, 14),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('tmTitle'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                        Text(
                          _updatedAt == null
                              ? tr('tmCount', {'n': _terms.length})
                              : '${tr('tmCount', {'n': _terms.length})} · ${tr('tmUpdated', {'date': formatDateTime(_updatedAt)})}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _terms.length >= maxTerms ? null : () => _edit(),
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(tr('tmAdd')),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
                          onPressed: !_changed || _saving || _terms.isEmpty ? null : _save,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: Text(_saving ? tr('saving') : tr('save')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_changed)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  color: const Color(0xFFFFFBEB),
                  child: Text(tr('tmUnsaved'), style: const TextStyle(fontSize: 13, color: Color(0xFF92400E))),
                ),
              const Divider(height: 1),
              if (_terms.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Center(child: Text(tr('tmEmpty'), style: const TextStyle(color: AppColors.muted))),
                ),
              for (var i = 0; i < _terms.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Color(0xFFEEF2F6)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 10, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(8)),
                        child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_terms[i], style: const TextStyle(fontSize: 14, height: 1.45)),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('moveEarlier'),
                        visualDensity: VisualDensity.compact,
                        onPressed: i == 0 ? null : () => _move(i, -1),
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: tr('moveLater'),
                        visualDensity: VisualDensity.compact,
                        onPressed: i == _terms.length - 1 ? null : () => _move(i, 1),
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                      IconButton(
                        tooltip: tr('tmEdit'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _edit(index: i),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: tr('delete'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _delete(i),
                        icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TermDialog extends StatefulWidget {
  const _TermDialog({required this.initial, required this.maxLength});
  final String initial;
  final int maxLength;

  @override
  State<_TermDialog> createState() => _TermDialogState();
}

class _TermDialogState extends State<_TermDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial.isEmpty ? tr('tmAdd') : tr('tmEdit')),
      content: SizedBox(
        width: 480,
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: widget.maxLength,
          decoration: InputDecoration(labelText: tr('tmRule'), border: const OutlineInputBorder()),
          onChanged: (_) => setState(() {}),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('cancel'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.ink, foregroundColor: Colors.white),
          onPressed: _controller.text.trim().isEmpty ? null : () => Navigator.pop(context, _controller.text),
          child: Text(tr('save')),
        ),
      ],
    );
  }
}
