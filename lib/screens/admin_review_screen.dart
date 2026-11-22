import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'property_details_screen.dart';
import '../smartblock_text.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({required this.isGreek, super.key});
  final bool isGreek;

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen>
    with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final tabs = TabController(length: 7, vsync: this);
  bool isAdmin = false;
  String _propertyQuery = '';
  String _organizationQuery = '';
  String _membershipQuery = '';
  bool get gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _loadAdminAccess();
  }

  Future<void> _loadAdminAccess() async {
    try {
      final value = await db.rpc('is_smartblock_admin');
      if (mounted) setState(() => isAdmin = value == true);
    } catch (_) {}
  }

  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> loadReviews(String table) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from(table)
            .select()
            .inFilter('approval_status', [
              'pending_review',
              'under_review',
              'changes_required',
            ])
            .order('created_at'),
      );

  Future<List<Map<String, dynamic>>> loadProperties() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('properties')
            .select(
              'id, name, property_type, building_model, other_description, total_apartments, apartment_id, address, city, country, management_model, approval_status, organization_id, created_by, organizations(display_name, approval_status)',
            )
            .order('created_at', ascending: false),
      );

  Future<List<Map<String, dynamic>>> loadOrganizations() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('organizations')
            .select(
              'id, organization_type, display_name, legal_name, country, phone_e164, approval_status, created_at',
            )
            .order('created_at', ascending: false),
      );

  Future<List<Map<String, dynamic>>> loadRegistrationRequests() async =>
      List<Map<String, dynamic>>.from(
        await db.rpc('admin_list_account_role_requests'),
      );

  Future<List<Map<String, dynamic>>> loadAccounts() async =>
      List<Map<String, dynamic>>.from(await db.rpc('admin_list_user_accounts'));

  Future<void> editAccount(Map<String, dynamic> account) async {
    final name = TextEditingController(text: account['full_name'] as String? ?? '');
    final phone = TextEditingController(text: account['phone'] as String? ?? '');
    final roles = Set<String>.from((account['requested_roles'] as List?) ?? const []);
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(gr ? 'Επεξεργασία λογαριασμού' : 'Edit account'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(account['email'] as String? ?? ''),
            const SizedBox(height: 12),
            TextField(controller: name, decoration: InputDecoration(labelText: gr ? 'Ονοματεπώνυμο' : 'Full name')),
            const SizedBox(height: 8),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: gr ? 'Τηλέφωνο' : 'Phone')),
            const SizedBox(height: 12),
            CheckboxListTile(value: roles.contains('property_owner'),title: Text(gr ? 'Ιδιοκτήτης' : 'Property owner'),onChanged: (v) => setDialog(() { if (v == true) { roles.add('property_owner'); } else { roles.remove('property_owner'); } })),
            CheckboxListTile(value: roles.contains('tenant'),title: Text(gr ? 'Ενοικιαστής' : 'Tenant'),onChanged: (v) => setDialog(() { if (v == true) { roles.add('tenant'); } else { roles.remove('tenant'); } })),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(onPressed: roles.isEmpty || name.text.trim().isEmpty ? null : () => Navigator.pop(dialogContext, true), child: Text(gr ? 'Αποθήκευση' : 'Save')),
          ],
        ),
      ),
    );
    if (result == true) {
      try {
        await db.rpc('admin_update_user_account', params: {
          'p_user_id': account['user_id'],
          'p_full_name': name.text.trim(),
          'p_phone': phone.text.trim(),
          'p_roles': roles.toList(),
        });
        if (mounted) setState(() {});
      } on PostgrestException catch (error) {
        notify(error.message);
      }
    }
    name.dispose();
    phone.dispose();
  }

  Widget accountDirectory() => FutureBuilder<List<Map<String, dynamic>>>(
    future: loadAccounts(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError(snapshot.error);
      final accounts = snapshot.data ?? const [];
      return RefreshIndicator(onRefresh: () async => setState(() {}), child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(padding: const EdgeInsets.all(8), child: Text(gr ? 'Επεξεργασία στοιχείων και ρόλων λογαριασμών' : 'Edit account details and roles')),
          ...accounts.map((account) {
            final roles = ((account['requested_roles'] as List?) ?? const []).map((role) => role == 'property_owner' ? (gr ? 'Ιδιοκτήτης' : 'Owner') : (gr ? 'Ενοικιαστής' : 'Tenant')).join(' · ');
            return Card(child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text((account['full_name'] as String?)?.isNotEmpty == true ? account['full_name'] as String : account['email'] as String? ?? ''),
              subtitle: Text('${account['email'] ?? ''} · ${account['phone'] ?? ''}\n$roles · ${statusLabel(account['role_status'] as String?)}'),
              isThreeLine: true,
              trailing: isAdmin ? IconButton(tooltip: gr ? 'Επεξεργασία' : 'Edit', onPressed: () => editAccount(account), icon: const Icon(Icons.edit_outlined)) : null,
            ));
          }),
        ],
      ));
    },
  );

  Future<List<Map<String, dynamic>>> loadManagerRequests() async =>
      List<Map<String, dynamic>>.from(await db.rpc('admin_list_property_manager_requests'));

  Future<void> reviewManagerRequest(String requestId, String status) async {
    if (status == 'approved') {
      final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
        title: Text(gr ? 'Επαλήθευση διαχειριστή' : 'Verify manager'),
        content: Text(gr
            ? 'Επιβεβαίωσες ότι το συνημμένο έγγραφο ορίζει αυτόν τον χρήστη ως διαχειριστή; Θα είναι ο μοναδικός ενεργός διαχειριστής της πολυκατοικίας.'
            : 'Have you verified that the attached document appoints this user as manager? They will become the building’s only active manager.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(gr ? 'Πίσω' : 'Back')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(gr ? 'Επαλήθευση' : 'Verify')),
        ],
      ));
      if (confirmed != true) return;
    }
    try {
      await db.rpc('admin_review_property_manager_request', params: {'p_request_id': requestId, 'p_status': status});
      if (mounted) setState(() {});
    } on PostgrestException catch (error) { notify(error.message); }
  }

  Future<void> openManagerProof(String path) async {
    try {
      final url = await db.storage.from('smartblock-manager-proofs').createSignedUrl(path, 300);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault)) throw StateError('Could not open the appointment document.');
    } catch (error) { notify('${gr ? 'Δεν ήταν δυνατή η προβολή' : 'Could not open proof'}: $error'); }
  }

  Widget managerRequests() => FutureBuilder<List<Map<String, dynamic>>>(
    future: loadManagerRequests(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError(snapshot.error);
      final requests = snapshot.data ?? const [];
      if (requests.isEmpty) return Center(child: Text(gr ? 'Δεν υπάρχουν αιτήματα διαχειριστή.' : 'There are no manager requests.'));
      return RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(padding: const EdgeInsets.all(12), children: requests.map((request) {
          final pending = request['status'] == 'pending';
          final proofPath = request['authority_document_path'] as String;
          final requestId = request['request_id'] as String;
          final propertyName = request['property_name'] as String? ?? '';
          final address = request['property_address'] as String? ?? '';
          final city = request['property_city'] as String? ?? '';
          return Card(child: ListTile(
            leading: CircleAvatar(child: Icon(pending ? Icons.manage_accounts_outlined : Icons.verified_user_outlined)),
            title: Text(request['requester_email'] as String? ?? ''),
            subtitle: Text('$propertyName · $address, $city\n${request['authority_note']}\n${pending ? (gr ? 'Σε αναμονή επαλήθευσης' : 'Awaiting verification') : statusLabel(request['status'] as String?)}'),
            isThreeLine: true,
            trailing: Wrap(children: [
              IconButton(tooltip: gr ? 'Προβολή εγγράφου' : 'View proof', onPressed: () => openManagerProof(proofPath), icon: const Icon(Icons.description_outlined)),
              if (pending && isAdmin) ...[
                IconButton(tooltip: gr ? 'Έγκριση' : 'Approve', onPressed: () => reviewManagerRequest(requestId, 'approved'), icon: const Icon(Icons.check_circle_outline), color: Colors.green),
                IconButton(tooltip: gr ? 'Απόρριψη' : 'Reject', onPressed: () => reviewManagerRequest(requestId, 'rejected'), icon: const Icon(Icons.cancel_outlined), color: Colors.red),
              ],
            ]),
          ));
        }).toList()),
      );
    },
  );

  Future<void> reviewRegistration(String userId, String status) async {
    try {
      await db.rpc(
        'admin_review_account_role_request',
        params: {'p_user_id': userId, 'p_status': status},
      );
      if (mounted) setState(() {});
    } on PostgrestException catch (error) {
      notify(error.message);
    }
  }

  Future<void> editRegistrationRoles(String userId, List<String> currentRoles) async {
    final selected = currentRoles.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(gr ? 'Δικαιώματα λογαριασμού' : 'Account roles'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            CheckboxListTile(
              value: selected.contains('property_owner'),
              title: Text(gr ? 'Ιδιοκτήτης' : 'Property owner'),
              onChanged: (v) => setDialog(() => v == true
                  ? selected.add('property_owner')
                  : selected.remove('property_owner')),
            ),
            CheckboxListTile(
              value: selected.contains('tenant'),
              title: Text(gr ? 'Ενοικιαστής' : 'Tenant'),
              onChanged: (v) => setDialog(() => v == true
                  ? selected.add('tenant')
                  : selected.remove('tenant')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, selected.toList()), child: Text(gr ? 'Αποθήκευση' : 'Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    try {
      await db.rpc('admin_set_account_roles', params: {
        'p_user_id': userId,
        'p_requested_roles': result,
      });
      if (mounted) setState(() {});
    } on PostgrestException catch (error) {
      notify(error.message);
    }
  }

  Widget registrationRequests() => FutureBuilder<List<Map<String, dynamic>>>(
    future: loadRegistrationRequests(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) return loadError(snapshot.error);
      final requests = snapshot.data ?? const [];
      if (requests.isEmpty) {
        return Center(
          child: Text(gr
              ? 'Δεν υπάρχουν αιτήσεις εγγραφής.'
              : 'There are no registration requests.'),
        );
      }
      return RefreshIndicator(
        onRefresh: () async => setState(() {}),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: requests.map((request) {
            final roles = List<String>.from(
              (request['requested_roles'] as List?) ?? const [],
            ).map((role) => role == 'property_owner'
                ? (gr ? 'Ιδιοκτήτης' : 'Owner')
                : (gr ? 'Ενοικιαστής' : 'Tenant')).join(' · ');
            final pending = request['status'] == 'pending';
            final userId = request['user_id'] as String;
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(pending
                      ? Icons.person_add_alt_1
                      : Icons.person_outline),
                ),
                title: Text(request['email'] as String? ?? ''),
                subtitle: Text(
                  '$roles · ${statusLabel(request['status'] as String?)}',
                ),
                isThreeLine: true,
                trailing: isAdmin
                    ? Wrap(
                        spacing: 0,
                        children: [
                          IconButton(
                            tooltip: gr ? 'Αλλαγή ρόλων' : 'Edit roles',
                            onPressed: () => editRegistrationRoles(
                              userId,
                              List<String>.from((request['requested_roles'] as List?) ?? const []),
                            ),
                            icon: const Icon(Icons.manage_accounts_outlined),
                          ),
                          if (pending) ...[
                          IconButton(
                            tooltip: gr ? 'Έγκριση' : 'Approve',
                            onPressed: () => reviewRegistration(userId, 'approved'),
                            icon: const Icon(Icons.check_circle_outline),
                            color: Colors.green,
                          ),
                          IconButton(
                            tooltip: gr ? 'Απόρριψη' : 'Reject',
                            onPressed: () => reviewRegistration(userId, 'rejected'),
                            icon: const Icon(Icons.cancel_outlined),
                            color: Colors.red,
                          ),
                          ],
                        ],
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      );
    },
  );

  void notify(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String statusLabel(String? status) {
    if (!gr) return (status ?? 'unknown').replaceAll('_', ' ');
    const labels = {
      'draft': 'Πρόχειρο',
      'pending_review': 'Σε αναμονή',
      'under_review': 'Υπό έλεγχο',
      'changes_required': 'Χρειάζονται αλλαγές',
      'approved': 'Εγκεκριμένο',
      'rejected': 'Απορρίφθηκε',
      'suspended': 'Σε αναστολή',
    };
    return labels[status] ?? 'Άγνωστη κατάσταση';
  }

  String propertyTypeLabel(Map<String, dynamic> row) {
    if (row['property_type'] == 'other' &&
        (row['other_description'] as String?)?.trim().isNotEmpty == true) {
      return (row['other_description'] as String).trim();
    }
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
    return (gr ? greek : english)[row['property_type']] ?? '';
  }

  Future<void> act(String function, String id, String status) async {
    try {
      await db.rpc(
        function,
        params: {
          function == 'review_property' ? 'p_property_id' : 'p_organization_id': id,
          'p_status': status,
          'p_review_notes': null,
        },
      );
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      notify(e.message);
    }
  }

  Future<void> editOrganization([Map<String, dynamic>? current]) async {
    final name = TextEditingController(text: current?['display_name'] as String? ?? '');
    final legal = TextEditingController(text: current?['legal_name'] as String? ?? '');
    final phone = TextEditingController(text: current?['phone_e164'] as String? ?? '');
    final country = TextEditingController(text: current?['country'] as String? ?? 'Cyprus');
    final form = GlobalKey<FormState>();
    var kind = current?['organization_type'] as String? ?? 'individual';
    var status = current?['approval_status'] as String? ?? 'draft';
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(current == null
              ? (gr ? 'Νέος οργανισμός / ιδιοκτήτης' : 'New owner / organization')
              : (gr ? 'Επεξεργασία στοιχείων' : 'Edit details')),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                    value: kind,
                    decoration: InputDecoration(labelText: gr ? 'Τύπος' : 'Type'),
                    items: [
                      DropdownMenuItem(value: 'individual', child: Text(gr ? 'Ιδιώτης' : 'Individual')),
                      DropdownMenuItem(value: 'company', child: Text(gr ? 'Εταιρεία / οργανισμός' : 'Company / organization')),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => kind = v); },
                  ),
                  TextFormField(
                    controller: name,
                    decoration: InputDecoration(labelText: gr ? 'Όνομα εμφάνισης' : 'Display name'),
                    validator: (v) => (v ?? '').trim().isEmpty ? (gr ? 'Συμπλήρωσε το όνομα.' : 'Enter a name.') : null,
                  ),
                  TextFormField(controller: legal, decoration: InputDecoration(labelText: gr ? 'Νόμιμη επωνυμία (προαιρετικά)' : 'Legal name (optional)')),
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: gr ? 'Τηλέφωνο (+357...)' : 'Phone (+357...)'),
                    validator: (v) {
                      final value = (v ?? '').trim();
                      if (value.isEmpty || RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(value)) return null;
                      return gr ? 'Χρησιμοποίησε διεθνή μορφή, π.χ. +357...' : 'Use international format, e.g. +357...';
                    },
                  ),
                  TextFormField(controller: country, decoration: InputDecoration(labelText: gr ? 'Χώρα' : 'Country')),
                  DropdownButtonFormField<String>(
                    value: status,
                    decoration: InputDecoration(labelText: gr ? 'Κατάσταση' : 'Status'),
                    items: ['draft','pending_review','under_review','changes_required','approved','rejected','suspended']
                        .map((s) => DropdownMenuItem(value: s, child: Text(statusLabel(s))))
                        .toList(),
                    onChanged: (v) { if (v != null) setDialog(() => status = v); },
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(onPressed: () => form.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: Text(gr ? 'Αποθήκευση' : 'Save')),
          ],
        ),
      ),
    );
    if (save == true) {
      final values = {
        'organization_type': kind,
        'display_name': name.text.trim(),
        'legal_name': legal.text.trim().isEmpty ? null : legal.text.trim(),
        'phone_e164': phone.text.trim().isEmpty ? null : phone.text.trim(),
        'country': country.text.trim().isEmpty ? 'Cyprus' : country.text.trim(),
        'approval_status': status,
      };
      try {
        if (current == null) {
          values['created_by'] = db.auth.currentUser!.id;
          await db.from('organizations').insert(values);
        } else {
          values['updated_at'] = DateTime.now().toUtc().toIso8601String();
          if (status != current['approval_status']) {
            values['reviewed_by'] = db.auth.currentUser!.id;
            values['reviewed_at'] = ['approved','changes_required','rejected','suspended','under_review'].contains(status)
                ? DateTime.now().toUtc().toIso8601String()
                : null;
          }
          await db.from('organizations').update(values).eq('id', current['id']);
        }
        if (mounted) setState(() {});
        notify(gr ? 'Τα στοιχεία αποθηκεύτηκαν.' : 'Changes saved.');
      } on PostgrestException catch (e) {
        notify(e.message);
      }
    }
    name.dispose(); legal.dispose(); phone.dispose(); country.dispose();
  }

  Future<void> editProperty(Map<String, dynamic> current) async {
    final name = TextEditingController(text: current['name'] as String? ?? '');
    final address = TextEditingController(text: current['address'] as String? ?? '');
    final city = TextEditingController(text: current['city'] as String? ?? '');
    final other = TextEditingController(text: current['other_description'] as String? ?? '');
    final apartments = TextEditingController(text: '${current['total_apartments'] ?? ''}');
    final form = GlobalKey<FormState>();
    var kind = current['property_type'] as String? ?? 'apartment';
    var buildingModel = current['building_model'] as String? ?? 'physical';
    var model = current['management_model'] as String? ?? 'self_service';
    var status = current['approval_status'] as String? ?? 'draft';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Επεξεργασία ακινήτου' : 'Edit property'),
          content: SizedBox(width: 440, child: Form(
            key: form,
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(value: kind, decoration: InputDecoration(labelText: gr ? 'Τύπος ακινήτου' : 'Property type'), items: current['apartment_id'] != null ? [DropdownMenuItem(value:'apartment',child:Text(gr?'Διαμέρισμα':'Apartment'))] : [
                ['apartment',gr?'Διαμέρισμα':'Apartment'],['building',gr?'Πολυκατοικία':'Apartment building'],['house',gr?'Κατοικία':'House'],['shop',gr?'Κατάστημα':'Shop'],['office',gr?'Γραφείο':'Office'],['warehouse',gr?'Αποθήκη':'Warehouse'],['land',gr?'Οικόπεδο':'Land'],['other',gr?'Άλλο':'Other']
              ].map((x)=>DropdownMenuItem(value:x[0],child:Text(x[1]))).toList(), onChanged:(v){if(v!=null)setDialog(()=>kind=v);}),
              if (kind == 'building') TextFormField(controller:apartments,keyboardType:TextInputType.number,decoration:InputDecoration(labelText:gr?'Συνολικά διαμερίσματα':'Total apartments'),validator:(v)=>(int.tryParse((v??'').trim())??0)<1?(gr?'Βάλε έγκυρο αριθμό.':'Enter a valid count.'):null),
              if (kind == 'building') DropdownButtonFormField<String>(value:buildingModel,decoration:InputDecoration(labelText:gr?'Μορφή πολυκατοικίας':'Building type'),items:[['physical',gr?'Πραγματική — 5 € ανά διαμέρισμα/μήνα':'Physical — €5 per apartment/month'],['virtual',gr?'Εικονική — 5% στις πληρωμές':'Virtual — 5% on payments']].map((x)=>DropdownMenuItem(value:x[0],child:Text(x[1]))).toList(),onChanged:(v){if(v!=null)setDialog(()=>buildingModel=v);}),
              if (kind == 'other') TextFormField(controller: other, decoration: InputDecoration(labelText: gr ? 'Προσδιορισμός άλλου τύπου' : 'Specify other type'), validator:(v)=>(v??'').trim().isEmpty?(gr?'Συμπλήρωσε τον τύπο.':'Specify the type.'):null),
              TextFormField(controller:name, decoration:InputDecoration(labelText:gr?'Όνομα ακινήτου':'Property name'), validator:(v)=>(v??'').trim().isEmpty?(gr?'Συμπλήρωσε το όνομα.':'Enter a name.'):null),
              TextFormField(controller:address, decoration:InputDecoration(labelText:gr?'Διεύθυνση':'Address'),validator:(v)=>(v??'').trim().isEmpty?(gr?'Συμπλήρωσε τη διεύθυνση.':'Enter an address.'):null),
              TextFormField(controller:city, decoration:InputDecoration(labelText:gr?'Πόλη':'City')),
              DropdownButtonFormField<String>(value:model, decoration:InputDecoration(labelText:gr?'Διαχείριση':'Management'), items:[['self_service',gr?'Αυτοδιαχείριση':'Self-service'],['assisted',gr?'Υποβοηθούμενη':'Assisted'],['managed',gr?'Πλήρης διαχείριση':'Managed']].map((x)=>DropdownMenuItem(value:x[0],child:Text(x[1]))).toList(), onChanged:(v){if(v!=null)setDialog(()=>model=v);}),
              DropdownButtonFormField<String>(value:status, decoration:InputDecoration(labelText:gr?'Κατάσταση':'Status'), items:['draft','pending_review','under_review','changes_required','approved','rejected','suspended'].map((s)=>DropdownMenuItem(value:s,child:Text(statusLabel(s)))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
            ])),
          )),
          actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
        ),
      ),
    );
    if (saved == true) {
      try {
        final values=<String,dynamic>{
          'name':name.text.trim(), 'address':address.text.trim().isEmpty?null:address.text.trim(),
          'city':city.text.trim().isEmpty?null:city.text.trim(), 'property_type':kind,
          'other_description':kind=='other'?other.text.trim():null,
          'total_apartments':kind=='building'?int.parse(apartments.text.trim()):null,
          'building_model':kind=='building'?buildingModel:'physical',
          'management_model':model,'approval_status':status,
          'updated_at':DateTime.now().toUtc().toIso8601String(),
        };
        if(status!=current['approval_status']){
          values['reviewed_by']=db.auth.currentUser!.id;
          values['reviewed_at']=['approved','changes_required','rejected','suspended','under_review'].contains(status)
              ?DateTime.now().toUtc().toIso8601String():null;
        }
        await db.from('properties').update(values).eq('id',current['id']);
        if(mounted)setState((){});
        notify(gr?'Το ακίνητο ενημερώθηκε.':'Property updated.');
      } on PostgrestException catch(e){notify(e.message);}
    }
    name.dispose();address.dispose();city.dispose();other.dispose();apartments.dispose();
  }

  Future<bool> confirmDelete(String title, String warning) async =>
      await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(title), content: Text(warning),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton.tonal(onPressed:()=>Navigator.pop(ctx,true),child:Text(gr?'Διαγραφή':'Delete'))],
      )) == true;

  Future<void> deleteProperty(Map<String,dynamic> property) async {
    if (!await confirmDelete(
      gr?'Διαγραφή ακινήτου;':'Delete property?',
      gr?'Θα αφαιρεθεί το ακίνητο μαζί με ιδιοκτησίες, σημειώσεις, ψηφοφορίες, κοινόχρηστα και μισθώσεις. Η ενέργεια δεν αναιρείται.':'This removes the property, ownership links, notices, votes, charges and rentals. This cannot be undone.',
    )) return;
    try {
      await db.rpc('admin_delete_property',params:{'p_property_id':property['id']});
      if(mounted)setState((){});
      notify(gr?'Το ακίνητο διαγράφηκε.':'Property deleted.');
    } on PostgrestException catch(e){notify(e.message);}
  }

  Future<void> deleteOrganization(Map<String,dynamic> organization) async {
    if (!await confirmDelete(
      gr?'Διαγραφή οργανισμού;':'Delete organization?',
      gr?'Η διαγραφή επιτρέπεται μόνο όταν δεν υπάρχουν ακίνητα ή συνδέσεις ιδιοκτησίας. Η ενέργεια δεν αναιρείται.':'Deletion is allowed only when no properties or ownership links refer to it. This cannot be undone.',
    )) return;
    try {
      await db.rpc('admin_delete_organization',params:{'p_organization_id':organization['id']});
      if(mounted)setState((){});
      notify(gr?'Ο οργανισμός διαγράφηκε.':'Organization deleted.');
    } on PostgrestException catch(e){notify(e.message);}
  }

  Future<List<Map<String,dynamic>>> loadMemberships() async =>
      List<Map<String,dynamic>>.from(await db.from('organization_members').select('id, organization_id, user_id, invited_email, member_role, membership_status, organizations(display_name)').order('created_at',ascending:false));

  Future<void> editMembership([Map<String,dynamic>? current]) async {
    final organizations=await loadOrganizations();
    if(!mounted)return;
    if(organizations.isEmpty){notify(gr?'Πρόσθεσε πρώτα έναν οργανισμό.':'Add an organization first.');return;}
    final email=TextEditingController(text:current?['invited_email'] as String? ?? '');
    var organizationId=current?['organization_id'] as String? ?? organizations.first['id'] as String;
    var role=current?['member_role'] as String? ?? 'representative';
    final roleOptions = current?['user_id'] != null ? ['owner','representative'] : ['representative'];
    var status=current?['membership_status'] as String? ?? 'pending_invitation';
    final form=GlobalKey<FormState>();
    final saved=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:Text(current==null?(gr?'Νέα πρόσκληση':'New invitation'):(gr?'Επεξεργασία πρόσβασης':'Edit access')),
      content:SizedBox(width:440,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<String>(value:organizationId,decoration:InputDecoration(labelText:gr?'Οργανισμός':'Organization'),items:organizations.map((o)=>DropdownMenuItem(value:o['id'] as String,child:Text(o['display_name'] as String? ?? ''))).toList(),onChanged:(v){if(v!=null)setDialog(()=>organizationId=v);}),
        TextFormField(controller:email,keyboardType:TextInputType.emailAddress,decoration:InputDecoration(labelText:gr?'Email πρόσκλησης':'Invitation email'),validator:(v)=>RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v??'').trim())?null:(gr?'Συμπλήρωσε έγκυρο email.':'Enter a valid email.')),
        DropdownButtonFormField<String>(value:role,decoration:InputDecoration(labelText:gr?'Ρόλος':'Role'),items:roleOptions.map((r)=>DropdownMenuItem(value:r,child:Text(r=='owner'?(gr?'Ιδιοκτήτης':'Owner'):(gr?'Εκπρόσωπος':'Representative')))).toList(),onChanged:(v){if(v!=null)setDialog(()=>role=v);}),
        DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:gr?'Κατάσταση πρόσβασης':'Access status'),items:['pending_owner_approval','pending_invitation','active','revoked'].map((s)=>DropdownMenuItem(value:s,child:Text(switch(s){'pending_owner_approval'=>gr?'Σε αναμονή έγκρισης':'Pending owner approval','pending_invitation'=>gr?'Πρόσκληση σε αναμονή':'Invitation pending','active'=>gr?'Ενεργή':'Active',_=>gr?'Ανακλήθηκε':'Revoked'}))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
        const SizedBox(height:8),Text(gr?'Οι προσκλήσεις συνδέονται με τον λογαριασμό όταν ο χρήστης εγγραφεί με αυτό το email.':'The invitation links to an account when the user signs up with this email.',style:Theme.of(context).textTheme.bodySmall),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
    )));
    if(saved==true){
      try{
        final values={'organization_id':organizationId,'invited_email':email.text.trim().toLowerCase(),'member_role':role,'membership_status':status};
        if(current==null){values['invited_by']=db.auth.currentUser!.id;await db.from('organization_members').insert(values);}
        else{await db.from('organization_members').update(values).eq('id',current['id']);}
        if(mounted)setState((){});notify(gr?'Η πρόσβαση αποθηκεύτηκε.':'Access saved.');
      }on PostgrestException catch(e){notify(e.message);}
    }
    email.dispose();
  }

  Future<void> deleteMembership(Map<String,dynamic> membership) async {
    if(!await confirmDelete(gr?'Ανάκληση πρόσβασης;':'Revoke access?','${gr?'Η σύνδεση με τον οργανισμό θα αφαιρεθεί.':'The organization membership will be removed.'}'))return;
    try{await db.from('organization_members').delete().eq('id',membership['id']);if(mounted)setState((){});notify(gr?'Η πρόσβαση αφαιρέθηκε.':'Access removed.');}on PostgrestException catch(e){notify(e.message);}
  }

  Widget loadError(Object? error) => Center(child: Padding(
    padding: const EdgeInsets.all(24), child: Column(mainAxisSize:MainAxisSize.min,children:[
      const Icon(Icons.cloud_off_outlined,size:40), const SizedBox(height:12),
      Text(gr?'Δεν φορτώθηκαν τα δεδομένα':'Could not load data',style:Theme.of(context).textTheme.titleMedium),
      Text(gr?'Έλεγξε τη σύνδεση και δοκίμασε ξανά.':'Check the connection and try again.',textAlign:TextAlign.center),
      TextButton.icon(onPressed:()=>setState((){}),icon:const Icon(Icons.refresh),label:Text(gr?'Δοκιμή ξανά':'Try again')),
    ]),
  ));

  Widget searchBox(String label, ValueChanged<String> onChanged) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
    child: TextField(
      onChanged:onChanged,
      decoration:InputDecoration(
        prefixIcon:const Icon(Icons.search),
        labelText:label,
        border:const OutlineInputBorder(),
        isDense:true,
      ),
    ),
  );

  Widget reviewList(String table, String function) => FutureBuilder<List<Map<String,dynamic>>>(
    future: loadReviews(table),
    builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return loadError(snapshot.error);
      final items=snapshot.data??[];
      if(items.isEmpty)return Center(child:Text(gr?'Δεν υπάρχουν εκκρεμότητες.':'No pending reviews.'));
      return RefreshIndicator(onRefresh:()async{setState((){});},child:ListView(padding:const EdgeInsets.all(12),children:items.map((item)=>Card(child:ListTile(
        title:Text((item['display_name']??item['name']??'').toString()),
        subtitle:Text('${statusLabel(item['approval_status'] as String?)} · ${item['address']??''}'),
        isThreeLine:true,
        trailing:PopupMenuButton<String>(onSelected:(value)=>act(function,item['id'] as String,value),itemBuilder:(ctx)=>[
          PopupMenuItem(value:'approved',child:Text(gr?'Έγκριση':'Approve')),
          PopupMenuItem(value:'changes_required',child:Text(gr?'Ζήτησε αλλαγές':'Request changes')),
          PopupMenuItem(value:'rejected',child:Text(gr?'Απόρριψη':'Reject')),
        ]),
      ))).toList()));
    },
  );

  Widget propertyDirectory() => FutureBuilder<List<Map<String,dynamic>>>(
    future:loadProperties(),
    builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return loadError(snapshot.error);
      final query=_propertyQuery.trim().toLowerCase();
      final properties=(snapshot.data??[]).where((p){
        if(query.isEmpty)return true;
        final org=p['organizations'] as Map<String,dynamic>? ?? {};
        return [p['name'],p['address'],p['city'],p['country'],p['property_type'],p['other_description'],org['display_name']]
            .any((v)=>(v??'').toString().toLowerCase().contains(query));
      }).toList();
      if(properties.isEmpty)return ListView(children:[searchBox(gr?'Αναζήτηση ακινήτου':'Search properties',(v)=>setState(()=>_propertyQuery=v)),Padding(padding:const EdgeInsets.all(24),child:Column(children:[Text(query.isEmpty?(gr?'Δεν υπάρχουν ακίνητα.':'No properties yet.'):(gr?'Δεν βρέθηκαν αποτελέσματα.':'No matching properties.')),if(query.isNotEmpty)TextButton(onPressed:()=>setState(()=>_propertyQuery=''),child:Text(gr?'Καθαρισμός αναζήτησης':'Clear search'))]))]);
      return RefreshIndicator(onRefresh:()async{setState((){});},child:ListView(padding:const EdgeInsets.all(12),children:[searchBox(gr?'Αναζήτηση ακινήτου':'Search properties',(v)=>setState(()=>_propertyQuery=v)),...properties.map((p){
        final org=p['organizations'] as Map<String,dynamic>? ?? {};
        return Card(child:ListTile(
          leading:const CircleAvatar(child:Icon(Icons.apartment_outlined)),
          title:Text(p['name'] as String? ?? ''),
          subtitle:Text('${propertyTypeLabel(p)} · ${p['address']??''} · ${org['display_name']??(gr?'Χωρίς οργανισμό':'No organization')} · ${statusLabel(p['approval_status'] as String?)}'),
          isThreeLine:true,
          onTap:()=>Navigator.of(context).push(MaterialPageRoute<void>(builder:(_)=>PropertyDetailsScreen(
            property:p,organizationId:p['organization_id'] as String?,organizationName:org['display_name'] as String? ?? '',organizationApprovalStatus:org['approval_status'] as String? ?? '',isGreek:gr,
          ))).then((_){if(mounted)setState((){});}),
          trailing:isAdmin?PopupMenuButton<String>(onSelected:(action){if(action=='edit')editProperty(p);if(action=='delete')deleteProperty(p);},itemBuilder:(ctx)=>[
            PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
            PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
          ]):null,
        ));
      })]));
    },
  );

  Widget organizationDirectory() => FutureBuilder<List<Map<String,dynamic>>>(
    future:loadOrganizations(),
    builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return loadError(snapshot.error);
      final query=_organizationQuery.trim().toLowerCase();
      final organizations=(snapshot.data??[]).where((o)=>query.isEmpty||[o['display_name'],o['legal_name'],o['phone_e164'],o['country']].any((v)=>(v??'').toString().toLowerCase().contains(query))).toList();
      if(organizations.isEmpty)return ListView(children:[searchBox(gr?'Αναζήτηση οργανισμού ή τηλεφώνου':'Search organizations or phone',(v)=>setState(()=>_organizationQuery=v)),Padding(padding:const EdgeInsets.all(24),child:Column(children:[Text(query.isEmpty?(gr?'Δεν υπάρχουν οργανισμοί.':'No organizations yet.'):(gr?'Δεν βρέθηκαν αποτελέσματα.':'No matching organizations.')),if(query.isNotEmpty)TextButton(onPressed:()=>setState(()=>_organizationQuery=''),child:Text(gr?'Καθαρισμός αναζήτησης':'Clear search'))]))]);
      return RefreshIndicator(onRefresh:()async{setState((){});},child:ListView(padding:const EdgeInsets.all(12),children:[searchBox(gr?'Αναζήτηση οργανισμού ή τηλεφώνου':'Search organizations or phone',(v)=>setState(()=>_organizationQuery=v)),...organizations.map((o)=>Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.business_outlined)),
        title:Text(o['display_name'] as String? ?? ''),
        subtitle:Text('${o['phone_e164']??(gr?'Χωρίς τηλέφωνο':'No phone')} · ${statusLabel(o['approval_status'] as String?)}'),
        isThreeLine:true,
        trailing:isAdmin?PopupMenuButton<String>(onSelected:(action){if(action=='edit')editOrganization(o);if(action=='delete')deleteOrganization(o);},itemBuilder:(ctx)=>[
          PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
          PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
        ]):null,
      )))]));
    },
  );

  Widget membershipDirectory()=>FutureBuilder<List<Map<String,dynamic>>>(
    future:loadMemberships(),
    builder:(context,snapshot){
      if(snapshot.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());
      if(snapshot.hasError)return loadError(snapshot.error);
      final query=_membershipQuery.trim().toLowerCase();
      final items=(snapshot.data??[]).where((m){final org=m['organizations'] as Map<String,dynamic>? ?? {};return query.isEmpty||[m['invited_email'],m['user_id'],m['member_role'],m['membership_status'],org['display_name']].any((v)=>(v??'').toString().toLowerCase().contains(query));}).toList();
      if(items.isEmpty)return ListView(children:[searchBox(gr?'Αναζήτηση email, χρήστη ή οργανισμού':'Search email, user or organization',(v)=>setState(()=>_membershipQuery=v)),Padding(padding:const EdgeInsets.all(24),child:Column(children:[Text(query.isEmpty?(gr?'Δεν υπάρχουν συνδέσεις ή προσκλήσεις.':'No memberships or invitations yet.'):(gr?'Δεν βρέθηκαν αποτελέσματα.':'No matching access records.')),if(query.isNotEmpty)TextButton(onPressed:()=>setState(()=>_membershipQuery=''),child:Text(gr?'Καθαρισμός αναζήτησης':'Clear search'))]))]);
      return RefreshIndicator(onRefresh:()async{setState((){});},child:ListView(padding:const EdgeInsets.all(12),children:[searchBox(gr?'Αναζήτηση email, χρήστη ή οργανισμού':'Search email, user or organization',(v)=>setState(()=>_membershipQuery=v)),...items.map((m){final org=m['organizations'] as Map<String,dynamic>? ?? {};return Card(child:ListTile(
        leading:const CircleAvatar(child:Icon(Icons.group_outlined)),
        title:Text(m['invited_email'] as String? ?? (m['user_id'] as String? ?? '')),
        subtitle:Text('${org['display_name']??''} · ${m['member_role']=='owner'?(gr?'Ιδιοκτήτης':'Owner'):(gr?'Εκπρόσωπος':'Representative')} · ${m['membership_status']}'),
        isThreeLine:true,
        trailing:isAdmin?PopupMenuButton<String>(onSelected:(action){if(action=='edit')editMembership(m);if(action=='delete')deleteMembership(m);},itemBuilder:(ctx)=>[
          PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
          PopupMenuItem(value:'delete',child:Text(gr?'Αφαίρεση πρόσβασης':'Remove access')),
        ]):null,
      ));})]));
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(
      title:Text(gr?'Κέντρο διαχείρισης':'Admin control center'),
      bottom:TabBar(controller:tabs,isScrollable:true,tabs:[
        Tab(icon:const Icon(Icons.pending_actions_outlined),text:gr?'Εγκρίσεις':'Reviews'),
        Tab(icon:const Icon(Icons.person_add_alt_1),text:gr?'Νέες εγγραφές':'New registrations'),
        Tab(icon:const Icon(Icons.apartment_outlined),text:gr?'Ακίνητα':'Properties'),
        Tab(icon:const Icon(Icons.business_outlined),text:gr?'Οργανισμοί':'Organizations'),
        Tab(icon:const Icon(Icons.group_outlined),text:gr?'Προσβάσεις':'Access'),
        Tab(icon:const Icon(Icons.verified_user_outlined),text:gr?'Διαχειριστές':'Managers'),
        Tab(icon:const Icon(Icons.manage_accounts_outlined),text:gr?'Λογαριασμοί':'Accounts'),
      ]),
    ),
    floatingActionButton:AnimatedBuilder(animation:tabs,builder:(context,_)=>!isAdmin?const SizedBox.shrink():switch(tabs.index){
      3=>FloatingActionButton.extended(onPressed:()=>editOrganization(),icon:const Icon(Icons.business_outlined),label:Text(gr?'Νέος οργανισμός':'New organization')),
      4=>FloatingActionButton.extended(onPressed:()=>editMembership(),icon:const Icon(Icons.person_add_alt_1),label:Text(gr?'Νέα πρόσβαση':'Invite user')),
      _=>const SizedBox.shrink(),
    }),
    body:TabBarView(controller:tabs,children:[
      DefaultTabController(length:2,child:Column(children:[
        TabBar(isScrollable:true,tabs:[Tab(text:gr?'Οργανισμοί':'Organizations'),Tab(text:gr?'Ακίνητα':'Properties')]),
        Expanded(child:TabBarView(children:[reviewList('organizations','review_organization'),reviewList('properties','review_property')]))
      ])),
      registrationRequests(),
      propertyDirectory(),
      organizationDirectory(),
      membershipDirectory(),
      managerRequests(),
      accountDirectory(),
    ]),
  );
}




