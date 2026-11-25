import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app_language.dart';
import '../smartblock_text.dart';

class AdminBillingScreen extends StatefulWidget {
  const AdminBillingScreen({super.key});

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen> {
  final _db = Supabase.instance.client;
  final _monthlyRate = TextEditingController(text: '5.00');
  final _paymentPercent = TextEditingController(text: '5.00');
  late Future<void> _load;
  DateTime _effectiveDate = DateTime.now().add(const Duration(days: 1));
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _availableTargets = [];
  final Set<String> _selectedTargetIds = {};
  Map<String, String> _targetLabels = {};
  String _scopeType = 'all';
  bool _loadingTargets = false;
  bool _saving = false;
  bool get _greek =>
      SmartBlockLanguageController.instance.selected.value.isGreek;

  @override
  void initState() {
    super.initState();
    _load = _refresh();
  }

  @override
  void dispose() {
    _monthlyRate.dispose();
    _paymentPercent.dispose();
    super.dispose();
  }

  String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> _refresh() async {
    final results = await Future.wait([
      _db.rpc('smartblock_current_billing_rates'),
      _db.rpc('admin_list_smartblock_billing_schedules'),
      _db.rpc('admin_list_smartblock_billing_targets', params: {'p_scope_type': 'users'}),
      _db.rpc('admin_list_smartblock_billing_targets', params: {'p_scope_type': 'properties'}),
    ]);
    if (!mounted) return;
    final current = results[0] as List;
    final rows = List<Map<String, dynamic>>.from(results[1] as List);
    final userTargets = List<Map<String, dynamic>>.from(results[2] as List);
    final propertyTargets = List<Map<String, dynamic>>.from(results[3] as List);
    final labels = <String, String>{};
    for (final target in userTargets) {
      labels['users:${target['target_id']}'] = target['display_name']?.toString() ?? '';
    }
    for (final target in propertyTargets) {
      labels['properties:${target['target_id']}'] = target['display_name']?.toString() ?? '';
    }
    final rate = current.first as Map<String, dynamic>;
    final scheduledRows = rows
        .where((row) => row['status'] == 'scheduled' && (row['scope_type']?.toString() ?? 'all') == 'all')
        .toList();
    final nextRate = scheduledRows.isNotEmpty ? scheduledRows.first : rate;
    _monthlyRate.text = ((nextRate['apartment_monthly_eur'] as num).toDouble()).toStringAsFixed(2);
    _paymentPercent.text = ((nextRate['online_payment_fee_percent'] as num).toDouble()).toStringAsFixed(2);
    setState(() {
      _schedules = rows;
      _targetLabels = labels;
      _availableTargets = _scopeType == 'users' ? userTargets : propertyTargets;
    });
  }

  Future<void> _setScope(String scope) async {
    setState(() {
      _scopeType = scope;
      _selectedTargetIds.clear();
      _availableTargets = [];
      _loadingTargets = scope != 'all';
    });
    if (scope == 'all') return;
    try {
      final rows = List<Map<String, dynamic>>.from(
        await _db.rpc('admin_list_smartblock_billing_targets', params: {'p_scope_type': scope}) as List,
      );
      if (!mounted || _scopeType != scope) return;
      setState(() {
        _availableTargets = rows;
        _loadingTargets = false;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => _loadingTargets = false);
      _message(error.message);
    }
  }

  Future<void> _pickTargets() async {
    if (_loadingTargets || _availableTargets.isEmpty) return;
    final search = TextEditingController();
    final selected = Set<String>.from(_selectedTargetIds);
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final query = search.text.trim().toLowerCase();
          final filtered = _availableTargets.where((target) {
            final name = target['display_name']?.toString().toLowerCase() ?? '';
            final detail = target['detail']?.toString().toLowerCase() ?? '';
            return query.isEmpty || name.contains(query) || detail.contains(query);
          }).toList();
          return AlertDialog(
            title: Text(_scopeType == 'users'
                ? (_greek ? 'Επιλογή λογαριασμών ιδιοκτητών' : 'Select owner accounts')
                : (_greek ? 'Επιλογή πολυκατοικιών' : 'Select buildings')),
            content: SizedBox(
              width: double.maxFinite,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    controller: search,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: _greek ? 'Αναζήτηση' : 'Search',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text(_greek ? 'Δεν βρέθηκαν αποτελέσματα.' : 'No matches found.'))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final target = filtered[index];
                              final id = target['target_id'].toString();
                              return CheckboxListTile(
                                value: selected.contains(id),
                                onChanged: (checked) => setDialogState(() {
                                  if (checked == true) {
                                    selected.add(id);
                                  } else {
                                    selected.remove(id);
                                  }
                                }),
                                title: Text(target['display_name']?.toString() ?? ''),
                                subtitle: target['detail']?.toString().isNotEmpty == true
                                    ? Text(target['detail'].toString())
                                    : null,
                                controlAffinity: ListTileControlAffinity.leading,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(_greek ? 'Άκυρο' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, selected),
                child: Text(_greek ? 'Επιλογή (${selected.length})' : 'Select (${selected.length})'),
              ),
            ],
          );
        },
      ),
    );
    search.dispose();
    if (result != null && mounted) {
      setState(() {
        _selectedTargetIds
          ..clear()
          ..addAll(result);
      });
    }
  }

  String _scopeDescription(Map<String, dynamic> row) {
    final scope = row['scope_type']?.toString() ?? 'all';
    if (scope == 'all') return _greek ? 'Όλοι οι ιδιοκτήτες' : 'All owners';
    final ids = List<String>.from(row['scope_ids'] as List? ?? const []);
    final names = ids
        .map((id) => _targetLabels['$scope:$id'])
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList();
    final title = scope == 'users'
        ? (_greek ? 'Λογαριασμοί' : 'Owner accounts')
        : (_greek ? 'Πολυκατοικίες' : 'Buildings');
    return '$title: ${names.isEmpty ? ids.length : names.join(', ')}';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _effectiveDate.isBefore(now) ? now : _effectiveDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (selected != null) setState(() => _effectiveDate = selected);
  }

  Future<void> _scheduleChange() async {
    final monthly = double.tryParse(_monthlyRate.text.replaceAll(',', '.'));
    final percent = double.tryParse(_paymentPercent.text.replaceAll(',', '.'));
    if (_scopeType != 'all' && _selectedTargetIds.isEmpty) {
      _message(_greek ? 'Επίλεξε τουλάχιστον έναν λογαριασμό ή πολυκατοικία.' : 'Select at least one account or building.');
      return;
    }
    if (monthly == null ||
        monthly < 0 ||
        percent == null ||
        percent < 0 ||
        percent > 100) {
      _message(
        _greek
            ? 'Έλεγξε τις τιμές. Το ποσοστό πρέπει να είναι από 0 έως 100.'
            : 'Check the rates. The percentage must be between 0 and 100.',
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _db.rpc(
        'admin_schedule_smartblock_billing_change',
        params: {
          'p_apartment_monthly_eur': monthly,
          'p_online_payment_fee_percent': percent,
          'p_effective_on': _date(_effectiveDate),
          'p_scope_type': _scopeType,
          'p_scope_ids': _scopeType == 'all' ? <String>[] : _selectedTargetIds.toList(),
        },
      );
      final details = (result as List).first as Map<String, dynamic>;
      await _refresh();
      if (!mounted) return;
      _message(
        _greek
            ? 'Η αλλαγή προγραμματίστηκε. Ενημερώθηκαν ${details['notified_owner_count']} λογαριασμοί ιδιοκτητών.'
            : 'Change scheduled. ${details['notified_owner_count']} owner accounts were notified.',
      );
    } on PostgrestException catch (error) {
      _message(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await _db.rpc(
        'admin_cancel_smartblock_billing_change',
        params: {'p_schedule_id': id},
      );
      await _refresh();
    } on PostgrestException catch (error) {
      _message(error.message);
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_greek ? 'Χρεώσεις SmartBlock' : 'SmartBlock billing'),
    ),
    body: FutureBuilder<void>(
      future: _load,
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
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _greek ? 'Νέα τιμολόγηση' : 'Schedule pricing changes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _greek
                  ? 'Η μηνιαία τιμή αφορά κάθε διαμέρισμα πολυκατοικίας. Η προμήθεια αφαιρείται από το ποσό που αποδίδεται στο ακίνητο.'
                  : 'The monthly rate applies to each apartment in a building. The payment fee is deducted from the amount paid to the property.',
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _scopeType,
              decoration: InputDecoration(
                labelText: _greek ? 'Εφαρμογή αλλαγής σε' : 'Apply change to',
                prefixIcon: const Icon(Icons.tune_outlined),
              ),
              items: [
                DropdownMenuItem(value: 'all', child: Text(_greek ? 'Όλους τους ιδιοκτήτες' : 'All owners')),
                DropdownMenuItem(value: 'users', child: Text(_greek ? 'Επιλεγμένους λογαριασμούς ιδιοκτητών' : 'Selected owner accounts')),
                DropdownMenuItem(value: 'properties', child: Text(_greek ? 'Επιλεγμένες πολυκατοικίες' : 'Selected buildings')),
              ],
              onChanged: _saving ? null : (value) {
                if (value != null) _setScope(value);
              },
            ),
            if (_scopeType != 'all') ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _loadingTargets ? null : _pickTargets,
                icon: _loadingTargets
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.checklist_outlined),
                label: Text(_loadingTargets
                    ? (_greek ? 'Φόρτωση επιλογών…' : 'Loading options…')
                    : _greek
                        ? 'Επιλογή ${_scopeType == 'users' ? 'λογαριασμών' : 'πολυκατοικιών'} (${_selectedTargetIds.length})'
                        : 'Choose ${_scopeType == 'users' ? 'accounts' : 'buildings'} (${_selectedTargetIds.length})'),
              ),
              if (_selectedTargetIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _selectedTargetIds
                        .map((id) => _targetLabels['$_scopeType:$id'] ?? id)
                        .take(4)
                        .join(', ') +
                        (_selectedTargetIds.length > 4 ? ' …' : ''),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _monthlyRate,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _greek
                    ? 'Ευρώ ανά διαμέρισμα / μήνα'
                    : 'Euros per apartment / month',
                prefixText: '€ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paymentPercent,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: _greek
                    ? 'Ποσοστό σε εικονικές πολυκατοικίες (online πληρωμές)'
                    : 'Virtual building percentage (online payments)',
                suffixText: '%',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                '${_greek ? 'Ημερομηνία ισχύος' : 'Effective date'}: ${_date(_effectiveDate)}',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _scheduleChange,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.schedule),
              label: Text(
                _greek
                    ? 'Προγραμματισμός και ενημέρωση ιδιοκτητών'
                    : 'Schedule and notify owners',
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _greek ? 'Προγραμματισμένες αλλαγές' : 'Scheduled changes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (_schedules.isEmpty)
              Text(
                _greek
                    ? 'Δεν υπάρχουν προγραμματισμένες αλλαγές.'
                    : 'No scheduled changes.',
              ),
            for (final row in _schedules)
              Builder(
                builder: (context) {
                  final effectiveDate = DateTime.parse(
                    row['effective_on'] as String,
                  );
                  final now = DateTime.now();
                  final isEffective = !effectiveDate.isAfter(
                    DateTime(now.year, now.month, now.day),
                  );
                  final status = row['status'] == 'cancelled'
                      ? (_greek ? 'Ακυρώθηκε' : 'Cancelled')
                      : isEffective
                      ? (_greek ? 'Σε ισχύ' : 'Active')
                      : (_greek ? 'Προγραμματισμένη' : 'Scheduled');
                  return Card(
                    child: ListTile(
                      title: Text(
                        '${row['effective_on']} · €${row['apartment_monthly_eur']} / ${_greek ? 'διαμέρισμα / μήνα' : 'apartment / month'}',
                      ),
                      subtitle: Text(
                        '${_scopeDescription(row)}\n${_greek ? 'Ποσοστό online πληρωμής' : 'Online payment fee'}: ${row['online_payment_fee_percent']}% · $status',
                      ),
                      trailing:
                          row['status'] == 'scheduled' &&
                              effectiveDate.isAfter(now)
                          ? IconButton(
                              tooltip: _greek ? 'Ακύρωση' : 'Cancel',
                              icon: const Icon(Icons.cancel_outlined),
                              onPressed: () => _cancel(row['id'] as String),
                            )
                          : null,
                    ),
                  );
                },
              ),
          ],
        );
      },
    ),
  );
}

