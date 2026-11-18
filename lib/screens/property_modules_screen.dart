Warning: truncated output (original token count: 17214)
Total output lines: 1858

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
              Icon(
                icon,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
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
          content: Text(
            gr
                ? 'Η διαγραφή δεν μπορεί να αναιρεθεί.'
                : 'This deletion cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(gr ? 'Διαγραφή' : 'Delete'),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _editNote(Map<String, dynamic> note) async {
    final text = TextEditingController(text: note['body'] as String? ?? '');
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(gr ? 'Επεξεργασία σημείωσης' : 'Edit notice'),
        content: Form(
          key: form,
          child: TextFormField(
            controller: text,
            autofocus: true,
            maxLines: 4,
            maxLength: 500,
            validator: required,
            decoration: InputDecoration(labelText: gr ? 'Μήνυμα' : 'Message'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                form.currentState!.validate() ? Navigator.pop(ctx, true) : null,
            child: Text(gr ? 'Αποθήκευση' : 'Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await db
            .from('property_notes')
            .update({'body': text.text.trim()})
            .eq('id', note['id']);
        await refresh();
      } on PostgrestException catch (e) {
        message(e.message);
      }
    }
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
    final question = TextEditingController(
      text: vote['question'] as String? ?? '',
    );
    var status = vote['status'] as String? ?? 'open';
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Επεξεργασία ψηφοφορίας' : 'Edit vote'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: title,
                      decoration: InputDecoration(
                        labelText: gr ? 'Τίτλος' : 'Title',
                      ),
                      validator: required,
                    ),
                    TextFormField(
                      controller: question,
                      decoration: InputDecoration(
                        labelText: gr ? 'Ερώτηση' : 'Question',
                      ),
                      validator: required,
                    ),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: InputDecoration(
                        labelText: gr ? 'Κατάσταση' : 'Status',
                      ),
                      items: ['draft', 'open', 'closed']
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(switch (s) {
                                'draft' => gr ? 'Πρόχειρη' : 'Draft',
                                'open' => gr ? 'Ανοιχτή' : 'Open',
                                _ => gr ? 'Κλειστή' : 'Closed',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => form.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await db
            .from('property_votes')
            .update({
              'title': title.text.trim(),
              'question': question.text.trim(),
              'status': status,
            })
            .eq('id', vote['id']);
        await refresh();
      } on PostgrestException catch (e) {
        message(e.message);
      }
    }
    title.dispose();
    question.dispose();
  }

  Future<void> _editCharge(Map<String, dynamic> run) async {
    final period = TextEditingController(
      text: run['period_label'] as String? ?? '',
    );
    final desc = TextEditingController(
      text: run['description'] as String? ?? '',
    );
    final due = TextEditingController(text: run['due_date'] as String? ?? '');
    var status = run['status'] as String? ?? 'open';
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Επεξεργασία χρέωσης' : 'Edit charge'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: period,
                      decoration: InputDecoration(
                        labelText: gr ? 'Περίοδος' : 'Period',
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
                      controller: due,
                      decoration: InputDecoration(labelText: 'YYYY-MM-DD'),
                      validator: (v) =>
                          DateTime.tryParse((v ?? '').trim()) == null
                          ? (gr
                                ? 'Χρησιμοποίησε ημερομηνία YYYY-MM-DD.'
                                : 'Enter a date as YYYY-MM-DD.')
                          : null,
                    ),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: InputDecoration(
                        labelText: gr ? 'Κατάσταση' : 'Status',
                      ),
                      items: ['open', 'closed']
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s == 'open'
                                    ? (gr ? 'Ανοιχτή' : 'Open')
                                    : (gr ? 'Κλειστή' : 'Closed'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => form.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await db
            .from('property_charge_runs')
            .update({
              'period_label': period.text.trim(),
              'description': desc.text.trim().isEmpty ? null : desc.text.trim(),
              'due_date': due.text.trim(),
              'status': status,
            })
            .eq('id', run['id']);
        await refresh();
      } on PostgrestException catch (e) {
        message(e.message);
      }
    }
    period.dispose();
    desc.dispose();
    due.dispose();
  }

  Future<void> _editRent(Map<String, dynamic> contract) async {
    final unit = TextEditingController(
      text: contract['unit_reference'] as String? ?? '',
    );
    final tenant = TextEditingController(
      text: contract['tenant_name'] as String? ?? '',
    );
    final phone = TextEditingController(
      text: contract['tenant_phone_e164'] as String? ?? '',
    );
    var status = contract['status'] as String? ?? 'active';
    final form = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Επεξεργασία μίσθωσης' : 'Edit rental'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: unit,
                      decoration: InputDecoration(
                        labelText: gr ? 'Μονάδα' : 'Unit',
                      ),
                      validator: required,
                    ),
                    TextFormField(
                      controller: tenant,
                      decoration: InputDecoration(
                        labelText: gr ? 'Ενοικιαστής' : 'Tenant',
                      ),
                      validator: required,
                    ),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: gr ? 'Τηλέφωνο' : 'Phone',
                      ),
                      validator: (v) {
                        final p = (v ?? '').trim();
                        return p.isEmpty ||
                                RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(p)
                            ? null
                            : (gr
                                  ? 'Χρησιμοποίησε διεθνή μορφή.'
                                  : 'Use international phone format.');
                      },
                    ),
                    DropdownButtonFormField<String>(
                      value: status,
                      decoration: InputDecoration(
                        labelText: gr ? 'Κατάσταση' : 'Status',
                      ),
                      items: ['active', 'ended', 'cancelled']
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(switch (s) {
                                'active' => gr ? 'Ενεργή' : 'Active',
                                'ended' => gr ? 'Έληξε' : 'Ended',
                                _ => gr ? 'Ακυρώθηκε' : 'Cancelled',
                              }),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => status = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => form.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (save == true) {
      try {
        await db
            .from('property_rent_contracts')
            .update({
              'unit_reference': unit.text.trim(),
              'tenant_name': tenant.text.trim(),
              'tenant_phone_e164': phone.text.trim().isEmpty
                  ? null
                  : phone.text.trim(),
              'status': status,
            })
            .eq('id', contract['id']);
        await refresh();
      } on PostgrestException catch (e) {
        message(e.message);
      }
    }
    unit.dispose();
    tenant.dispose();
    phone.dispose();
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

  String? normalizeRentPhone(String value) {
    var digits = value.trim().replaceAll(RegExp(r'[\s()\-]'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (!digits.startsWith('+')) {
      if (digits.startsWith('357') && digits.length == 11) {
        digits = '+$digits';
      } else if (RegExp(r'^\d{8}$').hasMatch(digits)) {
        digits = '+357$digits';
      }
    }
    return RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(digits) ? digits : null;
  }

  String? rentDateError(String? value, {bool optional = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) {
      return optional
          ? null
          : (gr ? 'Συμπλήρωσε την ημερομηνία.' : 'Enter a date.');
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != text) {
      return gr ? 'Χρησιμοποίησε μορφή YYYY-MM-DD.' : 'Use YYYY-MM-DD format.';
    }
    return null;
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
                    hintText: gr ? 'π.χ. 99123456' : 'e.g. 99123456',
                  ),
                  validator: (value) =>
                      (value?.trim().isEmpty ?? true) ||
                          normalizeRentPhone(value!) != null
                      ? null
                      : (gr
                            ? 'Βάλε έγκυρο τηλέφωνο, π.χ. 99123456.'
                            : 'Enter a valid phone number.'),
                ),
                TextFormField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: gr ? 'Μηνιαίο ενοίκιο (€)' : 'Monthly rent (€)',
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(
                      (value ?? '').trim().replaceAll(',', '.'),
                    );
                    return parsed == null || parsed <= 0
                        ? (gr
                              ? 'Βάλε έγκυρο ποσό μεγαλύτερο από 0.'
                              : 'Enter an amount greater than 0.')
                        : null;
                  },
                ),
                TextFormField(
                  controller: start,
                  decoration: InputDecoration(
                    labelText: gr ? 'Έναρξη YYYY-MM-DD' : 'Start YYYY-MM-DD',
                  ),
                  validator: rentDateError,
                ),
                TextFormField(
                  controller: end,
                  decoration: InputDecoration(
                    labelText: gr ? 'Λήξη (προαιρετικά)' : 'End (optional)',
                  ),
                  validator: (value) {
                    final error = rentDateError(value, optional: true);
                    if (error != null) return error;
                    if ((value ?? '').trim().isNotEmpty &&
                        (start.text.trim().isEmpty ||
                            value!.trim().compareTo(start.text.trim()) < 0)) {
                      return gr
                          ? 'Η λήξη πρέπει να είναι μετά την έναρξη.'
                          : 'End date must be on or after the start date.';
                    }
                    return null;
                  },
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
          'p_tenant_phone_e164': normalizeRentPhone(phone.text),
          'p_monthly_rent': double.parse(amount.text.replaceAll(',', '.')),
          'p_currency': 'EUR',
          'p_start_date': start.text.trim(),
          'p_end_date': end.text.trim().isEmpty ? null : end.text.trim(),
          'p_due_d…2214 tokens truncated…pple Pay ή Google Pay'
                                  : 'Pay online by card, Apple Pay, or Google Pay',
                              icon: const Icon(Icons.credit_card_outlined),
                              onPressed: due > paid && !busy
                                  ? () => payOnline('charge', entry['id'])
                                  : null,
                            ),
                            IconButton(
                              tooltip: gr
                                  ? 'Καταχώριση πληρωμής'
                                  : 'Record payment',
                              icon: const Icon(Icons.payments_outlined),
                              onPressed: () => recordPayment(entry, due - paid),
                            ),
                            IconButton(
                              tooltip: gr
                                  ? 'Ιστορικό πληρωμών'
                                  : 'Payment history',
                              icon: const Icon(Icons.history),
                              onPressed: () =>
                                  _showPaymentHistory(entry['id'], rent: false),
                            ),
                          ],
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
    final result = await _collectPayment(outstanding, rent: false);
    if (result == null) return;
    try {
      await db.rpc(
        'record_property_charge_payment',
        params: {
          'p_entry_id': entry['id'],
          'p_amount': result['amount'],
          'p_method': result['method'],
          'p_reference': result['reference'],
          'p_notes': result['notes'],
          'p_paid_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      if (mounted) {
        message(gr ? 'Η πληρωμή καταχωρίστηκε.' : 'Payment recorded.');
        setState(() {});
      }
    } on PostgrestException catch (e) {
      message(e.message);
    }
  }

  Future<void> payOnline(String targetType, dynamic targetId) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final response = await db.functions.invoke(
        'create-checkout-session',
        body: {'target_type': targetType, 'target_id': targetId.toString()},
      );
      final data = response.data;
      final url = data is Map ? data['url']?.toString() : null;
      if (response.status < 200 || response.status >= 300 || url == null) {
        final reason = data is Map ? data['error']?.toString() : null;
        throw Exception(
          reason ??
              (gr ? 'Δεν ξεκίνησε η πληρωμή.' : 'Could not start payment.'),
        );
      }
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.platformDefault,
      );
      if (!opened) {
        throw Exception(
          gr
              ? 'Δεν άνοιξε η ασφαλής σελίδα πληρωμής.'
              : 'Could not open the secure checkout page.',
        );
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final reason = details is Map ? details['error']?.toString() : null;
      message(
        reason ??
            (gr
                ? 'Δεν ξεκίνησε η ασφαλής πληρωμή. Δοκίμασε ξανά.'
                : 'Could not start secure checkout. Try again.'),
      );
    } catch (error) {
      message(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<Map<String, dynamic>?> _collectPayment(
    double outstanding, {
    required bool rent,
  }) async {
    final amount = TextEditingController(text: outstanding.toStringAsFixed(2));
    final reference = TextEditingController();
    final notes = TextEditingController();
    final key = GlobalKey<FormState>();
    var method = 'bank_transfer';
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          gr
              ? (rent ? 'Πληρωμή ενοικίου' : 'Πληρωμή κοινοχρήστων')
              : (rent ? 'Record rent payment' : 'Record charge payment'),
        ),
        content: Form(
          key: key,
          child: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
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
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: InputDecoration(
                      labelText: gr ? 'Τρόπος πληρωμής' : 'Payment method',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'bank_transfer',
                        child: Text(
                          gr ? 'Τραπεζική μεταφορά' : 'Bank transfer',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'cash',
                        child: Text(gr ? 'Μετρητά' : 'Cash'),
                      ),
                      DropdownMenuItem(
                        value: 'card',
                        child: Text(
                          gr ? 'Κάρτα / ηλεκτρονικά' : 'Card / online',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'cheque',
                        child: Text(gr ? 'Επιταγή' : 'Cheque'),
                      ),
                      DropdownMenuItem(
                        value: 'other',
                        child: Text(gr ? 'Άλλο' : 'Other'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) method = v;
                    },
                  ),
                  TextFormField(
                    controller: reference,
                    decoration: InputDecoration(
                      labelText: gr
                          ? 'Αριθμός αναφοράς (προαιρετικό)'
                          : 'Reference (optional)',
                    ),
                  ),
                  TextFormField(
                    controller: notes,
                    decoration: InputDecoration(
                      labelText: gr
                          ? 'Σημειώσεις (προαιρετικά)'
                          : 'Notes (optional)',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => key.currentState!.validate()
                ? Navigator.pop(ctx, {
                    'amount': double.parse(amount.text.replaceAll(',', '.')),
                    'method': method,
                    'reference': reference.text.trim().isEmpty
                        ? null
                        : reference.text.trim(),
                    'notes': notes.text.trim().isEmpty
                        ? null
                        : notes.text.trim(),
                  })
                : null,
            child: Text(gr ? 'Αποθήκευση' : 'Save'),
          ),
        ],
      ),
    );
    amount.dispose();
    reference.dispose();
    notes.dispose();
    return result;
  }

  Future<void> _showPaymentHistory(
    dynamic targetId, {
    required bool rent,
  }) async {
    try {
      final records = await db
          .from('property_payment_records')
          .select('amount,payment_method,reference,notes,paid_at')
          .eq(rent ? 'rent_installment_id' : 'charge_entry_id', targetId)
          .order('paid_at', ascending: false);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(gr ? 'Ιστορικό πληρωμών' : 'Payment history'),
          content: SizedBox(
            width: 420,
            child: records.isEmpty
                ? Text(
                    gr
                        ? 'Δεν έχουν καταχωριστεί πληρωμές.'
                        : 'No payments recorded yet.',
                  )
                : ListView(
                    shrinkWrap: true,
                    children: records
                        .map<Widget>(
                          (row) => ListTile(
                            leading: const Icon(Icons.receipt_long_outlined),
                            title: Text(
                              '${(row['amount'] as num).toStringAsFixed(2)} € · ${paymentMethodLabel(row['payment_method'])}',
                            ),
                            subtitle: Text(
                              [
                                if ((row['reference'] ?? '')
                                    .toString()
                                    .isNotEmpty)
                                  '${gr ? 'Αναφορά' : 'Ref'}: ${row['reference']}',
                                if ((row['notes'] ?? '').toString().isNotEmpty)
                                  row['notes'],
                                formatTimestamp(row['paid_at']),
                              ].join(' · '),
                            ),
                          ),
                        )
                        .toList(),
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

  String formatTimestamp(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
  }

  String paymentMethodLabel(dynamic method) => switch (method) {
    'bank_transfer' => gr ? 'Τραπεζική μεταφορά' : 'Bank transfer',
    'cash' => gr ? 'Μετρητά' : 'Cash',
    'card' => gr ? 'Κάρτα / ηλεκτρονικά' : 'Card / online',
    'apple_pay' => 'Apple Pay',
    'google_pay' => 'Google Pay',
    'cheque' => gr ? 'Επιταγή' : 'Cheque',
    _ => gr ? 'Άλλο' : 'Other',
  };

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
            description: gr
                ? 'Πρόσθεσε την πρώτη καταχώριση σε αυτή την ενότητα.'
                : 'Add the first record to this section.',
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
          description: gr
              ? 'Δημιούργησε μια ψηφοφορία για να αποφασίσουν οι ιδιοκτήτες.'
              : 'Create a vote so owners can decide together.',
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
                    '${vote['question'] ?? ''} · ${switch (vote['status']) {
                      'draft' => gr ? 'Πρόχειρη' : 'Draft',
                      'open' => gr ? 'Ανοιχτή' : 'Open',
                      'closed' => gr ? 'Κλειστή' : 'Closed',
                      _ => vote['status'] ?? '',
                    }}',
                  ),
                  onTap: () => openVote(vote),
                  trailing: isAdmin
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') _editVote(vote);
                            if (action == 'delete')
                              _deleteRow(
                                'property_votes',
                                vote['id'],
                                gr ? 'ψηφοφορία' : 'vote',
                              );
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(gr ? 'Επεξεργασία' : 'Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(gr ? 'Διαγραφή' : 'Delete'),
                            ),
                          ],
                        )
                      : null,
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
          title: gr
              ? 'Δεν υπάρχουν κοινόχρηστα ακόμη'
              : 'No shared charges yet',
          description: gr
              ? 'Καταχώρισε την περίοδο και το συνολικό ποσό για να δημιουργηθεί η κατανομή.'
              : 'Add a period and total amount to create a charge run.',
          action: gr ? 'Νέα χρέωση' : 'Add a charge',
          onPressed: createCharge,
        );
      final runIds = runs.map((run) => run['id'].toString()).toList();
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: db
            .from('property_charge_entries')
            .select('run_id, amount_due, amount_paid')
            .inFilter('run_id', runIds)
            .then((rows) => List<Map<String, dynamic>>.from(rows)),
        builder: (context, entriesSnapshot) {
          if (entriesSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (entriesSnapshot.hasError) return loadError();

          final totals = <String, (double, double)>{};
          for (final entry in entriesSnapshot.data ?? const []) {
            final key = entry['run_id'].toString();
            final current = totals[key] ?? (0.0, 0.0);
            totals[key] = (
              current.$1 + (entry['amount_due'] as num).toDouble(),
              current.$2 + (entry['amount_paid'] as num).toDouble(),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: runs.map((run) {
              final amounts = totals[run['id'].toString()] ?? (0.0, 0.0);
              final outstanding = (amounts.$1 - amounts.$2).clamp(
                0.0,
                double.infinity,
              );
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    '${run['period_label']} · ${run['total_amount']} ${run['currency']}',
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${gr ? 'Καταβλήθηκαν' : 'Collected'}: ${amounts.$2.toStringAsFixed(2)} € · ${gr ? 'Οφείλονται' : 'Outstanding'}: ${outstanding.toStringAsFixed(2)} €',
                      ),
                      Text(
                        '${run['description'] ?? ''} · ${gr ? 'Λήξη' : 'Due'} ${run['due_date']} · ${run['status'] == 'closed' ? (gr ? 'Κλειστή' : 'Closed') : (gr ? 'Ανοιχτή' : 'Open')}',
                      ),
                    ],
                  ),
                  onTap: () => openCharge(run),
                  trailing: isAdmin
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') _editCharge(run);
                            if (action == 'delete') {
                              _deleteRow(
                                'property_charge_runs',
                                run['id'],
                                gr ? 'χρέωση κοινοχρήστων' : 'charge',
                              );
                            }
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(gr ? 'Επεξεργασία' : 'Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(gr ? 'Διαγραφή' : 'Delete'),
                            ),
                          ],
                        )
                      : null,
                ),
              );
            }).toList(),
          );
        },
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
                        trailing: Wrap(
                          children: [
                            IconButton(
                              tooltip: gr
                                  ? 'Πληρωμή online με κάρτα, Apple Pay ή Google Pay'
                                  : 'Pay online by card, Apple Pay, or Google Pay',
                              icon: const Icon(Icons.credit_card_outlined),
                              onPressed: due > paid && !busy
                                  ? () => payOnline('rent', row['id'])
                                  : null,
                            ),
                            IconButton(
                              tooltip: gr
                                  ? 'Καταχώριση πληρωμής'
                                  : 'Record payment',
                              icon: const Icon(Icons.payments_outlined),
                              onPressed: () =>
                                  recordRentPayment(row, due - paid),
                            ),
                            IconButton(
                              tooltip: gr
                                  ? 'Ιστορικό πληρωμών'
                                  : 'Payment history',
                              icon: const Icon(Icons.history),
                              onPressed: () =>
                                  _showPaymentHistory(row['id'], rent: true),
                            ),
                          ],
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
    final result = await _collectPayment(outstanding, rent: true);
    if (result == null) return;
    try {
      await db.rpc(
        'record_property_rent_payment',
        params: {
          'p_installment_id': installment['id'],
          'p_amount': result['amount'],
          'p_method': result['method'],
          'p_reference': result['reference'],
          'p_notes': result['notes'],
          'p_paid_at': DateTime.now().toUtc().toIso8601String(),
        },
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
          title: gr
              ? 'Δεν υπάρχουν μισθώσεις ακόμη'
              : 'No rental contracts yet',
          description: gr
              ? 'Πρόσθεσε μίσθωση για να παρακολουθείς ενοίκια και πληρωμές.'
              : 'Add a rental to track rent and payments.',
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
                    '${contract['monthly_rent']} ${contract['currency']} / ${gr ? 'μήνα' : 'month'} · ${switch (contract['status']) {
                      'active' => gr ? 'Ενεργή' : 'Active',
                      'ended' => gr ? 'Έληξε' : 'Ended',
                      _ => gr ? 'Ακυρώθηκε' : 'Cancelled',
                    }}',
                  ),
                  onTap: () => openRent(contract),
                  trailing: isAdmin
                      ? PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'edit') _editRent(contract);
                            if (action == 'delete')
                              _deleteRow(
                                'property_rent_contracts',
                                contract['id'],
                                gr ? 'μίσθωση' : 'rental contract',
                              );
                          },
                          itemBuilder: (ctx) => [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text(gr ? 'Επεξεργασία' : 'Edit'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(gr ? 'Διαγραφή' : 'Delete'),
                            ),
                          ],
                        )
                      : null,
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

