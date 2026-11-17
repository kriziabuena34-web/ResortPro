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
  String _filter = 'all'; // all, unread, waiting

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

  static int _unreadOf(Map<String, dynamic> t) => (t['unread'] as num?)?.toInt() ?? 0;
  static bool _waiting(Map<String, dynamic> t) => t['last_sender'] == 'client';

  void _open(String clientId, {required bool wide}) {
    if (wide) {
      setState(() => _selected = clientId);
      return;
    }
    final t = _threads.firstWhere((e) => '${e['client_id']}' == clientId, orElse: () => {'client_id': clientId});
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                _Avatar(name: '${t['client_name'] ?? ''}', url: t['avatar_url'] as String?, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${t['client_name'] ?? tr('unknownClient')}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          body: _ThreadView(clientId: clientId, tick: _tick, onRead: _afterRead),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final height = (MediaQuery.sizeOf(context).height - 300).clamp(520.0, 900.0);
        return ListView(
          padding: pageInsets(context),
          children: [
            Text(tr('msgSubtitle'), style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            _overviewCard(wide: constraints.maxWidth >= 700),
            const SizedBox(height: 18),
            AppCard(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              child: wide
                  ? SizedBox(
                      height: height,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 370, child: _listPanel(wide: true)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _threadPanel()),
                        ],
                      ),
                    )
                  : _listPanel(wide: false),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Buod
  // ---------------------------------------------------------------------------

  Widget _overviewCard({required bool wide}) {
    final unreadThreads = _threads.where((t) => _unreadOf(t) > 0).length;
    final unreadMsgs = _threads.fold<int>(0, (s, t) => s + _unreadOf(t));
    final waiting = _threads.where(_waiting).length;
    final today = DateUtils.dateOnly(DateTime.now());
    final repliedToday = _threads.where((t) {
      final d = parseDate(t['last_at'])?.toLocal();
      return t['last_sender'] == 'admin' && d != null && DateUtils.isSameDay(d, today);
    }).length;

    final tiles = [
      _tile(tr('msgKThreads'), tr('msgKThreadsSub'), '${_threads.length}', Colors.white, Icons.forum_outlined),
      _tile(tr('msgKUnread'), tr('msgKUnreadSub', {'n': unreadThreads}), '$unreadMsgs', const Color(0xFFFBBF24),
          Icons.mark_chat_unread_outlined),
      _tile(tr('msgKWaiting'), tr('msgKWaitingSub'), '$waiting', const Color(0xFFF87171), Icons.hourglass_top_rounded),
      _tile(tr('msgKReplied'), tr('msgKRepliedSub'), '$repliedToday', const Color(0xFF4ADE80), Icons.mark_chat_read_outlined),
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
              const Icon(Icons.chat_rounded, color: AppColors.inkText, size: 20),
              const SizedBox(width: 8),
              Text(tr('msgOverview'),
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
          Text(value, style: TextStyle(color: valueColor, fontSize: 24, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Listahan ng usapan
  // ---------------------------------------------------------------------------

  Widget _listPanel({required bool wide}) {
    final q = _query.trim().toLowerCase();
    final shown = _threads.where((t) {
      if (_filter == 'unread' && _unreadOf(t) == 0) return false;
      if (_filter == 'waiting' && !_waiting(t)) return false;
      return q.isEmpty ||
          '${t['client_name'] ?? ''}'.toLowerCase().contains(q) ||
          '${t['last_body'] ?? ''}'.toLowerCase().contains(q);
    }).toList();

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SearchBox(controller: _search, hint: tr('msgSearch'), onChanged: (v) => setState(() => _query = v)),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: CountTabs<String>(
              value: _filter,
              accent: 'unread',
              onChanged: (v) => setState(() => _filter = v),
              items: [
                (value: 'all', label: tr('filterAll'), count: _threads.length),
                (value: 'unread', label: tr('msgTabUnread'), count: _threads.where((t) => _unreadOf(t) > 0).length),
                (value: 'waiting', label: tr('msgTabWaiting'), count: _threads.where(_waiting).length),
              ],
            ),
          ),
        ],
      ),
    );

    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = Padding(padding: const EdgeInsets.all(24), child: EmptyState(icon: Icons.error_outline, message: _error!));
    } else if (_threads.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(24), child: EmptyState(icon: Icons.forum_outlined, message: tr('msgNone')));
    } else if (shown.isEmpty) {
      body = Padding(padding: const EdgeInsets.all(24), child: EmptyState(icon: Icons.search_off, message: tr('noResults')));
    } else {
      final tiles = [for (final t in shown) _threadTile(t, wide: wide)];
      body = wide
          ? ListView.separated(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: tiles.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) => tiles[i],
            )
          : Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) const Divider(height: 1, indent: 72),
                  tiles[i],
                ],
              ],
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
      children: [
        header,
        const Divider(height: 1),
        if (wide) Expanded(child: RefreshIndicator(onRefresh: _loadThreads, child: body)) else body,
      ],
    );
  }

  Widget _threadTile(Map<String, dynamic> t, {required bool wide}) {
    final id = '${t['client_id']}';
    final unread = _unreadOf(t);
    final fromAdmin = t['last_sender'] == 'admin';
    final selected = wide && id == _selected;
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.07) : Colors.transparent,
      child: InkWell(
        onTap: () => _open(id, wide: wide),
        child: Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: selected ? AppColors.primary : Colors.transparent, width: 3)),
          ),
          padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _Avatar(name: '${t['client_name'] ?? ''}', url: t['avatar_url'] as String?, radius: 22),
                  if (unread > 0)
                    Positioned(
                      right: -1,
                      top: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${t['client_name'] ?? tr('unknownClient')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700, fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(_shortTime(parseDate(t['last_at'])),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: unread > 0 ? AppColors.primary : AppColors.muted,
                              fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w500,
                            )),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (fromAdmin) ...[
                          const Icon(Icons.reply_rounded, size: 14, color: AppColors.muted),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Text(
                            '${t['last_body'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: unread > 0 ? AppColors.text : AppColors.muted,
                              fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                            child: Text('$unread',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
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

  static String _shortTime(DateTime? d) {
    if (d == null) return '';
    final local = d.toLocal();
    if (DateUtils.isSameDay(local, DateTime.now())) return _hm(local);
    return formatDate(local);
  }

  // ---------------------------------------------------------------------------
  // Usapan (malapad na screen)
  // ---------------------------------------------------------------------------

  Widget _threadPanel() {
    final t = _selectedThread;
    if (_selected == null) {
      return Container(
        color: AppColors.subtle,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: const Icon(Icons.forum_outlined, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 14),
            Text(tr('msgPick'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(tr('msgPickSub'), style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );
    }
    final waiting = t != null && _waiting(t);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              _Avatar(name: '${t?['client_name'] ?? ''}', url: t?['avatar_url'] as String?, radius: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${t?['client_name'] ?? tr('unknownClient')}',
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                    Text(tr('msgGuest'), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (waiting)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFF5D08A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hourglass_top_rounded, size: 14, color: Color(0xFFB7791F)),
                      const SizedBox(width: 4),
                      Text(tr('msgTabWaiting'),
                          style: const TextStyle(color: Color(0xFFB7791F), fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
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
    );
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
          child: Container(
            color: const Color(0xFFF4F7F9),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(child: Text(tr('msgNone'), style: const TextStyle(color: AppColors.muted)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 12),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.border),
                                    ),
                                    child: Text(formatDate(at),
                                        style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
                                    boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 6, offset: Offset(0, 2))],
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
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (i == lastAdmin && m['read_at'] != null) ...[
                                        const Icon(Icons.done_all_rounded, size: 14, color: AppColors.primary),
                                        const SizedBox(width: 3),
                                      ],
                                      Text(
                                        [
                                          ?staff,
                                          if (i == lastAdmin && m['read_at'] != null) tr('msgSeen'),
                                        ].join(' · '),
                                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
          ),
        ),
        // Composer
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
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
                    decoration: InputDecoration(
                      hintText: tr('msgTypeHint'),
                      counterText: '',
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.subtle,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 46,
                  height: 46,
                  child: IconButton.filled(
                    tooltip: tr('msgSend'),
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send_rounded),
                  ),
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
  const _Avatar({required this.name, this.url, this.radius = 20});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final u = (url ?? '').trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.12),
      foregroundImage: u.isEmpty ? null : NetworkImage(u),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800),
      ),
    );
  }
}
