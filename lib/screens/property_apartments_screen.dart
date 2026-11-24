import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';
import 'package:url_launcher/url_launcher.dart';

class PropertyApartmentsScreen extends StatefulWidget {
  const PropertyApartmentsScreen({required this.propertyId, required this.propertyName, required this.isGreek, super.key});
  final String propertyId;
  final String propertyName;
  final bool isGreek;
  @override
  State<PropertyApartmentsScreen> createState() => _PropertyApartmentsScreenState();
}

class _PropertyApartmentsScreenState extends State<PropertyApartmentsScreen> {
  final db = SmartBlockTrialSession.client;
  bool busy = false;
  List<Map<String, dynamic>> apartments = [];
  List<Map<String, dynamic>> leases = [];
  bool get gr => widget.isGreek;
  String t(String el, String en) => gr ? el : en;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    try {
      final result = await Future.wait([
        db.from('property_apartments').select().eq('property_id', widget.propertyId).order('apartment_number'),
        db.rpc('list_lease_contract_offers', params: {'p_property_id': widget.propertyId}),
      ]);
      if (!mounted) return;
      setState(() {
        apartments = List<Map<String, dynamic>>.from(result[0]);
        leases = List<Map<String, dynamic>>.from(result[1]);
      });
    } catch (e) { if (mounted) message('$e'); }
  }

  void message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  Future<void> createApartment() async {
    final number = TextEditingController(), rooms = TextEditingController(), area = TextEditingController(), furniture = TextEditingController(), comments = TextEditingController();
    final form = GlobalKey<FormState>();
    var furnished = false;
    final save = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text(t('Νέο διαμέρισμα', 'New apartment')),
      content: SizedBox(width: 440, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: number, decoration: InputDecoration(labelText: t('Αριθμός διαμερίσματος', 'Apartment number')), validator: required),
        TextFormField(controller: rooms, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Αριθμός δωματίων', 'Number of rooms')), validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0 ? t('Μη έγκυρος αριθμός', 'Invalid number') : null),
        TextFormField(controller: area, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Τετραγωνικά (m²)', 'Area (m²)')), validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? t('Μη έγκυρα τ.μ.', 'Invalid area') : null),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t('Επιπλωμένο', 'Furnished')), value: furnished, onChanged: (v) => setDialog(() => furnished = v)),
        if (furnished) TextFormField(controller: furniture, maxLines: 2, decoration: InputDecoration(labelText: t('Έπιπλα και εξοπλισμός', 'Furniture and equipment'))),
        TextFormField(controller: comments, maxLines: 3, decoration: InputDecoration(labelText: t('Σχόλια', 'Comments'))),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Άκυρο', 'Cancel'))), FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: Text(t('Αποθήκευση', 'Save'))],
    )));
    if (save == true) {
      setState(() => busy = true);
      try {
        await db.from('property_apartments').insert({'property_id': widget.propertyId, 'apartment_number': number.text.trim(), 'room_count': int.parse(rooms.text), 'area_sqm': double.parse(area.text.replaceAll(',', '.')), 'furnished': furnished, 'furniture_details': furniture.text.trim(), 'comments': comments.text.trim(), 'created_by': db.auth.currentUser!.id});
        await refresh();
      } on PostgrestException catch (e) { message(e.code == '23505' ? t('Υπάρχει ήδη αυτός ο αριθμός διαμερίσματος.', 'That apartment number already exists.') : e.message); }
      finally { if (mounted) setState(() => busy = false); }
    }
    for (final c in [number, rooms, area, furniture, comments]) { c.dispose(); }
  }

  Future<void> createLease(Map<String, dynamic> unit) async {
    final ownerName = TextEditingController(text: db.auth.currentUser?.userMetadata?['full_name']?.toString() ?? '');
    final ownerIdNo = TextEditingController(), tenantName = TextEditingController(), tenantEmail = TextEditingController(), tenantPhone = TextEditingController();
    final rent = TextEditingController(), deposit = TextEditingController(text: '0'), charges = TextEditingController(text: '0');
    final starts = TextEditingController(), ends = TextEditingController();
    final terms = TextEditingController(text: t(
      '1. Το ενοίκιο καταβάλλεται έως την συμφωνημένη ημερομηνία.\n2. Τα κοινόχρηστα καταβάλλονται όπως αναγράφονται.\n3. Ο ενοικιαστής διατηρεί το διαμέρισμα σε καλή κατάσταση και αναφέρει έγκαιρα βλάβες.\n4. Η εγγύηση επιστρέφεται μετά τη λήξη, σύμφωνα με την κατάσταση του ακινήτου και τους εφαρμοστέους όρους.\n5. Οι πληρωμές της μίσθωσης καταγράφονται στο SmartBlock. Το SmartBlock είναι ψηφιακό κανάλι διαχείρισης και δεν αποτελεί συμβαλλόμενο μέρος.',
      '1. Rent is paid by the agreed due date.\n2. Common charges are paid as stated.\n3. The tenant keeps the apartment in good condition and reports defects promptly.\n4. The deposit is returned at lease end subject to the property condition and applicable terms.\n5. Lease payments are recorded in SmartBlock. SmartBlock is a digital management channel and is not a party to the lease.'));
    final form = GlobalKey<FormState>(); var ownerIdType = 'national_id'; var dueDay = 1;
    final send = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text(t('Συμβόλαιο · Διαμέρισμα ', 'Lease · Apartment ') + '${unit['apartment_number']}'),
      content: SizedBox(width: 540, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: ownerName, decoration: InputDecoration(labelText: t('Ονοματεπώνυμο ιδιοκτήτη', 'Owner full name')), validator: required),
        DropdownButtonFormField<String>(value: ownerIdType, decoration: InputDecoration(labelText: t('Έγγραφο ιδιοκτήτη', 'Owner document')), items: [DropdownMenuItem(value: 'national_id', child: Text(t('Ταυτότητα', 'National ID'))), DropdownMenuItem(value: 'passport', child: Text(t('Διαβατήριο', 'Passport')))], onChanged: (v) => setDialog(() => ownerIdType = v ?? 'national_id')),
        TextFormField(controller: ownerIdNo, decoration: InputDecoration(labelText: t('Αριθμός εγγράφου ιδιοκτήτη', 'Owner document number')), validator: required),
        const Divider(),
        TextFormField(controller: tenantName, decoration: InputDecoration(labelText: t('Ονοματεπώνυμο ενοικιαστή', 'Tenant full name')), validator: required),
        TextFormField(controller: tenantEmail, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (v) => (v ?? '').contains('@') ? null : t('Βάλε έγκυρο email', 'Enter a valid email')),
        TextFormField(controller: tenantPhone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Τηλέφωνο (+357...)', 'Phone (+357...)'))),
        TextFormField(controller: rent, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Μηνιαίο ενοίκιο (€)', 'Monthly rent (€)')), validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '.')) ?? 0) <= 0 ? t('Μη έγκυρο ποσό', 'Invalid amount') : null),
        TextFormField(controller: deposit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Εγγύηση (€)', 'Deposit (€)'))),
        TextFormField(controller: charges, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: t('Κοινόχρηστα (€ / μήνα)', 'Common charges (€ / month)'))),
        DropdownButtonFormField<int>(value: dueDay, decoration: InputDecoration(labelText: t('Ημέρα πληρωμής ενοικίου', 'Rent due day')), items: List.generate(28, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))), onChanged: (v) => setDialog(() => dueDay = v ?? 1)),
        TextFormField(controller: starts, readOnly: true, decoration: InputDecoration(labelText: t('Έναρξη', 'Start date'), suffixIcon: const Icon(Icons.calendar_today)), onTap: () => chooseDate(starts)),
        TextFormField(controller: ends, readOnly: true, decoration: InputDecoration(labelText: t('Λήξη', 'End date'), suffixIcon: const Icon(Icons.calendar_today)), onTap: () => chooseDate(ends)),
        Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('Όροι συμφωνίας · επεξεργάσιμοι', 'Agreement terms · editable')))),
        TextFormField(controller: terms, minLines: 5, maxLines: 10, validator: required),
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(t('Ο ενοικιαστής θα συμπληρώσει τα στοιχεία ταυτότητας και θα υπογράψει πρώτος. Η ηλεκτρονική αποδοχή καταγράφει λογαριασμό και χρόνο· δεν είναι από μόνη της πιστοποιημένη ηλεκτρονική υπογραφή.', 'Tenant completes ID details and signs first. Electronic acceptance records account and time; it is not by itself a certified electronic signature.'), style: Theme.of(context).textTheme.bodySmall)),
      ])))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Άκυρο', 'Cancel'))), FilledButton.icon(onPressed: () { if (form.currentState!.validate() && starts.text.isNotEmpty && ends.text.isNotEmpty) Navigator.pop(ctx, true); }, icon: const Icon(Icons.send_outlined), label: Text(t('Πρόσκληση ενοικιαστή', 'Invite tenant')))],
    )));
    if (send == true) {
      setState(() => busy = true);
      try {
        final result = await db.rpc('create_apartment_lease_offer', params: {
          'p_apartment_id': unit['id'], 'p_owner_name': ownerName.text.trim(), 'p_owner_id_type': ownerIdType, 'p_owner_id_number': ownerIdNo.text.trim(),
          'p_tenant_name': tenantName.text.trim(), 'p_tenant_email': tenantEmail.text.trim().toLowerCase(), 'p_tenant_phone_e164': tenantPhone.text.trim().isEmpty ? null : tenantPhone.text.trim(),
          'p_monthly_rent': double.parse(rent.text.replaceAll(',', '.')), 'p_deposit_amount': double.tryParse(deposit.text.replaceAll(',', '.')) ?? 0,
          'p_common_charges': double.tryParse(charges.text.replaceAll(',', '.')) ?? 0, 'p_start_date': starts.text, 'p_end_date': ends.text, 'p_rent_due_day': dueDay,
          'p_furniture_and_inventory': '${unit['furnished'] == true ? t('Επιπλωμένο', 'Furnished') : t('Μη επιπλωμένο', 'Unfurnished')}: ${unit['furniture_details'] ?? ''}',
          'p_included_services': '', 'p_special_terms': terms.text.trim(), 'p_guarantor_name': '', 'p_guarantor_terms': '', 'p_owner_confirm': true,
        });
        final response = Map<String, dynamic>.from(result as Map);
        final token = response['token'] as String;
        final offerId = response['offer_id'] as String;
        final url = Uri.https('lefteris0124.github.io', '/SmartBlock/', {'lease_invite': token});
        final subject = Uri.encodeComponent(t('Πρόσκληση για το μισθωτήριο SmartBlock', 'SmartBlock lease invitation'));
        final body = Uri.encodeComponent(t('Γεια σας ${tenantName.text.trim()},\n\nΟ ιδιοκτήτης σάς προσκαλεί να δείτε και να υπογράψετε ηλεκτρονικά το μισθωτήριο για το διαμέρισμα ${unit['apartment_number']}. Συνδεθείτε/εγγραφείτε με το email ${tenantEmail.text.trim()} από τον σύνδεσμο:\n$url\n\nΑφού υπογράψετε, το συμβόλαιο θα επιστρέψει στον ιδιοκτήτη για τελική έγκριση.', 'Hello ${tenantName.text.trim()},\n\nThe owner invites you to review and sign the lease for apartment ${unit['apartment_number']}. Sign up or log in with ${tenantEmail.text.trim()} using this link:\n$url\n\nAfter signing, the lease returns to the owner for final approval.'));
        final mail = Uri(scheme: 'mailto', path: tenantEmail.text.trim(), query: 'subject=$subject&body=$body');
        try {
          await db.functions.invoke('send-lease-invitation', body: {'offer_id': offerId, 'token': token});
          if (mounted) message(t('Η πρόσκληση στάλθηκε στο email του ενοικιαστή.', 'Invitation email sent to the tenant.'));
        } catch (_) {
          if (await canLaunchUrl(mail)) await launchUrl(mail);
          if (mounted) message(t('Το συμβόλαιο αποθηκεύτηκε. Άνοιξε το email για να στείλεις τον σύνδεσμο πρόσκλησης.', 'Lease saved. Email opened so you can send the invitation link.'));
        }
        await refresh();
      } catch (e) { message('$e'); }
      finally { if (mounted) setState(() => busy = false); }
    }
    for (final c in [ownerName, ownerIdNo, tenantName, tenantEmail, tenantPhone, rent, deposit, charges, starts, ends, terms]) { c.dispose(); }
  }

  Future<void> reviewLease(Map<String, dynamic> item) async {
    try {
      final value = await db.rpc('get_lease_contract_offer_for_owner', params: {'p_offer_id': item['id']});
      final offer = Map<String, dynamic>.from(value as Map);
      final signer = TextEditingController(text: db.auth.currentUser?.userMetadata?['full_name']?.toString() ?? offer['owner_name']?.toString() ?? '');
      var confirmed = false;
      final approve = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
        title: Text(t('Τελικός έλεγχος συμβολαίου', 'Final lease review')),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${offer['property_name'] ?? ''} · ${offer['unit_reference']}'),
          Text('${offer['tenant_name']} · ${offer['tenant_email']}'),
          Text('${offer['start_date']} – ${offer['end_date']}'),
          Text('${t('Ενοίκιο','Rent')}: €${offer['monthly_rent']} · ${t('Εγγύηση','Deposit')}: €${offer['deposit_amount']} · ${t('Κοινόχρηστα','Common charges')}: €${offer['common_charges']}'),
          Text('${t('Ταυτότητα ενοικιαστή','Tenant ID')}: ${offer['tenant_id_type']} · ${offer['tenant_id_country']} · ${offer['tenant_id_number']}'),
          const SizedBox(height: 10), Text(offer['special_terms']?.toString() ?? ''),
          TextField(controller: signer, decoration: InputDecoration(labelText: t('Το ονοματεπώνυμό σου για υπογραφή','Your full name for signature'))),
          CheckboxListTile(value: confirmed, onChanged: (v) => setDialog(() => confirmed = v ?? false), title: Text(t('Επισκόπησα το υπογεγραμμένο συμβόλαιο και το εγκρίνω.','I reviewed and approve the tenant-signed lease.'))),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Πίσω','Back'))), FilledButton(onPressed: confirmed && signer.text.trim().length >= 3 ? () => Navigator.pop(ctx, true) : null, child: Text(t('Τελική υπογραφή','Sign and activate'))],
      )));
      if (approve == true) {
        setState(() => busy = true);
        await db.rpc('finalize_lease_contract_offer', params: {'p_offer_id': item['id'], 'p_signer_name': signer.text.trim(), 'p_confirm': true});
        if (mounted) message(t('Το συμβόλαιο ολοκληρώθηκε και ενεργοποιήθηκε.','The lease is complete and active.'));
        await refresh();
        if (mounted) setState(() => busy = false);
      }
      signer.dispose();
    } catch (e) { if (mounted) { setState(() => busy = false); message('$e'); } }
  }

  String? required(String? v) => (v?.trim().isEmpty ?? true) ? t('Υποχρεωτικό πεδίο', 'Required') : null;
  Future<void> chooseDate(TextEditingController c) async {
    final now = DateTime.now(); final date = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(now.year - 2), lastDate: DateTime(now.year + 20));
    if (date != null) c.text = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(t('Διαμερίσματα · ${widget.propertyName}', 'Apartments · ${widget.propertyName}'))),
    floatingActionButton: FloatingActionButton.extended(onPressed: busy ? null : createApartment, icon: const Icon(Icons.add_home_work_outlined), label: Text(t('Νέο διαμέρισμα', 'New apartment'))),
    body: busy ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(onRefresh: refresh, child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), children: [
      Text(t('Διαμερίσματα', 'Apartments'), style: Theme.of(context).textTheme.titleLarge),
      if (apartments.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(t('Δεν υπάρχουν διαμερίσματα. Πρόσθεσε ένα για να ξεκινήσεις μίσθωση.', 'No apartments yet. Add one to start a lease.'))),
      ...apartments.map((u) => Card(child: ListTile(leading: const CircleAvatar(child: Icon(Icons.apartment_outlined)), title: Text('${t('Διαμέρισμα', 'Apartment')} ${u['apartment_number']}'), subtitle: Text('${u['room_count']} ${t('δωμάτια', 'rooms')} · ${u['area_sqm']} m² · ${u['furnished'] == true ? t('Επιπλωμένο', 'Furnished') : t('Μη επιπλωμένο', 'Unfurnished')}\n${u['furniture_details'] ?? ''} ${u['comments'] ?? ''}'), isThreeLine: true, trailing: IconButton(tooltip: t('Νέο συμβόλαιο', 'New lease'), icon: const Icon(Icons.description_outlined), onPressed: () => createLease(u))))),
      const SizedBox(height: 18), Text(t('Συμβόλαια / προσκλήσεις', 'Leases / invitations'), style: Theme.of(context).textTheme.titleLarge),
      if (leases.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(t('Τα συμβόλαια που δημιουργείς θα εμφανίζονται εδώ.', 'Leases you create will appear here.'))),
      ...leases.map((l) => Card(child: ListTile(leading: const Icon(Icons.assignment_outlined), title: Text('${l['unit_reference']} · ${l['tenant_name']} · €${l['monthly_rent']}'), subtitle: Text('${l['tenant_email']} · ${l['start_date']} – ${l['end_date']}\n${l['status']}'), isThreeLine: true, trailing: l['status'] == 'awaiting_owner' ? IconButton(tooltip: t('Έλεγχος και υπογραφή','Review and sign'), icon: const Icon(Icons.fact_check_outlined), onPressed: busy ? null : () => reviewLease(l)) : null))),
    ])),
  );
}

