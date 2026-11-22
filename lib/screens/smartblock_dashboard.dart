import 'package:flutter/material.dart' hide Text;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_review_screen.dart';
import 'admin_billing_screen.dart';
import 'properties_screen.dart';
import 'lease_renewals_screen.dart';
import 'support_chat_screen.dart';
import 'role_preview_screen.dart';
import 'property_modules_screen.dart';
import 'property_management_screen.dart';
import 'resident_service_requests_screen.dart';
import '../app_language.dart';
import '../smartblock_text.dart';
import '../smartblock_trial_session.dart';

class SmartBlockDashboard extends StatefulWidget {
  const SmartBlockDashboard({super.key});

  @override
  State<SmartBlockDashboard> createState() => _SmartBlockDashboardState();
}

class _SmartBlockDashboardState extends State<SmartBlockDashboard> {
  final _client = SmartBlockTrialSession.client;
  late Future<_RoleAccess> _access = _loadAccess();
  bool _greek = true;
  dynamic _roleRequestChannel;
  dynamic _billingNoticeChannel;
  dynamic _userNotificationChannel;
  late final VoidCallback _languageListener;
  late Future<List<Map<String, dynamic>>> _billingNotices;
  late Future<List<Map<String, dynamic>>> _userNotifications;

  @override
  void initState() {
    super.initState();
    final language = SmartBlockLanguageController.instance;
    _greek = language.selected.value.isGreek;
    _languageListener = () {
      if (mounted) setState(() => _greek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
    _billingNotices = _loadBillingNotices();
    _userNotifications = _loadUserNotifications();
    _refreshDueNotifications();
    _subscribeUserNotifications();
    _subscribeAdminNotifications();
    _subscribeBillingNotifications();
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(
      _languageListener,
    );
    if (_roleRequestChannel != null) {
      _client.removeChannel(_roleRequestChannel);
    }
    if (_billingNoticeChannel != null) {
      _client.removeChannel(_billingNoticeChannel);
    }
    if (_userNotificationChannel != null) {
      _client.removeChannel(_userNotificationChannel);
    }
    super.dispose();
  }

  Future<void> _refreshDueNotifications() async {
    try {
      await _client.rpc('refresh_property_due_notifications');
      if (mounted)
        setState(() => _userNotifications = _loadUserNotifications());
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _loadUserNotifications() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];
      return List<Map<String, dynamic>>.from(
        await _client
            .from('user_notifications')
            .select(
              'id,property_id,notification_type,title_el,title_en,message_el,message_en,is_read,created_at,related_type,related_id',
            )
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(40),
      );
    } catch (_) {
      return [];
    }
  }

  void _subscribeUserNotifications() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _userNotificationChannel = _client
        .channel('smartblock-user-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'user_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            if (!mounted) return;
            setState(() => _userNotifications = _loadUserNotifications());
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _greek
                      ? 'Έχεις νέα ειδοποίηση SmartBlock.'
                      : 'You have a new SmartBlock notification.',
                ),
                action: SnackBarAction(
                  label: _greek ? 'Προβολή' : 'View',
                  onPressed: _openNotificationInbox,
                ),
              ),
            );
          },
        )
        .subscribe();
  }

  Future<void> _markNotificationRead(String id) async {
    await _client
        .from('user_notifications')
        .update({'is_read': true})
        .eq('id', id);
    if (mounted) setState(() => _userNotifications = _loadUserNotifications());
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    final id = item['id'] as String?;
    if (id != null && item['is_read'] != true) {
      try {
        await _markNotificationRead(id);
      } catch (_) {}
    }
    if (!mounted) return;

    final type = item['notification_type'] as String? ?? '';
    final relatedType = item['related_type'] as String? ?? '';
    final relatedId = item['related_id'] as String?;
    final propertyId = item['property_id'] as String?;
    final isStaff = await _isStaff();

    if (type == 'registration' || relatedType == 'account_role_requests') {
      await _open(AdminReviewScreen(isGreek: _greek, initialTab: 1));
      return;
    }
    if (type == 'new_property') {
      await _open(AdminReviewScreen(isGreek: _greek, initialTab: 2));
      return;
    }
    if (relatedType == 'support_messages' && relatedId != null) {
      await _openSupportNotification(relatedId, isStaff: isStaff);
      return;
    }
    if (type.startsWith('lease_') || relatedType.contains('lease_renewal')) {
      await _open(LeaseRenewalsScreen(isGreek: _greek, isStaff: isStaff));
      return;
    }
    if (propertyId == null) {
      await _open(SupportChatScreen(isGreek: _greek));
      return;
    }

    if (relatedType == 'property_service_requests' || type == 'damage') {
      if (isStaff || await _canManageProperty(propertyId)) {
        await _open(
          await _managementScreen(propertyId, focus: 'service_request'),
        );
      } else {
        final request = relatedId == null
            ? null
            : await _client
                  .from('property_service_requests')
                  .select('apartment_number')
                  .eq('id', relatedId)
                  .maybeSingle();
        final residentRows = List<Map<String, dynamic>>.from(
          await _client.rpc('list_my_resident_properties'),
        );
        final residentMatches = residentRows.where(
          (row) => row['property_id'] == propertyId,
        );
        final resident = residentMatches.isEmpty ? null : residentMatches.first;
        await _open(
          ResidentServiceRequestsScreen(
            propertyId: propertyId,
            propertyName: await _propertyName(propertyId),
            apartmentNumber:
                (request?['apartment_number'] as String?) ??
                (resident?['apartment_number'] as String? ?? ''),
            isGreek: _greek,
          ),
        );
      }
      return;
    }
    if (relatedType == 'property_meetings' || type == 'meeting') {
      await _open(await _managementScreen(propertyId, focus: 'meeting'));
      return;
    }

    final moduleTab = switch (relatedType) {
      'property_votes' => 0,
      'property_notes' => 1,
      'property_charge_entries' || 'property_charge_runs' => 2,
      'property_rent_installments' || 'property_rent_contracts' => 3,
      _ => switch (type) {
        'vote' => 0,
        'announcement' => 1,
        'charges_due' ||
        'charges_overdue' ||
        'building_charges_due' ||
        'building_charges_overdue' => 2,
        'rent_due' || 'rent_overdue' => 3,
        _ => -1,
      },
    };
    if (moduleTab >= 0) {
      await _open(
        PropertyModulesScreen(
          propertyId: propertyId,
          propertyName: await _propertyName(propertyId),
          isGreek: _greek,
          initialTab: moduleTab,
        ),
      );
    } else {
      await _open(await _managementScreen(propertyId));
    }
  }

  Future<bool> _canManageProperty(String propertyId) async {
    try {
      return await _client.rpc(
            'can_manage_property',
            params: {'target_property_id': propertyId},
          ) ==
          true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isStaff() async {
    try {
      return await _client.rpc('is_smartblock_staff') == true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _propertyName(String propertyId) async {
    try {
      final row = await _client
          .from('properties')
          .select('name')
          .eq('id', propertyId)
          .maybeSingle();
      return row?['name'] as String? ?? (_greek ? 'Ακίνητο' : 'Property');
    } catch (_) {
      return _greek ? 'Ακίνητο' : 'Property';
    }
  }

  Future<PropertyManagementScreen> _managementScreen(
    String propertyId, {
    String? focus,
  }) async {
    String name = _greek ? 'Διαχείριση ακινήτου' : 'Property management';
    int? totalApartments;
    try {
      final property = await _client
          .from('properties')
          .select('name,total_apartments')
          .eq('id', propertyId)
          .maybeSingle();
      name = property?['name'] as String? ?? name;
      totalApartments = (property?['total_apartments'] as num?)?.toInt();
    } catch (_) {}
    return PropertyManagementScreen(
      propertyId: propertyId,
      propertyName: name,
      totalApartments: totalApartments,
      isGreek: _greek,
      initialSection: focus,
    );
  }

  Future<void> _openSupportNotification(
    String messageId, {
    required bool isStaff,
  }) async {
    try {
      final message = await _client
          .from('support_messages')
          .select('conversation_id')
          .eq('id', messageId)
          .maybeSingle();
      final conversationId = message?['conversation_id'] as String?;
      if (conversationId == null) {
        await _open(SupportChatScreen(isGreek: _greek));
        return;
      }
      final conversations = List<Map<String, dynamic>>.from(
        await _client.rpc('list_support_conversations'),
      );
      final matches = conversations.where(
        (row) => row['conversation_id'] == conversationId,
      );
      if (matches.isEmpty) {
        await _open(SupportChatScreen(isGreek: _greek));
        return;
      }
      final conversation = matches.first;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SupportConversationScreen(
            conversationId: conversationId,
            subject: conversation['subject'] as String? ?? '',
            status: conversation['status'] as String? ?? 'open',
            userEmail: conversation['user_email'] as String? ?? '',
            isStaff: isStaff,
            isGreek: _greek,
          ),
        ),
      );
    } catch (_) {
      if (mounted) await _open(SupportChatScreen(isGreek: _greek));
    }
  }

  Future<void> _openNotificationInbox() async {
    final notifications = await _userNotifications;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined),
                    const SizedBox(width: 10),
                    Text(
                      _greek ? 'Ειδοποιήσεις' : 'Notifications',
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: notifications.isEmpty
                    ? Center(
                        child: Text(
                          _greek
                              ? 'Δεν υπάρχουν ειδοποιήσεις.'
                              : 'No notifications yet.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final item = notifications[index];
                          final greek = _greek;
                          final createdAt = item['created_at'] as String? ?? '';
                          final timestamp = createdAt.length > 16
                              ? createdAt
                                    .substring(0, 16)
                                    .replaceFirst('T', ' ')
                              : createdAt.replaceFirst('T', ' ');
                          return ListTile(
                            leading: Icon(
                              item['is_read'] == true
                                  ? Icons.notifications_none
                                  : Icons.notifications_active,
                              color: item['is_read'] == true
                                  ? null
                                  : Theme.of(context).colorScheme.primary,
                            ),
                            title: Text(
                              (greek ? item['title_el'] : item['title_en'])
                                      as String? ??
                                  '',
                            ),
                            subtitle: Text(
                              (greek ? item['message_el'] : item['message_en'])
                                      as String? ??
                                  '',
                            ),
                            trailing: Text(timestamp),
                            onTap: () {
                              Navigator.of(context).pop();
                              _openNotification(item);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadBillingNotices() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];
      return List<Map<String, dynamic>>.from(
        await _client
            .from('property_billing_notifications')
            .select(
              'id, property_id, apartment_monthly_eur, online_payment_fee_percent, effective_on, notification_kind, properties(name)',
            )
            .eq('recipient_id', userId)
            .eq('is_read', false)
            .order('created_at', ascending: false)
            .limit(10),
      );
    } catch (_) {
      return [];
    }
  }

  void _subscribeBillingNotifications() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    _billingNoticeChannel = _client
        .channel('smartblock-billing-notices-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'property_billing_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (_) {
            if (mounted)
              setState(() => _billingNotices = _loadBillingNotices());
          },
        )
        .subscribe();
  }

  Future<void> _markBillingNoticeRead(String id) async {
    try {
      await _client
          .from('property_billing_notifications')
          .update({'is_read': true})
          .eq('id', id);
      if (mounted) setState(() => _billingNotices = _loadBillingNotices());
    } catch (_) {}
  }

  Future<void> _enableBiometrics() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || kIsWeb) return;
    try {
      final auth = LocalAuthentication();
      if ((await auth.getAvailableBiometrics()).isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _greek
                  ? 'Δεν βρέθηκε ενεργό Face ID ή δακτυλικό αποτύπωμα στη συσκευή.'
                  : 'No enrolled Face ID or fingerprint was found on this device.',
            ),
          ),
        );
        return;
      }
      final success = await auth.authenticate(
        localizedReason: _greek
            ? 'Επιβεβαίωσε για να ενεργοποιήσεις το βιομετρικό ξεκλείδωμα SmartBlock.'
            : 'Authenticate to enable SmartBlock biometric unlock.',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!success) return;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool('smartblock_biometric_$userId', true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Το βιομετρικό ξεκλείδωμα ενεργοποιήθηκε σε αυτή τη συσκευή.'
                : 'Biometric unlock is enabled on this device.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Δεν ήταν δυνατή η ενεργοποίηση. Έλεγξε τις ρυθμίσεις βιομετρικών της συσκευής.'
                : 'Could not enable biometrics. Check this device’s biometric settings.',
          ),
        ),
      );
    }
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
      _client.rpc('is_smartblock_admin'),
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
      isAdmin: results[4] == true,
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

  Future<void> _leaveTrial() async {
    await SmartBlockTrialSession.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('SmartBlock'),
      actions: [
        const SmartBlockLanguageMenu(),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _userNotifications,
          builder: (context, snapshot) {
            final unread = (snapshot.data ?? const [])
                .where((item) => item['is_read'] != true)
                .length;
            return IconButton(
              tooltip: _greek ? 'Ειδοποιήσεις' : 'Notifications',
              onPressed: _openNotificationInbox,
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text(unread > 9 ? '9+' : '$unread'),
                child: const Icon(Icons.notifications_outlined),
              ),
            );
          },
        ),
        if (!kIsWeb)
          IconButton(
            tooltip: _greek
                ? 'Ενεργοποίηση Face ID / δακτυλικού'
                : 'Enable Face ID / fingerprint',
            onPressed: _enableBiometrics,
            icon: const Icon(Icons.fingerprint),
          ),
        if (SmartBlockTrialSession.isActive)
          IconButton(
            tooltip: _greek ? 'Επιστροφή στον admin' : 'Return to admin',
            onPressed: _leaveTrial,
            icon: const Icon(Icons.admin_panel_settings_outlined),
          )
        else
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
        final showOwner = approvedRoles.contains('property_owner') ||
            (registration == null && access.ownerHasProperties);
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
            if (SmartBlockTrialSession.isActive)
              Card(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(
                    _greek
                        ? 'ΔΟΚΙΜΗ · ${SmartBlockTrialSession.role == 'owner' ? 'Ιδιοκτήτης' : 'Ενοικιαστής'}'
                        : 'TRIAL · ${SmartBlockTrialSession.role == 'owner' ? 'Owner' : 'Tenant'}',
                  ),
                  subtitle: Text(
                    _greek
                        ? 'Δοκιμαστικός λογαριασμός και δοκιμαστικά στοιχεία.'
                        : 'Test account and sample data.',
                  ),
                  trailing: TextButton(
                    onPressed: _leaveTrial,
                    child: Text(_greek ? 'Έξοδος' : 'Exit'),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF245B73), Color(0xFF438F83)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF245B73).withOpacity(.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.16),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.apartment_rounded,
                      color: Colors.white,
                      size: 29,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _greek
                              ? 'Πού θέλεις να πας;'
                              : 'Where would you like to go?',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _greek
                              ? 'Οι λειτουργίες εμφανίζονται ανάλογα με τον ρόλο και την πρόσβασή σου.'
                              : 'Your features are organized around your role and access.',
                          style: const TextStyle(
                            color: Color(0xFFE6F1F0),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (access.isAdmin)
              _RoleCard(
                icon: Icons.visibility_outlined,
                title: _greek ? 'Προβολή ως χρήστης' : 'Preview as user',
                detail: _greek
                    ? 'Μπες σε ξεχωριστό δοκιμαστικό λογαριασμό με πραγματικά δικαιώματα.'
                    : 'Enter a separate trial account with real permissions.',
                onTap: () => _open(const RolePreviewScreen()),
              ),
            if (access.isAdmin)
              _RoleCard(
                icon: Icons.price_change_outlined,
                title: _greek ? 'Χρεώσεις SmartBlock' : 'SmartBlock billing',
                detail: _greek
                    ? 'Ρύθμισε τιμή ανά διαμέρισμα, προμήθεια και ημερομηνίες ισχύος.'
                    : 'Set per-apartment pricing, payment fee and effective dates.',
                onTap: () => _open(const AdminBillingScreen()),
              )
            else
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _billingNotices,
                builder: (context, noticeSnapshot) {
                  final notices = noticeSnapshot.data ?? const [];
                  if (notices.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: notices.map((notice) {
                      final property =
                          notice['properties'] as Map<String, dynamic>? ?? {};
                      final name =
                          property['name'] as String? ??
                          (_greek ? 'Το ακίνητό σου' : 'Your property');
                      final wasCancelled =
                          notice['notification_kind'] == 'cancelled';
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: Text(
                            wasCancelled
                                ? (_greek
                                      ? 'Ακυρώθηκε αλλαγή χρεώσεων · $name'
                                      : 'Billing change cancelled · $name')
                                : (_greek
                                      ? 'Ενημέρωση χρεώσεων · $name'
                                      : 'Billing update · $name'),
                          ),
                          subtitle: Text(
                            wasCancelled
                                ? (_greek
                                      ? 'Η προγραμματισμένη αλλαγή για ${notice['effective_on']} ακυρώθηκε. Ισχύουν οι προηγούμενες χρεώσεις.'
                                      : 'The scheduled change for ${notice['effective_on']} was cancelled. The previous rates remain in effect.')
                                : (_greek
                                      ? 'Από ${notice['effective_on']}: €${notice['apartment_monthly_eur']} ανά διαμέρισμα/μήνα και προμήθεια ${notice['online_payment_fee_percent']}%.'
                                      : 'From ${notice['effective_on']}: €${notice['apartment_monthly_eur']} per apartment/month and a ${notice['online_payment_fee_percent']}% payment fee.'),
                          ),
                          trailing: IconButton(
                            tooltip: _greek ? 'Εντάξει' : 'Dismiss',
                            icon: const Icon(Icons.done),
                            onPressed: () =>
                                _markBillingNoticeRead(notice['id'] as String),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            const SizedBox(height: 8),
            _RoleCard(
              icon: Icons.edit_document,
              title: _greek ? 'Ανανεώσεις μισθώσεων' : 'Lease renewals',
              detail: _greek
                  ? 'Δες και αποδέξου ηλεκτρονικά τις ανανεώσεις που αφορούν τον λογαριασμό σου.'
                  : 'Review and electronically accept renewals linked to your account.',
              onTap: () => _open(
                LeaseRenewalsScreen(isGreek: _greek, isStaff: access.isStaff),
              ),
            ),
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
    required this.isAdmin,
    required this.residentCount,
    required this.ownerHasProperties,
    required this.registration,
  });

  final bool isStaff;
  final bool isAdmin;
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final iconColor = icon == Icons.home_outlined
        ? const Color(0xFF438F83)
        : colors.primary;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 12,
        ),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(.11),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: iconColor, size: 26),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF17364A),
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            detail,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.35),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: colors.primary.withOpacity(.7),
        ),
        onTap: onTap,
      ),
    );
  }
}
\n