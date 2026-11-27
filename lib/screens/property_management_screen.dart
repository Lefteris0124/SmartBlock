import 'package:flutter/material.dart' hide Text;
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';
import 'package:url_launcher/url_launcher.dart';

import '../smartblock_text.dart';

class PropertyManagementScreen extends StatefulWidget {
  const PropertyManagementScreen({
    required this.propertyId,
    required this.propertyName,
    this.totalApartments,
    this.initialSection,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final int? totalApartments;
  final String? initialSection;
  final bool isGreek;

  @override
  State<PropertyManagementScreen> createState() =>
      _PropertyManagementScreenState();
}

class _PropertyManagementScreenState extends State<PropertyManagementScreen> {
  final db = SmartBlockTrialSession.client;
  late Future<Map<String, dynamic>> data = _load();
  bool get gr => widget.isGreek;
  bool busy = false;
  bool canManage = false;
  bool _managementPolicyAccepted = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _focusKey = GlobalKey();
  bool _focusScheduled = false;
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedCalendarDay = DateUtils.dateOnly(DateTime.now());
  final TextEditingController _authorizationLimitController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAccess();
  }

  @override
  void dispose() {
    _authorizationLimitController.dispose();
    _scrollController.dispose();
    super.dispose();
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
      db
          .from('property_management_policies')
          .select()
          .eq('property_id', widget.propertyId)
          .maybeSingle(),
      db.from('property_calendar_events').select().eq('property_id', widget.propertyId).order('starts_at'),
      db.from('property_tasks').select().eq('property_id', widget.propertyId).order('due_on', nullsFirst: false),
      db.from('property_management_audit')
          .select('id,actor_display_name,action,entity_type,entity_id,details,created_at')
          .eq('property_id', widget.propertyId)
          .order('created_at', ascending: false)
          .limit(50),
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
      'management_policy': values[13] as Map<String, dynamic>?,
      'calendar_events': List<Map<String, dynamic>>.from(values[14]),
      'tasks': List<Map<String, dynamic>>.from(values[15]),
      'activity': List<Map<String, dynamic>>.from(values[16]),
    };
  }

  String _calendarDateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _calendarDateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  Future<void> _newCalendarEvent() async {
    final title = TextEditingController();
    final description = TextEditingController();
    var eventType = 'maintenance';
    var date = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 1)));
    var allDay = true;
    var time = const TimeOfDay(hour: 9, minute: 0);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Νέα εκδήλωση' : 'New calendar event'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .65),
              child: SingleChildScrollView(child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(title, gr ? 'Τίτλος' : 'Title', validator: _required),
                  _field(description, gr ? 'Σημειώσεις' : 'Notes', lines: 3),
                  DropdownButtonFormField<String>(
                    initialValue: eventType,
                    decoration: InputDecoration(labelText: gr ? 'Κατηγορία' : 'Category'),
                    items: [
                      DropdownMenuItem(value: 'inspection', child: Text(gr ? 'Έλεγχος / επιθεώρηση' : 'Inspection')),
                      DropdownMenuItem(value: 'maintenance', child: Text(gr ? 'Συντήρηση' : 'Maintenance')),
                      DropdownMenuItem(value: 'service', child: Text(gr ? 'Εργασία / υπηρεσία' : 'Work / service')),
                      DropdownMenuItem(value: 'payment_deadline', child: Text(gr ? 'Προθεσμία πληρωμής' : 'Payment deadline')),
                      DropdownMenuItem(value: 'meeting', child: Text(gr ? 'Συνάντηση' : 'Meeting')),
                      DropdownMenuItem(value: 'other', child: Text(gr ? 'Άλλο' : 'Other')),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => eventType = v); },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: Text(gr ? 'Ημερομηνία' : 'Date'),
                    subtitle: Text(_calendarDateLabel(date)),
                    onTap: () async {
                      final chosen = await showDatePicker(context: ctx, initialDate: date,
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)));
                      if (chosen != null) setDialog(() => date = DateUtils.dateOnly(chosen));
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(gr ? 'Ολοήμερο' : 'All day'),
                    value: allDay,
                    onChanged: (v) => setDialog(() => allDay = v),
                  ),
                  if (!allDay) ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(gr ? 'Ώρα έναρξης' : 'Start time'),
                    subtitle: Text(time.format(ctx)),
                    onTap: () async {
                      final chosen = await showTimePicker(context: ctx, initialTime: time);
                      if (chosen != null) setDialog(() => time = chosen);
                    },
                  ),
                ]),
              )),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(onPressed: () => _formKey.currentState!.validate() ? Navigator.pop(ctx, true) : null,
              child: Text(gr ? 'Αποθήκευση' : 'Save')),
          ],
        ),
      ),
    );
    if (saved == true) {
      final starts = DateTime(date.year, date.month, date.day, allDay ? 12 : time.hour, allDay ? 0 : time.minute);
      await _insert('property_calendar_events', {
        'title': title.text.trim(), 'description': description.text.trim(),
        'event_type': eventType, 'starts_at': starts.toUtc().toIso8601String(),
        'all_day': allDay,
      });
    }
    title.dispose();
    description.dispose();
  }

  Future<void> _newTask() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final provider = TextEditingController();
    final contact = TextEditingController();
    final requests = List<Map<String, dynamic>>.from(
      await db.from('property_service_requests').select('id,title,status')
        .eq('property_id', widget.propertyId).order('created_at', ascending: false).limit(40),
    );
    if (!mounted) return;
    DateTime? due = DateUtils.dateOnly(DateTime.now().add(const Duration(days: 7)));
    var category = 'maintenance', priority = 'normal', linkedRequest = '';
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Νέα εργασία' : 'New work task'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .68),
              child: SingleChildScrollView(child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _field(title, gr ? 'Εργασία' : 'Task', validator: _required),
                  _field(description, gr ? 'Περιγραφή / οδηγίες' : 'Description / instructions', lines: 3),
                  DropdownButtonFormField<String>(
                    initialValue: category,
                    decoration: InputDecoration(labelText: gr ? 'Κατηγορία' : 'Category'),
                    items: [
                      DropdownMenuItem(value: 'maintenance', child: Text(gr ? 'Συντήρηση' : 'Maintenance')),
                      DropdownMenuItem(value: 'repair', child: Text(gr ? 'Επισκευή' : 'Repair')),
                      DropdownMenuItem(value: 'cleaning', child: Text(gr ? 'Καθαρισμός' : 'Cleaning')),
                      DropdownMenuItem(value: 'inspection', child: Text(gr ? 'Έλεγχος' : 'Inspection')),
                      DropdownMenuItem(value: 'administration', child: Text(gr ? 'Διαχείριση' : 'Administration')),
                      DropdownMenuItem(value: 'other', child: Text(gr ? 'Άλλο' : 'Other')),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => category = v); },
                  ),
                  _field(provider, gr ? 'Ανάθεση σε συνεργείο / προμηθευτή' : 'Assign to contractor / provider'),
                  _field(contact, gr ? 'Στοιχεία επικοινωνίας (προαιρετικά)' : 'Contact details (optional)'),
                  DropdownButtonFormField<String>(
                    initialValue: priority,
                    decoration: InputDecoration(labelText: gr ? 'Προτεραιότητα' : 'Priority'),
                    items: [
                      DropdownMenuItem(value: 'low', child: Text(gr ? 'Χαμηλή' : 'Low')),
                      DropdownMenuItem(value: 'normal', child: Text(gr ? 'Κανονική' : 'Normal')),
                      DropdownMenuItem(value: 'high', child: Text(gr ? 'Υψηλή' : 'High')),
                      DropdownMenuItem(value: 'urgent', child: Text(gr ? 'Επείγουσα' : 'Urgent')),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => priority = v); },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_available_outlined),
                    title: Text(gr ? 'Προθεσμία' : 'Due date'),
                    subtitle: Text(due == null ? (gr ? 'Χωρίς προθεσμία' : 'No due date') : _calendarDateLabel(due!)),
                    trailing: IconButton(onPressed: () => setDialog(() => due = null),
                      tooltip: gr ? 'Καθαρισμός προθεσμίας' : 'Clear due date', icon: const Icon(Icons.clear)),
                    onTap: () async {
                      final chosen = await showDatePicker(context: ctx, initialDate: due ?? DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 3650)));
                      if (chosen != null) setDialog(() => due = DateUtils.dateOnly(chosen));
                    },
                  ),
                  if (requests.isNotEmpty) DropdownButtonFormField<String>(
                    initialValue: linkedRequest,
                    decoration: InputDecoration(labelText: gr ? 'Σύνδεση με αναφορά βλάβης (προαιρετικά)' : 'Link to problem report (optional)'),
                    items: [
                      DropdownMenuItem(value: '', child: Text(gr ? 'Χωρίς σύνδεση' : 'No linked report')),
                      ...requests.map((r) => DropdownMenuItem(value: r['id'] as String,
                        child: Text('${r['title']} · ${r['status']}', overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => linkedRequest = v); },
                  ),
                ]),
              )),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(onPressed: () => _formKey.currentState!.validate() ? Navigator.pop(ctx, true) : null,
              child: Text(gr ? 'Ανάθεση εργασίας' : 'Assign task')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _insert('property_tasks', {
        'title': title.text.trim(), 'description': description.text.trim(),
        'category': category, 'assigned_provider': provider.text.trim(),
        'assigned_contact': contact.text.trim(), 'due_on': due == null ? null : _calendarDateKey(due!),
        'priority': priority, 'linked_service_request_id': linkedRequest.isEmpty ? null : linkedRequest,
        'status': 'open',
      });
    }
    title.dispose(); description.dispose(); provider.dispose(); contact.dispose();
  }

  Future<void> _setTaskStatus(Map<String, dynamic> task, String status) async {
    final userId = db.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await db.from('property_tasks').update({
        'status': status, 'updated_by': userId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'completed_at': status == 'completed' ? DateTime.now().toUtc().toIso8601String() : null,
      }).eq('id', task['id']);
      await _refresh();
    } on PostgrestException catch (error) {
      _message(error.message);
    }
  }

  Widget _calendarCard(Map<String, dynamic> data) {
    final items = <_PropertyCalendarItem>[];
    void addEvent(dynamic raw, String title, String detail, IconData icon) {
      final date = DateTime.tryParse(raw as String? ?? '')?.toLocal();
      if (date != null) items.add(_PropertyCalendarItem(date: DateUtils.dateOnly(date), title: title, detail: detail, icon: icon));
    }
    for (final meeting in data['meetings'] as List<Map<String, dynamic>>) {
      if (meeting['status'] != 'cancelled') addEvent(meeting['starts_at'], meeting['title'] as String? ?? '', gr ? 'Συνέλευση · ${meeting['status']}' : 'Meeting · ${meeting['status']}', Icons.groups_outlined);
    }
    for (final event in data['calendar_events'] as List<Map<String, dynamic>>) {
      if (event['status'] != 'cancelled') addEvent(event['starts_at'], event['title'] as String? ?? '', gr ? 'Εκδήλωση · ${event['status']}' : 'Event · ${event['status']}', Icons.event_note_outlined);
    }
    for (final task in data['tasks'] as List<Map<String, dynamic>>) {
      if (task['status'] != 'cancelled' && task['due_on'] != null) addEvent(task['due_on'], task['title'] as String? ?? '', gr ? 'Εργασία · ${task['status']}' : 'Task · ${task['status']}', Icons.assignment_outlined);
    }
    final monthsEl = const ['Ιανουάριος','Φεβρουάριος','Μάρτιος','Απρίλιος','Μάιος','Ιούνιος','Ιούλιος','Αύγουστος','Σεπτέμβριος','Οκτώβριος','Νοέμβριος','Δεκέμβριος'];
    final monthsEn = const ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final offset = DateTime(_calendarMonth.year, _calendarMonth.month, 1).weekday - 1;
    final dayCount = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    final cellCount = ((offset + dayCount + 6) ~/ 7) * 7;
    final weekdays = gr ? const ['Δ','Τ','Τ','Π','Π','Σ','Κ'] : const ['M','T','W','T','F','S','S'];
    final selectedItems = items.where((e) => _calendarDateKey(e.date) == _calendarDateKey(_selectedCalendarDay)).toList();
    void shiftMonth(int amount) {
      setState(() {
        _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + amount);
        if (_selectedCalendarDay.year != _calendarMonth.year || _selectedCalendarDay.month != _calendarMonth.month) {
          _selectedCalendarDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
        }
      });
    }
    return Card(child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_month_outlined), const SizedBox(width: 8),
          Expanded(child: Text(gr ? 'Ημερολόγιο κτιρίου' : 'Building calendar', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (canManage) IconButton(tooltip: gr ? 'Νέα εκδήλωση' : 'New event', onPressed: busy ? null : _newCalendarEvent, icon: const Icon(Icons.add_circle_outline)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(onPressed: () => shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
          Text('${gr ? monthsEl[_calendarMonth.month - 1] : monthsEn[_calendarMonth.month - 1]} ${_calendarMonth.year}', style: Theme.of(context).textTheme.titleSmall),
          IconButton(onPressed: () => shiftMonth(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: weekdays.map((d) => Expanded(child: Center(child: Text(d, style: Theme.of(context).textTheme.labelSmall)))).toList()),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: cellCount,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 3, crossAxisSpacing: 3, childAspectRatio: 1.25),
          itemBuilder: (ctx, index) {
            final day = index - offset + 1;
            if (day < 1 || day > dayCount) return const SizedBox.shrink();
            final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
            final hasEvents = items.any((e) => _calendarDateKey(e.date) == _calendarDateKey(date));
            final selected = _calendarDateKey(date) == _calendarDateKey(_selectedCalendarDay);
            return InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() => _selectedCalendarDay = date),
              child: Container(
                decoration: BoxDecoration(color: selected ? Theme.of(context).colorScheme.primaryContainer : null, borderRadius: BorderRadius.circular(9)),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('$day', style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
                  const SizedBox(height: 2),
                  Container(width: 5, height: 5, decoration: BoxDecoration(color: hasEvents ? Theme.of(context).colorScheme.primary : Colors.transparent, shape: BoxShape.circle)),
                ]),
              ),
            );
          },
        ),
        const Divider(height: 20),
        Text(_calendarDateLabel(_selectedCalendarDay), style: Theme.of(context).textTheme.titleSmall),
        if (selectedItems.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(gr ? 'Δεν υπάρχουν προγραμματισμένα συμβάντα.' : 'No events scheduled.'))
        else
          ...selectedItems.map((item) => ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(item.icon), title: Text(item.title), subtitle: Text(item.detail))),
      ]),
    ));
  }

  Widget _activitySection(List<Map<String, dynamic>> rows) {
    String typeLabel(String v) => gr ? switch (v) {
      'property_calendar_events' => 'Ημερολόγιο',
      'property_tasks' => 'Εργασία',
      'property_service_requests' => 'Βλάβη / υπηρεσία',
      'property_meetings' => 'Συνέλευση',
      'property_operating_expenses' => 'Έξοδο',
      'property_management_contracts' => 'Σύμβαση',
      'property_management_contract_amendments' => 'Τροποποίηση σύμβασης',
      'property_management_services' => 'Υπηρεσία',
      'property_insurance_policies' => 'Ασφαλιστήριο',
      'property_insurance_claims' => 'Ασφαλιστική απαίτηση',
      'property_handover_records' => 'Παράδοση διαχείρισης',
      'property_charge_runs' => 'Κοινόχρηστα',
      'property_votes' => 'Ψηφοφορία',
      'property_notes' => 'Ανακοίνωση',
      _ => v.replaceAll('property_', '').replaceAll('_', ' '),
    } : v.replaceAll('property_', '').replaceAll('_', ' ');
    String actionLabel(String v) => gr ? switch (v) {
      'insert' => 'δημιουργήθηκε', 'update' => 'ενημερώθηκε', 'delete' => 'διαγράφηκε', _ => v,
    } : switch (v) {
      'insert' => 'created', 'update' => 'updated', 'delete' => 'deleted', _ => v,
    };
    return Card(clipBehavior: Clip.antiAlias, child: Column(children: [
      ListTile(leading: const Icon(Icons.history_rounded),
        title: Text(gr ? 'Ιστορικό ενεργειών' : 'Activity history', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(gr ? 'Πρόσφατες αλλαγές σε αυτό το ακίνητο' : 'Recent changes for this property')),
      if (rows.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: Align(alignment: Alignment.centerLeft, child: Text(gr ? 'Δεν υπάρχουν ακόμη καταγεγραμμένες ενέργειες.' : 'No recorded activity yet.')))
      else
        ...rows.take(20).map((row) {
          final at = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
          final stamp = at == null ? '' : '${_calendarDateLabel(at)} ${at.hour.toString().padLeft(2,'0')}:${at.minute.toString().padLeft(2,'0')}';
          final actor = row['actor_display_name'] as String? ?? (gr ? 'Χρήστης' : 'User');
          return ListTile(
            dense: true,
            leading: Icon(switch (row['action']) { 'insert' => Icons.add_task_outlined, 'delete' => Icons.delete_outline, _ => Icons.edit_note_outlined }),
            title: Text('$actor · ${actionLabel(row['action'] as String? ?? '')} · ${typeLabel(row['entity_type'] as String? ?? '')}'),
            subtitle: Text(stamp),
          );
        }),
    ]));
  }

  Future<void> _refresh() async {
    setState(() => data = _load());
    try {
      await data;
    } catch (_) {}
  }

  Future<void> _saveManagementPolicy() async {
    final limit = num.tryParse(
      _authorizationLimitController.text.trim().replaceAll(',', '.'),
    );
    if (limit == null || limit < 0 || !_managementPolicyAccepted) {
      _message(
        gr
            ? 'Βάλε έγκυρο όριο € και επιβεβαίωσε τους όρους.'
            : 'Enter a valid € limit and accept the terms.',
      );
      return;
    }
    setState(() => busy = true);
    try {
      await db.rpc(
        'save_property_management_policy',
        params: {
          'p_property_id': widget.propertyId,
          'p_authorization_limit_eur': limit,
          'p_accept': true,
        },
      );
      _managementPolicyAccepted = false;
      _message(
        gr
            ? 'Όροι και όριο εξουσιοδότησης αποθηκεύτηκαν.'
            : 'Management terms and authorization limit saved.',
      );
      await _refresh();
    } catch (error) {
      _message('${gr ? 'Δεν αποθηκεύτηκε' : 'Could not save'}: $error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _managementPolicyCard(Map<String, dynamic>? policy) {
    final savedLimit = policy?['authorization_limit_eur'];
    if (_authorizationLimitController.text.isEmpty && savedLimit != null) {
      _authorizationLimitController.text = savedLimit.toString();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              gr
                  ? 'Όροι και εξουσιοδότηση διαχείρισης'
                  : 'Management terms and authorization',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              gr
                  ? 'Ο ιδιοκτήτης εξουσιοδοτεί την ομάδα SmartBlock να συντονίζει τις επιλεγμένες υπηρεσίες και να εγκρίνει δαπάνες μέχρι το παρακάτω όριο ανά περιστατικό. Για μεγαλύτερο ποσό απαιτείται προηγούμενη έγκριση μέσα από την εφαρμογή. Οι καταχωρίσεις και αλλαγές διατηρούν αυτόματα ημερομηνία, ώρα και όνομα λογαριασμού. Η εξουσιοδότηση ισχύει μόνο για αυτό το ακίνητο και δεν αντικαθιστά ξεχωριστή σύμβαση ή ασφαλιστικούς όρους.'
                  : 'The owner authorizes the SmartBlock team to coordinate selected services and approve expenses up to the per-incident limit below. Amounts above the limit require prior in-app approval. Entries and changes are automatically recorded with date, time, and account name. This authorization applies only to this property and does not replace a separate contract or insurance terms.',
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _authorizationLimitController,
              enabled: canManage && !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: gr
                    ? 'Μέγιστο ποσό χωρίς νέα έγκριση (€)'
                    : 'Maximum amount before approval (€)',
              ),
            ),
            if (policy != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  gr
                      ? 'Τελευταία αποδοχή: ${policy['accepted_by_name']} · ${policy['accepted_at']}'
                      : 'Last accepted by ${policy['accepted_by_name']} · ${policy['accepted_at']}',
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _managementPolicyAccepted,
              onChanged: !canManage || busy
                  ? null
                  : (value) => setState(
                      () => _managementPolicyAccepted = value == true,
                    ),
              title: Text(
                gr ? 'Επιβεβαιώνω ότι έχω δικαίωμα αποδοχής για το ακίνητο.' : 'I confirm I am authorized to accept this for the property.',
              ),
            ),
            if (canManage)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: busy ? null : _saveManagementPolicy,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(gr ? 'Αποθήκευση όρων' : 'Save terms'),
                ),
              ),
          ],
        ),
      ),
    );
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
                      child: Text(
                        gr
                            ? 'Η τροποποίηση θα μείνει σε αναμονή μέχρι να εγκριθεί από εξουσιοδοτημένο διαχειριστή.'
                            : 'The amendment remains pending until an authorized manager approves it.',
                      ),
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
              child: Text(gr ? 'Καταχώριση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _insert('property_management_contract_amendments', {
        'contract_id': contractId,
        'title': title.text.trim(),
        'amendment_reference': reference.text.trim(),
        'effective_on': effective.text.trim(),
        'changes_summary': summary.text.trim(),
        'monthly_fee_new': fee.text.trim().isEmpty
            ? null
            : double.tryParse(fee.text.replaceAll(',', '.')),
        'vat_rate_new': vat.text.trim().isEmpty
            ? null
            : double.tryParse(vat.text.replaceAll(',', '.')),
      });
    }
    for (final c in [title, reference, effective, summary, fee, vat]) {
      c.dispose();
    }
  }

  Future<void> _reviewAmendment(
    Map<String, dynamic> amendment,
    String decision,
  ) async {
    try {
      await db.rpc(
        'review_property_contract_amendment',
        params: {
          'p_amendment_id': amendment['id'],
          'p_approval_status': decision,
        },
      );
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _setContractStatus(
    Map<String, dynamic> contract,
    String status,
  ) async {
    try {
      await db
          .from('property_management_contracts')
          .update({'status': status})
          .eq('id', contract['id']);
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
    }
  }

  String _serviceCategoryLabel(String? category) => gr
      ? switch (category) {
          'plumbing' => 'Υδραυλικά',
          'building_work' => 'Οικοδομικά',
          'electrical' => 'Ηλεκτρολογικά',
          'furniture_assembly' => 'Συναρμολόγηση επίπλων',
          'painting' => 'Βαψίματα',
          'cleaning' => 'Καθαρισμός',
          'safety' => 'Ασφάλεια',
          _ => 'Άλλη υπηρεσία',
        }
      : switch (category) {
          'plumbing' => 'Plumbing',
          'building_work' => 'Building work',
          'electrical' => 'Electrical',
          'furniture_assembly' => 'Furniture assembly',
          'painting' => 'Painting',
          'cleaning' => 'Cleaning',
          'safety' => 'Safety',
          _ => 'Other service',
        };

  Future<void> _newService() async {
    final title = TextEditingController(),
        desc = TextEditingController(),
        fee = TextEditingController();
    var unit = 'fixed', approved = true;
    var serviceCategory = 'cleaning';
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
                  DropdownButtonFormField<String>(
                    value: serviceCategory,
                    decoration: InputDecoration(labelText: gr ? 'Κατηγορία' : 'Category'),
                    items: const [
                      DropdownMenuItem(value: 'plumbing', child: Text('Υδραυλικά / Plumbing')),
                      DropdownMenuItem(value: 'building_work', child: Text('Οικοδομικά / Building work')),
                      DropdownMenuItem(value: 'electrical', child: Text('Ηλεκτρολογικά / Electrical')),
                      DropdownMenuItem(value: 'furniture_assembly', child: Text('Συναρμολόγηση επίπλων / Furniture assembly')),
                      DropdownMenuItem(value: 'painting', child: Text('Βαψίματα / Painting')),
                      DropdownMenuItem(value: 'cleaning', child: Text('Καθαρισμός / Cleaning')),
                      DropdownMenuItem(value: 'safety', child: Text('Ασφάλεια / Safety')),
                      DropdownMenuItem(value: 'other', child: Text('Άλλη υπηρεσία / Other')),
                    ],
                    onChanged: (value) { if (value != null) setDialog(() => serviceCategory = value); },
                  ),
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
        'service_category': serviceCategory,
        'fee_unit': unit,
        'fee_amount': double.tryParse(fee.text.replaceAll(',', '.')),
        'requires_prior_approval': approved,
      });
    title.dispose();
    desc.dispose();
    fee.dispose();
  }

  Future<void> _newServiceRequest() async {
    final services = List<Map<String, dynamic>>.from(
      await db
          .from('property_management_services')
          .select('id,title,service_category')
          .eq('property_id', widget.propertyId)
          .eq('active', true)
          .order('title'),
    );
    if (!mounted) return;
    var serviceId = '';
    var requestType = 'service';
    var serviceCategory = 'other';
    var priority = 'normal';
    var apartmentNumber = '1';
    final apartmentOptions = List<String>.generate(
      (widget.totalApartments ?? 1).clamp(1, 500),
      (index) => '${index + 1}',
    );
    final title = TextEditingController(),
        description = TextEditingController(),
        location = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Νέα αναφορά ή υπηρεσία' : 'New report or service'),
          content: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * .62,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: apartmentNumber,
                        decoration: InputDecoration(
                          labelText: gr ? 'Διαμέρισμα' : 'Apartment',
                        ),
                        items: [
                          ...apartmentOptions.map(
                            (number) => DropdownMenuItem(
                              value: number,
                              child: Text(
                                gr ? 'Διαμέρισμα $number' : 'Apartment $number',
                              ),
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'common_area',
                            child: Text(
                              gr ? 'Κοινόχρηστος χώρος' : 'Common area',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialog(() => apartmentNumber = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: requestType,
                        decoration: InputDecoration(
                          labelText: gr ? 'Τύπος αιτήματος' : 'Request type',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'service',
                            child: Text(
                              gr ? 'Επιλογή υπηρεσίας' : 'Request a service',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'damage_report',
                            child: Text(
                              gr ? 'Αναφορά βλάβης' : 'Report a problem',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'maintenance',
                            child: Text(gr ? 'Συντήρηση' : 'Maintenance'),
                          ),
                          DropdownMenuItem(
                            value: 'cleaning',
                            child: Text(gr ? 'Καθαρισμός' : 'Cleaning'),
                          ),
                          DropdownMenuItem(
                            value: 'safety',
                            child: Text(
                              gr
                                  ? 'Ασφάλεια / κοινόχρηστος χώρος'
                                  : 'Safety / common area',
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text(gr ? 'Άλλο αίτημα' : 'Other request'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null)
                            setDialog(() => requestType = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: serviceCategory,
                        decoration: InputDecoration(labelText: gr ? 'Κατηγορία υπηρεσίας / βλάβης' : 'Service / problem category'),
                        items: const [
                          DropdownMenuItem(value: 'plumbing', child: Text('Υδραυλικά / Plumbing')),
                          DropdownMenuItem(value: 'building_work', child: Text('Οικοδομικά / Building work')),
                          DropdownMenuItem(value: 'electrical', child: Text('Ηλεκτρολογικά / Electrical')),
                          DropdownMenuItem(value: 'furniture_assembly', child: Text('Συναρμολόγηση επίπλων / Furniture assembly')),
                          DropdownMenuItem(value: 'painting', child: Text('Βαψίματα / Painting')),
                          DropdownMenuItem(value: 'cleaning', child: Text('Καθαρισμός / Cleaning')),
                          DropdownMenuItem(value: 'safety', child: Text('Ασφάλεια / Safety')),
                          DropdownMenuItem(value: 'other', child: Text('Άλλο / Other')),
                        ],
                        onChanged: (value) { if (value != null) setDialog(() => serviceCategory = value); },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: serviceCategory,
                        decoration: InputDecoration(labelText: gr ? 'Κατηγορία υπηρεσίας / βλάβης' : 'Service / problem category'),
                        items: const [
                          DropdownMenuItem(value: 'plumbing', child: Text('Υδραυλικά / Plumbing')),
                          DropdownMenuItem(value: 'building_work', child: Text('Οικοδομικά / Building work')),
                          DropdownMenuItem(value: 'electrical', child: Text('Ηλεκτρολογικά / Electrical')),
                          DropdownMenuItem(value: 'furniture_assembly', child: Text('Συναρμολόγηση επίπλων / Furniture assembly')),
                          DropdownMenuItem(value: 'painting', child: Text('Βαψίματα / Painting')),
                          DropdownMenuItem(value: 'cleaning', child: Text('Καθαρισμός / Cleaning')),
                          DropdownMenuItem(value: 'safety', child: Text('Ασφάλεια / Safety')),
                          DropdownMenuItem(value: 'other', child: Text('Άλλο / Other')),
                        ],
                        onChanged: (value) { if (value != null) setDialog(() => serviceCategory = value); },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: priority,
                        decoration: InputDecoration(
                          labelText: gr ? 'Προτεραιότητα' : 'Priority',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'normal',
                            child: Text(gr ? 'Κανονική' : 'Normal'),
                          ),
                          DropdownMenuItem(
                            value: 'urgent',
                            child: Text(gr ? 'Επείγουσα' : 'Urgent'),
                          ),
                          DropdownMenuItem(
                            value: 'emergency',
                            child: Text(
                              gr ? 'Άμεσος κίνδυνος' : 'Immediate danger',
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value != null) setDialog(() => priority = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      if (services.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: serviceId,
                          decoration: InputDecoration(
                            labelText: gr
                                ? 'Υπηρεσία καταλόγου (προαιρετικά)'
                                : 'Catalogue service (optional)',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                gr ? 'Άλλη υπηρεσία' : 'Other service',
                              ),
                            ),
                            ...services.map(
                              (service) => DropdownMenuItem(
                                value: service['id'] as String,
                                child: Text(service['title'] as String),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialog(() {
                              serviceId = value;
                              if (value.isNotEmpty) {
                                serviceCategory = services.firstWhere((service) => service['id'] == value)['service_category'] as String? ?? serviceCategory;
                                serviceCategory =
                                    services.firstWhere((service) => service['id'] == value)['service_category'] as String? ?? serviceCategory;
                                title.text =
                                    services.firstWhere(
                                          (service) => service['id'] == value,
                                        )['title']
                                        as String;
                              }
                            });
                          },
                        ),
                      _field(
                        location,
                        gr
                            ? 'Τοποθεσία (π.χ. διαμέρισμα ή είσοδος)'
                            : 'Location (e.g. apartment or entrance)',
                      ),
                      _field(
                        title,
                        gr
                            ? 'Σύντομος τίτλος (π.χ. διαρροή νερού)'
                            : 'Short title (e.g. water leak)',
                        validator: _required,
                      ),
                      _field(
                        description,
                        gr
                            ? 'Περιγραφή / λεπτομέρειες'
                            : 'Description / details',
                        lines: 4,
                        validator: _required,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          gr
                              ? 'Το αίτημα θα λάβει προσφορά και θα χρειαστεί έγκριση πριν ξεκινήσει η εργασία.'
                              : 'The request will receive a quote and require approval before work starts.',
                        ),
                      ),
                    ],
                  ),
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
              child: Text(gr ? 'Υποβολή αναφοράς' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _insert('property_service_requests', {
        'service_id': serviceId.isEmpty ? null : serviceId,
        'apartment_number': apartmentNumber,
        'request_type': requestType,
        'service_category': serviceCategory,
        'priority': priority,
        'location': location.text.trim(),
        'title': title.text.trim(),
        'description': description.text.trim(),
      });
    }
    title.dispose();
    description.dispose();
    location.dispose();
  }

  Future<void> _newResident() async {
    final email = TextEditingController();
    final total = (widget.totalApartments ?? 1).clamp(1, 500);
    var apartmentNumber = '1';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Προσθήκη ενοίκου' : 'Add a resident'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: gr
                        ? 'Email λογαριασμού SmartBlock'
                        : 'SmartBlock account email',
                    helperText: gr
                        ? 'Ο ένοικος πρέπει πρώτα να δημιουργήσει λογαριασμό.'
                        : 'The tenant must create a SmartBlock account first.',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: apartmentNumber,
                  decoration: InputDecoration(
                    labelText: gr ? 'Διαμέρισμα' : 'Apartment',
                  ),
                  items: List<DropdownMenuItem<String>>.generate(
                    total,
                    (index) => DropdownMenuItem(
                      value: '${index + 1}',
                      child: Text(
                        gr
                            ? 'Διαμέρισμα ${index + 1}'
                            : 'Apartment ${index + 1}',
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    if (value != null) {
                      setDialog(() => apartmentNumber = value);
                    }
                  },
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
                  email.text.trim().isEmpty ? null : Navigator.pop(ctx, true),
              child: Text(gr ? 'Προσθήκη' : 'Add resident'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await db.rpc(
          'assign_property_resident',
          params: {
            'p_property_id': widget.propertyId,
            'p_resident_email': email.text.trim(),
            'p_apartment_number': apartmentNumber,
          },
        );
        _message(
          gr
              ? 'Ο ένοικος συνδέθηκε με το διαμέρισμα $apartmentNumber.'
              : 'Resident linked to apartment $apartmentNumber.',
        );
        await _refresh();
      } on PostgrestException catch (error) {
        _message(error.message);
      }
    }
    email.dispose();
  }

  Future<void> _deactivateResident(Map<String, dynamic> resident) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          gr ? 'Αφαίρεση πρόσβασης ενοίκου;' : 'Remove resident access?',
        ),
        content: Text(
          gr
              ? 'Ο λογαριασμός δεν θα μπορεί πλέον να στέλνει αναφορές για αυτό το διαμέρισμα.'
              : 'This account will no longer be able to submit reports for this apartment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(gr ? 'Άκυρο' : 'Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(gr ? 'Αφαίρεση' : 'Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await db.rpc(
        'deactivate_property_resident',
        params: {'p_resident_id': resident['id']},
      );
      await _refresh();
    } on PostgrestException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _quoteServiceRequest(Map<String, dynamic> request) async {
    final amount = TextEditingController(),
        supplier = TextEditingController(),
        notes = TextEditingController();
    final ok = await _formDialog(gr ? 'Καταχώριση προσφοράς' : 'Add a quote', [
      _field(
        amount,
        gr ? 'Ποσό προσφοράς (€)' : 'Quote amount (€)',
        validator: _required,
        keyboard: const TextInputType.numberWithOptions(decimal: true),
      ),
      _field(supplier, gr ? 'Προμηθευτής' : 'Supplier'),
      _field(
        notes,
        gr ? 'Όροι / σημειώσεις προσφοράς' : 'Quote terms / notes',
        lines: 3,
      ),
    ]);
    if (ok) {
      await _transitionServiceRequest(
        request,
        'quoted',
        quoteAmount: double.tryParse(amount.text.replaceAll(',', '.')),
        supplier: supplier.text.trim(),
        quoteNotes: notes.text.trim(),
      );
    }
    amount.dispose();
    supplier.dispose();
    notes.dispose();
  }

  Future<void> _transitionServiceRequest(
    Map<String, dynamic> request,
    String nextStatus, {
    double? quoteAmount,
    String? supplier,
    String? quoteNotes,
    bool confirmBelowReserve = false,
  }) async {
    try {
      var result = await db.rpc(
        'transition_property_service_request',
        params: {
          'p_request_id': request['id'],
          'p_next_status': nextStatus,
          'p_quote_amount': quoteAmount,
          'p_quote_notes': quoteNotes,
          'p_supplier': supplier,
          'p_confirm_below_reserve': confirmBelowReserve,
        },
      );
      if (result is Map && result['needs_confirmation'] == true) {
        if (!mounted) return;
        final projected =
            (result['projected_balance'] as num?)?.toDouble() ?? 0;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(gr ? 'Κάτω από το αποθεματικό' : 'Below reserve'),
            content: Text(
              gr
                  ? 'Η έγκριση της προσφοράς θα αφήσει εκτιμώμενο υπόλοιπο ${_money(projected)}. Να εγκριθεί παρ’ όλα αυτά;'
                  : 'Approving this quote would leave estimated funds of ${_money(projected)}. Approve it anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(gr ? 'Άκυρο' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(gr ? 'Έγκριση' : 'Approve'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        result = await db.rpc(
          'transition_property_service_request',
          params: {
            'p_request_id': request['id'],
            'p_next_status': nextStatus,
            'p_quote_amount': quoteAmount,
            'p_quote_notes': quoteNotes,
            'p_supplier': supplier,
            'p_confirm_below_reserve': true,
          },
        );
      }
      if (result is Map && result['updated'] != true) {
        _message(
          gr ? 'Δεν έγινε η αλλαγή κατάστασης.' : 'The status was not changed.',
        );
        return;
      }
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _newExpense() async {
    final desc = TextEditingController(),
        amount = TextEditingController(),
        supplier = TextEditingController(),
        date = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10),
        ),
        notes = TextEditingController();
    var category = 'other';
    final ok = await _formDialog(gr ? 'Νέο έξοδο' : 'New expense', [
      _field(desc, gr ? 'Περιγραφή' : 'Description', validator: _required),
      DropdownButtonFormField<String>(
        value: category,
        decoration: InputDecoration(
          labelText: gr ? 'Κατηγορία εξόδου' : 'Expense category',
        ),
        items: [
          DropdownMenuItem(
            value: 'damage_repair',
            child: Text(gr ? 'Βλάβη / επισκευή' : 'Damage / repair'),
          ),
          DropdownMenuItem(
            value: 'maintenance',
            child: Text(gr ? 'Συντήρηση' : 'Maintenance'),
          ),
          DropdownMenuItem(
            value: 'water_bill',
            child: Text(gr ? 'Λογαριασμός νερού' : 'Water bill'),
          ),
          DropdownMenuItem(
            value: 'electricity_bill',
            child: Text(gr ? 'Λογαριασμός ρεύματος' : 'Electricity bill'),
          ),
          DropdownMenuItem(
            value: 'elevator_maintenance',
            child: Text(gr ? 'Συντήρηση ανελκυστήρα' : 'Elevator maintenance'),
          ),
          DropdownMenuItem(
            value: 'cleaning',
            child: Text(gr ? 'Καθαρισμός' : 'Cleaning'),
          ),
          DropdownMenuItem(
            value: 'other',
            child: Text(gr ? 'Άλλο έξοδο' : 'Other expense'),
          ),
        ],
        onChanged: (value) {
          if (value != null) category = value;
        },
      ),
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
        'category': category,
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

  Future<void> _newInsuranceClaim() async {
    final policies = List<Map<String, dynamic>>.from(
      await db
          .from('property_insurance_policies')
          .select('id,insurer,policy_number')
          .eq('property_id', widget.propertyId)
          .order('expires_on'),
    );
    if (!mounted) return;
    if (policies.isEmpty) {
      _message(
        gr
            ? 'Καταχώρισε πρώτα ένα ασφαλιστήριο.'
            : 'Add an insurance policy first.',
      );
      return;
    }
    var policyId = policies.first['id'] as String;
    final reference = TextEditingController(),
        incidentDate = TextEditingController(
          text: DateTime.now().toIso8601String().substring(0, 10),
        ),
        description = TextEditingController(),
        amount = TextEditingController(),
        notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(gr ? 'Νέα ασφαλιστική απαίτηση' : 'New insurance claim'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: policyId,
                      decoration: InputDecoration(
                        labelText: gr ? 'Ασφαλιστήριο' : 'Insurance policy',
                      ),
                      items: policies
                          .map(
                            (policy) => DropdownMenuItem(
                              value: policy['id'] as String,
                              child: Text(
                                '${policy['insurer']} · ${policy['policy_number']}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setDialog(() => policyId = value);
                      },
                    ),
                    _field(
                      reference,
                      gr ? 'Αριθμός απαίτησης' : 'Claim reference',
                    ),
                    _field(
                      incidentDate,
                      gr
                          ? 'Ημερομηνία περιστατικού (YYYY-MM-DD)'
                          : 'Incident date (YYYY-MM-DD)',
                      validator: _dateValidator,
                    ),
                    _field(
                      description,
                      gr ? 'Περιγραφή περιστατικού' : 'Incident description',
                      validator: _required,
                      lines: 4,
                    ),
                    _field(
                      amount,
                      gr ? 'Αιτούμενο ποσό (€)' : 'Claimed amount (€)',
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    _field(notes, gr ? 'Σημειώσεις' : 'Notes', lines: 2),
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
              child: Text(gr ? 'Καταχώριση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _insert('property_insurance_claims', {
        'policy_id': policyId,
        'claim_reference': reference.text.trim(),
        'incident_date': incidentDate.text.trim(),
        'description': description.text.trim(),
        'claimed_amount': amount.text.trim().isEmpty
            ? null
            : double.tryParse(amount.text.replaceAll(',', '.')),
        'notes': notes.text.trim(),
      });
    }
    for (final c in [reference, incidentDate, description, amount, notes]) {
      c.dispose();
    }
  }

  Future<void> _reviewInsuranceClaim(
    Map<String, dynamic> claim,
    String status,
  ) async {
    double? approvedAmount;
    if (status == 'accepted') {
      final amount = TextEditingController(
        text: '${claim['claimed_amount'] ?? ''}',
      );
      final ok = await _formDialog(gr ? 'Έγκριση απαίτησης' : 'Approve claim', [
        _field(
          amount,
          gr ? 'Εγκεκριμένο ποσό (€)' : 'Approved amount (€)',
          validator: _required,
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
      ]);
      if (!ok) {
        amount.dispose();
        return;
      }
      approvedAmount = double.tryParse(amount.text.replaceAll(',', '.'));
      amount.dispose();
    }
    try {
      await db
          .from('property_insurance_claims')
          .update({
            'status': status,
            if (status == 'accepted') 'approved_amount': approvedAmount,
          })
          .eq('id', claim['id']);
      await _refresh();
    } on PostgrestException catch (e) {
      _message(e.message);
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

  Future<void> _newArrearsAction({
    String? defaultOwnerId,
    String? chargeEntryId,
  }) async {
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
    var ownerId = owners.any((o) => o['id'] == defaultOwnerId)
            ? defaultOwnerId!
            : owners.first['id'] as String,
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
        'charge_entry_id': chargeEntryId,
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
      if (status == 'paid') {
        var result = await db.rpc(
          'mark_property_expense_paid',
          params: {
            'p_expense_id': expense['id'],
            'p_confirm_below_reserve': false,
          },
        );
        if (result is Map && result['needs_confirmation'] == true) {
          if (!mounted) return;
          final projected = (result['projected_balance'] as num?)?.toDouble();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(gr ? 'Κάτω από το αποθεματικό' : 'Below reserve'),
              content: Text(
                gr
                    ? 'Η πληρωμή θα αφήσει εκτιμώμενο υπόλοιπο ${_money(projected ?? 0)}, κάτω από το ελάχιστο αποθεματικό. Να εγκριθεί η πληρωμή;'
                    : 'This payment would leave an estimated balance of ${_money(projected ?? 0)}, below the minimum reserve. Approve the payment?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(gr ? 'Άκυρο' : 'Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(gr ? 'Έγκριση πληρωμής' : 'Approve payment'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          result = await db.rpc(
            'mark_property_expense_paid',
            params: {
              'p_expense_id': expense['id'],
              'p_confirm_below_reserve': true,
            },
          );
        }
        if (result is Map && result['paid'] != true) {
          _message(
            gr
                ? 'Δεν έγινε η πληρωμή. Ανανεώστε τα στοιχεία και δοκιμάστε ξανά.'
                : 'Payment was not recorded. Refresh and try again.',
          );
          return;
        }
        await _refresh();
        return;
      }
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

  double _entryOutstanding(Map<String, dynamic> row) {
    final due = (row['amount_due'] as num?)?.toDouble() ?? 0;
    final paid = (row['amount_paid'] as num?)?.toDouble() ?? 0;
    final remainder = due - paid;
    return remainder > 0 ? remainder : 0;
  }

  Widget _overdueSection(List<Map<String, dynamic>> rows) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        ListTile(
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text(
            gr ? 'Ληξιπρόθεσμα κοινόχρηστα' : 'Overdue common charges',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                gr
                    ? 'Δεν υπάρχουν ληξιπρόθεσμες χρεώσεις.'
                    : 'No overdue charges.',
              ),
            ),
          ),
        ...rows.map((row) {
          final run =
              row['property_charge_runs'] as Map<String, dynamic>? ?? {};
          final owner = row['property_owners'] as Map<String, dynamic>? ?? {};
          final organization =
              owner['organizations'] as Map<String, dynamic>? ?? {};
          final dueDate = run['due_date'] as String? ?? '';
          final title =
              organization['display_name'] as String? ??
              (gr ? 'Ιδιοκτήτης' : 'Owner');
          return ListTile(
            dense: true,
            title: Text('$title · ${_money(_entryOutstanding(row))}'),
            subtitle: Text(
              '${run['period_label'] ?? run['description'] ?? ''} · ${gr ? 'Έληξε' : 'Due'} $dueDate',
            ),
            trailing: canManage
                ? IconButton(
                    tooltip: gr ? 'Καταγραφή επικοινωνίας' : 'Log follow-up',
                    icon: const Icon(Icons.mark_email_unread_outlined),
                    onPressed: () => _newArrearsAction(
                      defaultOwnerId: row['property_owner_id'] as String?,
                      chargeEntryId: row['id'] as String?,
                    ),
                  )
                : null,
          );
        }),
      ],
    ),
  );

  Widget? _sectionStatusAction(Map<String, dynamic> row, String type) {
    if (!canManage) return null;
    if (type == 'expense' && row['status'] != 'paid') {
      return PopupMenuButton<String>(
        onSelected: (value) => _setExpenseStatus(row, value),
        itemBuilder: (_) => [
          if (row['status'] == 'awaiting_approval')
            PopupMenuItem(
              value: 'approved',
              child: Text(gr ? 'Έγκριση' : 'Approve'),
            ),
          if (row['status'] == 'approved')
            PopupMenuItem(
              value: 'paid',
              child: Text(gr ? 'Σήμανση ως πληρωμένο' : 'Mark paid'),
            ),
          PopupMenuItem(
            value: 'rejected',
            child: Text(gr ? 'Απόρριψη' : 'Reject'),
          ),
        ],
      );
    }
    if (type == 'handover' && row['status'] == 'awaiting_acceptance') {
      return IconButton(
        tooltip: gr ? 'Αποδοχή παράδοσης' : 'Accept handover',
        onPressed: () => _acceptHandover(row),
        icon: const Icon(Icons.task_alt),
      );
    }
    if (type == 'contract' && ['active', 'draft'].contains(row['status'])) {
      return PopupMenuButton<String>(
        onSelected: (value) => _setContractStatus(row, value),
        itemBuilder: (_) => [
          if (row['status'] == 'draft')
            PopupMenuItem(
              value: 'active',
              child: Text(gr ? 'Ενεργοποίηση' : 'Activate'),
            ),
          if (row['status'] == 'active') ...[
            PopupMenuItem(
              value: 'terminated',
              child: Text(gr ? 'Τερματισμός' : 'Terminate'),
            ),
            PopupMenuItem(
              value: 'expired',
              child: Text(gr ? 'Λήξη σύμβασης' : 'Mark expired'),
            ),
          ],
        ],
      );
    }
    if (type == 'contract_amendment' && row['approval_status'] == 'pending') {
      return PopupMenuButton<String>(
        onSelected: (value) => _reviewAmendment(row, value),
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'approved',
            child: Text(gr ? 'Έγκριση' : 'Approve'),
          ),
          PopupMenuItem(
            value: 'rejected',
            child: Text(gr ? 'Απόρριψη' : 'Reject'),
          ),
        ],
      );
    }
    if (type == 'resident') {
      return IconButton(
        tooltip: gr ? 'Αφαίρεση πρόσβασης' : 'Remove access',
        onPressed: busy ? null : () => _deactivateResident(row),
        icon: const Icon(Icons.person_remove_outlined),
      );
    }
    if (type == 'task') {
      final status = row['status'] as String? ?? 'open';
      if (status == 'cancelled') return null;
      return PopupMenuButton<String>(
        tooltip: gr ? 'Αλλαγή κατάστασης εργασίας' : 'Change task status',
        onSelected: (value) => _setTaskStatus(row, value),
        itemBuilder: (_) => [
          if (status != 'open') PopupMenuItem(value: 'open', child: Text(gr ? 'Ανοιχτή' : 'Open')),
          if (status != 'in_progress') PopupMenuItem(value: 'in_progress', child: Text(gr ? 'Σε εξέλιξη' : 'In progress')),
          if (status != 'blocked') PopupMenuItem(value: 'blocked', child: Text(gr ? 'Σε αναμονή' : 'Blocked')),
          if (status != 'completed') PopupMenuItem(value: 'completed', child: Text(gr ? 'Ολοκληρώθηκε' : 'Completed')),
          PopupMenuItem(value: 'cancelled', child: Text(gr ? 'Ακύρωση' : 'Cancel task')),
        ],
      );
    }
    if (type == 'service_request') return _serviceRequestAction(row);
    if (type == 'claim') return _insuranceClaimAction(row);
    return null;
  }

  Widget _section(
    String title,
    IconData icon,
    List<Map<String, dynamic>> rows,
    VoidCallback add,
    String type, {
    bool allowMemberRequests = false,
  }) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: canManage || allowMemberRequests
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
            titleText = '${_serviceCategoryLabel(row['service_category'] as String?)} · ${row['title'] as String? ?? ''}';
            subtitle =
                '${row['fee_amount'] == null ? (gr ? 'Απαιτείται προσφορά' : 'Quote required') : _money((row['fee_amount'] as num))} · ${row['fee_unit']} · ${row['requires_prior_approval'] == true ? (gr ? 'με έγκριση' : 'approval required') : ''}';
          } else if (type == 'task') {
            final provider = (row['assigned_provider'] as String? ?? '').trim();
            final due = row['due_on'] as String?;
            final status = row['status'] as String? ?? '';
            final priority = row['priority'] as String? ?? 'normal';
            titleText = row['title'] as String? ?? '';
            subtitle = '${provider.isEmpty ? (gr ? 'Χωρίς ανάθεση' : 'Unassigned') : provider} · ${due ?? (gr ? 'Χωρίς προθεσμία' : 'No due date')} · ${gr ? switch (status) { 'open' => 'Ανοιχτή', 'in_progress' => 'Σε εξέλιξη', 'blocked' => 'Σε αναμονή', 'completed' => 'Ολοκληρώθηκε', 'cancelled' => 'Ακυρώθηκε', _ => status } : status} · ${gr ? switch (priority) { 'low' => 'Χαμηλή', 'high' => 'Υψηλή', 'urgent' => 'Επείγουσα', _ => 'Κανονική' } : priority}${(row['description'] as String? ?? '').isEmpty ? '' : ' · ${row['description']}'}';
          } else if (type == 'resident') {
            titleText = row['resident_email'] as String? ?? '';
            final apartment = row['apartment_number'] as String? ?? '';
            subtitle = gr ? 'Διαμέρισμα $apartment' : 'Apartment $apartment';
          } else if (type == 'expense') {
            final category = switch (row['category'] as String? ?? 'other') {
              'damage_repair' => gr ? 'Βλάβη / επισκευή' : 'Damage / repair',
              'maintenance' => gr ? 'Συντήρηση' : 'Maintenance',
              'water_bill' => gr ? 'Νερό' : 'Water',
              'electricity_bill' => gr ? 'Ρεύμα' : 'Electricity',
              'elevator_maintenance' => gr ? 'Συντήρηση ανελκυστήρα' : 'Elevator maintenance',
              'cleaning' => gr ? 'Καθαρισμός' : 'Cleaning',
              _ => gr ? 'Άλλο έξοδο' : 'Other expense',
            };
            titleText =
                '$category · ${row['description']} · ${_money(row['amount'] as num)}';
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
                '$typeLabel · ${_serviceCategoryLabel(row['service_category'] as String?)} · ${row['title']}${serviceTitle == null ? '' : ' · $serviceTitle'}';
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
    if (widget.initialSection != null && !_focusScheduled) {
      _focusScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = _focusKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 350),
            alignment: .08,
          );
        }
      });
    }
    final entries = d['charge_entries'] as List<Map<String, dynamic>>;
    final expenses = d['expenses'] as List<Map<String, dynamic>>;
    final serviceRequests = d['service_requests'] as List<Map<String, dynamic>>;
    final tasks = d['tasks'] as List<Map<String, dynamic>>;
    final activity = d['activity'] as List<Map<String, dynamic>>;
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
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.propertyName,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          _managementPolicyCard(
            d['management_policy'] as Map<String, dynamic>?,
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
          _calendarCard(d),
          _section(gr ? 'Εργασίες και αναθέσεις' : 'Tasks and assignments', Icons.assignment_outlined, tasks, _newTask, 'task'),
          _activitySection(activity),
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
          if (widget.initialSection == 'service_request')
            Container(
              key: _focusKey,
              child: _section(
                gr
                    ? 'Υπηρεσίες και αναφορές βλαβών'
                    : 'Services and problem reports',
                Icons.handyman_outlined,
                serviceRequests,
                _newServiceRequest,
                'service_request',
                allowMemberRequests: true,
              ),
            )
          else
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
          if (widget.initialSection == 'meeting')
            Container(
              key: _focusKey,
              child: _section(
                gr ? 'Συνελεύσεις και πρακτικά' : 'Meetings and minutes',
                Icons.groups_outlined,
                d['meetings'],
                _newMeeting,
                'meeting',
              ),
            )
          else
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

class _PropertyCalendarItem {
  const _PropertyCalendarItem({required this.date, required this.title, required this.detail, required this.icon});
  final DateTime date;
  final String title;
  final String detail;
  final IconData icon;
}
