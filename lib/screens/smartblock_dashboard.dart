import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_review_screen.dart';
import 'properties_screen.dart';
import 'support_chat_screen.dart';

class SmartBlockDashboard extends StatefulWidget {
  const SmartBlockDashboard({super.key});

  @override
  State<SmartBlockDashboard> createState() => _SmartBlockDashboardState();
}

class _SmartBlockDashboardState extends State<SmartBlockDashboard> {
  final _client = Supabase.instance.client;
  late Future<_RoleAccess> _access = _loadAccess();
  bool _greek = true;
  dynamic _roleRequestChannel;

  @override
  void initState() {
    super.initState();
    _subscribeAdminNotifications();
  }

  @override
  void dispose() {
    if (_roleRequestChannel != null) {
      _client.removeChannel(_roleRequestChannel);
    }
    super.dispose();
  }

  Future<void> _subscribeAdminNotifications() async {
    try {
      if (await _client.rpc('is_smartblock_admin') != true || !mounted) return;
      _roleRequestChannel = _client
          .channel('smartblock-registration-requests')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'account_role_requests',
            callback: (_) {
              if (!mounted) return;
              setState(() => _access = _loadAccess());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _greek
                        ? 'Νέα εγγραφή περιμένει έγκριση.'
                        : 'A new registration is waiting for approval.',
                  ),
                  action: SnackBarAction(
                    label: _greek ? 'Προβολή' : 'View',
                    onPressed: () => _open(AdminReviewScreen(isGreek: _greek)),
                  ),
                ),
              );
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'property_manager_requests',
            callback: (_) {
              if (!mounted) return;
              setState(() => _access = _loadAccess());
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _greek
                        ? 'Νέο αίτημα επαλήθευσης διαχειριστή.'
                        : 'A new building manager claim needs review.',
                  ),
                  action: SnackBarAction(
                    label: _greek ? 'Προβολή' : 'View',
                    onPressed: () => _open(AdminReviewScreen(isGreek: _greek)),
                  ),
                ),
              );
            },
          )
          .subscribe();
    } catch (_) {
      // The dashboard still shows pending requests if realtime is unavailable.
    }
  }

  Future<_RoleAccess> _loadAccess() async {
    final results = await Future.wait<dynamic>([
      _client.rpc('is_smartblock_staff'),
      _client.rpc('list_my_resident_properties'),
      _client.from('properties').select('id').limit(1),
      _client.rpc('list_my_account_role_request'),
    ]);
    var requestRows = List<Map<String, dynamic>>.from(results[3] as List);
    if (requestRows.isEmpty &&
        (results[1] as List).isEmpty &&
        (results[2] as List).isEmpty) {
      final rolesFromOAuth =
          (Uri.base.queryParameters['sb_requested_roles'] ?? '')
              .split(',')
              .where((role) => role == 'property_owner' || role == 'tenant')
              .toSet()
              .toList();
      if (rolesFromOAuth.isNotEmpty) {
        try {
          await _client.rpc(
            'submit_account_role_request',
            params: {'p_requested_roles': rolesFromOAuth},
          );
          requestRows = List<Map<String, dynamic>>.from(
            await _client.rpc('list_my_account_role_request'),
          );
        } catch (_) {}
      }
    }
    return _RoleAccess(
      isStaff: results[0] == true,
      residentCount: (results[1] as List).length,
      ownerHasProperties: (results[2] as List).isNotEmpty,
      registration: requestRows.isEmpty ? null : requestRows.first,
    );
  }

  Future<void> _requestRoles({List<String> initialRoles = const []}) async {
    final selected = initialRoles.toSet();
    final roles = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(_greek ? 'Δήλωση ρόλου' : 'Choose your role'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _greek
                    ? 'Ο admin θα ελέγξει τη δήλωσή σου πριν ενεργοποιηθεί η πρόσβαση.'
                    : 'An administrator will review your selection before access is enabled.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    selected: selected.contains('property_owner'),
                    avatar: const Icon(Icons.apartment_outlined),
                    label: Text(_greek ? 'Ιδιοκτήτης' : 'Property owner'),
                    onSelected: (value) => setDialog(() {
                      if (value) {
                        selected.add('property_owner');
                      } else {
                        selected.remove('property_owner');
                      }
                    }),
                  ),
                  FilterChip(
                    selected: selected.contains('tenant'),
                    avatar: const Icon(Icons.home_outlined),
                    label: Text(_greek ? 'Ενοικιαστής' : 'Tenant'),
                    onSelected: (value) => setDialog(() {
                      if (value) {
                        selected.add('tenant');
                      } else {
                        selected.remove('tenant');
                      }
                    }),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_greek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, selected.toList()),
              child: Text(
                _greek ? 'Αποστολή για έγκριση' : 'Submit for review',
              ),
            ),
          ],
        ),
      ),
    );
    if (roles == null) return;
    try {
      await _client.rpc(
        'submit_account_role_request',
        params: {'p_requested_roles': roles},
      );
      if (!mounted) return;
      setState(() => _access = _loadAccess());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Η δήλωση στάλθηκε στον admin για έγκριση.'
                : 'Your role selection was sent for administrator approval.',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
    if (mounted) setState(() => _access = _loadAccess());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SmartBlock'),
      actions: [
        IconButton(
          tooltip: _greek ? 'English' : 'Ελληνικά',
          onPressed: () => setState(() => _greek = !_greek),
          icon: const Icon(Icons.language),
        ),
        IconButton(
          tooltip: _greek ? 'Αποσύνδεση' : 'Sign out',
          onPressed: () => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: FutureBuilder<_RoleAccess>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 42),
                  const SizedBox(height: 12),
                  Text(
                    _greek
                        ? 'Δεν φορτώθηκαν οι προσβάσεις. Έλεγξε τη σύνδεση.'
                        : 'Could not load your access. Check your connection.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => setState(() => _access = _loadAccess()),
                    child: Text(_greek ? 'Δοκιμή ξανά' : 'Try again'),
                  ),
                ],
              ),
            ),
          );
        }

        final access = snapshot.data!;
        final registration = access.registration;
        final status = registration?['status'] as String?;
        final approvedRoles = List<String>.from(
          (registration?['requested_roles'] as List?) ?? const [],
        );
        final showOwner =
            approvedRoles.contains('property_owner') || access.ownerHasProperties;
        final showResident =
            approvedRoles.contains('tenant') ||
            (status == null && access.residentCount > 0);
        final needsRoleRequest =
            status == 'rejected' ||
            (status == null &&
                !access.ownerHasProperties &&
                access.residentCount == 0);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            Text(
              _greek ? 'Πού θέλεις να πας;' : 'Where would you like to go?',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _greek
                  ? 'Οι λειτουργίες εμφανίζονται ανάλογα με τον ρόλο και την πρόσβασή σου.'
                  : 'Features are separated by your role and assigned access.',
            ),
            const SizedBox(height: 20),
            _RoleCard(
              icon: Icons.support_agent_outlined,
              title: access.isStaff
                  ? (_greek ? 'Υποστήριξη χρηστών' : 'Support inbox')
                  : (_greek ? 'Βοήθεια & chat' : 'Help chat'),
              detail: access.isStaff
                  ? (_greek
                        ? 'Δες και απάντησε στα αιτήματα βοήθειας.'
                        : 'View and reply to user help requests.')
                  : (_greek
                        ? 'Στείλε μήνυμα στην ομάδα SmartBlock.'
                        : 'Message the SmartBlock support team.'),
              onTap: () => _open(SupportChatScreen(isGreek: _greek)),
            ),
            if (access.isStaff)
              _RoleCard(
                icon: Icons.admin_panel_settings_outlined,
                title: _greek ? 'Διαχείριση SmartBlock' : 'SmartBlock admin',
                detail: _greek
                    ? 'Εγκρίσεις, ακίνητα, οργανισμοί και προσβάσεις.'
                    : 'Reviews, properties, organizations and access.',
                onTap: () => _open(AdminReviewScreen(isGreek: _greek)),
              ),
            if (status == 'pending')
              Card(
                child: ListTile(
                  leading: const Icon(Icons.hourglass_top_outlined),
                  title: Text(
                    _greek
                        ? 'Η δήλωσή σου ελέγχεται'
                        : 'Your role selection is under review',
                  ),
                  subtitle: Text(
                    _greek
                        ? 'Θα ενεργοποιηθούν οι αντίστοιχες λειτουργίες μόλις εγκρίνει ο admin.'
                        : 'Your role features will be enabled after administrator approval.',
                  ),
                ),
              ),
            if (status == 'approved' &&
                approvedRoles.contains('tenant') &&
                access.residentCount == 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(
                    _greek
                        ? 'Αναμένεται σύνδεση διαμερίσματος'
                        : 'Waiting for an apartment assignment',
                  ),
                  subtitle: Text(
                    _greek
                        ? 'Ο διαχειριστής της πολυκατοικίας θα συνδέσει το email σου με το διαμέρισμα.'
                        : 'Your building manager will connect your account to your apartment.',
                  ),
                ),
              ),
            if (showOwner)
              _RoleCard(
                icon: Icons.apartment_outlined,
                title: _greek ? 'Ιδιοκτήτης / διαχειριστής' : 'Owner / manager',
                detail: _greek
                    ? 'Ακίνητα, ιδιοκτήτες, ψηφοφορίες, ανακοινώσεις και οικονομικά.'
                    : 'Properties, owners, votes, notices and finances.',
                onTap: () => _open(
                  PropertiesScreen(
                    isGreek: _greek,
                    viewMode: PropertiesViewMode.owner,
                  ),
                ),
              ),
            if (showResident)
              _RoleCard(
                icon: Icons.home_outlined,
                title: _greek ? 'Ένοικος' : 'Resident',
                detail: _greek
                    ? 'Το διαμέρισμά σου, αναφορές βλαβών και αιτήματα υπηρεσιών.'
                    : 'Your apartment, problem reports and service requests.',
                onTap: () => _open(
                  PropertiesScreen(
                    isGreek: _greek,
                    viewMode: PropertiesViewMode.resident,
                  ),
                ),
              ),
            if (needsRoleRequest)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.how_to_reg_outlined),
                  title: Text(
                    status == 'rejected'
                        ? (_greek
                              ? 'Η δήλωση απορρίφθηκε'
                              : 'Role request declined')
                        : (_greek ? 'Δήλωσε τον ρόλο σου' : 'Choose your role'),
                  ),
                  subtitle: Text(
                    status == 'rejected'
                        ? (registration?['review_note'] as String? ??
                              (_greek
                                  ? 'Μπορείς να στείλεις νέα δήλωση.'
                                  : 'You can submit a new selection.'))
                        : (_greek
                              ? 'Επίλεξε ιδιοκτήτης, ενοικιαστής ή και τα δύο. Ο admin θα εξετάσει τη δήλωση.'
                              : 'Select owner, tenant, or both. An administrator will review it.'),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () => _requestRoles(
                      initialRoles: List<String>.from(
                        (registration?['requested_roles'] as List?) ?? const [],
                      ),
                    ),
                    child: Text(_greek ? 'Δήλωση' : 'Choose'),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _RoleAccess {
  const _RoleAccess({
    required this.isStaff,
    required this.residentCount,
    required this.ownerHasProperties,
    required this.registration,
  });

  final bool isStaff;
  final int residentCount;
  final bool ownerHasProperties;
  final Map<String, dynamic>? registration;
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text(detail),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
