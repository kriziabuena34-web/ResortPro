import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/offline_cache.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Chat ng guest at ng resort (isang tuloy-tuloy na usapan bawat account).
/// Text lang; may "Seen" at real-time. Kailangan ang Part 16 ng SQL.
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  /// True habang bukas ang chat (para hindi na lumabas ang banner ng bagong mensahe).
  static bool isOpen = false;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _db = Supabase.instance.client;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  DateTime? _offlineSavedAt;
  RealtimeChannel? _channel;

  String? get _uid => _db.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    ChatPage.isOpen = true;
    _load();
    _subscribe();
  }

  @override
  void dispose() {
    ChatPage.isOpen = false;
    final c = _channel;
    if (c != null) _db.removeChannel(c);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    // Ipakita muna ang naka-save (para may laman kahit offline).
    final cached = await OfflineCache.load('chat');
    if (cached != null && _messages.isEmpty && mounted) {
      setState(() {
        _messages = List<Map<String, dynamic>>.from((cached.data as List).map((e) => Map<String, dynamic>.from(e as Map)));
        _loading = false;
      });
    }
    try {
      final rows = await _db
          .from('chat_messages')
          .select()
          .eq('client_id', uid)
          .order('created_at', ascending: false)
          .limit(200);
      final list = List<Map<String, dynamic>>.from(rows).reversed.toList();
      await OfflineCache.save('chat', list);
      if (!mounted) return;
      setState(() {
        _messages = list;
        _loading = false;
        _error = null;
        _offlineSavedAt = null;
      });
      _scrollToBottom();
      _markRead();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (cached != null) {
          _offlineSavedAt = cached.savedAt;
        } else {
          _error = '$e'.contains('chat_messages')
              ? 'Chat is not available yet. Please try again later.'
              : friendlyError(e, action: 'load your messages');
        }
      });
    }
  }

  void _subscribe() {
    final uid = _uid;
    if (uid == null) return;
    _channel = _db
        .channel('chat-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'client_id', value: uid),
          callback: (payload) {
            final row = Map<String, dynamic>.from(payload.newRecord);
            if (row.isEmpty || !mounted) return;
            final i = _messages.indexWhere((m) => '${m['id']}' == '${row['id']}');
            setState(() {
              if (i >= 0) {
                _messages[i] = row; // hal. nabasa na (Seen)
              } else {
                _messages = [..._messages, row];
              }
            });
            if (i < 0) {
              _scrollToBottom();
              if (row['sender'] == 'admin') _markRead();
            }
          },
        )
        .subscribe();
  }

  Future<void> _markRead() async {
    if (!_messages.any((m) => m['sender'] == 'admin' && m['read_at'] == null)) return;
    try {
      await _db.rpc('mark_chat_read');
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final uid = _uid;
    if (text.isEmpty || _sending || uid == null) return;
    if (!await hasInternet()) {
      if (mounted) showOfflineSnack(context);
      return;
    }
    setState(() => _sending = true);
    try {
      final row = await _db
          .from('chat_messages')
          .insert({'client_id': uid, 'body': text})
          .select()
          .single();
      _input.clear();
      if (!mounted) return;
      setState(() {
        if (!_messages.any((m) => '${m['id']}' == '${row['id']}')) {
          _messages = [..._messages, Map<String, dynamic>.from(row)];
        }
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyError(e, action: 'send your message'))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.pool, color: Colors.white, size: 20),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Aryana's Guests House", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Chat with the resort', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_offlineSavedAt != null) OfflineNotice(savedAt: _offlineSavedAt!, onRetry: _load),
          Expanded(child: _buildMessages()),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return OfflineEmpty(message: _error!, onRetry: _load);
    if (_messages.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 56, color: AppColors.muted),
              SizedBox(height: 12),
              Text('Ask us anything', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                'Questions about packages, dates, or your booking? Send a message and the resort will reply here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      );
    }

    // Ang huling mensahe ng guest na nabasa na ng resort (para sa "Seen").
    final lastMine = _messages.lastIndexWhere((m) => m['sender'] == 'client');

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final m = _messages[i];
        final mine = m['sender'] == 'client';
        final at = parseDate(m['created_at'])?.toLocal();
        final prevAt = i == 0 ? null : parseDate(_messages[i - 1]['created_at'])?.toLocal();
        final newDay = at != null && (prevAt == null || !DateUtils.isSameDay(at, prevAt));
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
            _Bubble(text: '${m['body'] ?? ''}', time: at, mine: mine),
            if (mine && i == lastMine && m['read_at'] != null)
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 6),
                child: Text('Seen', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInput() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                decoration: const InputDecoration(
                  hintText: 'Type a message',
                  counterText: '',
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'Send',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.text, required this.time, required this.mine});

  final String text;
  final DateTime? time;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final t = time;
    final hm = t == null
        ? ''
        : '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
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
              text,
              style: TextStyle(color: mine ? Colors.white : AppColors.text, fontSize: 15, height: 1.35),
            ),
            const SizedBox(height: 2),
            Text(hm, style: TextStyle(color: mine ? Colors.white70 : AppColors.muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
