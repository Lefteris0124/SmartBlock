import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyModulesScreen extends StatefulWidget {
  const PropertyModulesScreen({
    required this.propertyId,
    required this.propertyName,
    required this.isGreek,
    super.key,
  });
  final String propertyId, propertyName;
  final bool isGreek;
  @override
  State<PropertyModulesScreen> createState() => _PropertyModulesScreenState();
}

class _PropertyModulesScreenState extends State<PropertyModulesScreen>
    with SingleTickerProviderStateMixin {
  final db = Supabase.instance.client;
  late final tabs = TabController(length: 4, vsync: this);
  bool busy = false;
  bool isAdmin = false;
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
    } catch (_) {
      // Older deployed schemas do not expose the admin control function yet.
    }
  }
  @override
  void dispose() {
    tabs.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (mounted) setState(() {});
  }

  Widget loadError() => Center(
    child: Card(
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 36),
            const SizedBox(height: 10),
            Text(
              gr ? 'Δεν φορτώθηκαν τα στοιχεία' : 'Could not load this section',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              gr
                  ? 'Έλεγξε τη σύνδεση και δοκίμασε ξανά.'
                  : 'Check your connection and try again.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: refresh,
              icon: const Icon(Icons.refresh),
              label: Text(gr ? 'Δοκιμή ξανά' : 'Try again'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget emptyState({
    required IconData icon,
    required String title,
    required String description,
    required String action,
    required VoidCallback onPressed,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(description, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.add),
                label: Text(action),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<bool> confirmDelete(String item) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(gr ? 'Διαγραφή $item;' : 'Delete $item?'),
          content: Text(gr
              ? 'Η διαγραφή δεν μπορεί να αναιρεθεί.'
              : 'This deletion cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton.tonal(onPressed: () => Navigator.pop(ctx, true), child: Text(gr ? 'Διαγραφή' : 'Delete')),
          ],
        ),
      ) == true;

  Future<void> _editNote(Map<String, dynamic> note) async {
    final text = TextEditingController(text: note['body'] as String? ?? '');
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(gr ? 'Επεξεργασία σημείωσης' : 'Edit notice'),
      content: Form(key: form, child: TextFormField(controller: text, autofocus: true, maxLines: 4, maxLength: 500, validator: required, decoration: InputDecoration(labelText: gr ? 'Μήνυμα' : 'Message'))),
      actions: [TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
    ));
    if(save==true){try{await db.from('property_notes').update({'body':text.text.trim()}).eq('id',note['id']);await refresh();}on PostgrestException catch(e){message(e.message);}}
    text.dispose();
  }

  Future<void> _deleteRow(String table, dynamic id, String label) async {
    if (!await confirmDelete(label)) return;
    try {
      await db.from(table).delete().eq('id', id);
      await refresh();
      message(gr ? 'Η καταχώριση διαγράφηκε.' : 'Record deleted.');
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> _editVote(Map<String, dynamic> vote) async {
    final title = TextEditingController(text: vote['title'] as String? ?? '');
    final question = TextEditingController(text: vote['question'] as String? ?? '');
    var status = vote['status'] as String? ?? 'open';
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx,setDialog)=>AlertDialog(
      title: Text(gr ? 'Επεξεργασία ψηφοφορίας' : 'Edit vote'),
      content: SizedBox(width:440,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:title,decoration:InputDecoration(labelText:gr?'Τίτλος':'Title'),validator:required),
        TextFormField(controller:question,decoration:InputDecoration(labelText:gr?'Ερώτηση':'Question'),validator:required),
        DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:gr?'Κατάσταση':'Status'),items:['draft','open','closed'].map((s)=>DropdownMenuItem(value:s,child:Text(switch(s){'draft'=>gr?'Πρόχειρη':'Draft','open'=>gr?'Ανοιχτή':'Open',_=>gr?'Κλειστή':'Closed'}))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
    )));
    if(save==true){try{await db.from('property_votes').update({'title':title.text.trim(),'question':question.text.trim(),'status':status}).eq('id',vote['id']);await refresh();}on PostgrestException catch(e){message(e.message);}}
    title.dispose();question.dispose();
  }

  Future<void> _editCharge(Map<String, dynamic> run) async {
    final period=TextEditingController(text:run['period_label'] as String? ?? '');
    final desc=TextEditingController(text:run['description'] as String? ?? '');
    final due=TextEditingController(text:run['due_date'] as String? ?? '');
    var status=run['status'] as String? ?? 'open';
    final form=GlobalKey<FormState>();
    final save=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:Text(gr?'Επεξεργασία χρέωσης':'Edit charge'),
      content:SizedBox(width:440,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:period,decoration:InputDecoration(labelText:gr?'Περίοδος':'Period'),validator:required),
        TextFormField(controller:desc,decoration:InputDecoration(labelText:gr?'Περιγραφή':'Description')),
        TextFormField(controller:due,decoration:InputDecoration(labelText:'YYYY-MM-DD'),validator:(v)=>DateTime.tryParse((v??'').trim())==null?(gr?'Χρησιμοποίησε ημερομηνία YYYY-MM-DD.':'Enter a date as YYYY-MM-DD.'):null),
        DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:gr?'Κατάσταση':'Status'),items:['open','closed'].map((s)=>DropdownMenuItem(value:s,child:Text(s=='open'?(gr?'Ανοιχτή':'Open'):(gr?'Κλειστή':'Closed')))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
    )));
    if(save==true){try{await db.from('property_charge_runs').update({'period_label':period.text.trim(),'description':desc.text.trim().isEmpty?null:desc.text.trim(),'due_date':due.text.trim(),'status':status}).eq('id',run['id']);await refresh();}on PostgrestException catch(e){message(e.message);}}
    period.dispose();desc.dispose();due.dispose();
  }

  Future<void> _editRent(Map<String, dynamic> contract) async {
    final unit=TextEditingController(text:contract['unit_reference'] as String? ?? '');
    final tenant=TextEditingController(text:contract['tenant_name'] as String? ?? '');
    final phone=TextEditingController(text:contract['tenant_phone_e164'] as String? ?? '');
    var status=contract['status'] as String? ?? 'active';
    final form=GlobalKey<FormState>();
    final save=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setDialog)=>AlertDialog(
      title:Text(gr?'Επεξεργασία μίσθωσης':'Edit rental'),
      content:SizedBox(width:440,child:Form(key:form,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(controller:unit,decoration:InputDecoration(labelText:gr?'Μονάδα':'Unit'),validator:required),
        TextFormField(controller:tenant,decoration:InputDecoration(labelText:gr?'Ενοικιαστής':'Tenant'),validator:required),
        TextFormField(controller:phone,keyboardType:TextInputType.phone,decoration:InputDecoration(labelText:gr?'Τηλέφωνο':'Phone'),validator:(v){final p=(v??'').trim();return p.isEmpty||RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(p)?null:(gr?'Χρησιμοποίησε διεθνή μορφή.':'Use international phone format.');}),
        DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:gr?'Κατάσταση':'Status'),items:['active','ended','cancelled'].map((s)=>DropdownMenuItem(value:s,child:Text(switch(s){'active'=>gr?'Ενεργή':'Active','ended'=>gr?'Έληξε':'Ended',_=>gr?'Ακυρώθηκε':'Cancelled'}))).toList(),onChanged:(v){if(v!=null)setDialog(()=>status=v);}),
      ])))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,true):null,child:Text(gr?'Αποθήκευση':'Save'))],
    )));
    if(save==true){try{await db.from('property_rent_contracts').update({'unit_reference':unit.text.trim(),'tenant_name':tenant.text.trim(),'tenant_phone_e164':phone.text.trim().isEmpty?null:phone.text.trim(),'status':status}).eq('id',contract['id']);await refresh();}on PostgrestException catch(e){message(e.message);}}
    unit.dispose();tenant.dispose();phone.dispose();
  }

  Future<List<Map<String, dynamic>>> rows(String table) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from(table)
            .select()
            .eq('property_id', widget.propertyId)
            .order('created_at', ascending: false),
      );

  Future<void> createVote() async {
    final title = TextEditingController(),
        question = TextEditingController(),
        choices = TextEditingController(text: gr ? 'Ναι,Όχι' : 'Yes,No');
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Νέα ψηφοφορία' : 'New vote'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: title,
                decoration: InputDecoration(labelText: gr ? 'Τίτλος' : 'Title'),
                validator: required,
              ),
              TextFormField(
                controller: question,
                decoration: InputDecoration(
                  labelText: gr ? 'Ερώτηση' : 'Question',
                ),
                validator: required,
              ),
              TextFormField(
                controller: choices,
                decoration: InputDecoration(
                  labelText: gr
                      ? 'Επιλογές, χωρισμένες με κόμμα'
                      : 'Options, comma separated',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (!key.currentState!.validate()) return;
              Navigator.pop(ctx, true);
            },
            child: Text(gr ? 'Δημιουργία' : 'Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final user = db.auth.currentUser!;
      final vote = await db
          .from('property_votes')
          .insert({
            'property_id': widget.propertyId,
            'title': title.text.trim(),
            'question': question.text.trim(),
            'status': 'open',
            'created_by': user.id,
          })
          .select('id')
          .single();
      final opts = choices.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      await db
          .from('property_vote_options')
          .insert(
            opts
                .asMap()
                .entries
                .map(
                  (e) => {
                    'vote_id': vote['id'],
                    'label': e.value,
                    'sort_order': e.key,
                  },
                )
                .toList(),
          );
      await refresh();
    } on PostgrestException catch (e) {
      message(e.message);
    } finally {
      title.dispose();
      question.dispose();
      choices.dispose();
    }
  }

  Future<void> createCharge() async {
    final period = TextEditingController(),
        desc = TextEditingController(),
        amount = TextEditingController(),
        due = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Νέα χρέωση κοινοχρήστων' : 'New common charge'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: period,
                decoration: InputDecoration(
                  labelText: gr
                      ? 'Περίοδος (π.χ. 11/2026)'
                      : 'Period (e.g. Nov 2026)',
                ),
                validator: required,
              ),
              TextFormField(
                controller: desc,
                decoration: InputDecoration(
                  labelText: gr ? 'Περιγραφή' : 'Description',
                ),
              ),
              TextFormField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: gr ? 'Συνολικό ποσό (€)' : 'Total amount (€)',
                ),
                validator: required,
              ),
              TextFormField(
                controller: due,
                decoration: InputDecoration(
                  labelText: gr
                      ? 'Ημερομηνία λήξης YYYY-MM-DD'
                      : 'Due date YYYY-MM-DD',
                ),
                validator: required,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                key.currentState!.validate() ? Navigator.pop(ctx, true) : null,
            child: Text(gr ? 'Καταχώριση' : 'Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.rpc(
        'create_property_charge_run',
        params: {
          'p_property_id': widget.propertyId,
          'p_period_label': period.text.trim(),
          'p_description': desc.text.trim(),
          'p_total_amount': double.parse(amount.text.replaceAll(',', '.')),
          'p_due_date': due.text.trim(),
          'p_currency': 'EUR',
        },
      );
      await refresh();
    } on PostgrestException catch (e) {
      message(e.message);
    } catch (e) {
      message('$e');
    } finally {
      period.dispose();
      desc.dispose();
      amount.dispose();
      due.dispose();
    }
  }

  Future<void> createRent() async {
    final unit = TextEditingController(),
        tenant = TextEditingController(),
        phone = TextEditingController(),
        amount = TextEditingController(),
        start = TextEditingController(),
        end = TextEditingController();
    final key = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Νέα μίσθωση' : 'New rental'),
        content: Form(
          key: key,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: unit,
                  decoration: InputDecoration(
                    labelText: gr ? 'Διαμέρισμα/μονάδα' : 'Unit',
                  ),
                  validator: required,
                ),
                TextFormField(
                  controller: tenant,
                  decoration: InputDecoration(
                    labelText: gr ? 'Όνομα ενοικιαστή' : 'Tenant name',
                  ),
                  validator: required,
                ),
                TextFormField(
                  controller: phone,
                  decoration: InputDecoration(
                    labelText: gr ? 'Τηλέφωνο' : 'Phone',
                  ),
                ),
                TextFormField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: gr ? 'Μηνιαίο ενοίκιο (€)' : 'Monthly rent (€)',
                  ),
                  validator: required,
                ),
                TextFormField(
                  controller: start,
                  decoration: InputDecoration(
                    labelText: gr ? 'Έναρξη YYYY-MM-DD' : 'Start YYYY-MM-DD',
                  ),
                  validator: required,
                ),
                TextFormField(
                  controller: end,
                  decoration: InputDecoration(
                    labelText: gr ? 'Λήξη (προαιρετικά)' : 'End (optional)',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                key.currentState!.validate() ? Navigator.pop(ctx, true) : null,
            child: Text(gr ? 'Καταχώριση' : 'Create'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await db.rpc(
        'create_property_rent_contract',
        params: {
          'p_property_id': widget.propertyId,
          'p_unit_reference': unit.text.trim(),
          'p_tenant_name': tenant.text.trim(),
          'p_tenant_phone_e164': phone.text.trim(),
          'p_monthly_rent': double.parse(amount.text.replaceAll(',', '.')),
          'p_currency': 'EUR',
          'p_start_date': start.text.trim(),
          'p_end_date': end.text.trim().isEmpty ? null : end.text.trim(),
          'p_due_day': 1,
        },
      );
      await refresh();
    } on PostgrestException catch (e) {
      message(e.message);
    } catch (e) {
      message('$e');
    } finally {
      unit.dispose();
      tenant.dispose();
      phone.dispose();
      amount.dispose();
      start.dispose();
      end.dispose();
    }
  }

  Future<void> createNote() async {
    final controller = TextEditingController();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Νέα σημείωση πολυκατοικίας' : 'New property note'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: gr ? 'Σύντομη ενημέρωση' : 'Short update',
              hintText: gr ? 'π.χ. Παρκάρω μπροστά στην είσοδο για 5 λεπτά' : 'e.g. Parking by the entrance for 5 minutes',
            ),
            validator: (value) => value == null || value.trim().isEmpty
                ? (gr ? 'Γράψε ένα μήνυμα.' : 'Enter a message.')
                : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
          FilledButton(onPressed: () => key.currentState!.validate() ? Navigator.pop(ctx, true) : null, child: Text(gr ? 'Δημοσίευση' : 'Post')),
        ],
      ),
    );
    if (saved == true) {
      try {
        await db.from('property_notes').insert({'property_id': widget.propertyId, 'body': controller.text.trim(), 'created_by': db.auth.currentUser!.id});
        await refresh();
      } on PostgrestException catch (e) {
        message(e.message);
      }
    }
    controller.dispose();
  }

  Widget notesListing() => FutureBuilder<List<Map<String, dynamic>>>(
    future: db.from('property_notes').select('id, body, created_at, created_by').eq('property_id', widget.propertyId).order('created_at', ascending: false).then((rows) => List<Map<String, dynamic>>.from(rows)),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError();
      final notes = snapshot.data ?? [];
      if (notes.isEmpty) return emptyState(
        icon: Icons.chat_bubble_outline,
        title: gr ? 'Δεν υπάρχουν σημειώσεις ακόμη' : 'No notices yet',
        description: gr ? 'Χρησιμοποίησε τις σημειώσεις για σύντομες ενημερώσεις προς τους ενοίκους.' : 'Use notices for short updates to residents.',
        action: gr ? 'Νέα σημείωση' : 'Write a notice',
        onPressed: createNote,
      );
      return RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: notes.map((note) {
            return Card(child: ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(note['body'] as String? ?? ''),
              subtitle: Text('${gr ? 'Κάτοικος' : 'Resident'} · ${formatTimestamp(note['created_at'])}'),
              trailing: isAdmin ? PopupMenuButton<String>(
                onSelected: (action) {
                  if (action == 'edit') _editNote(note);
                  if (action == 'delete') _deleteRow('property_notes', note['id'], gr ? 'σημείωση' : 'notice');
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
                  PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
                ],
              ) : null,
            ));
          }).toList(),
        ),
      );
    },
  );

  Future<void> openVote(Map<String, dynamic> vote) async {
    final options = List<Map<String, dynamic>>.from(
      await db
          .from('property_vote_options')
          .select('id, label')
          .eq('vote_id', vote['id']),
    );
    if (!mounted || options.isEmpty) return;
    String? selected;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(vote['title'] as String? ?? ''),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(vote['question'] as String? ?? ''),
              ...options.map(
                (o) => RadioListTile<String>(
                  value: o['id'] as String,
                  groupValue: selected,
                  onChanged: (v) => setDialog(() => selected = v),
                  title: Text(o['label'] as String),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(gr ? 'Κλείσιμο' : 'Close'),
            ),
            FilledButton(
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(ctx, selected),
              child: Text(gr ? 'Ψήφισε' : 'Vote'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    try {
      await db.rpc(
        'cast_property_vote',
        params: {'p_vote_id': vote['id'], 'p_option_id': choice},
      );
      message(gr ? 'Η ψήφος καταχωρίστηκε.' : 'Your vote was recorded.');
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> openCharge(Map<String, dynamic> run) async {
    try {
      final entries = List<Map<String, dynamic>>.from(
        await db
            .from('property_charge_entries')
            .select(
              'id, amount_due, amount_paid, status, property_owners(organizations(display_name))',
            )
            .eq('run_id', run['id']),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${run['period_label']} · ${run['total_amount']} ${run['currency']}',
          ),
          content: SizedBox(
            width: 440,
            child: entries.isEmpty
                ? Text(gr ? 'Δεν υπάρχουν κατανομές.' : 'No allocations yet.')
                : ListView(
                    shrinkWrap: true,
                    children: entries.map((entry) {
                      final owner =
                          entry['property_owners'] as Map<String, dynamic>? ??
                          {};
                      final org =
                          owner['organizations'] as Map<String, dynamic>? ?? {};
                      final due = (entry['amount_due'] as num).toDouble(),
                          paid = (entry['amount_paid'] as num).toDouble();
                      return ListTile(
                        title: Text(
                          org['display_name'] as String? ??
                              (gr ? 'Ιδιοκτήτης' : 'Owner'),
                        ),
                        subtitle: Text(
                          '${gr ? 'Οφειλή' : 'Due'}: ${due.toStringAsFixed(2)} € · ${gr ? 'Πληρωμή' : 'Paid'}: ${paid.toStringAsFixed(2)} €',
                        ),
                        trailing: IconButton(
                          tooltip: gr
                              ? (isAdmin ? 'Διόρθωση πληρωμής' : 'Καταχώριση πληρωμής')
                              : (isAdmin ? 'Adjust payment' : 'Record payment'),
                          icon: const Icon(Icons.payments_outlined),
                          onPressed: () => isAdmin
                              ? _editPaidAmount(table:'property_charge_entries',id:entry['id'],due:due,currentPaid:paid,rent:false)
                              : recordPayment(entry, due - paid),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(gr ? 'Κλείσιμο' : 'Close'),
            ),
          ],
        ),
      );
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> recordPayment(
    Map<String, dynamic> entry,
    double outstanding,
  ) async {
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    final key = GlobalKey<FormState>();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Καταχώριση πληρωμής' : 'Record payment'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: gr ? 'Ποσό (€)' : 'Amount (€)',
            ),
            validator: (v) {
              final n = double.tryParse((v ?? '').replaceAll(',', '.'));
              return n == null || n <= 0 || n > outstanding
                  ? (gr ? 'Μη έγκυρο ποσό.' : 'Invalid amount.')
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => key.currentState!.validate()
                ? Navigator.pop(
                    ctx,
                    double.parse(amount.text.replaceAll(',', '.')),
                  )
                : null,
            child: Text(gr ? 'Αποθήκευση' : 'Save'),
          ),
        ],
      ),
    );
    amount.dispose();
    if (result == null) return;
    try {
      await db.rpc(
        'record_property_charge_payment',
        params: {'p_entry_id': entry['id'], 'p_amount': result},
      );
      if (mounted) {
        message(gr ? 'Η πληρωμή καταχωρίστηκε.' : 'Payment recorded.');
        setState(() {});
      }
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> _editPaidAmount({
    required String table,
    required dynamic id,
    required double due,
    required double currentPaid,
    required bool rent,
  }) async {
    final amount = TextEditingController(text: currentPaid.toStringAsFixed(2));
    final form = GlobalKey<FormState>();
    final result = await showDialog<double>(context: context, builder: (ctx) => AlertDialog(
      title: Text(gr ? 'Διόρθωση καταβληθέντος ποσού' : 'Adjust amount paid'),
      content: Form(key:form,child:TextFormField(
        controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),
        decoration:InputDecoration(labelText:gr?'Ποσό που έχει πληρωθεί (€)':'Amount paid (€)'),
        validator:(v){final n=double.tryParse((v??'').replaceAll(',','.'));return n==null||n<0||n>due?(gr?'Βάλε ποσό από 0 έως ${due.toStringAsFixed(2)} €':'Enter an amount from 0 to ${due.toStringAsFixed(2)} €'):null;},
      )),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(gr?'Άκυρο':'Cancel')),FilledButton(onPressed:()=>form.currentState!.validate()?Navigator.pop(ctx,double.parse(amount.text.replaceAll(',','.'))):null,child:Text(gr?'Αποθήκευση':'Save'))],
    ));
    amount.dispose();
    if(result==null)return;
    final status=result==0?'unpaid':result>=due?'paid':'partial';
    try{
      await db.from(table).update({
        'amount_paid':result,'status':status,
        if(rent)'paid_at':result>=due?DateTime.now().toUtc().toIso8601String():null,
        if(!rent)'updated_at':DateTime.now().toUtc().toIso8601String(),
      }).eq('id',id);
      if(mounted){message(gr?'Η πληρωμή ενημερώθηκε.':'Payment updated.');setState((){});}
    }on PostgrestException catch(e){message(e.message);}
  }

  String formatTimestamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  String? required(String? v) =>
      v == null || v.trim().isEmpty ? (gr ? 'Υποχρεωτικό' : 'Required') : null;
  void message(String s) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  Widget listing(String table, String title, IconData icon) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: rows(table),
      builder: (ctx, s) {
        if (s.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (s.hasError) return loadError();
        final items = s.data ?? [];
        if (items.isEmpty)
          return emptyState(
            icon: icon,
            title: gr ? 'Δεν υπάρχουν εγγραφές ακόμη' : 'No records yet',
            description: gr ? 'Πρόσθεσε την πρώτη καταχώριση σε αυτή την ενότητα.' : 'Add the first record to this section.',
            action: gr ? 'Νέα καταχώριση' : 'Add record',
            onPressed: () => tabs.index == 0 ? createVote() : createRent(),
          );
        return RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: items
                .map(
                  (x) => Card(
                    child: ListTile(
                      leading: Icon(icon),
                      title: Text(
                        (x['title'] ??
                                x['period_label'] ??
                                x['unit_reference'] ??
                                '')
                            .toString(),
                      ),
                      subtitle: Text(
                        (x['question'] ??
                                x['description'] ??
                                '${x['tenant_name'] ?? ''} · ${x['monthly_rent'] ?? ''} €')
                            .toString(),
                      ),
                      trailing: Text((x['status'] ?? '').toString()),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }

  Widget voteListing() => FutureBuilder<List<Map<String, dynamic>>>(
    future: rows('property_votes'),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError();
      final votes = snapshot.data ?? [];
      if (votes.isEmpty)
        return emptyState(
          icon: Icons.how_to_vote_outlined,
          title: gr ? 'Δεν υπάρχουν ψηφοφορίες ακόμη' : 'No votes yet',
          description: gr ? 'Δημιούργησε μια ψηφοφορία για να αποφασίσουν οι ιδιοκτήτες.' : 'Create a vote so owners can decide together.',
          action: gr ? 'Νέα ψηφοφορία' : 'Create a vote',
          onPressed: createVote,
        );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: votes
            .map(
              (vote) => Card(
                child: ListTile(
                  leading: const Icon(Icons.how_to_vote_outlined),
                  title: Text(vote['title'] as String? ?? ''),
                  subtitle: Text(
                    '${vote['question'] ?? ''} · ${switch(vote['status']) {'draft' => gr ? 'Πρόχειρη' : 'Draft', 'open' => gr ? 'Ανοιχτή' : 'Open', 'closed' => gr ? 'Κλειστή' : 'Closed', _ => vote['status'] ?? ''}}',
                  ),
                  onTap: () => openVote(vote),
                  trailing: isAdmin ? PopupMenuButton<String>(
                    onSelected:(action){if(action=='edit')_editVote(vote);if(action=='delete')_deleteRow('property_votes',vote['id'],gr?'ψηφοφορία':'vote');},
                    itemBuilder:(ctx)=>[
                      PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
                      PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
                    ],
                  ):null,
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget chargeListing() => FutureBuilder<List<Map<String, dynamic>>>(
    future: rows('property_charge_runs'),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError();
      final runs = snapshot.data ?? [];
      if (runs.isEmpty)
        return emptyState(
          icon: Icons.receipt_long_outlined,
          title: gr ? 'Δεν υπάρχουν κοινόχρηστα ακόμη' : 'No shared charges yet',
          description: gr ? 'Καταχώρισε την περίοδο και το συνολικό ποσό για να δημιουργηθεί η κατανομή.' : 'Add a period and total amount to create a charge run.',
          action: gr ? 'Νέα χρέωση' : 'Add a charge',
          onPressed: createCharge,
        );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: runs
            .map(
              (run) => Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    '${run['period_label']} · ${run['total_amount']} ${run['currency']}',
                  ),
                  subtitle: Text(
                    '${run['description'] ?? ''} · ${gr ? 'Λήξη' : 'Due'} ${run['due_date']} · ${run['status'] == 'closed' ? (gr?'Κλειστή':'Closed') : (gr?'Ανοιχτή':'Open')}',
                  ),
                  onTap: () => openCharge(run),
                  trailing: isAdmin ? PopupMenuButton<String>(
                    onSelected:(action){if(action=='edit')_editCharge(run);if(action=='delete')_deleteRow('property_charge_runs',run['id'],gr?'χρέωση κοινοχρήστων':'charge');},
                    itemBuilder:(ctx)=>[
                      PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
                      PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
                    ],
                  ):null,
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Future<void> openRent(Map<String, dynamic> contract) async {
    try {
      final installments = List<Map<String, dynamic>>.from(
        await db
            .from('property_rent_installments')
            .select(
              'id, period_start, due_date, amount_due, amount_paid, status',
            )
            .eq('contract_id', contract['id'])
            .order('period_start'),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '${contract['unit_reference']} · ${contract['tenant_name']}',
          ),
          content: SizedBox(
            width: 440,
            child: installments.isEmpty
                ? Text(
                    gr ? 'Δεν υπάρχουν δόσεις.' : 'No installments scheduled.',
                  )
                : ListView(
                    shrinkWrap: true,
                    children: installments.map((row) {
                      final due = (row['amount_due'] as num).toDouble();
                      final paid = (row['amount_paid'] as num).toDouble();
                      return ListTile(
                        title: Text(
                          '${row['period_start']} · ${row['status']}',
                        ),
                        subtitle: Text(
                          '${gr ? 'Οφειλή' : 'Due'} ${due.toStringAsFixed(2)} € · ${gr ? 'Πληρώθηκε' : 'Paid'} ${paid.toStringAsFixed(2)} €',
                        ),
                        trailing: IconButton(
                          tooltip: gr
                              ? (isAdmin ? 'Διόρθωση πληρωμής' : 'Καταχώριση πληρωμής')
                              : (isAdmin ? 'Adjust payment' : 'Record payment'),
                          icon: const Icon(Icons.payments_outlined),
                          onPressed: () => isAdmin
                              ? _editPaidAmount(table:'property_rent_installments',id:row['id'],due:due,currentPaid:paid,rent:true)
                              : recordRentPayment(row, due - paid),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(gr ? 'Κλείσιμο' : 'Close'),
            ),
          ],
        ),
      );
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> recordRentPayment(
    Map<String, dynamic> installment,
    double outstanding,
  ) async {
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    final key = GlobalKey<FormState>();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Πληρωμή ενοικίου' : 'Record rent payment'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: gr ? 'Ποσό (€)' : 'Amount (€)',
            ),
            validator: (v) {
              final n = double.tryParse((v ?? '').replaceAll(',', '.'));
              return n == null || n <= 0 || n > outstanding
                  ? (gr ? 'Μη έγκυρο ποσό.' : 'Invalid amount.')
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => key.currentState!.validate()
                ? Navigator.pop(
                    ctx,
                    double.parse(amount.text.replaceAll(',', '.')),
                  )
                : null,
            child: Text(gr ? 'Αποθήκευση' : 'Save'),
          ),
        ],
      ),
    );
    amount.dispose();
    if (result == null) return;
    try {
      await db.rpc(
        'record_property_rent_payment',
        params: {'p_installment_id': installment['id'], 'p_amount': result},
      );
      if (mounted) {
        message(gr ? 'Η πληρωμή καταχωρίστηκε.' : 'Payment recorded.');
        setState(() {});
      }
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Widget rentListing() => FutureBuilder<List<Map<String, dynamic>>>(
    future: rows('property_rent_contracts'),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return loadError();
      final contracts = snapshot.data ?? [];
      if (contracts.isEmpty)
        return emptyState(
          icon: Icons.key_outlined,
          title: gr ? 'Δεν υπάρχουν μισθώσεις ακόμη' : 'No rental contracts yet',
          description: gr ? 'Πρόσθεσε μίσθωση για να παρακολουθείς ενοίκια και πληρωμές.' : 'Add a rental to track rent and payments.',
          action: gr ? 'Νέα μίσθωση' : 'Add a rental',
          onPressed: createRent,
        );
      return ListView(
        padding: const EdgeInsets.all(16),
        children: contracts
            .map(
              (contract) => Card(
                child: ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: Text(
                    '${contract['unit_reference']} · ${contract['tenant_name']}',
                  ),
                  subtitle: Text(
                    '${contract['monthly_rent']} ${contract['currency']} / ${gr ? 'μήνα' : 'month'} · ${switch(contract['status']) {'active' => gr?'Ενεργή':'Active', 'ended' => gr?'Έληξε':'Ended', _ => gr?'Ακυρώθηκε':'Cancelled'}}',
                  ),
                  onTap: () => openRent(contract),
                  trailing: isAdmin ? PopupMenuButton<String>(
                    onSelected:(action){if(action=='edit')_editRent(contract);if(action=='delete')_deleteRow('property_rent_contracts',contract['id'],gr?'μίσθωση':'rental contract');},
                    itemBuilder:(ctx)=>[
                      PopupMenuItem(value:'edit',child:Text(gr?'Επεξεργασία':'Edit')),
                      PopupMenuItem(value:'delete',child:Text(gr?'Διαγραφή':'Delete')),
                    ],
                  ):null,
                ),
              ),
            )
            .toList(),
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.propertyName),
      bottom: TabBar(
        controller: tabs,
        isScrollable: true,
        tabs: [
          Tab(text: gr ? 'Ψηφοφορίες' : 'Votes'),
          Tab(text: gr ? 'Ανακοινώσεις' : 'Notices'),
          Tab(text: gr ? 'Οικονομικά' : 'Finances'),
          Tab(text: gr ? 'Ενοίκια' : 'Rent'),
        ],
      ),
    ),
    floatingActionButton: AnimatedBuilder(
      animation: tabs,
      builder: (context, _) => FloatingActionButton.extended(
        onPressed: switch (tabs.index) {
          0 => createVote,
          1 => createNote,
          2 => createCharge,
          _ => createRent,
        },
        icon: const Icon(Icons.add),
        label: Text(switch (tabs.index) {
          0 => gr ? 'Νέα ψηφοφορία' : 'New vote',
          1 => gr ? 'Νέα σημείωση' : 'New notice',
          2 => gr ? 'Νέα χρέωση' : 'New charge',
          _ => gr ? 'Νέα μίσθωση' : 'New rental',
        }),
      ),
    ),
    body: TabBarView(
      controller: tabs,
      children: [voteListing(), notesListing(), chargeListing(), rentListing()],
    ),
  );
}


