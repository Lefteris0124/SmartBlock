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
              'id,request_type,priority,apartment_number,title,description,status,quote_amount,supplier,created_at',
            )
            .eq('property_id', widget.propertyId)
            .order('created_at', ascending: false),
      );

  Future<List<Map<String, dynamic>>> _loadServices() async =>
      List<Map<String, dynamic>>.from(
        await db.rpc(
          'list_resident_services',
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
                          DropdownButtonFormField<String>(
                            initialValue: issueScope,
                            decoration: InputDecoration(
                              labelText: gr ? 'Πού είναι η βλάβη;' : 'Where is the problem?',
                            ),
                            items: [
                              DropdownMenuItem(value: 'unit', child: Text(gr ? 'Μέσα στο διαμέρισμα' : 'Inside my apartment')),
                              DropdownMenuItem(value: 'building', child: Text(gr ? 'Στο κτίριο / κοινόχρηστο χώρο' : 'Building / common area')),
                            ],
                            onChanged: (value) {
                              if (value != null) setDialog(() {
                                issueScope = value;
                                apartmentNumber = value == 'building' ? 'common_area' : widget.apartmentNumber;
                              });
                            },
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
                                setDialog(() => serviceId = value);
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
        'submit_resident_service_request',
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
                            '${_typeLabel(row['request_type'] as String?)} · ${_priorityLabel(row['priority'] as String?)} · ${_statusLabel(row['status'] as String?)}${row['apartment_number'] == 'common_area' ? (gr ? ' · Κοινόχρηστος χώρος' : ' · Common area') : ''}${row['quote_amount'] == null ? '' : ' · €${row['quote_amount']}'}',
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