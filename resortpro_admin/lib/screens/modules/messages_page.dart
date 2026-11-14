import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../services/admin_data.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin_widgets.dart';
import '../../widgets/list_controls.dart';

/// Messages: mga usapan ng guest at ng resort (Part 16 ng SQL).
/// Malapad na screen: listahan sa kaliwa, usapan sa kanan. Phone: isa-isa.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key, this.onUnreadChanged, this.initialClientId});

  /// Tinatawag kapag may nabasa (para ma-update ang badge sa sidebar).
  final VoidCallback? onUnreadChanged;

  /// Usapang bubuksan agad (galing sa notification).
  final String? initialClientId;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _db = Supabase.instance.client;
  final _search = TextEditingController();
  String _query = '';

  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  String? _error;
  late String? _selected = widget.initialClientId;
  RealtimeChannel? _channel;

  /// Nagbabago tuwing may bagong mensahe (para mag-reload ang bukas na usapan).
  final _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    _loadThreads();
    _channel = _db
        .channel('admin-chat')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          callback: (_) {
            _loadThreads();
            _tick.value++;
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    final c = _channel;
    if (c != null) _db.removeChannel(c);
    _search.dispose();
    _tick.dispose();
    super.dispose();
  }

  Future<void> _loadThreads() async {
    try {
      final rows = await _db.rpc('chat_threads');
      if (!mounted) return;
      setState(() {
        _threads = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e'.contains('chat_threads') ? tr('msgNotReady') : tr('failed', {'e': e});
      });
    }
  }

  Map<String, dynamic>? get _selectedThread {
    for (final t in _threads) {
      if ('${t['client_id']}' == _selected) return t;
    }
    return null;
  }

  void _open(String clientId) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) {
      setState(() => _selected = clientId);
      return;
    }
    final t = _threads.firstWhere((e) => '${e['client_id']}' == clientId, orElse: () => {'client_id': clientId});
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('${t['client_name'] ?? tr('unknownClient')}')),
          body: _ThreadView(
            clientId: clientId,
            tick: _tick,
            onRead: _afterRead,
          ),
        ),
      ),
    );
  }

  void _afterRead() {
    _loadThreads();
    widget.onUnreadChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = _buildList();
    if (!wide) return list;

    final t = _selectedThread;
    return Row(
      children: [
        SizedBox(width: 360, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? EmptyState(icon: Icons.forum_outlined, message: tr('msgPick'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        children: [
                          _Avatar(name: '${t?['client_name'] ?? ''}', url: t?['avatar_url'] as String?),
                          const SizedBox(width: 12),
                          Text(
                            '${t?['client_name'] ?? tr('unknownClient')}',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _ThreadView(
                        key: ValueKey(_selected),
                        clientId: _selected!,
                        tick: _tick,
                        onRead: _afterRead,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return EmptyState(icon: Icons.error_outline, message: _error!);

    final q = _query.trim().toLowerCase();
    final shown = _threads
        .where((t) => q.isEmpty || '${t['client_name'] ?? ''}'.toLowerCase().contains(q))
        .toList();

    return RefreshIndicator(
      onRefresh: _loadThreads,
      child: ListView(
        padding: EdgeInsets.fromLTRB(pageGutter(context), 16, pageGutter(context), 24),
        children: [
          SearchBox(
            controller: _search,
            hint: tr('msgSearch'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 12),
          if (_threads.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: EmptyState(icon: Icons.forum_outlined, message: tr('msgNone')),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: EmptyState(icon: Icons.search_off, message: tr('noResults')),
            )
          else
            AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _threadTile(shown[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _threadTile(Map<String, dynamic> t) {
    final id = '${t['client_id']}';
    final unread = (t['unread'] as num?)?.toInt() ?? 0;
    final fromAdmin = t['last_sender'] == 'admin';
    final selected = id == _selected && MediaQuery.sizeOf(context).width >= 900;
    return ListTile(
      selected: selected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.06),
      leading: _Avatar(name: '${t['client_name'] ?? ''}', url: t['avatar_url'] as String?),
      title: Text(
        '${t['client_name'] ?? tr('unknownClient')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Text(
        '${fromAdmin ? tr('msgYou') : ''}${t['last_body'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: unread > 0 ? AppColors.text : AppColors.muted,
          fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_shortTime(parseDate(t['last_at'])), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (unread > 0) ...[
            const SizedBox(height: 4),
            Badge(label: Text('$unread')),
          ],
        ],
      ),
      onTap: () => _open(id),
    );
  }

  static String _shortTime(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    if (DateUtils.isSameDay(local, DateTime.now())) return _hm(local);
    return formatDate(local);
  }
}

String _hm(DateTime t) =>
    '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';

/// Isang usapan: mga mensahe at sagot ng admin.
class _ThreadView extends StatefulWidget {
  const _ThreadView({super.key, required this.clientId, required this.tick, required this.onRead});

  final String clientId;
  final ValueNotifier<int> tick;
  final VoidCallback onRead;

  @override
  State<_ThreadView> createState() => _ThreadViewState();
}

class _ThreadViewState extends State<_ThreadView> {
  final _db = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    widget.tick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.tick.removeListener(_load);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _db
          .from('chat_messages')
          .select()
          .eq('client_id', widget.clientId)
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      final before = _messages.length;
      setState(() {
        _messages = List<Map<String, dynamic>>.from(rows).reversed.toList();
        _loading = false;
      });
      if (_messages.length != before) _scrollToBottom();
      if (_messages.any((m) => m['sender'] == 'client' && m['read_at'] == null)) {
        await _db.rpc('mark_chat_read', params: {'p_client_id': widget.clientId});
        widget.onRead();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _db.from('chat_messages').insert({'client_id': widget.clientId, 'body': text});
      _input.clear();
      await _load();
    } catch (e) {
      if (mounted) showToast(context, tr('msgSendFail', {'e': e}));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lastAdmin = _messages.lastIndexWhere((m) => m['sender'] == 'admin');
    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) {
                    final m = _messages[i];
                    final mine = m['sender'] == 'admin';
                    final at = parseDate(m['created_at'])?.toLocal();
                    final prevAt = i == 0 ? null : parseDate(_messages[i - 1]['created_at'])?.toLocal();
                    final newDay = at != null && (prevAt == null || !DateUtils.isSameDay(at, prevAt));
                    final staff = mine ? staffNameOf(m['sender_id']) : null;
                    return Column(
                      crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (newDay)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(formatDate(at), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ),
                          ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 3),
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                            decoration: BoxDecoration(
                              color: mine ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(18),
                                topRight: const Radius.circular(18),
                                bottomLeft: Radius.circular(mine ? 18 : 4),
                                bottomRight: Radius.circular(mine ? 4 : 18),
                              ),
                              border: mine ? null : Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SelectableText(
                                  '${m['body'] ?? ''}',
                                  style: TextStyle(color: mine ? Colors.white : AppColors.text, fontSize: 15, height: 1.35),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  at == null ? '' : _hm(at),
                                  style: TextStyle(color: mine ? Colors.white70 : AppColors.muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (mine && (staff != null || (i == lastAdmin && m['read_at'] != null)))
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 6, bottom: 4),
                            child: Text(
                              [
                                ?staff,
                                if (i == lastAdmin && m['read_at'] != null) tr('msgSeen'),
                              ].join(' · '),
                              style: const TextStyle(color: AppColors.muted, fontSize: 11),
                            ),
                          ),
                      ],
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 1000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(hintText: tr('msgTypeHint'), counterText: '', isDense: true),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: tr('msgSend'),
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.url});

  final String name;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      backgroundImage: u.isEmpty ? null : NetworkImage(u),
      child: u.isEmpty
          ? Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
            )
          : null,
    );
  }
}
