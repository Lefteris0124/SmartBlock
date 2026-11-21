import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({required this.isGreek, super.key});

  final bool isGreek;

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _db = Supabase.instance.client;
  late final Future<bool> _staff = _loadStaff();
  late Future<List<Map<String, dynamic>>> _conversations = _loadConversations();
  dynamic _channel;
  bool get gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) _db.removeChannel(_channel);
    super.dispose();
  }

  Future<bool> _loadStaff() async =>
      await _db.rpc('is_smartblock_staff') == true;

  Future<List<Map<String, dynamic>>> _loadConversations() async =>
      List<Map<String, dynamic>>.from(
        await _db.rpc('list_support_conversations'),
      );

  void _subscribe() {
    _channel = _db
        .channel('support-inbox-${_db.auth.currentUser?.id ?? 'guest'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'support_messages',
          callback: (_) {
            if (mounted) setState(() => _conversations = _loadConversations());
          },
        )
        .subscribe();
  }

  Future<void> _refresh() async {
    final pending = _loadConversations();
    setState(() => _conversations = pending);
    try {
      await pending;
    } catch (_) {}
  }

  Future<void> _newConversation() async {
    final subject = TextEditingController();
    final message = TextEditingController();
    final form = GlobalKey<FormState>();
    var sending = false;
    String? newId;
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(gr ? 'Νέο αίτημα βοήθειας' : 'Start a help chat'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: subject,
                    maxLength: 120,
                    decoration: InputDecoration(
                      labelText: gr ? 'Θέμα' : 'Subject',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? (gr
                              ? 'Γράψε ένα σύντομο θέμα.'
                              : 'Enter a short subject.')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: message,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 4000,
                    decoration: InputDecoration(
                      labelText: gr
                          ? 'Πώς μπορούμε να βοηθήσουμε;'
                          : 'How can we help?',
                      alignLabelWithHint: true,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? (gr ? 'Γράψε το μήνυμά σου.' : 'Enter your message.')
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton.icon(
              onPressed: sending
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setDialog(() => sending = true);
                      try {
                        newId = await _db.rpc(
                          'create_support_conversation',
                          params: {
                            'p_subject': subject.text.trim(),
                            'p_initial_message': message.text.trim(),
                          },
                        ) as String?;
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, newId != null);
                        }
                      } on PostgrestException catch (error) {
                        if (dialogContext.mounted) {
                          setDialog(() => sending = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      }
                    },
              icon: sending
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(gr ? 'Αποστολή' : 'Send'),
            ),
          ],
        ),
      ),
    );
    final newSubject = subject.text.trim();
    subject.dispose();
    message.dispose();
    if (created == true && newId != null && mounted) {
      await _openConversation({
        'conversation_id': newId,
        'subject': newSubject,
        'status': 'open',
        'user_email': _db.auth.currentUser?.email ?? '',
      }, isStaff: false);
    }
  }

  Future<void> _openConversation(
    Map<String, dynamic> conversation, {
    required bool isStaff,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupportConversationScreen(
          conversationId: conversation['conversation_id'] as String,
          subject: conversation['subject'] as String? ?? '',
          status: conversation['status'] as String? ?? 'open',
          userEmail: conversation['user_email'] as String? ?? '',
          isStaff: isStaff,
          isGreek: gr,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  String _statusLabel(String? status) => gr
      ? (status == 'closed' ? 'Ολοκληρώθηκε' : 'Ανοιχτό')
      : (status == 'closed' ? 'Closed' : 'Open');

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _staff,
    builder: (context, staffSnapshot) {
      final isStaff = staffSnapshot.data == true;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            isStaff
                ? (gr ? 'Υποστήριξη χρηστών' : 'Support inbox')
                : (gr ? 'Βοήθεια' : 'Help chat'),
          ),
        ),
        floatingActionButton:
            isStaff || staffSnapshot.connectionState == ConnectionState.waiting
            ? null
            : FloatingActionButton.extended(
                onPressed: _newConversation,
                icon: const Icon(Icons.chat_outlined),
                label: Text(gr ? 'Νέο αίτημα' : 'New request'),
              ),
        body: staffSnapshot.hasError
            ? _errorView()
            : RefreshIndicator(
                onRefresh: _refresh,
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _conversations,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return ListView(
                        children: [
                          SizedBox(height: 220),
                          Center(child: CircularProgressIndicator()),
                        ],
                      );
                    }
                    if (snapshot.hasError) return _errorView();
                    final rows = snapshot.data ?? const [];
                    if (rows.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(28),
                        children: [
                          const SizedBox(height: 80),
                          Icon(
                            Icons.support_agent_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isStaff
                                ? (gr
                                      ? 'Δεν υπάρχουν αιτήματα υποστήριξης.'
                                      : 'No support requests yet.')
                                : (gr ? 'Χρειάζεσαι βοήθεια;' : 'Need a hand?'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isStaff
                                ? (gr
                                      ? 'Τα νέα αιτήματα θα εμφανιστούν εδώ.'
                                      : 'New requests will appear here.')
                                : (gr
                                      ? 'Στείλε μας μήνυμα και θα σου απαντήσουμε εδώ.'
                                      : 'Send us a message and we will reply here.'),
                            textAlign: TextAlign.center,
                          ),
                          if (!isStaff) ...[
                            const SizedBox(height: 20),
                            Center(
                              child: FilledButton.icon(
                                onPressed: _newConversation,
                                icon: const Icon(Icons.chat_outlined),
                                label: Text(
                                  gr
                                      ? 'Νέο αίτημα βοήθειας'
                                      : 'Start a help chat',
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    }
                    return ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final customer = row['user_email'] as String? ?? '';
                        final lastMessage =
                            row['last_message'] as String? ?? '';
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              child: Icon(
                                row['status'] == 'closed'
                                    ? Icons.check_circle_outline
                                    : Icons.chat_bubble_outline,
                              ),
                            ),
                            title: Text(row['subject'] as String? ?? ''),
                            subtitle: Text(
                              [
                                if (isStaff) customer,
                                '${_statusLabel(row['status'] as String?)} · $lastMessage',
                              ].where((part) => part.isNotEmpty).join('\n'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: isStaff,
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () =>
                                _openConversation(row, isStaff: isStaff),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
      );
    },
  );

  Widget _errorView() => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(28),
    children: [
      const SizedBox(height: 90),
      const Icon(Icons.cloud_off_outlined, size: 48),
      const SizedBox(height: 12),
      Text(
        gr ? 'Δεν φορτώθηκε η συνομιλία.' : 'Could not load support chat.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Center(
        child: FilledButton.tonal(
          onPressed: _refresh,
          child: Text(gr ? 'Δοκιμή ξανά' : 'Try again'),
        ),
      ),
    ],
  );
}

class SupportConversationScreen extends StatefulWidget {
  const SupportConversationScreen({
    required this.conversationId,
    required this.subject,
    required this.status,
    required this.userEmail,
    required this.isStaff,
    required this.isGreek,
    super.key,
  });

  final String conversationId;
  final String subject;
  final String status;
  final String userEmail;
  final bool isStaff;
  final bool isGreek;

  @override
  State<SupportConversationScreen> createState() =>
      _SupportConversationScreenState();
}

class _SupportConversationScreenState extends State<SupportConversationScreen> {
  final _db = Supabase.instance.client;
  final _messageController = TextEditingController();
  late Future<List<Map<String, dynamic>>> _messages = _loadMessages();
  late String _status = widget.status;
  dynamic _channel;
  bool _sending = false;
  bool get gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _channel = _db
        .channel('support-chat-${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) {
            if (mounted) setState(() => _messages = _loadMessages());
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _messageController.dispose();
    if (_channel != null) _db.removeChannel(_channel);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadMessages() async =>
      List<Map<String, dynamic>>.from(
        await _db
            .from('support_messages')
            .select('id,sender_id,body,created_at')
            .eq('conversation_id', widget.conversationId)
            .order('created_at'),
      );

  Future<void> _refreshMessages() async {
    final pending = _loadMessages();
    setState(() => _messages = pending);
    try {
      await pending;
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _db.rpc(
        'send_support_message',
        params: {'p_conversation_id': widget.conversationId, 'p_body': body},
      );
      _messageController.clear();
      if (mounted) setState(() => _messages = _loadMessages());
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _changeStatus() async {
    final next = _status == 'open' ? 'closed' : 'open';
    try {
      await _db.rpc(
        'set_support_conversation_status',
        params: {'p_conversation_id': widget.conversationId, 'p_status': next},
      );
      if (mounted) setState(() => _status = next);
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  String _timeLabel(dynamic value) {
    final time = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (time == null) return '';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _db.auth.currentUser?.id;
    final closedForUser = _status == 'closed' && !widget.isStaff;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              widget.isStaff
                  ? widget.userEmail
                  : (_status == 'closed'
                        ? (gr ? 'Ολοκληρώθηκε' : 'Closed')
                        : (gr
                              ? 'Σε αναμονή απάντησης'
                              : 'Waiting for support')),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (widget.isStaff)
            IconButton(
              tooltip: _status == 'open'
                  ? (gr ? 'Ολοκλήρωση αιτήματος' : 'Close request')
                  : (gr ? 'Άνοιγμα ξανά' : 'Reopen request'),
              onPressed: _changeStatus,
              icon: Icon(
                _status == 'open' ? Icons.check_circle_outline : Icons.refresh,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshMessages,
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _messages,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        gr
                            ? 'Δεν φορτώθηκαν τα μηνύματα.'
                            : 'Could not load messages.',
                      ),
                    );
                  }
                  final messages = snapshot.data ?? const [];
                  if (messages.isEmpty) {
                    return Center(
                      child: Text(
                        gr
                            ? 'Ξεκίνησε τη συνομιλία.'
                            : 'Start the conversation.',
                      ),
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      final mine = message['sender_id'] == currentUserId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .82,
                          ),
                          child: Card(
                            color: mine
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    mine
                                        ? (gr ? 'Εσύ' : 'You')
                                        : (widget.isStaff
                                              ? widget.userEmail
                                              : 'SmartBlock'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  SelectableText(
                                    message['body'] as String? ?? '',
                                  ),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(
                                      _timeLabel(message['created_at']),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          if (closedForUser)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  gr
                      ? 'Το αίτημα ολοκληρώθηκε. Αν χρειάζεσαι επιπλέον βοήθεια, άνοιξε νέο αίτημα.'
                      : 'This request is closed. Start a new chat if you need more help.',
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: gr ? 'Γράψε μήνυμα…' : 'Write a message…',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      tooltip: gr ? 'Αποστολή' : 'Send',
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
