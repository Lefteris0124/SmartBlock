Warning: truncated output (original token count: 26473)
Total output lines: 2784

import 'package:flutter/material.dart' hide Text;
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../smartblock_text.dart';

class PropertyManagementScreen extends StatefulWidget {
  const PropertyManagementScreen({
    required this.propertyId,
    required this.propertyName,
    this.totalApartments,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final int? totalApartments;
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
          .from('property_management_contract_amendments')
          .select('*,property_management_contracts(provider_name)')
          .eq('property_id', widget.propertyId)
          .order('effective_on', ascending: false),
      db
          .from('property_management_services')
          .select()
          .eq('property_id', widget.propertyId)
          .order('active', ascending: false),
      db
          .from('property_service_requests')
          .select('*,property_management_services(title)')
          .eq('property_id', widget.propertyId)
          .order('created_at', ascending: false),
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
          .select('*,property_owners(organizations(display_name))')
          .eq('property_id', widget.propertyId)
          .order('occurred_at', ascending: false),
      db
          .from('property_insurance_policies')
          .select()
          .eq('property_id', widget.propertyId)
          .order('expires_on'),
      db
          .from('property_insurance_claims')
          .select('*,property_insurance_policies(insurer,policy_number)')
          .eq('property_id', widget.propertyId)
          .order('reported_on', ascending: false),
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
          .select(
            'id,property_owner_id,amount_due,amount_paid,status,property_owners!inner(id,organizations(display_name)),property_charge_runs!inner(property_id,period_label,description,due_date)',
          )
          .eq('property_charge_runs.property_id', widget.propertyId),
      db.rpc(
        'list_property_residents',
        params: {'p_property_id': widget.propertyId},
      ),
    ]);
    return {
      'contracts': List<Map<String, dynamic>>.from(values[0]),
      'amendments': List<Map<String, dynamic>>.from(values[1]),
      'services': List<Map<String, dynamic>>.from(values[2]),
      'service_requests': List<Map<String, dynamic>>.from(values[3]),
      'expenses': List<Map<String, dynamic>>.from(values[4]),
      'settings': values[5] as Map<String, dynamic>?,
      'arrears': List<Map<String, dynamic>>.from(values[6]),
      'insurance': List<Map<String, dynamic>>.from(values[7]),
      'claims': List<Map<String, dynamic>>.from(values[8]),
      'meetings': List<Map<String, dynamic>>.from(values[9]),
      'handovers': List<Map<String, dynamic>>.from(values[10]),
      'charge_entries': List<Map<String, dynamic>>.from(values[11]),
      'residents': List<Map<String, dynamic>>.from(values[12]),
    };
  }

  Future<void> _refresh() async {
    setState(() => data = _load());
    try {
      await data;
    } catch (_) {}
  }

  String? _documentColumn(String type) => switch (type) {
    'contract' || 'contract_amendment' => 'source_document_path',
    'expense' => 'document_path',
    'insurance' || 'claim' => 'document_path',
    'arrears' => 'letter_document_path',
    'service_request' => 'quote_document_path',
    'meeting' || 'handover' => 'document_paths',
    _ => null,
  };

  bool _documentListType(String type) =>
      type == 'meeting' || type == 'handover';

  List<String> _documentPaths(Map<String, dynamic> row, String type) {
    final column = _documentColumn(type);
    if (column == null) return const [];
    final value = row[column];
    if (_documentListType(type)) {
      if (value is List) return value.whereType<String>().toList();
      return const [];
    }
    return value is String && value.isNotEmpty ? [value] : const [];
  }

  String _documentFolder(String type) =>
      {
        'expense',
        'claim',
        'arrears',
        'handover',
        'service_request',
      }.contains(type)
      ? 'restricted'
      : 'shared';

  Future<void> _attachDocument(Map<String, dynamic> row, String type) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return;
      final size = await file.length();
      if (size == null || size > 15 * 1024 * 1024) {
        _message(
          gr
              ? 'Το αρχείο πρέπει να είναι έως 15 MB.'
              : 'The file must be 15 MB or smaller.',
        );
        return;
      }
      final extension = (file.extension ?? '').toLowerCase();
      final mime = switch (extension) {
        'pdf' => 'application/pdf',
        'jpg' || 'jpeg' => 'image/jpeg',
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => null,
      };
      if (mime == null) return;
      final bytes = await file.readAsBytes();
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path =
          '${widget.propertyId}/${_documentFolder(type)}/'
          '${DateTime.now().microsecondsSinceEpoch}_$safeName';
      final bucket = db.storage.from('property-management-documents');
      await bucket.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(contentType: mime),
      );
      try {
        final column = _documentColumn(type)!;
        if (_documentListType(type)) {
          final paths = _documentPaths(row, type)..add(path);
          final table = type == 'meeting'
              ? 'property_meetings'
              : 'property_handover_records';
          await db.from(table).update({column: paths}).eq('id', row['id']);
        } else {
          final table = switch (type) {
            'contract' => 'property_management_contracts',
            'contract_amendment' => 'property_management_contract_amendments',
            'expense' => 'property_operating_expenses',
            'insurance' => 'property_insurance_policies',
            'claim' => 'property_insurance_claims',
            'arrears' => 'property_arrears_actions',
            'service_request' => 'property_service_requests',
            _ => throw StateError('Unsupported document record'),
          };
          final oldPaths = _documentPaths(row, type);
          await db.from(table).update({column: path}).eq('id', row['id']);
          if (oldPaths.isNotEmpty) {
            try {
              await bucket.remove(oldPaths);
            } catch (_) {}
          }
        }
      } catch (_) {
        await bucket.remove([path]);
        rethrow;
      }
      _message(gr ? 'Το έγγραφο αποθηκεύτηκε.' : 'Document saved.');
      await _refresh();
    } catch (error) {
      _message(
        '${gr ? 'Δεν ήταν δυνατή η επισύναψη' : 'Could not attach document'}: $error',
      );
    }
  }

  Future<void> _openDocument(String path) async {
    try {
      final url = await db.storage
          .from('property-management-documents')
          .createSignedUrl(path, 300);
      if (!await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault)) {
        throw StateError('Could not open document');
      }
    } catch (error) {
      _message(
        '${gr ? 'Δεν ήταν δυνατή η προβολή του εγγράφου' : 'Could not open document'}: $error',
      );
    }
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
      _message(
        table == 'property_management_contracts' && e.code == '23505'
            ? (gr
                  ? 'Υπάρχει ήδη ενεργή σύμβαση. Τερμάτισε την προηγούμενη ή αποθήκευσε τη νέα ως προσχέδιο.'
                  : 'An active contract already exists. Terminate it first or save the new contract as a draft.')
            : e.message,
      );
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

  Future<void> _newContractAmendment() async {
    final contracts = List<Map<String, dynamic>>.from(
      await db
          .from('property_management_contracts')
          .select('id,provider_name')
          .eq('property_id', widget.propertyId)
          .eq('status', 'active')
          .order('starts_on', ascending: false),
    );
    if (contracts.isEmpty) {
      _message(
        gr
            ? 'Χρειάζεται ενεργή σύμβαση για να προστεθεί τροποποίηση.'
            : 'An active contract is required before adding an amendment.',
      );
      return;
    }
    var contractId = contracts.first['id'] as String;
    final title = TextEditingController(),
        reference = TextEditingController(),
        effective = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10),
        ),
        summary = TextEditingController(),
        fee = TextEditingController(),
        vat = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            gr ? 'Νέα τροποποίηση σύμβασης' : 'New contract amendment',
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: contractId,
                      decoration: InputDecoration(
                        labelText: gr ? 'Ενεργή σύμβαση' : 'Active contract',
                      ),
                      items: contracts
                          .map(
                            (c) => DropdownMenuItem(
                              value: c['id'] as String,
                              child: Text(c['provider_name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => contractId = v);
                      },
                    ),
                    _field(
                      title,
                      gr ? 'Τίτλος τροποποίησης' : 'Amendment title',
                      validator: _required,
                    ),
                    _field(reference, gr ? 'Αριθμός / αναφορά' : 'Reference'),
                    _field(
                      effective,
                      gr
                          ? 'Ημερομηνία ισχύος (YYYY-MM-DD)'
                          : 'Effective date (YYYY-MM-DD)',
                      validator: _dateValidator,
                    ),
                    _field(
                      summary,
                      gr ? 'Περιγραφή των αλλαγών' : 'Changes summary',
                      lines: 4,
                    ),
                    _field(
                      fee,
                      gr
                          ? 'Νέα μηνιαία αμοιβή (προαιρετικά)'
                          : 'New monthly fee (optional)',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(
                      vat,
                      gr ? 'Νέος ΦΠΑ % (προαιρετικά)' : 'New VAT % (optional)',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
        …14473 tokens truncated…       subtitle =
                '${row['starts_at']} · ${row['status']} · ${row['agreed_service_fee'] == null ? '' : _money(row['agreed_service_fee'] as num)}';
          } else if (type == 'handover') {
            titleText = '${row['from_manager']} → ${row['to_manager']}';
            subtitle = '${row['handover_date']} · ${row['status']}';
          } else if (type == 'contract_amendment') {
            final contract =
                row['property_management_contracts'] as Map<String, dynamic>? ??
                {};
            final newFee = row['monthly_fee_new'] as num?;
            titleText = '${row['title']} · ${contract['provider_name'] ?? ''}';
            subtitle =
                '${row['effective_on']} · ${row['approval_status']}${newFee == null ? '' : ' · ${_money(newFee)}/${gr ? 'μήνα' : 'month'}'}';
          } else if (type == 'service_request') {
            final service =
                row['property_management_services'] as Map<String, dynamic>? ??
                {};
            final serviceTitle = service['title'] as String?;
            final requestType = row['request_type'] as String? ?? 'service';
            final typeLabel = gr
                ? switch (requestType) {
                    'damage_report' => 'Βλάβη',
                    'maintenance' => 'Συντήρηση',
                    'cleaning' => 'Καθαρισμός',
                    'safety' => 'Ασφάλεια',
                    'other' => 'Άλλο',
                    _ => 'Υπηρεσία',
                  }
                : switch (requestType) {
                    'damage_report' => 'Problem',
                    'maintenance' => 'Maintenance',
                    'cleaning' => 'Cleaning',
                    'safety' => 'Safety',
                    'other' => 'Other',
                    _ => 'Service',
                  };
            final priority = row['priority'] as String? ?? 'normal';
            final priorityLabel = gr
                ? switch (priority) {
                    'emergency' => 'Άμεσος κίνδυνος',
                    'urgent' => 'Επείγον',
                    _ => 'Κανονικό',
                  }
                : switch (priority) {
                    'emergency' => 'Immediate danger',
                    'urgent' => 'Urgent',
                    _ => 'Normal',
                  };
            final location = (row['location'] as String? ?? '').trim();
            final apartmentNumber =
                row['apartment_number'] as String? ?? 'common_area';
            titleText =
                '$typeLabel · ${row['title']}${serviceTitle == null ? '' : ' · $serviceTitle'}';
            final quote = row['quote_amount'] as num?;
            subtitle =
                '${apartmentNumber == 'common_area' ? (gr ? 'Κοινόχρηστος χώρος' : 'Common area') : (gr ? 'Διαμέρισμα $apartmentNumber' : 'Apartment $apartmentNumber')} · $priorityLabel${location.isEmpty ? '' : ' · $location'} · ${row['status']}${quote == null ? '' : ' · ${_money(quote)}'}${(row['supplier'] as String? ?? '').isEmpty ? '' : ' · ${row['supplier']}'}${(row['description'] as String? ?? '').isEmpty ? '' : ' · ${row['description']}'}';
          } else if (type == 'claim') {
            final policy =
                row['property_insurance_policies'] as Map<String, dynamic>? ??
                {};
            final amount =
                row['approved_amount'] as num? ?? row['claimed_amount'] as num?;
            titleText =
                '${row['claim_reference'] == '' ? (gr ? 'Απαίτηση' : 'Claim') : row['claim_reference']} · ${policy['policy_number'] ?? ''}';
            subtitle =
                '${row['reported_on']} · ${row['status']}${amount == null ? '' : ' · ${_money(amount)}'} · ${row['description']}';
          } else {
            final owner = row['property_owners'] as Map<String, dynamic>? ?? {};
            final org = owner['organizations'] as Map<String, dynamic>? ?? {};
            titleText =
                '${org['display_name'] ?? (gr ? 'Ιδιοκτήτης' : 'Owner')} · ${row['stage']}';
            subtitle =
                '${row['occurred_at']} · ${row['communication_method']} · ${row['notes']}';
          }
          final statusAction = _sectionStatusAction(row, type);
          final documentPaths = _documentPaths(row, type);
          final readableDocumentPaths =
              canManage || _documentFolder(type) == 'shared'
              ? documentPaths
              : const <String>[];
          final showAttachment = _documentColumn(type) != null;
          return ListTile(
            dense: true,
            title: Text(titleText),
            subtitle: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: canManage || readableDocumentPaths.isNotEmpty
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (readableDocumentPaths.isNotEmpty)
                        IconButton(
                          tooltip: gr ? 'Προβολή εγγράφων' : 'Open documents',
                          onPressed: () =>
                              _openDocument(readableDocumentPaths.last),
                          icon: const Icon(Icons.attach_file),
                        ),
                      if (canManage && showAttachment)
                        IconButton(
                          tooltip: gr ? 'Επισύναψη αρχείου' : 'Attach file',
                          onPressed: busy
                              ? null
                              : () => _attachDocument(row, type),
                          icon: const Icon(Icons.upload_file_outlined),
                        ),
                      if (statusAction != null) statusAction,
                    ],
                  )
                : null,
          );
        }),
      ],
    ),
  );

  Widget? _serviceRequestAction(Map<String, dynamic> request) {
    final status = request['status'];
    if (status == 'requested') {
      return IconButton(
        tooltip: gr ? 'Καταχώριση προσφοράς' : 'Add quote',
        onPressed: () => _quoteServiceRequest(request),
        icon: const Icon(Icons.request_quote_outlined),
      );
    }
    if (status == 'quoted') {
      return PopupMenuButton<String>(
        onSelected: (value) => _transitionServiceRequest(request, value),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'approved',
            child: Text(gr ? 'Έγκριση προσφοράς' : 'Approve quote'),
          ),
          PopupMenuItem(
            value: 'rejected',
            child: Text(gr ? 'Απόρριψη προσφοράς' : 'Reject quote'),
          ),
        ],
      );
    }
    if (status == 'approved') {
      return IconButton(
        tooltip: gr ? 'Έναρξη εργασίας' : 'Start work',
        onPressed: () => _transitionServiceRequest(request, 'in_progress'),
        icon: const Icon(Icons.play_circle_outline),
      );
    }
    if (status == 'in_progress') {
      return IconButton(
        tooltip: gr ? 'Ολοκλήρωση εργασίας' : 'Complete work',
        onPressed: () => _transitionServiceRequest(request, 'completed'),
        icon: const Icon(Icons.task_alt),
      );
    }
    return null;
  }

  Widget? _insuranceClaimAction(Map<String, dynamic> claim) {
    final status = claim['status'];
    final List<PopupMenuEntry<String>> items = switch (status) {
      'reported' => [
        PopupMenuItem(
          value: 'under_review',
          child: Text(gr ? 'Σε εξέταση' : 'Under review'),
        ),
      ],
      'under_review' => [
        PopupMenuItem(
          value: 'accepted',
          child: Text(gr ? 'Έγκριση' : 'Accept'),
        ),
        PopupMenuItem(
          value: 'rejected',
          child: Text(gr ? 'Απόρριψη' : 'Reject'),
        ),
      ],
      'accepted' => [
        PopupMenuItem(value: 'paid', child: Text(gr ? 'Πληρώθηκε' : 'Paid')),
      ],
      'paid' => [
        PopupMenuItem(value: 'closed', child: Text(gr ? 'Κλείσιμο' : 'Close')),
      ],
      _ => [],
    };
    if (items.isEmpty) return null;
    return PopupMenuButton<String>(
      onSelected: (value) => _reviewInsuranceClaim(claim, value),
      itemBuilder: (_) => items,
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final entries = d['charge_entries'] as List<Map<String, dynamic>>;
    final expenses = d['expenses'] as List<Map<String, dynamic>>;
    final serviceRequests = d['service_requests'] as List<Map<String, dynamic>>;
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
    final awaitingApproval = expenses
        .where((x) => x['status'] == 'awaiting_approval')
        .fold<double>(
          0,
          (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0),
        );
    final serviceCommitments = serviceRequests
        .where(
          (request) =>
              request['status'] == 'approved' ||
              request['status'] == 'in_progress',
        )
        .fold<double>(
          0,
          (sum, request) =>
              sum + ((request['quote_amount'] as num?)?.toDouble() ?? 0),
        );
    final receivables = entries.fold<double>(
      0,
      (sum, row) => sum + _entryOutstanding(row),
    );
    final balance = opening + received - paidExpenses;
    final minimum =
        (settings?['minimum_operating_reserve'] as num?)?.toDouble() ?? 0;
    final projectedBalance =
        balance +
        receivables -
        committed -
        serviceCommitments -
        awaitingApproval;
    final below =
        balance - committed - serviceCommitments - awaitingApproval < minimum;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final overdueEntries =
        entries.where((row) {
          final run =
              row['property_charge_runs'] as Map<String, dynamic>? ?? {};
          final dueDate = DateTime.tryParse(run['due_date'] as String? ?? '');
          return _entryOutstanding(row) > 0 &&
              dueDate != null &&
              dueDate.isBefore(today);
        }).toList()..sort((a, b) {
          final aRun = a['property_charge_runs'] as Map<String, dynamic>? ?? {};
          final bRun = b['property_charge_runs'] as Map<String, dynamic>? ?? {};
          return (aRun['due_date'] as String? ?? '').compareTo(
            bRun['due_date'] as String? ?? '',
          );
        });
    final overdueAmount = overdueEntries.fold<double>(
      0,
      (sum, row) => sum + _entryOutstanding(row),
    );
    final alerts = <String>[];
    for (final contract in d['contracts'] as List<Map<String, dynamic>>) {
      final rawEnd = contract['ends_on'] as String?;
      if (rawEnd == null || contract['status'] != 'active') continue;
      final end = DateTime.tryParse(rawEnd);
      if (end == null) continue;
      final noticeMonths =
          (contract['notice_period_months'] as num?)?.toInt() ?? 0;
      final noticeAt = DateTime(end.year, end.month - noticeMonths, end.day);
      final reminderAt = noticeMonths > 0
          ? noticeAt
          : end.subtract(const Duration(days: 30));
      if (!now.isAfter(end) && !now.isBefore(reminderAt)) {
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
      final daysLeft = expiry.difference(today).inDays;
      if (daysLeft < 0 || daysLeft <= 30) {
        alerts.add(
          gr
              ? (daysLeft < 0
                    ? 'Το ασφαλιστήριο ${policy['policy_number']} έληξε στις ${policy['expires_on']}.'
                    : 'Το ασφαλιστήριο ${policy['policy_number']} λήγει στις ${policy['expires_on']}.')
              : (daysLeft < 0
                    ? 'Insurance policy ${policy['policy_number']} expired on ${policy['expires_on']}.'
                    : 'Insurance policy ${policy['policy_number']} expires on ${policy['expires_on']}.'),
        );
      }
    }
    if (canManage) {
      final dueSoonCount = entries.where((row) {
        if (_entryOutstanding(row) <= 0) return false;
        final run = row['property_charge_runs'] as Map<String, dynamic>? ?? {};
        final due = DateTime.tryParse(run['due_date'] as String? ?? '');
        return due != null &&
            !due.isBefore(today) &&
            due.isBefore(today.add(const Duration(days: 8)));
      }).length;
      if (dueSoonCount > 0) {
        alerts.add(
          gr
              ? '${dueSoonCount} χρεώσεις κοινοχρήστων λήγουν μέσα στις επόμενες 7 ημέρες.'
              : '${dueSoonCount} common charges are due within the next 7 days.',
        );
      }
    }
    for (final meeting in d['meetings'] as List<Map<String, dynamic>>) {
      if (meeting['status'] != 'scheduled') continue;
      final starts = DateTime.tryParse(meeting['starts_at'] as String? ?? '');
      if (starts == null ||
          starts.isBefore(now) ||
          starts.isAfter(now.add(const Duration(days: 7)))) {
        continue;
      }
      alerts.add(
        gr
            ? 'Η συνέλευση «${meeting['title']}» είναι προγραμματισμένη για ${meeting['starts_at']}.'
            : 'Meeting “${meeting['title']}” is scheduled for ${meeting['starts_at']}.',
      );
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
                    '${gr ? 'Εγκεκριμένες προσφορές υπηρεσιών' : 'Approved service quotes'}: ${_money(serviceCommitments)}',
                  ),
                  Text(
                    '${gr ? 'Εκκρεμείς προς έγκριση' : 'Awaiting approval'}: ${_money(awaitingApproval)}',
                  ),
                  Text(
                    '${gr ? 'Αναμενόμενες εισπράξεις' : 'Expected receivables'}: ${_money(receivables)}',
                  ),
                  Text(
                    '${gr ? 'Ληξιπρόθεσμα' : 'Overdue'}: ${_money(overdueAmount)}',
                  ),
                  Text(
                    '${gr ? 'Προβολή μετά από γνωστά ποσά' : 'Projected after known items'}: ${_money(projectedBalance)}',
                  ),
                  Text(
                    '${gr ? 'Ελάχιστο αποθεματικό' : 'Minimum reserve'}: ${_money(minimum)}',
                  ),
                  if (below)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        gr
                            ? 'Προσοχή: οι γνωστές υποχρεώσεις μπορούν να μειώσουν το ταμείο κάτω από το όριο.'
                            : 'Warning: known obligations may reduce funds below the reserve.',
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
          if (canManage) _overdueSection(overdueEntries),
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
            gr ? 'Τροποποιήσεις συμβάσεων' : 'Contract amendments',
            Icons.edit_document,
            d['amendments'],
            _newContractAmendment,
            'contract_amendment',
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
            gr
                ? 'Υπηρεσίες και αναφορές βλαβών'
                : 'Services and problem reports',
            Icons.handyman_outlined,
            serviceRequests,
            _newServiceRequest,
            'service_request',
            allowMemberRequests: true,
          ),
          _section(
            gr ? 'Ένοικοι ανά διαμέρισμα' : 'Residents by apartment',
            Icons.people_alt_outlined,
            d['residents'],
            _newResident,
            'resident',
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
            gr ? 'Ασφαλιστικές απαιτήσεις' : 'Insurance claims',
            Icons.assignment_late_outlined,
            d['claims'],
            _newInsuranceClaim,
            'claim',
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

