import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:country_picker/country_picker.dart';

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
  String propertyAddress = '';
  bool get gr => widget.isGreek;
  String t(String el, String en) => gr ? el : en;

  @override
  void initState() { super.initState(); refresh(); }

  Future<void> refresh() async {
    try {
      final result = await Future.wait<dynamic>([
        db.from('property_apartments').select().eq('property_id', widget.propertyId).order('apartment_number'),
        db.rpc('list_lease_contract_offers', params: {'p_property_id': widget.propertyId}),
        db.from('properties').select('address,city,country').eq('id', widget.propertyId).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        apartments = List<Map<String, dynamic>>.from(result[0]);
        leases = List<Map<String, dynamic>>.from(result[1]);
        final property = Map<String, dynamic>.from(result[2] as Map? ?? {});
        propertyAddress = [property['address'], property['city'], property['country']]
            .where((part) => part != null && part.toString().trim().isNotEmpty)
            .join(', ');
      });
    } catch (e) { if (mounted) message('$e'); }
  }

  void message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  InputDecoration _input(String label, IconData icon, {String? hint}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        filled: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      );

  Widget _formSection(String title, IconData icon, List<Widget> fields) =>
      Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ),
              ]),
              const SizedBox(height: 6),
              ...fields.map((field) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: field,
              )),
            ],
          ),
        ),
      );



  Widget _countryPickerField({
    required BuildContext fieldContext,
    required TextEditingController controller,
    required String label,
  }) => FormField<String>(
    initialValue: controller.text,
    validator: required,
    builder: (fieldState) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => showCountryPicker(
        context: fieldContext,
        countryListTheme: CountryListThemeData(
          bottomSheetHeight: MediaQuery.sizeOf(fieldContext).height * .72,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          inputDecoration: InputDecoration(
            labelText: t('Αναζήτηση χώρας', 'Search countries'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        onSelect: (country) {
          controller.text = country.name;
          fieldState.didChange(country.name);
        },
      ),
      child: InputDecorator(
        decoration: _input(label, Icons.public_outlined).copyWith(
          suffixIcon: const Icon(Icons.arrow_drop_down),
          errorText: fieldState.errorText,
        ),
        child: Text(
          controller.text.isEmpty
              ? t('Επίλεξε χώρα', 'Select a country')
              : controller.text,
          style: Theme.of(fieldContext).textTheme.bodyLarge,
        ),
      ),
    ),
  );


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
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Άκυρο', 'Cancel'))), FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(ctx, true); }, child: Text(t('Αποθήκευση', 'Save')))],
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
    Map<String, dynamic> leaseTermSettings;
    try {
      final value = await db.rpc('get_owner_lease_term_settings');
      leaseTermSettings = Map<String, dynamic>.from(value as Map);
    } catch (error) {
      message('${t('Δεν φορτώθηκαν οι όροι συμβολαίου', 'Could not load lease terms')}: $error');
      return;
    }
    final ownerDefaultTerms =
        (leaseTermSettings['owner_terms'] as String? ?? '').trim();
    final ownerFurnitureDefault =
        (leaseTermSettings['owner_furniture_inventory'] as String? ?? '').trim();
    final smartBlockTerms = (leaseTermSettings[
                gr ? 'smartblock_terms_el' : 'smartblock_terms_en'] as String? ??
            '')
        .trim();
    if (smartBlockTerms.isEmpty) {
      message(t(
        'Οι υποχρεωτικοί όροι SmartBlock δεν έχουν ρυθμιστεί.',
        'Required SmartBlock terms are not configured.',
      ));
      return;
    }
    final ownerName = TextEditingController(
      text: db.auth.currentUser?.userMetadata?['full_name']?.toString() ?? '',
    );
    final ownerIdNo = TextEditingController();
    final ownerIdCountry = TextEditingController();
    final ownerIdExpiry = TextEditingController();
    final tenantName = TextEditingController();
    final tenantEmail = TextEditingController();
    final tenantPhone = TextEditingController();
    final tenantIdCountry = TextEditingController();
    final tenantIdNumber = TextEditingController();
    final tenantIdExpiry = TextEditingController();
    final rent = TextEditingController();
    final deposit = TextEditingController(text: '0');
    final charges = TextEditingController(text: '0');
    final starts = TextEditingController();
    final ends = TextEditingController();
    final ownerTerms = TextEditingController(text: ownerDefaultTerms);
    final furnitureInventory = TextEditingController(
      text: ownerFurnitureDefault.isNotEmpty
          ? ownerFurnitureDefault
          : (unit['furniture_details']?.toString() ?? ''),
    );
    final leaseOnlyTerms = TextEditingController();
    final form = GlobalKey<FormState>();
    var ownerIdType = 'national_id';
    var tenantIdType = 'national_id';
    var dueDay = 1;
    var saveOwnerTermsAsDefault = true;
    final tenantSuggestions = <Map<String, dynamic>>[];
    Timer? tenantLookupTimer;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Νέο συμβόλαιο', 'New lease')),
              const SizedBox(height: 7),
              Card(
                color: Theme.of(ctx).colorScheme.secondaryContainer,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(widget.propertyName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${propertyAddress.isEmpty ? t('Διεύθυνση δεν έχει καταχωρηθεί', 'Address not recorded') : propertyAddress}\\n${t('Αριθμός διαμερίσματος', 'Apartment number')}: ${unit['apartment_number']}'),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                t('Συμπλήρωσε τα πεδία ανά ενότητα. Τα πεδία με * είναι απαραίτητα.', 'Complete each section. Fields marked * are required.'),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          content: SizedBox(
            width: 680,
            height: MediaQuery.sizeOf(ctx).height * .68,
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _formSection(
                    t('Στοιχεία ιδιοκτήτη', 'Owner details'),
                    Icons.person_outline,
                    [
                      TextFormField(
                        controller: ownerName,
                        decoration: _input(t('Ονοματεπώνυμο *', 'Full name *'), Icons.badge_outlined),
                        validator: required,
                      ),
                      DropdownButtonFormField<String>(
                        value: ownerIdType,
                        decoration: _input(t('Έγγραφο ταυτοποίησης *', 'Identity document *'), Icons.assignment_ind_outlined),
                        items: [
                          DropdownMenuItem(value: 'national_id', child: Text(t('Ταυτότητα', 'National ID'))),
                          DropdownMenuItem(value: 'passport', child: Text(t('Διαβατήριο', 'Passport'))),
                        ],
                        onChanged: (value) => setDialog(() => ownerIdType = value ?? 'national_id'),
                      ),
                      _countryPickerField(
                        fieldContext: ctx,
                        controller: ownerIdCountry,
                        label: t('Χώρα έκδοσης εγγράφου *', 'Document issuing country *'),
                      ),
                      TextFormField(
                        controller: ownerIdNo,
                        decoration: _input(t('Αριθμός εγγράφου *', 'Document number *'), Icons.credit_card_outlined),
                        validator: required,
                      ),
                      TextFormField(
                        controller: ownerIdExpiry,
                        readOnly: true,
                        decoration: _input(t('Ημερομηνία λήξης εγγράφου *', 'Document expiry date *'), Icons.event_busy_outlined, hint: 'YYYY-MM-DD'),
                        validator: (value) => validFutureDate(value) ? null : t('Η ημερομηνία λήξης πρέπει να είναι στο μέλλον', 'Expiry date must be in the future'),
                        onTap: () => chooseDate(ownerIdExpiry),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _formSection(
                    t('Στοιχεία ενοικιαστή', 'Tenant details'),
                    Icons.person_add_alt_1_outlined,
                    [
                      TextFormField(
                        controller: tenantName,
                        decoration: _input(t('Ονοματεπώνυμο *', 'Full name *'), Icons.badge_outlined),
                        validator: required,
                      ),
                      TextFormField(
                        controller: tenantEmail,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _input('Email *', Icons.email_outlined),
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          return email.contains('@') && email.split('@').last.contains('.')
                              ? null
                              : t('Βάλε έγκυρο email', 'Enter a valid email');
                        },
                        onChanged: (value) {
                          tenantLookupTimer?.cancel();
                          final query = value.trim();
                          setDialog(() => tenantSuggestions.clear());
                          if (query.length < 2) return;
                          tenantLookupTimer = Timer(const Duration(milliseconds: 300), () async {
                            try {
                              final response = await db.rpc(
                                'search_owner_tenant_suggestions',
                                params: {'p_search': query},
                              );
                              if (!ctx.mounted || tenantEmail.text.trim().toLowerCase() != query.toLowerCase()) return;
                              setDialog(() {
                                tenantSuggestions
                                  ..clear()
                                  ..addAll(List<Map<String, dynamic>>.from(response));
                              });
                            } catch (_) {
                              if (ctx.mounted) setDialog(() => tenantSuggestions.clear());
                            }
                          });
                        },
                      ),
                      if (tenantSuggestions.isNotEmpty)
                        Card(
                          margin: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                                child: Text(
                                  t('Προηγούμενοι ενοικιαστές', 'Previous tenants'),
                                  style: Theme.of(ctx).textTheme.labelLarge,
                                ),
                              ),
                              ...tenantSuggestions.map((person) => ListTile(
                                leading: const Icon(Icons.history),
                                title: Text(person['tenant_name']?.toString().trim().isNotEmpty == true
                                    ? person['tenant_name'].toString()
                                    : person['tenant_email'].toString()),
                                subtitle: Text(person['tenant_email']?.toString() ?? ''),
                                onTap: () {
                                  tenantEmail.text = person['tenant_email']?.toString() ?? '';
                                  if (tenantName.text.trim().isEmpty) {
                                    tenantName.text = person['tenant_name']?.toString() ?? '';
                                  }
                                  if (tenantPhone.text.trim().isEmpty) {
                                    tenantPhone.text = person['tenant_phone_e164']?.toString() ?? '';
                                  }
                                  setDialog(() => tenantSuggestions.clear());
                                },
                              )),
                            ],
                          ),
                        ),
                      TextFormField(
                        controller: tenantPhone,
                        keyboardType: TextInputType.phone,
                        decoration: _input(t('Τηλέφωνο', 'Phone'), Icons.phone_outlined, hint: '+357…'),
                      ),
                      DropdownButtonFormField<String>(
                        value: tenantIdType,
                        decoration: _input(t('Έγγραφο ταυτοποίησης *', 'Identity document *'), Icons.badge_outlined),
                        items: [
                          DropdownMenuItem(value: 'national_id', child: Text(t('Ταυτότητα', 'National ID'))),
                          DropdownMenuItem(value: 'passport', child: Text(t('Διαβατήριο', 'Passport'))),
                        ],
                        onChanged: (value) => setDialog(() => tenantIdType = value ?? 'national_id'),
                      ),
                      _countryPickerField(
                        fieldContext: ctx,
                        controller: tenantIdCountry,
                        label: t('Χώρα έκδοσης εγγράφου *', 'Document issuing country *'),
                      ),
                      TextFormField(
                        controller: tenantIdNumber,
                        decoration: _input(t('Αριθμός εγγράφου *', 'Document number *'), Icons.credit_card_outlined),
                        validator: (value) => (value?.trim().length ?? 0) < 3 ? t('Συμπλήρωσε έγκυρο αριθμό εγγράφου', 'Enter a valid document number') : null,
                      ),
                      TextFormField(
                        controller: tenantIdExpiry,
                        readOnly: true,
                        decoration: _input(t('Ημερομηνία λήξης εγγράφου *', 'Document expiry date *'), Icons.event_busy_outlined, hint: 'YYYY-MM-DD'),
                        validator: (value) => validFutureDate(value) ? null : t('Η ημερομηνία λήξης πρέπει να είναι στο μέλλον', 'Expiry date must be in the future'),
                        onTap: () => chooseDate(tenantIdExpiry),
                      ),
                      Card(
                        color: Theme.of(ctx).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline),
                              const SizedBox(width: 10),
                              Expanded(child: Text(t('Ο ενοικιαστής θα ελέγξει και θα επιβεβαιώσει αυτά τα στοιχεία όταν ανοίξει την πρόσκληση.', 'The tenant will review and confirm these details when opening the invitation.'))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _formSection(
                    t('Στοιχεία διαμερίσματος και έπιπλα', 'Apartment details and furniture'),
                    Icons.chair_alt_outlined,
                    [
                      Text('${t('Διαμέρισμα', 'Apartment')} ${unit['apartment_number']} · ${unit['room_count']} ${t('δωμάτια', 'rooms')} · ${unit['area_sqm']} m²'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: furnitureInventory,
                        minLines: 3,
                        maxLines: 7,
                        maxLength: 5000,
                        decoration: _input(t('Έπιπλα και απογραφή', 'Furniture and inventory'), Icons.chair_outlined, hint: t('π.χ. καναπές, τραπέζι, κρεβάτι, συσκευές', 'e.g. sofa, table, bed, appliances')),
                      ),
                      Text(t('Προσυμπληρώνεται από τα σταθερά έπιπλα του λογαριασμού ή από τα στοιχεία αυτού του διαμερίσματος. Μπορείς να το προσαρμόσεις για τη συγκεκριμένη μίσθωση.', 'Pre-filled from your saved defaults or this apartment. You can tailor it for this lease.'), style: Theme.of(ctx).textTheme.bodySmall),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _formSection(
                    t('Οικονομικοί όροι', 'Financial terms'),
                    Icons.euro,
                    [
                      TextFormField(
                        controller: rent,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _input(t('Μηνιαίο ενοίκιο (€) *', 'Monthly rent (€) *'), Icons.payments_outlined),
                        validator: (value) => (double.tryParse((value ?? '').replaceAll(',', '.')) ?? 0) <= 0
                            ? t('Βάλε έγκυρο ποσό', 'Enter a valid amount')
                            : null,
                      ),
                      TextFormField(
                        controller: deposit,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _input(t('Εγγύηση (€)', 'Deposit (€)'), Icons.savings_outlined),
                        validator: (value) => (double.tryParse((value ?? '').replaceAll(',', '.')) ?? -1) < 0
                            ? t('Το ποσό δεν είναι έγκυρο', 'Enter a valid amount')
                            : null,
                      ),
                      TextFormField(
                        controller: charges,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _input(t('Κοινόχρηστα (€ / μήνα)', 'Common charges (€ / month)'), Icons.receipt_long_outlined),
                        validator: (value) => (double.tryParse((value ?? '').replaceAll(',', '.')) ?? -1) < 0
                            ? t('Το ποσό δεν είναι έγκυρο', 'Enter a valid amount')
                            : null,
                      ),
                      DropdownButtonFormField<int>(
                        value: dueDay,
                        decoration: _input(t('Ημέρα πληρωμής ενοικίου', 'Rent due day'), Icons.event_repeat_outlined),
                        items: List.generate(28, (index) => DropdownMenuItem(value: index + 1, child: Text('${index + 1}'))),
                        onChanged: (value) => setDialog(() => dueDay = value ?? 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _formSection(
                    t('Διάρκεια μίσθωσης', 'Lease dates'),
                    Icons.calendar_month_outlined,
                    [
                      TextFormField(
                        controller: starts,
                        readOnly: true,
                        decoration: _input(t('Ημερομηνία έναρξης *', 'Start date *'), Icons.event_available_outlined),
                        validator: required,
                        onTap: () => chooseDate(starts),
                      ),
                      TextFormField(
                        controller: ends,
                        readOnly: true,
                        decoration: _input(t('Ημερομηνία λήξης *', 'End date *'), Icons.event_busy_outlined),
                        validator: (value) {
                          if (required(value) != null) return required(value);
                          final startDate = DateTime.tryParse(starts.text);
                          final endDate = DateTime.tryParse(value ?? '');
                          return startDate != null && endDate != null && endDate.isAfter(startDate)
                              ? null
                              : t('Η λήξη πρέπει να είναι μετά την έναρξη', 'End date must be after start date');
                        },
                        onTap: () => chooseDate(ends),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _formSection(
                    t('Όροι μίσθωσης', 'Lease terms'),
                    Icons.gavel_outlined,
                    [
                      Text(
                        t(
                          'Οι δικοί σου όροι φορτώνονται αυτόματα σε κάθε νέα μίσθωση. Επεξεργάσου τους εδώ και επίλεξε αν θέλεις να αποθηκευτούν ως προεπιλογή.',
                          'Your terms load automatically for each new lease. Edit them here and choose whether to save them as your default.',
                        ),
                        style: Theme.of(ctx).textTheme.bodySmall,
                      ),
                      TextFormField(
                        controller: ownerTerms,
                        minLines: 4,
                        maxLines: 8,
                        maxLength: 10000,
                        decoration: _input(
                          t('Οι σταθεροί όροι μου', 'My standard terms'),
                          Icons.bookmark_outline,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: saveOwnerTermsAsDefault,
                        onChanged: (value) => setDialog(
                          () => saveOwnerTermsAsDefault = value,
                        ),
                        title: Text(t(
                          'Αποθήκευση για τις επόμενες μισθώσεις',
                          'Save for future leases',
                        )),
                        subtitle: Text(t(
                          'Αν απενεργοποιηθεί, η αλλαγή θα ισχύσει μόνο για αυτό το συμβόλαιο.',
                          'If turned off, this change applies only to this lease.',
                        )),
                      ),
                      TextFormField(
                        controller: leaseOnlyTerms,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 5000,
                        decoration: _input(
                          t('Πρόσθετοι όροι μόνο για αυτή τη μίσθωση', 'Additional terms for this lease only'),
                          Icons.note_add_outlined,
                        ),
                      ),
                      Card(
                        color: Theme.of(ctx).colorScheme.secondaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t('Σταθεροί όροι SmartBlock · μόνο για ανάγνωση', 'SmartBlock standard terms · read only'),
                                style: Theme.of(ctx).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(smartBlockTerms),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Card(
                    color: Theme.of(ctx).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t('Ο ενοικιαστής συμπληρώνει τα στοιχεία του εγγράφου ταυτοποίησης και υπογράφει πρώτος. Η ηλεκτρονική αποδοχή καταγράφει λογαριασμό και χρόνο· δεν είναι από μόνη της πιστοποιημένη ηλεκτρονική υπογραφή.', 'The tenant enters their identity document details and signs first. Electronic acceptance records the account and time; by itself, it is not a certified electronic signature.'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Άκυρο', 'Cancel'))),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await db.rpc('save_owner_lease_defaults', params: {
                    'p_terms': ownerTerms.text.trim(),
                    'p_furniture_inventory': furnitureInventory.text.trim(),
                  });
                  setDialog(() => saveOwnerTermsAsDefault = true);
                  if (mounted) {
                    message(t(
                      'Οι προεπιλεγμένοι όροι αποθηκεύτηκαν.',
                      'Default terms saved.',
                    ));
                  }
                } catch (error) {
                  if (mounted) {
                    message('${t('Δεν αποθηκεύτηκαν οι όροι', 'Could not save terms')}: $error');
                  }
                }
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text(t('Αποθήκευση όρων', 'Save terms')),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final details = <String, String>{
                  t('Ονομασία πολυκατοικίας', 'Building name'): widget.propertyName,
                  t('Διεύθυνση ακινήτου', 'Property address'): propertyAddress.isEmpty ? '—' : propertyAddress,
                  t('Αριθμός διαμερίσματος', 'Apartment number'): '${unit['apartment_number']}',
                  t('Χώρος', 'Unit details'): '${unit['room_count']} ${t('δωμάτια', 'rooms')} · ${unit['area_sqm']} m² · ${unit['furnished'] == true ? t('Επιπλωμένο', 'Furnished') : t('Μη επιπλωμένο', 'Unfurnished')}',
                  t('Ιδιοκτήτης', 'Owner'): ownerName.text.trim(),
                  t('Έγγραφο ιδιοκτήτη', 'Owner document'): '${ownerIdType == 'passport' ? t('Διαβατήριο', 'Passport') : t('Ταυτότητα', 'National ID')} · ${ownerIdCountry.text.trim()} · ${ownerIdNo.text.trim()} · ${t('λήγει', 'expires')} ${ownerIdExpiry.text}',
                  t('Ενοικιαστής', 'Tenant'): tenantName.text.trim(),
                  t('Email ενοικιαστή', 'Tenant email'): tenantEmail.text.trim(),
                  t('Τηλέφωνο ενοικιαστή', 'Tenant phone'): tenantPhone.text.trim().isEmpty ? '—' : tenantPhone.text.trim(),
                  t('Έγγραφο ενοικιαστή', 'Tenant document'): '${tenantIdType == 'passport' ? t('Διαβατήριο', 'Passport') : t('Ταυτότητα', 'National ID')} · ${tenantIdCountry.text.trim()} · ${tenantIdNumber.text.trim()} · ${t('λήγει', 'expires')} ${tenantIdExpiry.text}',
                  t('Έναρξη – Λήξη', 'Start – End'): '${starts.text} – ${ends.text}',
                  t('Μηνιαίο ενοίκιο', 'Monthly rent'): '€${rent.text.trim()}',
                  t('Εγγύηση', 'Deposit'): '€${deposit.text.trim()}',
                  t('Κοινόχρηστα ανά μήνα', 'Monthly common charges'): '€${charges.text.trim()}',
                  t('Ημέρα πληρωμής', 'Payment due day'): '${dueDay}',
                  t('Έπιπλα και απογραφή', 'Furniture and inventory'): furnitureInventory.text.trim().isEmpty ? '—' : furnitureInventory.text.trim(),
                  t('Σταθεροί όροι ιδιοκτήτη', 'Owner standard terms'): ownerTerms.text.trim(),
                  t('Πρόσθετοι όροι αυτής της μίσθωσης', 'Additional terms for this lease'): leaseOnlyTerms.text.trim(),
                  t('Σταθεροί όροι SmartBlock', 'SmartBlock standard terms'): smartBlockTerms,
                };
                final invite = await _showLeasePreview(details, unit['apartment_number'].toString());
                if (invite == true && ctx.mounted) Navigator.of(ctx).pop(true);
              },
              icon: const Icon(Icons.visibility_outlined),
              label: Text(t('Προεπισκόπηση συμβολαίου', 'Preview contract')),
            ),
          ],
        ),
      ),
    );
    tenantLookupTimer?.cancel();
    if (send == true) {
      setState(() => busy = true);
      try {
        final result = await db.rpc('create_apartment_lease_offer', params: {
          'p_apartment_id': unit['id'],
          'p_owner_name': ownerName.text.trim(),
          'p_owner_id_type': ownerIdType,
          'p_owner_id_country': ownerIdCountry.text.trim(),
          'p_owner_id_number': ownerIdNo.text.trim(),
          'p_owner_id_expiry_date': ownerIdExpiry.text,
          'p_tenant_name': tenantName.text.trim(),
          'p_tenant_email': tenantEmail.text.trim().toLowerCase(),
          'p_tenant_phone_e164': tenantPhone.text.trim().isEmpty ? null : tenantPhone.text.trim(),
          'p_tenant_id_type': tenantIdType,
          'p_tenant_id_country': tenantIdCountry.text.trim(),
          'p_tenant_id_number': tenantIdNumber.text.trim(),
          'p_tenant_id_expiry_date': tenantIdExpiry.text,
          'p_monthly_rent': double.parse(rent.text.replaceAll(',', '.')),
          'p_deposit_amount': double.tryParse(deposit.text.replaceAll(',', '.')) ?? 0,
          'p_common_charges': double.tryParse(charges.text.replaceAll(',', '.')) ?? 0,
          'p_start_date': starts.text,
          'p_end_date': ends.text,
          'p_rent_due_day': dueDay,
          'p_furniture_and_inventory': '${unit['furnished'] == true ? t('Επιπλωμένο', 'Furnished') : t('Μη επιπλωμένο', 'Unfurnished')}: ${furnitureInventory.text.trim()}',
          'p_included_services': '',
          'p_special_terms': [
            ownerTerms.text.trim(),
            leaseOnlyTerms.text.trim(),
          ].where((value) => value.isNotEmpty).join('\n\n'),
          'p_guarantor_name': '',
          'p_guarantor_terms': '',
          'p_owner_confirm': true,
        });
        final response = Map<String, dynamic>.from(result as Map);
        final token = response['token'] as String;
        final offerId = response['offer_id'] as String;
        String? templateSaveError;
        if (saveOwnerTermsAsDefault) {
          try {
            await db.rpc('save_owner_lease_defaults', params: {
              'p_terms': ownerTerms.text.trim(),
              'p_furniture_inventory': furnitureInventory.text.trim(),
            });
          } catch (error) {
            templateSaveError = '$error';
          }
        }
        final url = Uri.https('lefteris0124.github.io', '/SmartBlock/', {'lease_invite': token});
        final subject = Uri.encodeComponent(t('Πρόσκληση για το μισθωτήριο SmartBlock', 'SmartBlock lease invitation'));
        final body = Uri.encodeComponent(t('Γεια σας ${tenantName.text.trim()},\\n\\nΟ ιδιοκτήτης σάς προσκαλεί να δείτε και να υπογράψετε ηλεκτρονικά το μισθωτήριο για το διαμέρισμα ${unit['apartment_number']}. Συνδεθείτε/εγγραφείτε με το email ${tenantEmail.text.trim()} από τον σύνδεσμο:\\n$url\\n\\nΑφού υπογράψετε, το συμβόλαιο θα επιστρέψει στον ιδιοκτήτη για τελική έγκριση.', 'Hello ${tenantName.text.trim()},\\n\\nThe owner invites you to review and sign the lease for apartment ${unit['apartment_number']}. Sign up or log in with ${tenantEmail.text.trim()} using this link:\\n$url\\n\\nAfter signing, the lease returns to the owner for final approval.'));
        final mail = Uri(scheme: 'mailto', path: tenantEmail.text.trim(), query: 'subject=$subject&body=$body');
        try {
          await db.functions.invoke('send-lease-invitation', body: {'offer_id': offerId, 'token': token});
          if (mounted) message(t('Η πρόσκληση στάλθηκε στο email του ενοικιαστή.', 'Invitation email sent to the tenant.'));
        } catch (_) {
          if (await canLaunchUrl(mail)) await launchUrl(mail);
          if (mounted) message(t('Το συμβόλαιο αποθηκεύτηκε. Άνοιξε το email για να στείλεις τον σύνδεσμο πρόσκλησης.', 'Lease saved. Email opened so you can send the invitation link.'));
        }
        await refresh();
        if (templateSaveError != null && mounted) {
          message(t(
            'Το μισθωτήριο δημιουργήθηκε, αλλά δεν αποθηκεύτηκαν οι προεπιλεγμένοι όροι: $templateSaveError',
            'The lease was created, but the default terms were not saved: $templateSaveError',
          ));
        }
      } catch (e) { message('$e'); }
      finally { if (mounted) setState(() => busy = false); }
    }
    for (final controller in [
      ownerName, ownerIdNo, ownerIdCountry, ownerIdExpiry, tenantName, tenantEmail, tenantPhone,
      tenantIdCountry, tenantIdNumber, tenantIdExpiry,
      rent, deposit, charges, starts, ends, ownerTerms, furnitureInventory, leaseOnlyTerms,
    ]) {
      controller.dispose();
    }
  }

  Future<bool?> _showLeasePreview(Map<String, String> details, String apartmentNumber) {
    final termLabels = [
      t('Σταθεροί όροι ιδιοκτήτη', 'Owner standard terms'),
      t('Πρόσθετοι όροι αυτής της μίσθωσης', 'Additional terms for this lease'),
      t('Σταθεροί όροι SmartBlock', 'SmartBlock standard terms'),
    ];
    return showDialog<bool>(
      context: context,
      builder: (previewContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        title: Row(children: [
          const Icon(Icons.description_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(t('Προεπισκόπηση συμβολαίου', 'Contract preview'))),
        ]),
        content: SizedBox(
          width: 680,
          height: MediaQuery.sizeOf(previewContext).height * .65,
          child: ListView(
            children: [
              Card(
                color: Theme.of(previewContext).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(t('Πρόχειρο προς έλεγχο πριν από την αποστολή', 'Draft for review before sending'), style: Theme.of(previewContext).textTheme.titleSmall),
                ),
              ),
              ...details.entries.where((entry) => !termLabels.contains(entry.key)).map((entry) => ListTile(
                dense: true,
                title: Text(entry.key, style: Theme.of(previewContext).textTheme.labelMedium),
                subtitle: SelectableText(entry.value),
              )),
              const Divider(),
              ...termLabels
                  .where((label) => (details[label] ?? '').trim().isNotEmpty)
                  .map((label) => Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: Theme.of(previewContext).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            SelectableText(details[label]!),
                          ],
                        ),
                      )),
              const SizedBox(height: 18),
              Text(t('Η ηλεκτρονική αποδοχή καταγράφει λογαριασμό και χρόνο· δεν είναι από μόνη της πιστοποιημένη ηλεκτρονική υπογραφή.', 'Electronic acceptance records the account and time; it is not by itself a certified electronic signature.'), style: Theme.of(previewContext).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(previewContext, false), child: Text(t('Επιστροφή στη φόρμα', 'Back to form'))),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await Printing.layoutPdf(
                  onLayout: (format) => _buildLeasePdf(details, format),
                );
              } catch (error) {
                if (mounted) message('${t('Δεν ήταν δυνατή η εκτύπωση', 'Could not print')}: $error');
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: Text(t('Εκτύπωση', 'Print')),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final bytes = await _buildLeasePdf(details, PdfPageFormat.a4);
                await Printing.sharePdf(bytes: bytes, filename: 'SmartBlock-lease-$apartmentNumber.pdf');
              } catch (error) {
                if (mounted) message('${t('Δεν ήταν δυνατή η δημιουργία PDF', 'Could not create PDF')}: $error');
              }
            },
            icon: const Icon(Icons.save_alt_outlined),
            label: Text(t('Αποθήκευση PDF', 'Save PDF')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(previewContext, true),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('Αποστολή πρόσκλησης', 'Send invitation')),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildLeasePdf(Map<String, String> details, PdfPageFormat format) async {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final document = pw.Document();
    final termLabels = [
      t('Σταθεροί όροι ιδιοκτήτη', 'Owner standard terms'),
      t('Πρόσθετοι όροι αυτής της μίσθωσης', 'Additional terms for this lease'),
      t('Σταθεροί όροι SmartBlock', 'SmartBlock standard terms'),
    ];
    document.addPage(pw.MultiPage(
      pageFormat: format,
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      margin: const pw.EdgeInsets.all(38),
      header: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        padding: const pw.EdgeInsets.only(bottom: 10),
        child: pw.Text('SmartBlock', style: pw.TextStyle(font: bold, fontSize: 11)),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount} · ${t('Πρόχειρο προς έλεγχο', 'Draft for review')}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      build: (context) => [
        pw.Center(child: pw.Text(t('ΠΡΟΣΧΕΔΙΟ ΜΙΣΘΩΤΗΡΙΟΥ', 'LEASE AGREEMENT DRAFT'), style: pw.TextStyle(font: bold, fontSize: 18))),
        pw.SizedBox(height: 18),
        ...details.entries.where((entry) => !termLabels.contains(entry.key)).map((entry) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(width: 150, child: pw.Text(entry.key, style: pw.TextStyle(font: bold, fontSize: 9))),
            pw.SizedBox(width: 8),
            pw.Expanded(child: pw.Text(entry.value.isEmpty ? '—' : entry.value, style: const pw.TextStyle(fontSize: 9))),
          ]),
        )),
        ...termLabels
            .where((label) => (details[label] ?? '').trim().isNotEmpty)
            .map((label) => pw.Container(
                  margin: const pw.EdgeInsets.only(top: 14),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(label, style: pw.TextStyle(font: bold, fontSize: 12)),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        details[label]!,
                        style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
                      ),
                    ],
                  ),
                )),
        pw.SizedBox(height: 44),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(children: [
            pw.Container(height: 1, color: PdfColors.grey700),
            pw.SizedBox(height: 6),
            pw.Text(t('Υπογραφή ενοικιαστή', 'Tenant signature'), style: const pw.TextStyle(fontSize: 9)),
          ])),
          pw.SizedBox(width: 28),
          pw.Expanded(child: pw.Column(children: [
            pw.Container(height: 1, color: PdfColors.grey700),
            pw.SizedBox(height: 6),
            pw.Text(t('Υπογραφή ιδιοκτήτη', 'Owner signature'), style: const pw.TextStyle(fontSize: 9)),
          ])),
        ]),
        pw.SizedBox(height: 18),
        pw.Text(
          t('Το παρόν PDF είναι προσχέδιο για έλεγχο και δεν αποτελεί πιστοποιημένη ηλεκτρονική υπογραφή.', 'This PDF is a review draft and is not a certified electronic signature.'),
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ],
    ));
    return document.save();
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
          Text('${offer['property_name'] ?? ''} · ${offer['unit_reference']}\\n${offer['property_address'] ?? ''}'),
          Text('${offer['tenant_name']} · ${offer['tenant_email']}'),
          Text('${offer['start_date']} – ${offer['end_date']}'),
          Text('${t('Ενοίκιο','Rent')}: €${offer['monthly_rent']} · ${t('Εγγύηση','Deposit')}: €${offer['deposit_amount']} · ${t('Κοινόχρηστα','Common charges')}: €${offer['common_charges']}'),
          Text('${t('Έγγραφο ενοικιαστή','Tenant document')}: ${offer['tenant_id_type']} · ${offer['tenant_id_country']} · ${offer['tenant_id_number']} · ${offer['tenant_id_expiry_date']}'),
          Text('${t('Έγγραφο ιδιοκτήτη','Owner ID')}: ${offer['owner_id_type']} · ${offer['owner_id_country']} · ${offer['owner_id_number']}'),
          const SizedBox(height: 10), Text(offer['special_terms']?.toString() ?? ''),
          TextField(controller: signer, decoration: InputDecoration(labelText: t('Το ονοματεπώνυμό σου για υπογραφή','Your full name for signature'))),
          CheckboxListTile(value: confirmed, onChanged: (v) => setDialog(() => confirmed = v ?? false), title: Text(t('Επισκόπησα το υπογεγραμμένο συμβόλαιο και το εγκρίνω.','I reviewed and approve the tenant-signed lease.'))),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Πίσω','Back'))), FilledButton(onPressed: confirmed && signer.text.trim().length >= 3 ? () => Navigator.pop(ctx, true) : null, child: Text(t('Τελική υπογραφή','Sign and activate')))],
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
  bool validFutureDate(String? value) {
    final parsed = DateTime.tryParse(value ?? '');
    final today = DateTime.now();
    return parsed != null && !parsed.isBefore(DateTime(today.year, today.month, today.day));
  }
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
      const SizedBox(height: 18),
      Text(t('Συμβόλαια / προσκλήσεις', 'Leases / invitations'), style: Theme.of(context).textTheme.titleLarge),
      if (leases.isEmpty) Padding(padding: const EdgeInsets.all(20), child: Text(t('Τα συμβόλαια που δημιουργείς θα εμφανίζονται εδώ.', 'Leases you create will appear here.'))),
      ...leases.map((l) => Card(child: ListTile(leading: const Icon(Icons.assignment_outlined), title: Text('${l['unit_reference']} · ${l['tenant_name']} · €${l['monthly_rent']}'), subtitle: Text('${l['tenant_email']} · ${l['start_date']} – ${l['end_date']}\n${l['status']}'), isThreeLine: true, trailing: l['status'] == 'awaiting_owner' ? IconButton(tooltip: t('Έλεγχος και υπογραφή','Review and sign'), icon: const Icon(Icons.fact_check_outlined), onPressed: busy ? null : () => reviewLease(l)) : null))),
    ])),
  );
}

