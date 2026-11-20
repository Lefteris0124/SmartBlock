import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'property_details_screen.dart';
import 'admin_review_screen.dart';
import 'resident_service_requests_screen.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({
    this.organizationId,
    this.organizationName,
    this.organizationApprovalStatus,
    required this.isGreek,
    super.key,
  });

  final String? organizationId;
  final String? organizationName;
  final String? organizationApprovalStatus;
  final bool isGreek;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _propertiesFuture;
  late bool _greek;

  @override
  void initState() {
    super.initState();
    _greek = widget.isGreek;
    _propertiesFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var query = _client
        .from('properties')
        .select(
          'id, name, property_type, other_description, total_apartments, address, city, country, management_model, approval_status, organization_id, created_by',
        );
    final userId = _client.auth.currentUser?.id;
    if (widget.organizationId != null && userId != null) {
      query = query.or(
        'created_by.eq.$userId,organization_id.eq.${widget.organizationId}',
      );
    } else if (widget.organizationId != null) {
      query = query.eq('organization_id', widget.organizationId!);
    }
    final rows = List<Map<String, dynamic>>.from(
      await query.order('created_at', ascending: false),
    );
    final fullAccessPropertyIds = rows
        .map((property) => property['id'] as String)
        .toSet();
    final residentRows = List<Map<String, dynamic>>.from(
      await _client.rpc('list_my_resident_properties'),
    );
    for (final resident in residentRows) {
      final id = resident['property_id'] as String;
      if (fullAccessPropertyIds.contains(id)) continue;
      rows.add({
        'id': id,
        'name': resident['property_name'],
        'property_type': resident['property_type'],
        'address': resident['property_address'],
        'city': resident['property_city'],
        'total_apartments': resident['total_apartments'],
        'approval_status': 'approved',
        'organization_id': null,
        '_resident_only': true,
        '_resident_apartment_number': resident['apartment_number'],
      });
    }
    return rows;
  }

  Future<void> _refresh() async {
    final pending = _load();
    setState(() => _propertiesFuture = pending);
    try {
      await pending;
    } catch (_) {}
  }

  Future<void> _createProperty() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController();
    final other = TextEditingController();
    final apartments = TextEditingController();
    final form = GlobalKey<FormState>();
    var type = 'apartment';
    var model = 'self_service';
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(_greek ? 'Νέο ακίνητο' : 'New property'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Τύπος ακινήτου' : 'Property type',
                      ),
                      items: [
                        _option(
                          'apartment',
                          _greek ? 'Διαμέρισμα' : 'Apartment',
                        ),
                        _option(
                          'building',
                          _greek ? 'Πολυκατοικία' : 'Apartment building',
                        ),
                        _option('house', _greek ? 'Κατοικία' : 'House'),
                        _option('shop', _greek ? 'Κατάστημα' : 'Shop'),
                        _option('office', _greek ? 'Γραφείο' : 'Office'),
                        _option('warehouse', _greek ? 'Αποθήκη' : 'Warehouse'),
                        _option('land', _greek ? 'Οικόπεδο' : 'Land'),
                        _option('other', _greek ? 'Άλλο' : 'Other'),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) setDialog(() => type = v);
                            },
                    ),
                    if (type == 'building') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: apartments,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Συνολικά διαμερίσματα'
                              : 'Total apartments',
                        ),
                        validator: (v) => type != 'building'
                            ? null
                            : (int.tryParse((v ?? '').trim()) ?? 0) < 1
                            ? (_greek
                                  ? 'Βάλε τον αριθμό διαμερισμάτων.'
                                  : 'Enter the apartment count.')
                            : null,
                      ),
                    ],
                    if (type == 'other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: other,
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Προσδιορίστε το άλλο είδος'
                              : 'Specify the property type',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? (_greek
                                  ? 'Απαιτείται περιγραφή.'
                                  : 'Description is required.')
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Όνομα ακινήτου' : 'Property name',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: address,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Διεύθυνση' : 'Address',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: city,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Πόλη' : 'City',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: model,
                      decoration: InputDecoration(
                        labelText: _greek
                            ? 'Μοντέλο διαχείρισης'
                            : 'Management model',
                      ),
                      items: [
                        _option(
                          'self_service',
                          _greek ? 'Αυτοδιαχείριση' : 'Self-service',
                        ),
                        _option(
                          'assisted',
                          _greek ? 'Υποβοηθούμενη' : 'Assisted',
                        ),
                        _option(
                          'managed',
                          _greek ? 'Πλήρης διαχείριση' : 'Managed',
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) setDialog(() => model = v);
                            },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _greek
                          ? 'Πρώτα αποθηκεύεται το ακίνητο. Ο ιδιοκτήτης/οργανισμός προστίθεται έπειτα μέσα από τα στοιχεία του.'
                          : 'Save the property first. Add its owner organization afterward from the property details.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text(_greek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setDialog(() => saving = true);
                      try {
                        final id = await _client.rpc(
                          'create_property_draft_with_units',
                          params: {
                            'p_name': name.text.trim(),
                            'p_property_type': type,
                            'p_address': address.text.trim(),
                            'p_city': city.text.trim(),
                            'p_country': 'Cyprus',
                            'p_management_model': model,
                            'p_other_description': type == 'other'
                                ? other.text.trim()
                                : null,
                            'p_total_apartments': type == 'building'
                                ? int.parse(apartments.text.trim())
                                : null,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx, id != null);
                      } on PostgrestException catch (e) {
                        if (ctx.mounted) {
                          setDialog(() => saving = false);
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_greek ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    address.dispose();
    city.dispose();
    other.dispose();
    apartments.dispose();
    if (saved == true && mounted) await _refresh();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? (_greek ? 'Υποχρεωτικό πεδίο.' : 'Required field.')
      : null;

  String _propertyTypeLabel(String? type, String? otherDescription) {
    if (type == 'other' && (otherDescription ?? '').trim().isNotEmpty) {
      return otherDescription!.trim();
    }
    const greek = {
      'apartment': 'Διαμέρισμα',
      'building': 'Πολυκατοικία',
      'house': 'Κατοικία',
      'shop': 'Κατάστημα',
      'office': 'Γραφείο',
      'warehouse': 'Αποθήκη',
      'land': 'Οικόπεδο',
      'other': 'Άλλο ακίνητο',
    };
    const english = {
      'apartment': 'Apartment',
      'building': 'Apartment building',
      'house': 'House',
      'shop': 'Shop',
      'office': 'Office',
      'warehouse': 'Warehouse',
      'land': 'Land',
      'other': 'Other property',
    };
    return (_greek ? greek : english)[type] ?? (type ?? '');
  }

  String _approvalLabel(String? status) {
    if (!_greek) return (status ?? 'unknown').replaceAll('_', ' ');
    const labels = {
      'draft': 'Πρόχειρο',
      'pending_review': 'Σε αναμονή ελέγχου',
      'under_review': 'Υπό έλεγχο',
      'changes_required': 'Χρειάζονται αλλαγές',
      'approved': 'Εγκεκριμένο',
      'rejected': 'Απορρίφθηκε',
      'suspended': 'Σε αναστολή',
    };
    return labels[status] ?? 'Άγνωστη κατάσταση';
  }

  DropdownMenuItem<String> _option(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(label));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.organizationName ??
            (_greek ? 'Τα ακίνητά μου' : 'My properties'),
      ),
      actions: [
        IconButton(
          onPressed: () => setState(() => _greek = !_greek),
          icon: const Icon(Icons.language),
        ),
        FutureBuilder<dynamic>(
          future: _client.rpc('is_smartblock_staff'),
          builder: (context, snapshot) => snapshot.data == true
              ? IconButton(
                  tooltip: _greek
                      ? 'Κέντρο διαχείρισης'
                      : 'Admin control center',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminReviewScreen(isGreek: _greek),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        IconButton(
          tooltip: _greek ? 'Αποσύνδεση' : 'Sign out',
          onPressed: () async => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createProperty,
      icon: const Icon(Icons.add_home_work_outlined),
      label: Text(_greek ? 'Νέο ακίνητο' : 'New property'),
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _propertiesFuture,
        builder: (context, snapshot) {
          final properties = snapshot.data ?? const [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _greek ? 'Ακίνητα' : 'Properties',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _greek
                    ? 'Άνοιξε ένα ακίνητο για να δεις τους ιδιοκτήτες, τις ψηφοφορίες, τις ανακοινώσεις και τα οικονομικά του.'
                    : 'Open a property to see its owners, votes, notices and finances.',
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(
                      _greek
                          ? 'Δεν φορτώθηκαν τα ακίνητα'
                          : 'Properties could not be loaded',
                    ),
                    subtitle: Text(
                      _greek
                          ? 'Έλεγξε τη σύνδεση και δοκίμασε ξανά.'
                          : 'Check your connection and try again.',
                    ),
                    trailing: IconButton(
                      tooltip: _greek ? 'Δοκιμή ξανά' : 'Try again',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                )
              else if (properties.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.apartment_outlined,
                          size: 42,
                          color: Color(0xFF176B87),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _greek
                              ? 'Ξεκίνα με το πρώτο σου ακίνητο'
                              : 'Start with your first property',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _greek
                              ? 'Πρόσθεσε διαμέρισμα ή πολυκατοικία. Έπειτα θα καταχωρίσεις τους ιδιοκτήτες μέσα στο ακίνητο.'
                              : 'Add an apartment or building. You can add its owners from the property page.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _createProperty,
                          icon: const Icon(Icons.add_home_work_outlined),
                          label: Text(
                            _greek ? 'Προσθήκη ακινήτου' : 'Add property',
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ...properties.map(
                  (p) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.apartment_outlined),
                      ),
                      title: Text(p['name'] as String? ?? ''),
                      subtitle: Text(
                        p['_resident_only'] == true
                            ? [
                                    _greek
                                        ? 'Διαμέρισμα ${p['_resident_apartment_number']}'
                                        : 'Apartment ${p['_resident_apartment_number']}',
                                    p['address'],
                                    p['city'],
                                  ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · ')
                            : [
                                    _propertyTypeLabel(
                                      p['property_type'] as String?,
                                      p['other_description'] as String?,
                                    ),
                                    p['address'],
                                    p['city'],
                                    (p['total_apartments'] == null
                                        ? null
                                        : '${p['total_apartments']} ${_greek ? 'διαμερίσματα' : 'apartments'}'),
                                    _approvalLabel(
                                      p['approval_status'] as String?,
                                    ),
                                  ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        if (p['_resident_only'] == true) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ResidentServiceRequestsScreen(
                                propertyId: p['id'] as String,
                                propertyName: p['name'] as String? ?? '',
                                apartmentNumber:
                                    p['_resident_apartment_number'] as String,
                                isGreek: _greek,
                              ),
                            ),
                          );
                          await _refresh();
                          return;
                        }
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PropertyDetailsScreen(
                              property: p,
                              organizationId: p['organization_id'] as String?,
                              organizationName: widget.organizationName ?? '',
                              organizationApprovalStatus:
                                  widget.organizationApprovalStatus ??
                                  'pending_review',
                              isGreek: _greek,
                            ),
                          ),
                        );
                        await _refresh();
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
