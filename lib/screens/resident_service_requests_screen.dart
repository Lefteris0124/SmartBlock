import 'package:flutter/material.dart' hide Text;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';
import '../smartblock_text.dart';

class ResidentServiceRequestsScreen extends StatefulWidget {
  const ResidentServiceRequestsScreen({
    required this.propertyId,
    required this.propertyName,
    required this.apartmentNumber,
    required this.isGreek,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final String apartmentNumber;
  final bool isGreek;

  @override
  State<ResidentServiceRequestsScreen> createState() =>
      _ResidentServiceRequestsScreenState();
}

class _ResidentServiceRequestsScreenState
    extends State<ResidentServiceRequestsScreen> {
  final SupabaseClient db = SmartBlockTrialSession.client;
  late Future<List<Map<String, dynamic>>> _requests = _loadRequests();
  late Future<List<Map<String, dynamic>>> _services = _loadServices();
  final _formKey = GlobalKey<FormState>();
  bool busy = false;
  bool get gr => widget.isGreek;

  Future<List<Map<String, dynamic>>> _loadRequests() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('property_service_requests')
            .select(
              'id,request_type,service_category,priority,apartment_number,title,description,status,quote_amount,supplier,created_at',
            )
            .eq('property_id', widget.propertyId)
            .order('created_at', ascending: false),
      );

  Future<List<Map<String, dynamic>>> _loadServices() async =>
      List<Map<String, dynamic>>.from(
        await db.rpc(
          'list_resident_services_with_categories',
          params: {'p_property_id': widget.propertyId},
        ),
      );

  Future<void> _refresh() async {
    final requests = _loadRequests();
    setState(() => _requests = requests);
    try {
      await requests;
    } catch (_) {}
  }

  String _typeLabel(String? type) => gr
      ? switch (type) {
          'damage_report' => 'Αναφορά βλάβης',
          'maintenance' => 'Συντήρηση',
          'cleaning' => 'Καθαρισμός',
          'safety' => 'Ασφάλεια',
          'other' => 'Άλλη υπηρεσία',
          _ => 'Υπηρεσία',
        }
      : switch (type) {
          'damage_report' => 'Problem report',
          'maintenance' => 'Maintenance',
          'cleaning' => 'Cleaning',
          'safety' => 'Safety',
          'other' => 'Other service',
          _ => 'Service',
        };

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

  IconData _serviceCategoryIcon(String? category) => switch (category) {
        'plumbing' => Icons.plumbing_outlined,
        'building_work' => Icons.construction_outlined,
        'electrical' => Icons.electrical_services_outlined,
        'furniture_assembly' => Icons.chair_outlined,
        'painting' => Icons.format_paint_outlined,
        'cleaning' => Icons.cleaning_services_outlined,
        'safety' => Icons.health_and_safety_outlined,
        _ => Icons.miscellaneous_services_outlined,
      };

  String _serviceCategoryDescription(String? category) => gr
      ? switch (category) {
          'plumbing' => 'Διαρροές, βρύσες και σωληνώσεις',
          'building_work' => 'Ρωγμές, σοβάδες και οικοδομικές εργασίες',
          'electrical' => 'Φωτισμός, διακόπτες και ηλεκτρικός πίνακας',
          'furniture_assembly' => 'Συναρμολόγηση ή τοποθέτηση επίπλων',
          'painting' => 'Βάψιμο τοίχων και επιφανειών',
          'cleaning' => 'Καθαρισμός διαμερίσματος ή κοινόχρηστων',
          'safety' => 'Κίνδυνος ή θέμα ασφάλειας',
          _ => 'Περιέγραψε το αίτημα στις λεπτομέρειες',
        }
      : switch (category) {
          'plumbing' => 'Leaks, taps and pipes',
          'building_work' => 'Cracks, plaster and building work',
          'electrical' => 'Lighting, switches and electrical panel',
          'furniture_assembly' => 'Furniture assembly or installation',
          'painting' => 'Painting walls and surfaces',
          'cleaning' => 'Apartment or shared-area cleaning',
          'safety' => 'Safety concern or hazard',
          _ => 'Describe your request in the details',
        };

  Widget _serviceCategoryCard(
    String category,
    bool selected,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: selected ? colors.secondaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    child: Icon(_serviceCategoryIcon(category)),
                  ),
                  const Spacer(),
                  Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? colors.primary : colors.outline,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _serviceCategoryLabel(category),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  _serviceCategoryDescription(category),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _priorityLabel(String? priority) => gr
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

  String _statusLabel(String? status) => gr
      ? switch (status) {
          'requested' => 'Νέο',
          'quoted' => 'Με προσφορά',
          'approved' => 'Εγκρίθηκε',
          'rejected' => 'Δεν εγκρίθηκε',
          'in_progress' => 'Σε εξέλιξη',
          'completed' => 'Ολοκληρώθηκε',
          _ => status ?? '',
        }
      : (status ?? '').replaceAll('_', ' ');

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? (gr ? 'Συμπλήρωσε αυτό το πεδίο.' : 'This field is required.')
      : null;

  Future<void> _newReport() async {
    final services = await _services;
    if (!mounted) return;

    var requestType = 'damage_report';
    var issueScope = 'unit';
    var priority = 'normal';
    var serviceId = '';
    var serviceCategory = 'plumbing';
    var apartmentNumber = widget.apartmentNumber;
    final title = TextEditingController();
    final description = TextEditingController();
    final location = TextEditingController();

    try {
      final submitted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialog) => AlertDialog(
            title: Text(gr ? 'Νέα αναφορά' : 'New report'),
            content: SizedBox(
              width: 440,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * .62,
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (requestType == 'damage_report') ...[
                          Card(
                            child: Column(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.apartment_outlined),
                                  title: Text(gr ? 'Πού βρίσκεται η βλάβη;' : 'Where is the problem?'),
                                  subtitle: Text(gr ? 'Επίλεξε πολυκατοικία ή διαμέρισμα.' : 'Choose building or apartment.'),
                                ),
                                ListTile(
                                  selected: issueScope == 'building',
                                  leading: const CircleAvatar(child: Icon(Icons.domain_outlined)),
                                  title: Text(gr ? 'Πολυκατοικία / κοινόχρηστος χώρος' : 'Building / shared area'),
                                  trailing: Icon(issueScope == 'building' ? Icons.check_circle : Icons.chevron_right),
                                  onTap: () => setDialog(() {
                                    issueScope = 'building';
                                    apartmentNumber = 'common_area';
                                  }),
                                ),
                                ListTile(
                                  selected: issueScope == 'unit',
                                  leading: const CircleAvatar(child: Icon(Icons.home_outlined)),
                                  title: Text(gr ? 'Διαμέρισμα' : 'Apartment'),
                                  subtitle: Text(gr ? 'Διαμέρισμα ${widget.apartmentNumber}' : 'Apartment ${widget.apartmentNumber}'),
                                  trailing: Icon(issueScope == 'unit' ? Icons.check_circle : Icons.chevron_right),
                                  onTap: () => setDialog(() {
                                    issueScope = 'unit';
                                    apartmentNumber = widget.apartmentNumber;
                                  }),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (requestType != 'damage_report')
                        DropdownButtonFormField<String>(
                          initialValue: apartmentNumber,
                          decoration: InputDecoration(
                            labelText: gr ? 'Διαμέρισμα' : 'Apartment',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: widget.apartmentNumber,
                              child: Text(
                                gr
                                    ? 'Διαμέρισμα ${widget.apartmentNumber}'
                                    : 'Apartment ${widget.apartmentNumber}',
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
                          initialValue: requestType,
                          decoration: InputDecoration(
                            labelText: gr ? 'Τύπος αιτήματος' : 'Request type',
                          ),
                          items: [
                            DropdownMenuItem(
                              value: 'damage_report',
                              child: Text(
                                gr ? 'Αναφορά βλάβης' : 'Report a problem',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'service',
                              child: Text(gr ? 'Υπηρεσία' : 'Service'),
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
                              child: Text(gr ? 'Ασφάλεια' : 'Safety'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text(gr ? 'Άλλο' : 'Other'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setDialog(() => requestType = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.category_outlined),
                              title: Text(gr ? 'Κατηγορία αναφοράς' : 'Report category'),
                              subtitle: Text(gr ? 'Πάτησε την κάρτα που ταιριάζει.' : 'Tap the card that fits best.'),
                            ),
                            GridView.count(
                              crossAxisCount: 2,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 8,
                              mainAxisSpacing: 8,
                              childAspectRatio: 1.08,
                              children: [
                                for (final category in const [
                                  'plumbing',
                                  'building_work',
                                  'electrical',
                                  'furniture_assembly',
                                  'painting',
                                  'cleaning',
                                  'safety',
                                  'other',
                                ])
                                  _serviceCategoryCard(
                                    category,
                                    serviceCategory == category,
                                    () => setDialog(() => serviceCategory = category),
                                  ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: priority,
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
                            if (value != null)
                              setDialog(() => priority = value);
                          },
                        ),
                        if (services.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: serviceId,
                            decoration: InputDecoration(
                              labelText: gr
                                  ? 'Επιλογή υπηρεσίας (προαιρετικά)'
                                  : 'Select a service (optional)',
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(gr ? 'Χωρίς επιλογή' : 'None'),
                              ),
                              ...services.map(
                                (service) => DropdownMenuItem(
                                  value: service['service_id'] as String,
                                  child: Text(service['title'] as String),
                                ),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setDialog(() {
                                  serviceId = value;
                                  final selected = services.firstWhere((s) => s['service_id'] == value);
                                  serviceCategory = selected['service_category'] as String? ?? 'other';
                                });
                              }
                            },
                          ),
                        ],
                        TextFormField(
                          controller: location,
                          decoration: InputDecoration(
                            labelText: gr
                                ? 'Σημείο μέσα στο διαμέρισμα'
                                : 'Location within the apartment',
                            hintText: gr ? 'π.χ. κουζίνα' : 'e.g. kitchen',
                          ),
                        ),
                        TextFormField(
                          controller: title,
                          decoration: InputDecoration(
                            labelText: gr ? 'Σύντομος τίτλος' : 'Short title',
                            hintText: gr
                                ? 'π.χ. διαρροή νερού'
                                : 'e.g. water leak',
                          ),
                          validator: _required,
                        ),
                        TextFormField(
                          controller: description,
                          minLines: 3,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: gr
                                ? 'Περιγραφή του προβλήματος'
                                : 'Describe the problem',
                          ),
                          validator: _required,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(gr ? 'Άκυρο' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => _formKey.currentState!.validate()
                    ? Navigator.pop(dialogContext, true)
                    : null,
                child: Text(gr ? 'Υποβολή' : 'Submit'),
              ),
            ],
          ),
        ),
      );

      if (submitted != true || !mounted) return;
      setState(() => busy = true);
      await db.rpc(
        'submit_resident_service_request_v2',
        params: {
          'p_property_id': widget.propertyId,
          'p_apartment_number': apartmentNumber,
          'p_service_id': serviceId.isEmpty ? null : serviceId,
          'p_request_type': requestType,
          'p_priority': priority,
          'p_title': title.text.trim(),
          'p_description': description.text.trim(),
          'p_location': location.text.trim(),
          'p_issue_scope': issueScope,
          'p_service_category': serviceCategory,
        },
      );
      if (!mounted) return;
      setState(() {
        busy = false;
        _requests = _loadRequests();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            gr ? 'Η αναφορά καταχωρίστηκε.' : 'Your report was submitted.',
          ),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            gr
                ? 'Δεν ήταν δυνατή η καταχώριση. Δοκίμασε ξανά.'
                : 'Could not submit the report. Try again.',
          ),
        ),
      );
    } finally {
      title.dispose();
      description.dispose();
      location.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.propertyName)),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: busy ? null : _newReport,
      icon: const Icon(Icons.report_problem_outlined),
      label: Text(gr ? 'Νέα αναφορά' : 'New report'),
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.home_work_outlined),
              ),
              title: Text(
                gr
                    ? 'Το διαμέρισμά σου: ${widget.apartmentNumber}'
                    : 'Your apartment: ${widget.apartmentNumber}',
              ),
              subtitle: Text(
                gr
                    ? 'Οι αναφορές σου είναι συνδεδεμένες με αυτό το διαμέρισμα.'
                    : 'Your reports are linked to this apartment.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            gr ? 'Οι αναφορές μου' : 'My reports',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _requests,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: Text(
                      gr
                          ? 'Δεν ήταν δυνατή η φόρτωση των αναφορών.'
                          : 'Could not load reports.',
                    ),
                    trailing: IconButton(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.task_alt_outlined),
                    title: Text(
                      gr
                          ? 'Δεν έχεις υποβάλει αναφορές.'
                          : 'You have not submitted any reports.',
                    ),
                  ),
                );
              }
              return Column(
                children: rows
                    .map(
                      (row) => Card(
                        child: ListTile(
                          leading: Icon(
                            row['request_type'] == 'damage_report'
                                ? Icons.build_circle_outlined
                                : Icons.miscellaneous_services_outlined,
                          ),
                          title: Text(row['title'] as String? ?? ''),
                          subtitle: Text(
                            '${_typeLabel(row['request_type'] as String?)} · ${_serviceCategoryLabel(row['service_category'] as String?)} · ${_priorityLabel(row['priority'] as String?)} · ${_statusLabel(row['status'] as String?)}${row['apartment_number'] == 'common_area' ? (gr ? ' · Κοινόχρηστος χώρος' : ' · Common area') : ''}${row['quote_amount'] == null ? '' : ' · €${row['quote_amount']}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: false,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 88),
        ],
      ),
    ),
  );
}