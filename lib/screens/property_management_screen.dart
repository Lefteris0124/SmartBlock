import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PropertyManagementScreen extends StatefulWidget {
  const PropertyManagementScreen({
    required this.propertyId,
    required this.propertyName,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final bool isGreek;

  @override
  State<PropertyManagementScreen> createState() =>
      _PropertyManagementScreenState();
}

class _PropertyManagementScreenState extends State<PropertyManagementScreen> {
  final db = Supabase.instance.client;
  late Future<Map<String, dynamic>> data = _load();
  bool get gr => widget.isGreek;
  bool busy = false;
  bool canManage = false;

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  Future<void> _loadAccess() async {
    try {
      final allowed = await db.rpc(
        'can_manage_property',
        params: {'target_property_id': widget.propertyId},
      );
      if (mounted) setState(() => canManage = allowed == true);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _load() async {
    final values = await Future.wait<dynamic>([
      db
          .from('property_management_contracts')
          .select()
          .eq('property_id', widget.propertyId)
          .order('starts_on', ascending: false),
      db
          .from('property_management_services')
          .select()
          .eq('property_id', widget.propertyId)
          .order('active', ascending: false),
      db
          .from('property_operating_expenses')
          .select()
          .eq('property_id', widget.propertyId)
          .order('expense_date', ascending: false),
      db
          .from('property_finance_settings')
          .select()
          .eq('property_id', widget.propertyId)
          .maybeSingle(),
      db
          .from('property_arrears_actions')
          .select(
            'id,stage,communication_method,occurred_at,agreed_fee,fee_basis,notes,property_owners(organizations(display_name))',
          )
          .eq('property_id', widget.propertyId)
          .order('occurred_at', ascending: false),
      db
          .from('property_insurance_policies')
          .select()
          .eq('property_id', widget.propertyId)
          .order('expires_on'),
      db
          .from('property_meetings')
          .select()
          .eq('property_id', widget.propertyId)
          .order('starts_at', ascending: false),
      db
          .from('property_handover_records')
          .select()
          .eq('property_id', widget.propertyId)
          .order('handover_date', ascending: false),
      db
          .from('property_charge_entries')
          .select('amount_paid,property_charge_runs!inner(property_id)')
          .eq('property_charge_runs.property_id', widget.propertyId),
    ]);
    return {
      'contracts': List<Map<String, dynamic>>.from(values[0]),
      'services': List<Map<String, dynamic>>.from(values[1]),
      'expenses': List<Map<String, dynamic>>.from(values[2]),
      'settings': values[3] as Map<String, dynamic>?,
      'arrears': List<Map<String, dynamic>>.from(values[4]),
      'insurance': List<Map<String, dynamic>>.from(values[5]),
      'meetings': List<Map<String, dynamic>>.from(values[6]),
      'handovers': List<Map<String, dynamic>>.from(values[7]),
      'charge_entries': List<Map<String, dynamic>>.from(values[8]),
    };
  }

  Future<void> _refresh() async {
    setState(() => data = _load());
    try {
      await data;
    } catch (_) {}
  }

  void _message(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? (gr ? 'Υποχρεωτικό πεδίο' : 'Required')
      : null;

  String? _dateValidator(String? value, {bool optional = false}) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && optional) return null;
    return DateTime.tryParse(text) == null
        ? (gr ? 'Χρησιμοποίησε μορφή YYYY-MM-DD' : 'Use YYYY-MM-DD')
        : null;
  }

  TextFormField _field(
    TextEditingController controller,
    String label, {
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int lines = 1,
    String? helper,
  }) => TextFormField(
    controller: controller,
    validator: validator,
    keyboardType: keyboard,
    maxLines: lines,
    decoration: InputDecoration(labelText: label, helperText: helper),
  );

  Future<bool> _formDialog(String title, List<Widget> fields) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: fields),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(gr ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => _formKey.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ) ==
      true;

  final _formKey = GlobalKey<FormState>();

  Future<void> _insert(String table, Map<String, dynamic> values) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await db.from(table).insert({
        ...values,
        'property_id': widget.propertyId,
      });
      await _refresh();
      _message(gr ? 'Η καταχώριση αποθηκεύτηκε.' : 'Saved.');
    } on PostgrestException catch (e) {
      _message(e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _newContract() async {
    final provider = TextEditingController(),
        fee = TextEditingController(),
        vat = TextEditingController(text: '0'),
        starts = TextEditingController(),
        ends = TextEditingController(),
        notice = TextEditingController(text: '3'),
        approval = TextEditingController(),
        compensation = TextEditingController(),
        terms = TextEditingController();
    var cycle = 'monthly', autoRenew = false, pauseOnDeficit = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            gr ? 'Νέα σύμβαση διαχείρισης' : 'New management contract',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _field(
                      provider,
                      gr ? 'Εταιρεία διαχείρισης' : 'Management company',
                      validator: _required,
                    ),
                    _field(
                      fee,
                      gr
                          ? 'Βασική αμοιβή ανά μήνα (€)'
                          : 'Base monthly fee (€)',
                      validator: _required,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      vat,
                      'VAT %',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      starts,
                      gr ? 'Έναρξη (YYYY-MM-DD)' : 'Start date (YYYY-MM-DD)',
                      validator: _dateValidator,
                    ),
                    _field(
                      ends,
                      gr
                          ? 'Λήξη (προαιρετικά, YYYY-MM-DD)'
                          : 'End date (optional, YYYY-MM-DD)',
                      validator: (v) => _dateValidator(v, optional: true),
                    ),
                    DropdownButtonFormField<String>(
                      value: cycle,
                      decoration: InputDecoration(
                        labelText: gr
                            ? 'Περιοδικότητα χρεώσεων'
                            : 'Billing frequency',
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'monthly',
                          child: Text(gr ? 'Μηνιαία' : 'Monthly'),
                        ),
                        DropdownMenuItem(
                          value: 'quarterly',
                          child: Text(gr ? 'Τριμηνιαία' : 'Quarterly'),
                        ),
                        DropdownMenuItem(
                          value: 'semiannual',
                          child: Text(gr ? 'Εξαμηνιαία' : 'Semiannual'),
                        ),
                        DropdownMenuItem(
                          value: 'annual',
                          child: Text(gr ? 'Ετήσια' : 'Annual'),
                        ),
                        DropdownMenuItem(
                          value: 'custom',
                          child: Text(
                            gr
                                ? 'Άλλη συμφωνημένη περίοδος'
                                : 'Other agreed period',
                          ),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialog(() => cycle = v);
                      },
                    ),
                    _field(
                      notice,
                      gr
                          ? 'Προειδοποίηση λήξης (μήνες)'
                          : 'Notice period (months)',
                      keyboard: TextInputType.number,
                    ),
                    _field(
                      approval,
                      gr
                          ? 'Ποσοστό έγκρισης λύσης, αν προβλέπεται (%)'
                          : 'Termination approval percentage, if specified (%)',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      compensation,
                      gr
                          ? 'Αποζημίωση σε μήνες, αν προβλέπεται'
                          : 'Termination compensation in months, if specified',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      terms,
                      gr
                          ? 'Σημειώσεις όρων της συγκεκριμένης σύμβασης'
                          : 'Notes on this contract’s terms',
                      lines: 3,
                    ),
                    SwitchListTile(
                      title: Text(gr ? 'Αυτόματη ανανέωση' : 'Auto-renewal'),
                      value: autoRenew,
                      onChanged: (v) => setDialog(() => autoRenew = v),
                    ),
                    SwitchListTile(
                      title: Text(
                        gr
                            ? 'Παύση πληρωμών όταν υπάρχει έλλειμμα'
                            : 'Pause payments when funds are insufficient',
                      ),
                      value: pauseOnDeficit,
                      onChanged: (v) => setDialog(() => pauseOnDeficit = v),
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
              onPressed: () => _formKey.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _insert('property_management_contracts', {
        'provider_name': provider.text.trim(),
        'monthly_fee': double.parse(fee.text.replaceAll(',', '.')),
        'vat_rate': double.tryParse(vat.text.replaceAll(',', '.')) ?? 0,
        'starts_on': starts.text.trim(),
        'ends_on': ends.text.trim().isEmpty ? null : ends.text.trim(),
        'billing_cycle': cycle,
        'notice_period_months': int.tryParse(notice.text) ?? 0,
        'termination_approval_percent': double.tryParse(
          approval.text.replaceAll(',', '.'),
        ),
        'termination_compensation_months': double.tryParse(
          compensation.text.replaceAll(',', '.'),
        ),
        'terms_summary': terms.text.trim(),
        'auto_renew': autoRenew,
        'pause_payments_if_fund_deficit': pauseOnDeficit,
      });
    }
    for (final c in [
      provider,
      fee,
      vat,
      starts,
      ends,
      notice,
      approval,
      compensation,
      terms,
    ]) {
      c.dispose();
    }
  }

  Future<void> _newService() async {
    final title = TextEditingController(),
        desc = TextEditingController(),
        fee = TextEditingController();
    var unit = 'fixed', approved = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Πρόσθετη υπηρεσία' : 'Additional service'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(
                    title,
                    gr ? 'Υπηρεσία' : 'Service',
                    validator: _required,
                  ),
                  _field(desc, gr ? 'Περιγραφή' : 'Description', lines: 2),
                  DropdownButtonFormField<String>(
                    value: unit,
                    decoration: InputDecoration(
                      labelText: gr ? 'Μονάδα χρέωσης' : 'Fee unit',
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'fixed',
                        child: Text(gr ? 'Σταθερό ποσό' : 'Fixed fee'),
                      ),
                      DropdownMenuItem(
                        value: 'per_hour',
                        child: Text(gr ? 'Ανά ώρα' : 'Per hour'),
                      ),
                      DropdownMenuItem(
                        value: 'per_visit',
                        child: Text(gr ? 'Ανά επίσκεψη' : 'Per visit'),
                      ),
                      DropdownMenuItem(
                        value: 'per_letter',
                        child: Text(gr ? 'Ανά επιστολή' : 'Per letter'),
                      ),
                      DropdownMenuItem(
                        value: 'quote_required',
                        child: Text(
                          gr ? 'Απαιτείται προσφορά' : 'Quote required',
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialog(() => unit = v);
                    },
                  ),
                  _field(
                    fee,
                    gr ? 'Ποσό (€), αν έχει συμφωνηθεί' : 'Fee (€), if agreed',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  SwitchListTile(
                    title: Text(
                      gr
                          ? 'Απαιτείται προηγούμενη έγκριση'
                          : 'Prior approval required',
                    ),
                    value: approved,
                    onChanged: (v) => setDialog(() => approved = v),
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
              onPressed: () => _formKey.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true)
      await _insert('property_management_services', {
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'fee_unit': unit,
        'fee_amount': double.tryParse(fee.text.replaceAll(',', '.')),
        'requires_prior_approval': approved,
      });
    title.dispose();
    desc.dispose();
    fee.dispose();
  }

  Future<void> _newExpense() async {
    final desc = TextEditingController(),
        amount = TextEditingController(),
        supplier = TextEditingController(),
        date = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10),
        ),
        notes = TextEditingController();
    final ok = await _formDialog(gr ? 'Νέο έξοδο' : 'New expense', [
      _field(desc, gr ? 'Περιγραφή' : 'Description', validator: _required),
      _field(
        amount,
        gr ? 'Ποσό (€)' : 'Amount (€)',
        validator: _required,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
      _field(supplier, gr ? 'Προμηθευτής' : 'Supplier'),
      _field(
        date,
        gr ? 'Ημερομηνία (YYYY-MM-DD)' : 'Date (YYYY-MM-DD)',
        validator: _dateValidator,
      ),
      _field(
        notes,
        gr ? 'Σημειώσεις / σύνδεσμος προσφοράς' : 'Notes / quote reference',
        lines: 2,
      ),
    ]);
    if (ok)
      await _insert('property_operating_expenses', {
        'description': desc.text.trim(),
        'amount': double.parse(amount.text.replaceAll(',', '.')),
        'supplier': supplier.text.trim(),
        'expense_date': date.text.trim(),
        'notes': notes.text.trim(),
        'status': 'awaiting_approval',
      });
    for (final c in [desc, amount, supplier, date, notes]) {
      c.dispose();
    }
  }

  Future<void> _financeSettings(Map<String, dynamic>? current) async {
    final opening = TextEditingController(
          text: '${current?['opening_balance'] ?? 0}',
        ),
        reserve = TextEditingController(
          text: '${current?['minimum_operating_reserve'] ?? 0}',
        );
    var requireApproval = current?['require_approval_below_reserve'] != false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Όρια ταμείου' : 'Cash reserve settings'),
          content: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _field(
                  opening,
                  gr
                      ? 'Αρχικό υπόλοιπο ταμείου (€)'
                      : 'Opening fund balance (€)',
                  validator: _required,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                _field(
                  reserve,
                  gr ? 'Ελάχιστο αποθεματικό (€)' : 'Minimum reserve (€)',
                  validator: _required,
                  keyboard: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                SwitchListTile(
                  title: Text(
                    gr
                        ? 'Απαίτηση έγκρισης κάτω από το αποθεματικό'
                        : 'Require approval below reserve',
                  ),
                  value: requireApproval,
                  onChanged: (v) => setDialog(() => requireApproval = v),
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
              onPressed: () => _formKey.currentState!.validate()
                  ? Navigator.pop(ctx, true)
                  : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await db.from('property_finance_settings').upsert({
          'property_id': widget.propertyId,
          'opening_balance': double.parse(opening.text.replaceAll(',', '.')),
          'minimum_operating_reserve': double.parse(
            reserve.text.replaceAll(',', '.'),
          ),
          'require_approval_below_reserve': requireApproval,
          'updated_by': db.auth.currentUser!.id,
        });
        await _refresh();
      } on PostgrestException catch (e) {
        _message(e.message);
      }
    }
    opening.dispose();
    reserve.dispose();
  }

  Future<void> _newInsurance() async {
    final insurer = TextEditingController(),
        number = TextEditingController(),
        coverage = TextEditingController(),
        premium = TextEditingController(),
        expiry = TextEditingController(),
        notes = TextEditingController();
    final ok = await _formDialog(
      gr ? 'Νέο ασφαλιστήριο' : 'New insurance policy',
      [
        _field(
          insurer,
          gr ? 'Ασφαλιστική εταιρεία' : 'Insurer',
          validator: _required,
        ),
        _field(
          number,
          gr ? 'Αριθμός συμβολαίου' : 'Policy number',
          validator: _required,
        ),
        _field(coverage, gr ? 'Καλύψεις' : 'Coverage', lines: 2),
        _field(
          premium,
          gr ? 'Ασφάλιστρο (€)' : 'Premium (€)',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        _field(
          expiry,
          gr ? 'Λήξη (YYYY-MM-DD)' : 'Expiry (YYYY-MM-DD)',
          validator: _dateValidator,
        ),
        _field(notes, gr ? 'Σημειώσεις' : 'Notes', lines: 2),
      ],
    );
    if (ok)
      await _insert('property_insurance_policies', {
        'insurer': insurer.text.trim(),
        'policy_number': number.text.trim(),
        'coverage_summary': coverage.text.trim(),
        'premium_amount': double.tryParse(premium.text.replaceAll(',', '.')),
        'expires_on': expiry.text.trim(),
        'notes': notes.text.trim(),
      });
    for (final c in [insurer, number, coverage, premium, expiry, notes]) {
      c.dispose();
    }
  }

  Future<void> _newMeeting() async {
    final title = TextEditingController(),
        starts = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 16),
        ),
        ends = TextEditingController(),
        organizer = TextEditingController(),
        hours = TextEditingController(text: '0'),
        fee = TextEditingController(text: '0'),
        attendees = TextEditingController(),
        minutes = TextEditingController();
    final ok = await _formDialog(
      gr ? 'Νέα συνέλευση / πρακτικά' : 'New meeting / minutes',
      [
        _field(
          title,
          gr ? 'Τίτλος συνέλευσης' : 'Meeting title',
          validator: _required,
        ),
        _field(
          starts,
          gr ? 'Έναρξη (ISO)' : 'Start (ISO)',
          validator: _required,
        ),
        _field(ends, gr ? 'Λήξη (προαιρετικά, ISO)' : 'End (optional, ISO)'),
        _field(
          organizer,
          gr ? 'Εκπρόσωπος SmartBlock' : 'SmartBlock representative',
        ),
        _field(
          hours,
          gr ? 'Ώρες παρουσίας' : 'Representative hours',
          keyboard: TextInputType.number,
        ),
        _field(
          fee,
          gr ? 'Συμφωνημένη χρέωση (€)' : 'Agreed service fee (€)',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        _field(
          attendees,
          gr
              ? 'Παρόντες (ένα όνομα ανά γραμμή)'
              : 'Attendees (one name per line)',
          lines: 3,
        ),
        _field(
          minutes,
          gr ? 'Πρακτικά και αποφάσεις' : 'Minutes and decisions',
          lines: 5,
        ),
      ],
    );
    if (ok)
      await _insert('property_meetings', {
        'title': title.text.trim(),
        'starts_at': DateTime.parse(starts.text.trim())
            .toUtc()
            .toIso8601String(),
        'ends_at': ends.text.trim().isEmpty
            ? null
            : DateTime.parse(ends.text.trim()).toUtc().toIso8601String(),
        'organizer_name': organizer.text.trim(),
        'representative_hours':
            double.tryParse(hours.text.replaceAll(',', '.')) ?? 0,
        'agreed_service_fee':
            double.tryParse(fee.text.replaceAll(',', '.')) ?? 0,
        'fee_approved': false,
        'attendees': attendees.text
            .split('\n')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
        'minutes': minutes.text.trim(),
        'status': 'held',
      });
    for (final c in [
      title,
      starts,
      ends,
      organizer,
      hours,
      fee,
      attendees,
      minutes,
    ]) {
      c.dispose();
    }
  }

  Future<void> _newHandover() async {
    final from = TextEditingController(),
        to = TextEditingController(),
        date = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10),
        ),
        financial = TextEditingController(),
        openItems = TextEditingController();
    final ok = await _formDialog(
      gr ? 'Παράδοση διαχείρισης' : 'Management handover',
      [
        _field(from, gr ? 'Από διαχειριστή' : 'From manager'),
        _field(to, gr ? 'Προς διαχειριστή' : 'To manager'),
        _field(
          date,
          gr ? 'Ημερομηνία (YYYY-MM-DD)' : 'Handover date (YYYY-MM-DD)',
          validator: _dateValidator,
        ),
        _field(
          financial,
          gr ? 'Οικονομική σύνοψη' : 'Financial summary',
          lines: 3,
        ),
        _field(
          openItems,
          gr ? 'Εκκρεμότητες (μία ανά γραμμή)' : 'Open items (one per line)',
          lines: 4,
        ),
      ],
    );
    if (ok)
      await _insert('property_handover_records', {
        'from_manager': from.text.trim(),
        'to_manager': to.text.trim(),
        'handover_date': date.text.trim(),
        'financial_summary': financial.text.trim(),
        'open_items': openItems.text
            .split('\n')
            .map((v) => v.trim())
            .where((v) => v.isNotEmpty)
            .toList(),
        'status': 'awaiting_acceptance',
      });
    for (final c in [from, to, date, financial, openItems]) {
      c.dispose();
    }
  }

  Future<void> _newArrearsAction() async {
    final owners = List<Map<String, dynamic>>.from(
      await db
          .from('property_owners')
          .select('id,organizations(display_name)')
          .eq('property_id', widget.propertyId)
          .eq('ownership_status', 'active'),
    );
    if (owners.isEmpty) {
      _message(
        gr ? 'Δεν υπάρχουν ενεργοί ιδιοκτήτες.' : 'No active owners found.',
      );
      return;
    }
    var ownerId = owners.first['id'] as String,
        stage = 'reminder',
        method = 'email';
    final fee = TextEditingController(text: '0'),
        basis = TextEditingController(),
        notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            gr
                ? 'Καταγραφή υπενθύμισης οφειλής'
                : 'Record an arrears follow-up',
          ),
          content: SizedBox(
            width: 420,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: ownerId,
                    items: owners.map((o) {
                      final org =
                          o['organizations'] as Map<String, dynamic>? ?? {};
                      return DropdownMenuItem(
                        value: o['id'] as String,
                        child: Text(
                          org['display_name'] as String? ??
                              (gr ? 'Ιδιοκτήτης' : 'Owner'),
                        ),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => ownerId = v);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: stage,
                    decoration: InputDecoration(
                      labelText: gr ? 'Στάδιο' : 'Stage',
                    ),
                    items:
                        [
                              'reminder',
                              'first_notice',
                              'final_notice',
                              'legal_review',
                              'resolved',
                            ]
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.replaceAll('_', ' ')),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => stage = v);
                    },
                  ),
                  DropdownButtonFormField<String>(
                    value: method,
                    decoration: InputDecoration(
                      labelText: gr ? 'Τρόπος επικοινωνίας' : 'Contact method',
                    ),
                    items: ['email', 'phone', 'letter', 'in_person', 'other']
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text(v.replaceAll('_', ' ')),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setDialog(() => method = v);
                    },
                  ),
                  _field(
                    fee,
                    gr ? 'Συμφωνημένη χρέωση (€)' : 'Agreed fee (€)',
                    keyboard: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  _field(
                    basis,
                    gr
                        ? 'Βάση χρέωσης / σχετικός όρος'
                        : 'Fee basis / contract term',
                  ),
                  _field(
                    notes,
                    gr ? 'Ιστορικό επικοινωνίας' : 'Communication history',
                    lines: 3,
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
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(gr ? 'Καταχώριση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true)
      await _insert('property_arrears_actions', {
        'property_owner_id': ownerId,
        'stage': stage,
        'communication_method': method,
        'agreed_fee': double.tryParse(fee.text.replaceAll(',', '.')) ?? 0,
        'fee_basis': basis.text.trim(),
        'notes': notes.text.trim(),
      });
    fee.dispose();
    basis.dispose();
    notes.dispose();
  }

  Future<void> _setExpenseStatus(
    Map<String, dynamic> expense,
    String status,
  ) async {
    try {
      await db
          .from('property_operating_expenses')
          .update({
            'status': status,
            'approved_by': status == 'approved'
                ? db.auth.currentUser?.id
                : null,
            'approved_at': status == 'approved'
                ? DateTime.now().toUtc().toIso8601String()
                : null,
            'paid_at': status == 'paid'
                ? DateTime.now().toUtc().toIso8601String()
                : null,
          })
          .eq('id', expense['id']);
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _acceptHandover(Map<String, dynamic> handover) async {
    try {
      await db
          .from('property_handover_records')
          .update({
            'status': 'accepted',
            'accepted_by': db.auth.currentUser?.id,
            'accepted_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', handover['id']);
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
    }
  }

  String _money(num value) => '€${value.toStringAsFixed(2)}';

  Widget _section(
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    VoidCallback add,
    String type,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: canManage
              ? IconButton(
                  tooltip: gr ? 'Νέα καταχώριση' : 'Add record',
                  onPressed: busy ? null : add,
                  icon: const Icon(Icons.add_circle_outline),
                )
              : null,
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                gr ? 'Δεν υπάρχουν καταχωρίσεις.' : 'No records yet.',
              ),
            ),
          ),
        ...rows.map((row) {
          final String titleText;
          final String subtitle;
          if (type == 'contract') {
            titleText =
                '${row['provider_name']} · ${_money((row['monthly_fee'] as num?) ?? 0)}/${gr ? 'μήνα' : 'month'}';
            subtitle =
                '${row['starts_on']} – ${row['ends_on'] ?? (gr ? 'χωρίς λήξη' : 'open end')} · ${row['billing_cycle']} · ${row['status']}';
          } else if (type == 'service') {
            titleText = row['title'] as String? ?? '';
            subtitle =
                '${row['fee_amount'] == null ? (gr ? 'Απαιτείται προσφορά' : 'Quote required') : _money((row['fee_amount'] as num))} · ${row['fee_unit']} · ${row['requires_prior_approval'] == true ? (gr ? 'με έγκριση' : 'approval required') : ''}';
          } else if (type == 'expense') {
            titleText =
                '${row['description']} · ${_money(row['amount'] as num)}';
            subtitle =
                '${row['expense_date']} · ${row['status']} · ${row['supplier'] ?? ''}';
          } else if (type == 'insurance') {
            titleText = '${row['insurer']} · ${row['policy_number']}';
            subtitle =
                '${gr ? 'Λήξη' : 'Expires'}: ${row['expires_on']} · ${row['premium_amount'] == null ? '' : _money(row['premium_amount'] as num)}';
          } else if (type == 'meeting') {
            titleText = row['title'] as String? ?? '';
            subtitle =
                '${row['starts_at']} · ${row['status']} · ${row['agreed_service_fee'] == null ? '' : _money(row['agreed_service_fee'] as num)}';
          } else if (type == 'handover') {
            titleText = '${row['from_manager']} → ${row['to_manager']}';
            subtitle = '${row['handover_date']} · ${row['status']}';
          } else {
            final owner = row['property_owners'] as Map<String, dynamic>? ?? {};
            final org = owner['organizations'] as Map<String, dynamic>? ?? {};
            titleText =
                '${org['display_name'] ?? (gr ? 'Ιδιοκτήτης' : 'Owner')} · ${row['stage']}';
            subtitle =
                '${row['occurred_at']} · ${row['communication_method']} · ${row['notes']}';
          }
          return ListTile(
            dense: true,
            title: Text(titleText),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: canManage && type == 'expense' && row['status'] != 'paid'
                ? PopupMenuButton<String>(
                    onSelected: (v) => _setExpenseStatus(row, v),
                    itemBuilder: (_) => [
                      if (row['status'] == 'awaiting_approval')
                        PopupMenuItem(
                          value: 'approved',
                          child: Text(gr ? 'Έγκριση' : 'Approve'),
                        ),
                      if (row['status'] == 'approved')
                        PopupMenuItem(
                          value: 'paid',
                          child: Text(
                            gr ? 'Σήμανση ως πληρωμένο' : 'Mark paid',
                          ),
                        ),
                      PopupMenuItem(
                        value: 'rejected',
                        child: Text(gr ? 'Απόρριψη' : 'Reject'),
                      ),
                    ],
                  )
                : canManage &&
                      type == 'handover' &&
                      row['status'] == 'awaiting_acceptance'
                ? IconButton(
                    tooltip: gr ? 'Αποδοχή παράδοσης' : 'Accept handover',
                    onPressed: () => _acceptHandover(row),
                    icon: const Icon(Icons.task_alt),
                  )
                : null,
          );
        }),
      ],
    ),
  );

  Widget _body(Map<String, dynamic> d) {
    final entries = d['charge_entries'] as List<Map<String, dynamic>>;
    final expenses = d['expenses'] as List<Map<String, dynamic>>;
    final settings = d['settings'] as Map<String, dynamic>?;
    final opening = (settings?['opening_balance'] as num?)?.toDouble() ?? 0;
    final received = entries.fold<double>(
      0,
      (sum, row) => sum + ((row['amount_paid'] as num?)?.toDouble() ?? 0),
    );
    final paidExpenses = expenses
        .where((x) => x['status'] == 'paid')
        .fold<double>(
          0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
    final committed = expenses
        .where((x) => x['status'] == 'approved')
        .fold<double>(
          0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
    final balance = opening + received - paidExpenses;
    final minimum =
        (settings?['minimum_operating_reserve'] as num?)?.toDouble() ?? 0;
    final below = balance - committed < minimum;
    final now = DateTime.now();
    final alerts = <String>[];
    for (final contract in d['contracts'] as List<Map<String, dynamic>>) {
      final rawEnd = contract['ends_on'] as String?;
      if (rawEnd == null || contract['status'] != 'active') continue;
      final end = DateTime.tryParse(rawEnd);
      if (end == null) continue;
      final noticeMonths =
          (contract['notice_period_months'] as num?)?.toInt() ?? 0;
      final noticeAt = DateTime(end.year, end.month - noticeMonths, end.day);
      if (!now.isBefore(noticeAt) && !now.isAfter(end)) {
        alerts.add(
          gr
              ? 'Η σύμβαση ${contract['provider_name']} λήγει στις $rawEnd. Έλεγξε την προθεσμία ειδοποίησης.'
              : 'Contract with ${contract['provider_name']} ends on $rawEnd. Check the notice deadline.',
        );
      }
    }
    for (final policy in d['insurance'] as List<Map<String, dynamic>>) {
      final expiry = DateTime.tryParse(policy['expires_on'] as String? ?? '');
      if (expiry == null) continue;
      if (!expiry.isBefore(now) && expiry.difference(now).inDays <= 30) {
        alerts.add(
          gr
              ? 'Το ασφαλιστήριο ${policy['policy_number']} λήγει στις ${policy['expires_on']}.'
              : 'Insurance policy ${policy['policy_number']} expires on ${policy['expires_on']}.',
        );
      }
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.propertyName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (alerts.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gr ? 'Υπενθυμίσεις' : 'Reminders',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    ...alerts.map(
                      (alert) => Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('• $alert'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Card(
            color: below
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gr ? 'Ταμείο πολυκατοικίας' : 'Building funds',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${gr ? 'Εκτιμώμενο διαθέσιμο' : 'Estimated available'}: ${_money(balance)}',
                  ),
                  Text(
                    '${gr ? 'Εγκεκριμένες υποχρεώσεις' : 'Approved commitments'}: ${_money(committed)}',
                  ),
                  Text(
                    '${gr ? 'Ελάχιστο αποθεματικό' : 'Minimum reserve'}: ${_money(minimum)}',
                  ),
                  if (below)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        gr
                            ? 'Προσοχή: οι εγκεκριμένες υποχρεώσεις θα μειώσουν το ταμείο κάτω από το όριο.'
                            : 'Warning: approved commitments would reduce funds below the reserve.',
                      ),
                    ),
                  if (canManage)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _financeSettings(settings),
                        icon: const Icon(Icons.tune),
                        label: Text(
                          gr ? 'Ρύθμιση αποθεματικού' : 'Set reserve',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!canManage)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                gr
                    ? 'Προβολή μόνο. Η επεξεργασία είναι διαθέσιμη στον διαχειριστή του ακινήτου.'
                    : 'Read only. Editing is available to the property manager.',
              ),
            ),
          _section(
            gr ? 'Συμβάσεις διαχείρισης' : 'Management contracts',
            Icons.assignment_outlined,
            d['contracts'],
            _newContract,
            'contract',
          ),
          _section(
            gr
                ? 'Πρόσθετες υπηρεσίες και τιμοκατάλογος'
                : 'Additional services and fees',
            Icons.miscellaneous_services_outlined,
            d['services'],
            _newService,
            'service',
          ),
          _section(
            gr ? 'Έξοδα και εγκρίσεις' : 'Expenses and approvals',
            Icons.account_balance_wallet_outlined,
            expenses,
            _newExpense,
            'expense',
          ),
          _section(
            gr
                ? 'Ληξιπρόθεσμες οφειλές και επικοινωνία'
                : 'Arrears and contact history',
            Icons.mark_email_unread_outlined,
            d['arrears'],
            _newArrearsAction,
            'arrears',
          ),
          _section(
            gr ? 'Ασφαλιστήρια' : 'Insurance policies',
            Icons.shield_outlined,
            d['insurance'],
            _newInsurance,
            'insurance',
          ),
          _section(
            gr ? 'Συνελεύσεις και πρακτικά' : 'Meetings and minutes',
            Icons.groups_outlined,
            d['meetings'],
            _newMeeting,
            'meeting',
          ),
          _section(
            gr ? 'Παράδοση και παραλαβή διαχείρισης' : 'Management handover',
            Icons.swap_horiz_outlined,
            d['handovers'],
            _newHandover,
            'handover',
          ),
          const SizedBox(height: 16),
          Text(
            gr
                ? 'Οι όροι κάθε σύμβασης καταγράφονται ως συμφωνημένοι όροι του συγκεκριμένου ακινήτου.'
                : 'Contract fields record terms for this property only; they are not general legal rules.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(gr ? 'Διαχείριση κτιρίου' : 'Building management'),
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: data,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    gr
                        ? 'Δεν φορτώθηκαν οι λειτουργίες διαχείρισης.'
                        : 'Could not load management tools.',
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(gr ? 'Δοκίμασε ξανά' : 'Try again'),
                  ),
                ],
              ),
            ),
          );
        return _body(snapshot.data!);
      },
    ),
  );
}
