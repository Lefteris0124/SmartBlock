import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../smartblock_trial_session.dart';

class SharedFinancialOverviewScreen extends StatefulWidget {
  const SharedFinancialOverviewScreen({
    required this.propertyId,
    required this.propertyName,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final bool isGreek;

  @override
  State<SharedFinancialOverviewScreen> createState() =>
      _SharedFinancialOverviewScreenState();
}

class _SharedFinancialOverviewScreenState
    extends State<SharedFinancialOverviewScreen> {
  final _db = SmartBlockTrialSession.client;
  late Future<Map<String, dynamic>> _overview;
  bool get _gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _overview = _load();
  }

  Future<Map<String, dynamic>> _load() async {
    final result = await _db.rpc(
      'get_property_shared_financial_overview',
      params: {'p_property_id': widget.propertyId},
    );
    final canManage = await _db.rpc(
      'can_manage_property',
      params: {'target_property_id': widget.propertyId},
    );
    return {
      'data': Map<String, dynamic>.from(result as Map),
      'can_manage': canManage == true,
    };
  }

  Future<void> _refresh() async {
    setState(() => _overview = _load());
    await _overview;
  }

  String _money(dynamic value) =>
      '€${((value as num?) ?? 0).toStringAsFixed(2)}';

  Future<void> _manageUnitOwners() async {
    try {
      final units = List<Map<String, dynamic>>.from(
        await _db
            .from('property_apartments')
            .select('id,apartment_number,area_sqm,property_owner_id')
            .eq('property_id', widget.propertyId)
            .order('apartment_number'),
      );
      final owners = List<Map<String, dynamic>>.from(
        await _db
            .from('property_owners')
            .select('id,apartment_count,area_sqm,ownership_percentage,ownership_status,organizations(display_name)')
            .eq('property_id', widget.propertyId)
            .order('created_at'),
      );
      if (!mounted) return;
      if (units.isEmpty) {
        _message(_gr
            ? 'Δεν έχουν καταχωρηθεί διαμερίσματα για αυτό το ακίνητο.'
            : 'No apartments have been registered for this property.');
        return;
      }
      final original = <String, String>{
        for (final unit in units)
          unit['id'] as String: unit['property_owner_id'] as String? ?? '',
      };
      final selected = Map<String, String>.from(original);
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialog) => AlertDialog(
            title: Text(_gr ? 'Σύνδεση ιδιοκτητών με διαμερίσματα' : 'Assign owners to apartments'),
            content: SizedBox(
              width: 520,
              height: MediaQuery.sizeOf(dialogContext).height * .58,
              child: owners.isEmpty
                  ? Center(child: Text(_gr
                      ? 'Δεν υπάρχουν ενεργοί ιδιοκτήτες στο ακίνητο.'
                      : 'There are no active owners for this property.'))
                  : ListView.separated(
                      itemCount: units.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final unit = units[index];
                        final unitId = unit['id'] as String;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${_gr ? 'Διαμέρισμα' : 'Apartment'} ${unit['apartment_number']}',
                          ),
                          subtitle: Text('${unit['area_sqm']} m²'),
                          trailing: SizedBox(
                            width: 230,
                            child: DropdownButtonFormField<String>(
                              initialValue: selected[unitId] ?? '',
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: _gr ? 'Ιδιοκτήτης' : 'Owner',
                                isDense: true,
                              ),
                              items: [
                                DropdownMenuItem(
                                  value: '',
                                  child: Text(_gr ? 'Χωρίς σύνδεση' : 'Unassigned'),
                                ),
                                ...owners.map((owner) {
                                  final organization =
                                      owner['organizations'] as Map<String, dynamic>? ?? {};
                                  final apartments = owner['apartment_count'];
                                  return DropdownMenuItem(
                                    value: owner['id'] as String,
                                    enabled: owner['ownership_status'] == 'active',
                                    child: Text(
                                      '${organization['display_name'] ?? (_gr ? 'Ιδιοκτήτης' : 'Owner')} · ${apartments ?? '—'} ${_gr ? 'διαμ.' : 'units'}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setDialog(() => selected[unitId] = value);
                                }
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_gr ? 'Άκυρο' : 'Cancel'),
              ),
              FilledButton.icon(
                onPressed: owners.isEmpty ? null : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.save_outlined),
                label: Text(_gr ? 'Αποθήκευση' : 'Save'),
              ),
            ],
          ),
        ),
      );
      if (saved != true) return;
      for (final unit in units) {
        final unitId = unit['id'] as String;
        if (selected[unitId] == original[unitId]) continue;
        await _db.rpc(
          'set_property_apartment_owner',
          params: {
            'p_apartment_id': unitId,
            'p_property_owner_id':
                (selected[unitId] ?? '').isEmpty ? null : selected[unitId],
          },
        );
      }
      if (mounted) {
        _message(_gr ? 'Οι αντιστοιχίσεις αποθηκεύτηκαν.' : 'Apartment assignments saved.');
        await _refresh();
      }
    } on PostgrestException catch (error) {
      if (mounted) _message(error.message);
    } catch (_) {
      if (mounted) {
        _message(_gr
            ? 'Δεν ήταν δυνατή η φόρτωση των αντιστοιχίσεων.'
            : 'Could not load apartment assignments.');
      }
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _metric({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    required double width,
    String? detail,
  }) => SizedBox(
    width: width,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 5),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    ),
  );

  String _statusLabel(String status) => _gr
      ? switch (status) {
          'paid' => 'Εξοφλημένα',
          'partial' => 'Μερική πληρωμή',
          'unpaid' => 'Οφείλονται κοινόχρηστα',
          'needs_mapping' => 'Απαιτείται αντιστοίχιση',
          'not_charged' => 'Δεν υπάρχει χρέωση',
          _ => 'Εκκρεμεί',
        }
      : switch (status) {
          'paid' => 'Paid',
          'partial' => 'Partially paid',
          'unpaid' => 'Common charges due',
          'needs_mapping' => 'Owner mapping needed',
          'not_charged' => 'No charge',
          _ => 'Pending',
        };

  Color _statusColor(String status, ColorScheme colors) => switch (status) {
    'paid' => const Color(0xFF267657),
    'partial' => const Color(0xFFB7791F),
    'unpaid' => colors.error,
    'needs_mapping' => colors.tertiary,
    _ => colors.onSurfaceVariant,
  };

  Widget _buildOverview(Map<String, dynamic> outer) {
    final data = Map<String, dynamic>.from(outer['data'] as Map);
    final canManage = outer['can_manage'] == true;
    final apartments = List<Map<String, dynamic>>.from(
      (data['apartments'] as List?) ?? const [],
    );
    final colors = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Row(
            children: [
              const Icon(Icons.visibility_outlined),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _gr ? 'Οικονομική διαφάνεια πολυκατοικίας' : 'Building financial transparency',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (canManage)
                IconButton(
                  tooltip: _gr ? 'Σύνδεση διαμερισμάτων με ιδιοκτήτες' : 'Assign apartment owners',
                  onPressed: _manageUnitOwners,
                  icon: const Icon(Icons.manage_accounts_outlined),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _gr
                ? 'Εμφανίζονται μόνο κοινόχρηστα και έξοδα πολυκατοικίας. Τα ενοίκια και τα προσωπικά στοιχεία δεν εμφανίζονται.'
                : 'Only shared charges and building expenses appear here. Rent and personal details are not shown.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth > 760
                ? (constraints.maxWidth - 24) / 4
                : constraints.maxWidth > 520
                    ? (constraints.maxWidth - 16) / 3
                    : (constraints.maxWidth - 8) / 2;
            return Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _metric(
                  width: width,
                  icon: Icons.savings_outlined,
                  title: _gr ? 'Εκτιμώμενο κοινό ταμείο' : 'Estimated common fund',
                  value: _money(data['estimated_common_fund']),
                  color: (data['estimated_common_fund'] as num? ?? 0) < 0 ? colors.error : colors.primary,
                  detail: _gr ? 'Με βάση εισπράξεις, έξοδα και αρχικό υπόλοιπο' : 'Based on receipts, expenses and opening balance',
                ),
                _metric(
                  width: width,
                  icon: Icons.receipt_long_outlined,
                  title: _gr ? 'Κοινόχρηστα που εισπράχθηκαν' : 'Common charges collected',
                  value: _money(data['common_charges_paid']),
                  color: const Color(0xFF267657),
                  detail: '${_gr ? 'Από' : 'Of'} ${_money(data['common_charges_due'])} · ${_gr ? 'καθαρά στο ταμείο' : 'net to fund'} ${_money(data['common_charges_net_received'])}',
                ),
                _metric(
                  width: width,
                  icon: Icons.pending_actions_outlined,
                  title: _gr ? 'Υπόλοιπο κοινόχρηστων' : 'Common charges outstanding',
                  value: _money(data['common_charges_outstanding']),
                  color: (data['common_charges_outstanding'] as num? ?? 0) > 0 ? colors.error : const Color(0xFF267657),
                ),
                _metric(
                  width: width,
                  icon: Icons.build_outlined,
                  title: _gr ? 'Βλάβες / επισκευές' : 'Repairs',
                  value: _money(data['damage_repair_paid']),
                  color: colors.tertiary,
                ),
                _metric(
                  width: width,
                  icon: Icons.handyman_outlined,
                  title: _gr ? 'Συντήρηση κτιρίου' : 'Building maintenance',
                  value: _money(data['maintenance_paid']),
                  color: colors.tertiary,
                ),
                _metric(
                  width: width,
                  icon: Icons.water_drop_outlined,
                  title: _gr ? 'Λογαριασμοί νερού' : 'Water bills',
                  value: _money(data['water_bill_paid']),
                  color: colors.primary,
                ),
                _metric(
                  width: width,
                  icon: Icons.bolt_outlined,
                  title: _gr ? 'Λογαριασμοί ρεύματος' : 'Electricity bills',
                  value: _money(data['electricity_bill_paid']),
                  color: colors.primary,
                ),
                _metric(
                  width: width,
                  icon: Icons.elevator_outlined,
                  title: _gr ? 'Συντήρηση ανελκυστήρα' : 'Elevator maintenance',
                  value: _money(data['elevator_maintenance_paid']),
                  color: colors.secondary,
                ),
                _metric(
                  width: width,
                  icon: Icons.cleaning_services_outlined,
                  title: _gr ? 'Καθαρισμοί' : 'Cleaning',
                  value: _money(data['cleaning_paid']),
                  color: colors.secondary,
                ),
              ],
            );
          }),
          const SizedBox(height: 8),
          Card(
            color: colors.surfaceContainerHighest.withOpacity(.55),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _gr
                          ? 'Το κοινό ταμείο είναι εκτίμηση από τις καθαρές καταχωρημένες εισπράξεις (μετά από τυχόν προμήθεια online πληρωμής), το αρχικό υπόλοιπο και τα πληρωμένα έξοδα. Οι χρεώσεις ανά διαμέρισμα κατανέμονται με βάση τα δηλωμένα διαμερίσματα και τα τετραγωνικά.'
                          : 'The common fund is estimated from net recorded receipts (after any online payment fee), opening balance and paid expenses. Apartment amounts are apportioned using registered units and area.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.apartment_outlined),
                  title: Text(_gr ? 'Κοινόχρηστα ανά διαμέρισμα' : 'Common charges by apartment'),
                  subtitle: Text(_gr ? 'Αναλογικός επιμερισμός των καταγεγραμμένων χρεώσεων' : 'Apportioned share of recorded common charges'),
                ),
                if (apartments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_gr ? 'Δεν έχουν καταχωρηθεί διαμερίσματα.' : 'No apartments have been registered.'),
                    ),
                  )
                else
                  ...apartments.map((unit) {
                    final status = unit['status'] as String? ?? 'not_charged';
                    final ownerAssigned = unit['owner_assigned'] == true;
                    final color = _statusColor(status, colors);
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(.12),
                        foregroundColor: color,
                        child: const Icon(Icons.door_front_door_outlined),
                      ),
                      title: Text('${_gr ? 'Διαμέρισμα' : 'Apartment'} ${unit['apartment_number']}'),
                      subtitle: Text(
                        ownerAssigned
                            ? '${_gr ? 'Επιμερισμένη χρέωση' : 'Apportioned charge'}: ${_money(unit['amount_due'])} · ${_gr ? 'καταβλήθηκαν' : 'paid'} ${_money(unit['amount_paid'])} · ${_gr ? 'υπόλοιπο' : 'outstanding'} ${_money(unit['amount_outstanding'])}'
                            : (_gr ? 'Δεν έχει συνδεθεί ιδιοκτησιακός λογαριασμός.' : 'No owner account is linked.'),
                      ),
                      isThreeLine: true,
                      trailing: Container(
                        constraints: const BoxConstraints(maxWidth: 136),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                        decoration: BoxDecoration(
                          color: color.withOpacity(.1),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(_statusLabel(status), textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    );
                  }),
              ],
            ),
          ),
          if ((data['unallocated_common_charges_due'] as num? ?? 0) > 0 ||
              (data['unallocated_common_charges_paid'] as num? ?? 0) > 0 ||
              (data['unallocated_common_charges_billed'] as num? ?? 0) > 0)
            Card(
              color: colors.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.link_off_outlined),
                title: Text(_gr ? 'Χρεώσεις χωρίς ασφαλή αντιστοίχιση' : 'Charges without a verified apartment match'),
                subtitle: Text(
                  '${_gr ? 'Αντιστοίχισε όλα τα διαμερίσματα και έλεγξε τον αριθμό και τα τ.μ. που δηλώθηκαν στους ιδιοκτήτες. Μη κατανεμημένη τρέχουσα οφειλή' : 'Assign every apartment and verify each owner’s declared unit count and area. Unallocated outstanding balance'}: ${_money(data['unallocated_common_charges_due'])} · ${_gr ? 'μη αντιστοιχισμένες εισπράξεις' : 'unallocated receipts'}: ${_money(data['unallocated_common_charges_paid'])} · ${_gr ? 'μη κατανεμημένες συνολικές χρεώσεις' : 'unallocated billed total'}: ${_money(data['unallocated_common_charges_billed'])}',
                ),
                trailing: canManage
                    ? IconButton(
                        tooltip: _gr ? 'Αντιστοίχιση' : 'Assign',
                        onPressed: _manageUnitOwners,
                        icon: const Icon(Icons.manage_accounts_outlined),
                      )
                    : null,
              ),
            ),
          if ((data['other_operating_expenses_paid'] as num? ?? 0) > 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_outlined),
                title: Text(_gr ? 'Άλλα πληρωμένα έξοδα κτιρίου' : 'Other paid building expenses'),
                trailing: Text(_money(data['other_operating_expenses_paid'])),
              ),
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _overview,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(_gr ? 'Δεν φορτώθηκε η οικονομική επισκόπηση.' : 'Could not load the financial overview.'),
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: Text(_gr ? 'Δοκίμασε ξανά' : 'Try again'),
                ),
              ],
            ),
          ),
        );
      }
      return _buildOverview(snapshot.data!);
    },
  );
}
