import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ResidentContractsScreen extends StatefulWidget {
  const ResidentContractsScreen({required this.isGreek, super.key});
  final bool isGreek;
  @override
  State<ResidentContractsScreen> createState() => _ResidentContractsScreenState();
}

class _ResidentContractsScreenState extends State<ResidentContractsScreen> {
  final _db = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _contracts = _loadContracts();
  late Future<List<Map<String, dynamic>>> _requests = _loadRequests();
  bool busy = false;
  bool get gr => widget.isGreek;

  Future<List<Map<String, dynamic>>> _loadContracts() async =>
      List<Map<String, dynamic>>.from(await _db.rpc('my_tenant_lease_contracts'));

  Future<List<Map<String, dynamic>>> _loadRequests() async =>
      List<Map<String, dynamic>>.from(await _db
          .from('lease_tenant_requests')
          .select('id,contract_id,request_type,requested_end_date,message,status,decision_note,created_at')
          .eq('tenant_user_id', _db.auth.currentUser!.id)
          .order('created_at', ascending: false));

  String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '—';
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String _status(String? value) => gr
      ? switch (value) {
          'active' || 'current' || 'signed' => 'Ενεργό',
          'requested' => 'Σε αναμονή',
          'reviewed' => 'Υπό εξέταση',
          'accepted' => 'Εγκρίθηκε',
          'declined' => 'Δεν εγκρίθηκε',
          'withdrawn' => 'Ακυρώθηκε',
          _ => value ?? '—',
        }
      : (value ?? '—').replaceAll('_', ' ');

  void _reload() {
    setState(() {
      _contracts = _loadContracts();
      _requests = _loadRequests();
    });
  }

  Future<void> _newRequest(Map<String, dynamic> contract, String type) async {
    final message = TextEditingController();
    DateTime? requestedEndDate;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(type == 'renewal'
              ? (gr ? 'Αίτημα ανανέωσης' : 'Request a renewal')
              : (gr ? 'Αίτημα πρόωρης διακοπής' : 'Request early termination')),
          content: SizedBox(
            width: 460,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (type == 'early_termination')
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(gr ? 'Προτεινόμενη ημερομηνία λήξης' : 'Requested end date'),
                  subtitle: Text(requestedEndDate == null ? (gr ? 'Επίλεξε ημερομηνία' : 'Choose a date') : _date(requestedEndDate!.toIso8601String())),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: now.isBefore(DateTime.tryParse(contract['start_date']?.toString() ?? '') ?? now) ? (DateTime.tryParse(contract['start_date']?.toString() ?? '') ?? now) : now,
                      firstDate: DateTime.tryParse(contract['start_date']?.toString() ?? '') ?? now,
                      lastDate: DateTime.tryParse(contract['end_date']?.toString() ?? '') ?? DateTime(now.year + 5),
                    );
                    if (picked != null) setDialog(() => requestedEndDate = picked);
                  },
                ),
              TextField(
                controller: message,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: gr ? 'Μήνυμα προς τον ιδιοκτήτη (προαιρετικό)' : 'Message to the owner (optional)',
                ),
              ),
              const SizedBox(height: 8),
              Text(gr
                  ? 'Το αίτημα θα καταγραφεί και θα σταλεί ειδοποίηση στον ιδιοκτήτη. Δεν αλλάζει αυτόματα το συμβόλαιο.'
                  : 'The request will be recorded and the owner notified. It does not change the contract automatically.'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(
              onPressed: type == 'early_termination' && requestedEndDate == null ? null : () => Navigator.pop(ctx, true),
              child: Text(gr ? 'Αποστολή αιτήματος' : 'Send request'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) { message.dispose(); return; }
    setState(() => busy = true);
    try {
      await _db.rpc('create_tenant_lease_request', params: {
        'p_contract_id': contract['contract_id'],
        'p_request_type': type,
        'p_message': message.text.trim(),
        'p_requested_end_date': requestedEndDate == null ? null : '${requestedEndDate!.year.toString().padLeft(4, '0')}-${requestedEndDate!.month.toString().padLeft(2, '0')}-${requestedEndDate!.day.toString().padLeft(2, '0')}',
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(gr ? 'Το αίτημα στάλθηκε στον ιδιοκτήτη.' : 'Your request was sent to the owner.')));
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      message.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _detail(String label, dynamic value, {IconData? icon}) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty || text == 'null') return const SizedBox.shrink();
    return ListTile(dense: true, leading: icon == null ? null : Icon(icon), title: Text(label), subtitle: Text(text));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(gr ? 'Συμβόλαιο' : 'Rental agreement'),
      actions: [IconButton(onPressed: busy ? null : _reload, icon: const Icon(Icons.refresh))],
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _contracts,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(snapshot.error.toString())));
        final contracts = snapshot.data ?? const [];
        if (contracts.isEmpty) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(gr ? 'Δεν έχει συνδεθεί ακόμη ενεργό συμβόλαιο με τον λογαριασμό σου.' : 'No rental agreement is linked to your account yet.')));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text(gr ? 'Τα συμβόλαιά μου' : 'My agreements', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _requests,
            builder: (context, requestSnapshot) {
              final requests = requestSnapshot.data ?? const [];
              return Column(children: contracts.map((contract) {
                final active = ['active','signed','current'].contains(contract['contract_status']) &&
                    (contract['end_date'] == null || DateTime.tryParse(contract['end_date'].toString())?.isBefore(DateTime.now()) != true);
                final ownRequests = requests.where((request) => request['contract_id'] == contract['contract_id']).toList();
                return Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text('${contract['property_name'] ?? (gr ? 'Ακίνητο' : 'Property')} · ${gr ? 'Διαμέρισμα ' : 'Apartment '}${contract['unit_reference'] ?? '—'}'),
                    subtitle: Text('${_date(contract['start_date'])} – ${_date(contract['end_date'])} · €${contract['monthly_rent'] ?? 0}/${gr ? 'μήνα' : 'month'} · ${_status(contract['contract_status']?.toString())}'),
                    children: [
                      _detail(gr ? 'Διεύθυνση' : 'Address', contract['property_address'], icon: Icons.location_on_outlined),
                      _detail(gr ? 'Ιδιοκτήτης' : 'Owner', contract['owner_name'], icon: Icons.person_outline),
                      _detail(gr ? 'Ημερομηνία έναρξης' : 'Start date', _date(contract['start_date'])),
                      _detail(gr ? 'Ημερομηνία λήξης' : 'End date', _date(contract['end_date'])),
                      _detail(gr ? 'Ενοίκιο / μήνα' : 'Monthly rent', '€${contract['monthly_rent'] ?? 0} ${contract['currency'] ?? 'EUR'}'),
                      _detail(gr ? 'Εγγύηση (συμφωνημένο ποσό)' : 'Agreed deposit', contract['deposit_amount'] == null ? null : '€${contract['deposit_amount']}'),
                      _detail(gr ? 'Κοινόχρηστα' : 'Common charges', contract['common_charges']),
                      _detail(gr ? 'Έπιπλα και απογραφή' : 'Furniture and inventory', contract['furniture_and_inventory']),
                      _detail(gr ? 'Περιλαμβανόμενες υπηρεσίες' : 'Included services', contract['included_services']),
                      _detail(gr ? 'Όροι πληρωμής' : 'Payment terms', contract['payment_terms']),
                      _detail(gr ? 'Ειδικοί όροι' : 'Special terms', contract['special_terms']),
                      for (final request in ownRequests)
                        ListTile(
                          leading: Icon(request['request_type'] == 'renewal' ? Icons.autorenew : Icons.event_busy_outlined),
                          title: Text(request['request_type'] == 'renewal' ? (gr ? 'Αίτημα ανανέωσης' : 'Renewal request') : (gr ? 'Αίτημα πρόωρης διακοπής' : 'Early termination request')),
                          subtitle: Text('${_status(request['status']?.toString())}${request['requested_end_date'] == null ? '' : ' · ${_date(request['requested_end_date'])}'}${(request['decision_note'] as String? ?? '').isEmpty ? '' : ' · ${request['decision_note']}'}'),
                        ),
                      if (active) Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Wrap(spacing: 8, runSpacing: 8, children: [
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => _newRequest(contract, 'renewal'),
                            icon: const Icon(Icons.autorenew),
                            label: Text(gr ? 'Ζήτησε ανανέωση' : 'Request renewal'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : () => _newRequest(contract, 'early_termination'),
                            icon: const Icon(Icons.event_busy_outlined),
                            label: Text(gr ? 'Ζήτησε πρόωρη διακοπή' : 'Request early termination'),
                          ),
                        ]),
                      ),
                    ],
                  ),
                );
              }).toList());
            },
          ),
        ]);
      },
    ),
  );
}
