import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';

class LeaseRenewalsScreen extends StatefulWidget {
  const LeaseRenewalsScreen({
    required this.isGreek,
    this.isStaff = false,
    super.key,
  });
  final bool isGreek;
  final bool isStaff;
  @override
  State<LeaseRenewalsScreen> createState() => _LeaseRenewalsScreenState();
}

class _LeaseRenewalsScreenState extends State<LeaseRenewalsScreen> {
  final _db = SmartBlockTrialSession.client;
  late Future<List<Map<String, dynamic>>> _rows = _load();
  bool get _gr => widget.isGreek;
  Future<List<Map<String, dynamic>>> _load() async =>
      List<Map<String, dynamic>>.from(
        await _db
            .from('lease_renewals')
            .select()
            .order('created_at', ascending: false),
      );
  void _refresh() => setState(() => _rows = _load());

  String _date(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _dateTime(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (d == null) return '—';
    return '${_date(d.toIso8601String())} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _status(String value) => switch (value) {
    'signed' =>
      _gr
          ? 'Η αποδοχή καταχωρίστηκε και από τους δύο (χωρίς QES)'
          : 'Accepted by both (without QES)',
    'cancelled' => _gr ? 'Ακυρώθηκε' : 'Cancelled',
    _ => _gr ? 'Αναμένει αποδοχή' : 'Awaiting signatures',
  };

  String _qesStatus(dynamic value) => switch (value?.toString() ??
      'not_started') {
    'document_prepared' => _gr ? 'Έτοιμο για QES' : 'Ready for QES',
    'in_progress' =>
      _gr ? 'Υπογραφή QES σε εξέλιξη' : 'QES signing in progress',
    'partially_signed' =>
      _gr ? 'Υπογράφηκε από ένα μέρος' : 'Signed by one party',
    'completed' => _gr ? 'Η QES ολοκληρώθηκε' : 'QES completed',
    'failed' => _gr ? 'Αποτυχία QES' : 'QES failed',
    'expired' => _gr ? 'Έληξε το αίτημα QES' : 'QES request expired',
    'cancelled' => _gr ? 'Ακυρώθηκε το αίτημα QES' : 'QES request cancelled',
    _ =>
      _gr
          ? 'Δεν έχει συνδεθεί ακόμη πάροχος QES'
          : 'QES provider not connected yet',
  };

  Future<void> _review(Map<String, dynamic> row) async {
    final currentId = _db.auth.currentUser?.id;
    final isOwner = row['owner_user_id'] == currentId;
    final isTenant = row['tenant_user_id'] == currentId;
    final canEditDetails =
        row['status'] == 'awaiting_signatures' &&
        row['owner_signed_at'] == null &&
        row['tenant_signed_at'] == null &&
        (isOwner || isTenant);
    final bothIdentitiesComplete =
        (row['owner_id_number'] ?? '').toString().trim().length >= 3 &&
        (row['tenant_id_number'] ?? '').toString().trim().length >= 3 &&
        (row['owner_id_type'] ?? '').toString().trim().isNotEmpty &&
        (row['tenant_id_type'] ?? '').toString().trim().isNotEmpty;
    final canSign =
        row['status'] == 'awaiting_signatures' &&
        bothIdentitiesComplete &&
        ((isOwner && row['owner_signed_at'] == null) ||
            (isTenant && row['tenant_signed_at'] == null));
    final events = await _db
        .from('lease_renewal_events')
        .select('event_type,actor_name,occurred_at')
        .eq('renewal_id', row['id'])
        .order('occurred_at');
    if (!mounted) return;
    final name = TextEditingController(
      text:
          (isOwner ? row['owner_name'] : row['tenant_name'])?.toString() ??
          _db.auth.currentUser?.userMetadata?['full_name']?.toString() ??
          '',
    );
    final idType = TextEditingController(
      text:
          (isOwner ? row['owner_id_type'] : row['tenant_id_type'])
              ?.toString() ??
          '',
    );
    final idNumber = TextEditingController(
      text:
          (isOwner ? row['owner_id_number'] : row['tenant_id_number'])
              ?.toString() ??
          '',
    );
    final form = GlobalKey<FormState>();
    var confirm = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(_gr ? 'Ανανέωση μίσθωσης' : 'Lease renewal'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _line(
                    Icons.home_outlined,
                    '${row['property_name']} · ${row['unit_reference']}',
                  ),
                  _line(
                    Icons.location_on_outlined,
                    row['property_address']?.toString() ?? '',
                  ),
                  const Divider(height: 24),
                  _line(
                    Icons.person_outline,
                    '${_gr ? 'Ιδιοκτήτης' : 'Owner'}: ${row['owner_name']} (${row['owner_email']})',
                  ),
                  _line(
                    Icons.badge_outlined,
                    '${row['owner_id_type']}: ${row['owner_id_number']}',
                  ),
                  _line(
                    Icons.person,
                    '${_gr ? 'Ενοικιαστής' : 'Tenant'}: ${row['tenant_name']} (${row['tenant_email']})',
                  ),
                  _line(
                    Icons.badge_outlined,
                    '${row['tenant_id_type']}: ${row['tenant_id_number']}',
                  ),
                  const Divider(height: 24),
                  _line(
                    Icons.payments_outlined,
                    '${row['monthly_rent']} ${row['currency']} / ${_gr ? 'μήνα' : 'month'}',
                  ),
                  _line(
                    Icons.savings_outlined,
                    '${_gr ? 'Εγγύηση' : 'Deposit'}: ${row['deposit_amount']} ${row['currency']}',
                  ),
                  _line(
                    Icons.calendar_month_outlined,
                    '${_date(row['start_date'])} – ${_date(row['end_date'])} · ${_gr ? 'Πληρωμή έως' : 'Due day'} ${row['rent_due_day']}',
                  ),
                  _line(
                    Icons.apartment_outlined,
                    '${_gr ? 'Κοινόχρηστα' : 'Common charges'}: ${row['common_charges']} ${row['currency']}',
                  ),
                  if ((row['furniture_and_inventory'] ?? '')
                      .toString()
                      .isNotEmpty)
                    _paragraph(
                      _gr ? 'Έπιπλα και απογραφή' : 'Furniture and inventory',
                      row['furniture_and_inventory'],
                    ),
                  if ((row['included_services'] ?? '').toString().isNotEmpty)
                    _paragraph(
                      _gr ? 'Υπηρεσίες και παροχές' : 'Services and utilities',
                      row['included_services'],
                    ),
                  if ((row['special_terms'] ?? '').toString().isNotEmpty)
                    _paragraph(
                      _gr ? 'Ειδικοί όροι' : 'Special terms',
                      row['special_terms'],
                    ),
                  _paragraph(
                    _gr
                        ? 'Πληρωμές μέσω SmartBlock'
                        : 'SmartBlock payment terms',
                    row['payment_terms'],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status(row['status'].toString()),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  _line(
                    Icons.verified_user_outlined,
                    '${_gr ? 'Εγκεκριμένη ηλεκτρονική υπογραφή' : 'Qualified electronic signature'}: ${_qesStatus(row['qes_status'])}',
                  ),
                  if (row['owner_signed_at'] != null)
                    Text(
                      '${_gr ? 'Αποδοχή ιδιοκτήτη' : 'Owner acceptance'}: ${row['owner_signed_name']} · ${_dateTime(row['owner_signed_at'])}',
                    ),
                  if (row['tenant_signed_at'] != null)
                    Text(
                      '${_gr ? 'Αποδοχή ενοικιαστή' : 'Tenant acceptance'}: ${row['tenant_signed_name']} · ${_dateTime(row['tenant_signed_at'])}',
                    ),
                  if ((events as List).isNotEmpty) ...[
                    const Divider(height: 24),
                    Text(
                      _gr ? 'Ιστορικό αποδοχών' : 'Acceptance history',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    ...events.map(
                      (e) => Text(
                        '${e['actor_name']} · ${_dateTime(e['occurred_at'])} · ${e['event_type']}',
                      ),
                    ),
                  ],
                  _paragraph(
                    _gr
                        ? 'Αποτύπωμα όρων (SHA-256)'
                        : 'Terms fingerprint (SHA-256)',
                    row['terms_sha256'],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _gr
                          ? 'Η αποδοχή καταγράφεται με τον συνδεδεμένο λογαριασμό, το όνομα, την ώρα και αποτύπωμα SHA-256 των όρων. Δεν είναι εγκεκριμένη ειδική ηλεκτρονική υπογραφή (QES) και δεν εγγυάται ότι η συμφωνία δεν θα αμφισβητηθεί.'
                          : 'Acceptance is recorded with the signed-in account, typed name, time and SHA-256 terms fingerprint. This is not a qualified electronic signature (QES) and cannot guarantee that an agreement will never be disputed.',
                    ),
                  ),
                  if (canEditDetails || canSign) ...[
                    const SizedBox(height: 12),
                    Form(
                      key: form,
                      child: Column(
                        children: [
                          TextFormField(
                            controller: name,
                            decoration: InputDecoration(
                              labelText: _gr
                                  ? 'Το ονοματεπώνυμό σου όπως στην ταυτότητα'
                                  : 'Your full legal name as on ID',
                            ),
                            validator: (v) => (v?.trim().length ?? 0) < 3
                                ? (_gr
                                      ? 'Συμπλήρωσε το ονοματεπώνυμο.'
                                      : 'Enter your full legal name.')
                                : null,
                          ),
                          TextFormField(
                            controller: idType,
                            decoration: InputDecoration(
                              labelText: _gr
                                  ? 'Τύπος ταυτότητας (π.χ. ταυτότητα, διαβατήριο)'
                                  : 'ID type (e.g. national ID, passport)',
                            ),
                            validator: (v) => (v?.trim().length ?? 0) < 2
                                ? (_gr
                                      ? 'Συμπλήρωσε τον τύπο.'
                                      : 'Enter the ID type.')
                                : null,
                          ),
                          TextFormField(
                            controller: idNumber,
                            decoration: InputDecoration(
                              labelText: _gr
                                  ? 'Αριθμός ταυτότητας ή διαβατηρίου'
                                  : 'ID or passport number',
                            ),
                            validator: (v) => (v?.trim().length ?? 0) < 3
                                ? (_gr
                                      ? 'Συμπλήρωσε τον αριθμό.'
                                      : 'Enter the ID number.')
                                : null,
                          ),
                          if (canSign)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: confirm,
                              onChanged: (v) =>
                                  setDialogState(() => confirm = v ?? false),
                              title: Text(
                                _gr
                                    ? 'Διάβασα τους όρους και αποδέχομαι ηλεκτρονικά αυτήν την ανανέωση.'
                                    : 'I have read the terms and electronically accept this renewal.',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(_gr ? 'Κλείσιμο' : 'Close'),
            ),
            if (canEditDetails)
              OutlinedButton.icon(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  try {
                    await _db.rpc(
                      'save_lease_renewal_party_details',
                      params: {
                        'p_renewal_id': row['id'],
                        'p_full_name': name.text.trim(),
                        'p_id_type': idType.text.trim(),
                        'p_id_number': idNumber.text.trim(),
                      },
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _refresh();
                  } on PostgrestException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: Text(
                  _gr ? 'Αποθήκευση στοιχείων μου' : 'Save my details',
                ),
              ),
            if (canSign)
              FilledButton.icon(
                onPressed: () async {
                  if (!form.currentState!.validate() || !confirm) return;
                  try {
                    await _db.rpc(
                      'sign_lease_renewal',
                      params: {
                        'p_renewal_id': row['id'],
                        'p_signer_name': name.text.trim(),
                        'p_confirm': true,
                      },
                    );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                    }
                    _refresh();
                  } on PostgrestException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                icon: const Icon(Icons.draw_outlined),
                label: Text(
                  _gr
                      ? 'Καταχώριση αποδοχής (χωρίς QES)'
                      : 'Record acceptance (without QES)',
                ),
              ),
            if (widget.isStaff && row['status'] == 'awaiting_signatures')
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _cancelRenewal(row['id'].toString());
                },
                icon: const Icon(Icons.cancel_outlined),
                label: Text(_gr ? 'Ακύρωση πρότασης' : 'Cancel proposal'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _cancelRenewal(String renewalId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_gr ? 'Ακύρωση πρότασης;' : 'Cancel this proposal?'),
        content: Text(
          _gr
              ? 'Η πρόταση θα σημειωθεί ως ακυρωμένη και θα παραμείνει στο ιστορικό.'
              : 'The proposal will be marked cancelled and kept in the audit history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_gr ? 'Πίσω' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_gr ? 'Ακύρωση' : 'Cancel proposal'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _db.rpc(
        'cancel_lease_renewal',
        params: {'p_renewal_id': renewalId},
      );
      _refresh();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Widget _line(IconData icon, String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
  Widget _paragraph(String title, dynamic content) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(content?.toString() ?? ''),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_gr ? 'Ανανεώσεις μισθώσεων' : 'Lease renewals'),
      actions: [
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _rows,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(snapshot.error.toString()),
            ),
          );
        }
        final rows = snapshot.data ?? const [];
        if (rows.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _gr
                    ? 'Δεν υπάρχουν ανανεώσεις συνδεδεμένες με τον λογαριασμό σου.'
                    : 'There are no renewals linked to your account.',
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: rows
                .map(
                  (row) => Card(
                    child: ListTile(
                      leading: Icon(
                        row['status'] == 'signed'
                            ? Icons.verified_outlined
                            : Icons.edit_document,
                      ),
                      title: Text(
                        '${row['property_name']} · ${row['unit_reference']}',
                      ),
                      subtitle: Text(
                        '${row['monthly_rent']} ${row['currency']} / ${_gr ? 'μήνα' : 'month'} · ${_date(row['start_date'])} – ${_date(row['end_date'])}\n${_status(row['status'].toString())}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _review(row),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
    ),
  );
}

\n