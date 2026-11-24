import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';
import '../app_language.dart';
import '../smartblock_text.dart';

import 'property_owners_screen.dart';
import 'property_modules_screen.dart';
import 'property_management_screen.dart';
import 'property_apartments_screen.dart';

class _ReviewReadiness {
  const _ReviewReadiness({
    required this.activeShareTotal,
    required this.primaryOwnerStatus,
    required this.declarationsComplete,
    required this.apartmentCountsMatch,
    required this.ownerAccountsReady,
  });

  final double activeShareTotal;
  final String? primaryOwnerStatus;
  final bool declarationsComplete;
  final bool apartmentCountsMatch;
  final bool ownerAccountsReady;
}

class PropertyDetailsScreen extends StatefulWidget {
  const PropertyDetailsScreen({
    required this.property,
    this.organizationId,
    required this.organizationName,
    required this.organizationApprovalStatus,
    required this.isGreek,
    super.key,
  });

  final Map<String, dynamic> property;
  final String? organizationId;
  final String organizationName;
  final String organizationApprovalStatus;
  final bool isGreek;

  @override
  State<PropertyDetailsScreen> createState() => _PropertyDetailsScreenState();
}

class _PropertyDetailsScreenState extends State<PropertyDetailsScreen> {
  final SupabaseClient _client = SmartBlockTrialSession.client;
  late Map<String, dynamic> _property;
  late bool _isGreek;
  late Future<_ReviewReadiness> _reviewReadinessFuture;
  late Future<List<Map<String, dynamic>>> _ownersFuture;
  late Future<bool> _canManageProperty;
  late Future<bool> _ownerAccountsReady;
  late Future<bool> _isLinkedOwner;
  bool _isSubmitting = false;
  late final VoidCallback _languageListener;

  @override
  void initState() {
    super.initState();
    _property = Map<String, dynamic>.from(widget.property);
    final language = SmartBlockLanguageController.instance;
    _isGreek = language.selected.value.isGreek;
    _languageListener = () {
      if (mounted) setState(() => _isGreek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
    _reviewReadinessFuture = _loadReviewReadiness();
    _ownersFuture = _loadOwners();
    _isLinkedOwner = _ownersFuture.then((owners) {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return false;
      return owners.any((owner) {
        if (owner['ownership_status'] != 'active') return false;
        final accounts = List<Map<String, dynamic>>.from(
          (owner['registered_accounts'] as List?) ?? const [],
        );
        return accounts.any((account) => account['user_id']?.toString() == userId);
      });
    }).catchError((_) => false);
    _ownerAccountsReady = _client.rpc('property_owner_accounts_ready', params: {
      'p_property_id': _property['id'],
    }).then((value) => value == true).catchError((_) => false);
    _canManageProperty = Future.wait<dynamic>([
      _client.rpc('can_manage_property', params: {
        'p_property_id': _property['id'],
      }),
      _client.rpc('is_smartblock_admin'),
    ]).then((values) => values.any((value) => value == true))
        .catchError((_) => false);
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(_languageListener);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadOwners() async {
    final owners = List<Map<String, dynamic>>.from(
      await _client
          .from('property_owners')
          .select(
            'id, ownership_percentage, apartment_count, area_sqm, title_deed_photo_path, area_declaration_confirmed_at, is_primary_representative, ownership_status, organizations(display_name, phone_e164, approval_status)',
          )
          .eq('property_id', _property['id'])
          .order('created_at'),
    );
    List<Map<String, dynamic>> accountLinks = [];
    var accountLinksKnown = true;
    try {
      accountLinks = List<Map<String, dynamic>>.from(await _client.rpc(
        'list_property_owner_account_links',
        params: {'p_property_id': _property['id']},
      ));
    } catch (_) {
      // Account emails are shown only to people allowed to manage this property.
      accountLinksKnown = false;
    }
    return owners.map((owner) {
      final ownerId = owner['id'].toString();
      return {
        ...owner,
        '_account_links_known': accountLinksKnown,
        'registered_accounts': accountLinks
            .where((link) => link['owner_id'].toString() == ownerId)
            .toList(),
      };
    }).toList();
  }

  Future<_ReviewReadiness> _loadReviewReadiness() async {
    final ownerAccountsReady = await _client
        .rpc('property_owner_accounts_ready', params: {
          'p_property_id': _property['id'],
        })
        .then((value) => value == true)
        .catchError((_) => false);
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('property_owners')
          .select(
            'ownership_percentage, apartment_count, area_sqm, title_deed_photo_path, area_declaration_confirmed_at, is_primary_representative, organizations(approval_status)',
          )
          .eq('property_id', _property['id'])
          .eq('ownership_status', 'active'),
    );
    final total = rows.fold<double>(
      0,
      (sum, row) =>
          sum + ((row['ownership_percentage'] as num?)?.toDouble() ?? 0),
    );
    final incomplete =
        rows.isEmpty ||
        rows.any(
          (row) =>
              row['apartment_count'] == null ||
              row['area_sqm'] == null ||
              row['title_deed_photo_path'] == null ||
              row['area_declaration_confirmed_at'] == null,
        );
    final declaredApartments = rows.fold<int>(
      0,
      (sum, row) => sum + ((row['apartment_count'] as num?)?.toInt() ?? 0),
    );
    final expectedApartments = (_property['total_apartments'] as num?)?.toInt();
    final apartmentCountsMatch =
        expectedApartments == null || declaredApartments == expectedApartments;
    final primaryOwner = rows.where(
      (row) => row['is_primary_representative'] == true,
    );
    if (primaryOwner.isEmpty) {
      return _ReviewReadiness(
        activeShareTotal: total,
        primaryOwnerStatus: null,
        declarationsComplete: !incomplete,
        apartmentCountsMatch: apartmentCountsMatch,
        ownerAccountsReady: ownerAccountsReady,
      );
    }
    final organization =
        primaryOwner.first['organizations'] as Map<String, dynamic>? ?? {};
    return _ReviewReadiness(
      activeShareTotal: total,
      primaryOwnerStatus: organization['approval_status'] as String?,
      declarationsComplete: !incomplete,
      apartmentCountsMatch: apartmentCountsMatch,
      ownerAccountsReady: ownerAccountsReady,
    );
  }

  String _statusLabel(String? status) {
    if (!_isGreek) return (status ?? 'unknown').replaceAll('_', ' ');
    const labels = {
      'draft': 'Πρόχειρο',
      'pending_review': 'Σε αναμονή ελέγχου',
      'under_review': 'Υπό εξέταση',
      'changes_required': 'Απαιτούνται αλλαγές',
      'approved': 'Εγκεκριμένο',
      'rejected': 'Απορρίφθηκε',
      'suspended': 'Σε αναστολή',
    };
    return labels[status] ?? (status ?? 'Άγνωστη κατάσταση');
  }

  String _typeLabel(String? type) {
    const greek = {
      'apartment': 'Διαμέρισμα',
      'building': 'Πολυκατοικία',
      'house': 'Κατοικία',
      'shop': 'Κατάστημα',
      'office': 'Γραφείο',
      'warehouse': 'Αποθήκη',
      'land': 'Οικόπεδο',
      'other': 'Άλλο',
    };
    const english = {
      'apartment': 'Apartment',
      'building': 'Apartment building',
      'house': 'House',
      'shop': 'Shop',
      'office': 'Office',
      'warehouse': 'Warehouse',
      'land': 'Land',
      'other': 'Other',
    };
    return (_isGreek ? greek : english)[type] ?? (type ?? '');
  }

  String _modelLabel(String? model) {
    const greek = {
      'managed': 'Πλήρης διαχείριση',
      'assisted': 'Υποβοηθούμενη',
      'self_service': 'Αυτοδιαχείριση',
    };
    const english = {
      'managed': 'Managed',
      'assisted': 'Assisted',
      'self_service': 'Self-service',
    };
    return (_isGreek ? greek : english)[model] ?? (model ?? '');
  }

  Future<void> _submitForReview() async {
    setState(() => _isSubmitting = true);
    try {
      await _client.rpc(
        'submit_property_for_review',
        params: {'p_property_id': _property['id']},
      );
      if (!mounted) return;
      setState(() {
        _property = {..._property, 'approval_status': 'pending_review'};
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isGreek
                ? 'Το ακίνητο υποβλήθηκε για έλεγχο.'
                : 'Property submitted for review.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isGreek
                ? 'Δεν ήταν δυνατή η υποβολή. Δοκίμασε ξανά.'
                : 'Could not submit the property. Try again.',
          ),
        ),
      );
    }
  }

  Future<void> _openOwners() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyOwnersScreen(
          propertyId: _property['id'] as String,
          propertyName: _property['name'] as String? ?? '',
          organizationId: widget.organizationId,
          isGreek: _isGreek,
        ),
      ),
    );
    try {
      final row = await _client
          .from('properties')
          .select('organization_id')
          .eq('id', _property['id'])
          .single();
      if (mounted)
        setState(() => _property['organization_id'] = row['organization_id']);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _reviewReadinessFuture = _loadReviewReadiness();
        _ownersFuture = _loadOwners();
        _ownerAccountsReady = _client.rpc('property_owner_accounts_ready', params: {
          'p_property_id': _property['id'],
        }).then((value) => value == true).catchError((_) => false);
        _canManageProperty = _client.rpc('can_manage_property', params: {
          'p_property_id': _property['id'],
        }).then((value) => value == true).catchError((_) => false);
      });
    }
  }

  Future<void> _openModules() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyModulesScreen(
          propertyId: _property['id'] as String,
          propertyName: _property['name'] as String? ?? '',
          isGreek: _isGreek,
        ),
      ),
    );
  }

  Widget _modulesButton() => FilledButton.tonalIcon(
        onPressed: _openModules,
        icon: const Icon(Icons.dashboard_customize_outlined),
        label: Text(_isGreek
            ? 'Ψηφοφορίες · Σημειώσεις · Οικονομικά'
            : 'Votes · Notes · Finances'),
      );

  Future<void> _openApartments() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PropertyApartmentsScreen(
      propertyId: _property['id'] as String,
      propertyName: _property['name'] as String? ?? '',
      isGreek: _isGreek,
    )));
  }

  Widget _apartmentsButton() => FilledButton.tonalIcon(
    onPressed: _openApartments,
    icon: const Icon(Icons.apartment_outlined),
    label: Text(_isGreek ? 'Διαμερίσματα · Νέο συμβόλαιο' : 'Apartments · New lease'),
  );

  Future<void> _openManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyManagementScreen(
          propertyId: _property['id'] as String,
          propertyName: _property['name'] as String? ?? '',
          totalApartments: (_property['total_apartments'] as num?)?.toInt(),
          isGreek: _isGreek,
        ),
      ),
    );
  }

  Widget _detailTile(IconData icon, String label, String value) => Card(
    elevation: 0,
    child: ListTile(
      leading: Icon(icon, color: const Color(0xFF176B87)),
      title: Text(label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(value, style: Theme.of(context).textTheme.titleSmall),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final address = [
      _property['address'],
      _property['city'],
      _property['country'],
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(', ');
    final status = _property['approval_status'] as String?;
    final isDraft = status == 'draft' || status == 'changes_required';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isGreek ? 'Στοιχεία ακινήτου' : 'Property details'),
        actions: [
          const SmartBlockLanguageMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            _property['name'] as String? ?? '',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF17324D),
            ),
          ),
          const SizedBox(height: 8),
          Chip(
            avatar: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(_statusLabel(status)),
          ),
          const SizedBox(height: 12),
          _detailTile(
            Icons.home_work_outlined,
            _isGreek ? 'Τύπος ακινήτου' : 'Property type',
            _property['property_type'] == 'other'
                ? '${_typeLabel('other')}: ${_property['other_description'] ?? ''}'
                : _typeLabel(_property['property_type'] as String?),
          ),
          if (_property['property_type'] == 'building' ||
              _property['portfolio_id'] != null)
            _detailTile(
              Icons.account_balance_outlined,
              _isGreek ? 'Μορφή πολυκατοικίας' : 'Building type',
              (_property['building_model'] == 'virtual' ||
                      _property['portfolio_id'] != null)
                  ? (_isGreek
                        ? 'Εικονική — 5% στις πληρωμές μέσω SmartBlock'
                        : 'Virtual — 5% on payments through SmartBlock')
                  : (_isGreek
                        ? 'Πραγματική — 5 € ανά διαμέρισμα/μήνα'
                        : 'Physical — €5 per apartment/month'),
            ),
          _detailTile(
            Icons.location_on_outlined,
            _isGreek ? 'Τοποθεσία' : 'Location',
            address.isEmpty
                ? (_isGreek ? 'Δεν έχει οριστεί' : 'Not set')
                : address,
          ),
          _detailTile(
            Icons.settings_outlined,
            _isGreek ? 'Μοντέλο διαχείρισης' : 'Management model',
            _modelLabel(_property['management_model'] as String?),
          ),
          _detailTile(
            Icons.apartment_outlined,
            _isGreek ? 'Οργανισμός' : 'Organization',
            widget.organizationName.isEmpty
                ? (_property['organization_id'] == null
                      ? (_isGreek
                            ? 'Δεν έχει οριστεί ακόμη'
                            : 'Not assigned yet')
                      : (_isGreek ? 'Συνδεδεμένος ιδιοκτήτης' : 'Owner linked'))
                : widget.organizationName,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  _isGreek ? 'Ιδιοκτήτες' : 'Owners',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: _isGreek ? 'Διαχείριση ιδιοκτητών' : 'Manage owners',
                onPressed: _openOwners,
                icon: const Icon(Icons.person_add_alt_1),
              ),
            ],
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _ownersFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError)
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(snapshot.error.toString()),
                  ),
                );
              final owners = snapshot.data ?? const [];
              final activeOwners = owners
                  .where((owner) => owner['ownership_status'] == 'active')
                  .toList();
              final allAreasDeclared =
                  activeOwners.isNotEmpty &&
                  activeOwners.every(
                    (owner) =>
                        owner['area_sqm'] != null &&
                        owner['title_deed_photo_path'] != null &&
                        owner['area_declaration_confirmed_at'] != null,
                  );
              final declaredApartmentCount = activeOwners.fold<int>(
                0,
                (sum, owner) =>
                    sum + ((owner['apartment_count'] as num?)?.toInt() ?? 0),
              );
              final expectedApartmentCount =
                  (_property['total_apartments'] as num?)?.toInt();
              final shareIsReady =
                  allAreasDeclared &&
                  (expectedApartmentCount == null ||
                      expectedApartmentCount == declaredApartmentCount);
              if (owners.isEmpty)
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(
                      _isGreek
                          ? 'Δεν έχουν συνδεθεί ιδιοκτήτες ακόμη.'
                          : 'No owners linked yet.',
                    ),
                  ),
                );
              return Card(
                child: Column(
                  children: owners.map((owner) {
                    final organization =
                        owner['organizations'] as Map<String, dynamic>? ?? {};
                    final phone = organization['phone_e164'] as String? ?? '';
                    final percentage =
                        (owner['ownership_percentage'] as num?)?.toDouble() ??
                        0;
                    final active = owner['ownership_status'] == 'active';
                    final accountLinksKnown =
                        owner['_account_links_known'] == true;
                    final linkedAccounts = List<Map<String, dynamic>>.from(
                        (owner['registered_accounts'] as List?) ?? const []);
                    final linkedNames = linkedAccounts.map((account) {
                      final fullName =
                          (account['full_name'] as String?)?.trim() ?? '';
                      final email = account['email'] as String? ?? '';
                      return fullName.isEmpty ? email : '$fullName · $email';
                    }).join(', ');
                    return ListTile(
                      leading: CircleAvatar(
                        child: Icon(
                          owner['is_primary_representative'] == true
                              ? Icons.star_outline
                              : Icons.person_outline,
                        ),
                      ),
                      title: Text(
                        organization['display_name'] as String? ??
                            (_isGreek ? 'Ιδιοκτήτης' : 'Owner'),
                      ),
                      subtitle: Text(
                        [
                          phone,
                          if (owner['area_sqm'] != null)
                            '${owner['area_sqm']} m²',
                          if (active && shareIsReady)
                            '${percentage.toStringAsFixed(2)}%'
                          else if (active)
                            (_isGreek
                                ? 'ποσοστό σε εκκρεμότητα'
                                : 'share pending'),
                          if (!active)
                            (owner['ownership_status'] as String? ?? '')
                                .replaceAll('_', ' '),
                          if (active && accountLinksKnown && linkedAccounts.isNotEmpty)
                            '${_isGreek ? 'Λογαριασμός' : 'Account'}: $linkedNames',
                          if (active && accountLinksKnown && linkedAccounts.isEmpty)
                            (_isGreek
                                ? 'Δεν έχει συνδεθεί εγγραφή ιδιοκτήτη'
                                : 'Owner registration not linked'),
                        ].where((v) => v.isNotEmpty).join(' · '),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _openOwners,
            icon: const Icon(Icons.people_outline),
            label: Text(
              _isGreek ? 'Συνιδιοκτήτες και ποσοστά' : 'Co-owners and shares',
            ),
          ),
          const SizedBox(height: 10),
          FutureBuilder<bool>(
            future: _ownerAccountsReady,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data == true) {
                return _modulesButton();
              }
              return FutureBuilder<bool>(
                future: _canManageProperty,
                builder: (context, managerSnapshot) {
                  if (managerSnapshot.data == true) return _modulesButton();
                  return Card(
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.link_off_outlined),
                      title: Text(_isGreek
                          ? 'Εκκρεμεί η σύνδεση όλων των ιδιοκτητών'
                          : 'Link every owner account to continue'),
                      subtitle: Text(_isGreek
                          ? 'Οι ψηφοφορίες, τα οικονομικά και η διαχείριση ενεργοποιούνται όταν κάθε ενεργός ιδιοκτήτης συνδεθεί με εγκεκριμένη εγγραφή. Επικοινώνησε με τον δημιουργό ή τον διαχειριστή του ακινήτου.'
                          : 'Votes, finances and management unlock after every active owner is linked to an approved account. Ask the property creator or manager to link them.'),
                    ),
                  );
                },
              );
            },
          ),
          FutureBuilder<bool>(
            future: _isLinkedOwner,
            builder: (context, ownerSnapshot) {
              if (ownerSnapshot.data == true) return _apartmentsButton();
              return FutureBuilder<bool>(
                future: _canManageProperty,
                builder: (context, managerSnapshot) =>
                    managerSnapshot.data == true
                    ? _apartmentsButton()
                    : const SizedBox.shrink(),
              );
            },
          ),
          const SizedBox(height: 10),
          FutureBuilder<bool>(
            future: _canManageProperty,
            builder: (context, snapshot) => snapshot.data == true
                ? OutlinedButton.icon(
                    onPressed: _openManagement,
                    icon: const Icon(Icons.handyman_outlined),
                    label: Text(
                      _isGreek
                          ? 'Υπηρεσίες · Διαχείριση κτιρίου'
                          : 'Services · Building management',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (isDraft) ...[
            const SizedBox(height: 12),
            FutureBuilder<_ReviewReadiness>(
              future: _reviewReadinessFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return _readinessCard(
                    _isGreek
                        ? 'Δεν ήταν δυνατός ο έλεγχος ιδιοκτητών. Δοκίμασε ξανά.'
                        : 'Could not check the owners. Refresh and try again.',
                  );
                }
                final readiness = snapshot.data!;
                final reasons = <String>[];
                if (readiness.primaryOwnerStatus == null) {
                  reasons.add(
                    _isGreek
                        ? 'Πρόσθεσε κύριο ιδιοκτήτη με τηλέφωνο.'
                        : 'Add a primary owner using their phone number.',
                  );
                } else if (readiness.primaryOwnerStatus != 'approved') {
                  final status = readiness.primaryOwnerStatus!;
                  final statusText = _isGreek
                      ? switch (status) {
                          'pending_review' => 'σε αναμονή ελέγχου',
                          'under_review' => 'υπό εξέταση',
                          'changes_required' => 'απαιτούνται αλλαγές',
                          'rejected' => 'απορρίφθηκε',
                          'suspended' => 'σε αναστολή',
                          _ => status.replaceAll('_', ' '),
                        }
                      : status.replaceAll('_', ' ');
                  reasons.add(
                    _isGreek
                        ? 'Ο οργανισμός του κύριου ιδιοκτήτη είναι «$statusText». Χρειάζεται έγκριση από το SmartBlock.'
                        : 'The primary owner organization is "$statusText". SmartBlock approval is required.',
                  );
                }
                if ((readiness.activeShareTotal - 100).abs() > 0.001) {
                  reasons.add(
                    _isGreek
                        ? 'Τα ενεργά ποσοστά είναι ${readiness.activeShareTotal.toStringAsFixed(2)}%. Πρέπει να φτάσουν το 100%.'
                        : 'Active ownership totals ${readiness.activeShareTotal.toStringAsFixed(2)}%. It must total 100%.',
                  );
                }
                if (!readiness.declarationsComplete) {
                  reasons.add(
                    _isGreek
                        ? 'Κάθε ιδιοκτήτης πρέπει να δηλώσει διαμερίσματα και τετραγωνικά, να ανεβάσει φωτογραφία τίτλου και να επιβεβαιώσει τα στοιχεία.'
                        : 'Every owner must declare apartments and area, upload a title deed photo, and confirm the information.',
                  );
                }
                if (!readiness.apartmentCountsMatch) {
                  reasons.add(
                    _isGreek
                        ? 'Το άθροισμα διαμερισμάτων των ιδιοκτητών πρέπει να συμφωνεί με το σύνολο της πολυκατοικίας.'
                        : 'The owners’ apartment counts must match the building total.',
                  );
                }
                if (!readiness.ownerAccountsReady) {
                  reasons.add(
                    _isGreek
                        ? 'Σύνδεσε κάθε ενεργό ιδιοκτήτη με εγκεκριμένη εγγραφή ιδιοκτήτη πριν συνεχίσεις.'
                        : 'Link every active owner to an approved owner account before continuing.',
                  );
                }
                if (reasons.isNotEmpty) {
                  return _readinessCard(reasons.join('\n'));
                }
                return FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submitForReview,
                  icon: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_outlined),
                  label: Text(
                    _isGreek ? 'Υποβολή για έλεγχο' : 'Submit for review',
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _readinessCard(String message) => Card(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded),
          const SizedBox(width: 12),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}
