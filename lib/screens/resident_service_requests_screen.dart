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
    this.initialCategory,
    this.initialRequestId,
    super.key,
  });

  final String propertyId;
  final String propertyName;
  final String apartmentNumber;
  final bool isGreek;
  final String? initialCategory;
  final String? initialRequestId;

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
  String? _selectedCategory;
  String _selectedMode = 'menu';
  bool get gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _selectedMode = widget.initialRequestId == null ? 'menu' : 'track';
  }

  String _requestTypeForCategory(String category) => switch (category) {
        'plumbing' || 'building_work' || 'electrical' => 'damage_report',
        'furniture_assembly' || 'painting' => 'maintenance',
        'cleaning' => 'cleaning',
        'safety' => 'safety',
        _ => 'other',
      };

  Future<List<Map<String, dynamic>>> _loadRequests() async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('property_service_requests')
            .select(
              'id,request_type,service_category,priority,apartment_number,title,description,location,status,quote_amount,supplier,created_at',
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
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
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
              const SizedBox(height: 6),
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
                  maxLines: 2,
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

  Future<void> _newReport(String initialCategory) async {
    final services = await _services;
    if (!mounted) return;

    var requestType = _requestTypeForCategory(initialCategory);
    var issueScope = 'unit';
    var priority = 'normal';
    var serviceId = '';
    var serviceCategory = initialCategory;
    final categoryServices = services
        .where((service) => service['service_category'] == serviceCategory)
        .toList();
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
                        if (categoryServices.isNotEmpty) ...[
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
                              ...categoryServices.map(
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
        _selectedMode = 'track';
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

  Future<List<Map<String, dynamic>>> _loadComments(String requestId) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from('property_service_request_comments')
            .select('id,author_id,author_name,body,created_at')
            .eq('request_id', requestId)
            .order('created_at'),
      );

  Future<void> _commentOnRequest(Map<String, dynamic> request) async {
    final controller = TextEditingController();
    var comments = <Map<String, dynamic>>[];
    Object? loadError;
    try {
      comments = await _loadComments(request['id'] as String);
    } catch (error) {
      loadError = error;
    }
    if (!mounted) { controller.dispose(); return; }
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(gr ? 'Σχόλιο για παλιά βλάβη' : 'Comment on this report'),
          content: SizedBox(
            width: 460,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(dialogContext).height * .65,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(request['title'] as String? ?? ''),
                    const SizedBox(height: 8),
                    if (loadError != null)
                      Text(gr ? 'Δεν φορτώθηκαν τα προηγούμενα σχόλια.' : 'Previous comments could not be loaded.')
                    else if (comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(gr ? 'Δεν υπάρχουν σχόλια ακόμη.' : 'No comments yet.'),
                      )
                    else
                      ...comments.map((comment) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.chat_bubble_outline),
                          title: Text(comment['author_name'] as String? ?? ''),
                          subtitle: Text('${comment['body']}\n${comment['created_at']}'),
                        ),
                      )),
                    const SizedBox(height: 8),
                    TextField(
                      controller: controller,
                      onChanged: (_) => setDialog(() {}),
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: gr ? 'Το σχόλιό σου' : 'Your comment',
                        hintText: gr ? 'Γράψε ενημέρωση ή ερώτηση για τη βλάβη.' : 'Add an update or question about the problem.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(gr ? 'Άκυρο' : 'Cancel')),
            FilledButton(
              onPressed: busy || controller.text.trim().length < 2
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text(gr ? 'Αποστολή σχολίου' : 'Send comment'),
            ),
          ],
        ),
      ),
    );
    if (send == true) {
      setState(() => busy = true);
      try {
        await db.rpc('comment_on_property_service_request', params: {
          'p_request_id': request['id'],
          'p_body': controller.text.trim(),
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(gr ? 'Το σχόλιο καταχωρίστηκε.' : 'Comment added.')),
        );
      } on PostgrestException catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }
    controller.dispose();
  }

  Widget _actionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Card(
    child: ListTile(
      leading: CircleAvatar(child: Icon(icon)),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );

  Widget _commentThread(String requestId) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _loadComments(requestId),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snapshot.hasError) {
        return ListTile(title: Text(gr ? 'Δεν φορτώθηκαν τα σχόλια.' : 'Comments could not be loaded.'));
      }
      final comments = snapshot.data ?? const [];
      if (comments.isEmpty) {
        return ListTile(title: Text(gr ? 'Δεν υπάρχουν σχόλια.' : 'No comments yet.'));
      }
      return Column(children: comments.map((comment) => ListTile(
        leading: const Icon(Icons.chat_bubble_outline),
        title: Text(comment['author_name'] as String? ?? ''),
        subtitle: Text('${comment['body']}\n${comment['created_at']}'),
      )).toList());
    },
  );

  Widget _requestCard(Map<String, dynamic> row, {required bool commentMode}) {
    final requestId = row['id'] as String;
    final subtitle = '${_typeLabel(row['request_type'] as String?)} · ${_serviceCategoryLabel(row['service_category'] as String?)} · ${_statusLabel(row['status'] as String?)} · ${row['apartment_number'] == 'common_area' ? (gr ? 'Πολυκατοικία / κοινόχρηστος χώρος' : 'Building / common area') : (gr ? 'Διαμέρισμα ' : 'Apartment ') + (row['apartment_number'] as String? ?? '')}';
    if (commentMode) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.chat_bubble_outline),
          title: Text(row['title'] as String? ?? ''),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: busy ? null : () => _commentOnRequest(row),
        ),
      );
    }
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.track_changes_outlined),
        title: Text(row['title'] as String? ?? ''),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        children: [
          ListTile(
            title: Text(gr ? 'Περιγραφή' : 'Description'),
            subtitle: Text(row['description'] as String? ?? ''),
          ),
          if ((row['location'] as String? ?? '').isNotEmpty)
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(gr ? 'Τοποθεσία' : 'Location'),
              subtitle: Text(row['location'] as String),
            ),
          _commentThread(requestId),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => _commentOnRequest(row),
                icon: const Icon(Icons.add_comment_outlined),
                label: Text(gr ? 'Πρόσθεσε σχόλιο' : 'Add a comment'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryGrid() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Card(
        child: ListTile(
          leading: const Icon(Icons.home_work_outlined),
          title: Text(gr ? 'Διαμέρισμα ${widget.apartmentNumber}' : 'Apartment ${widget.apartmentNumber}'),
          subtitle: Text(gr ? 'Διάλεξε κατηγορία αναφοράς.' : 'Choose a report category.'),
        ),
      ),
      const SizedBox(height: 12),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1000
              ? 4
              : constraints.maxWidth >= 680
                  ? 3
                  : 2;
          return GridView.count(
            crossAxisCount: columns,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: columns == 2 ? 1.24 : 1.34,
            children: [
              for (final category in const [
                'plumbing','building_work','electrical','furniture_assembly',
                'painting','cleaning','safety','other',
              ])
                _serviceCategoryCard(
                  category,
                  false,
                  () => setState(() {
                    _selectedCategory = category;
                    _selectedMode = 'menu';
                  }),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _selectedCategoryView(List<Map<String, dynamic>> requests) {
    final category = _selectedCategory!;
    final rows = requests.where((row) => row['service_category'] == category).toList();
    if (_selectedMode == 'menu') {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Icon(_serviceCategoryIcon(category))),
              title: Text(_serviceCategoryLabel(category)),
              subtitle: Text(_serviceCategoryDescription(category)),
            ),
          ),
          const SizedBox(height: 12),
          _actionCard(
            icon: Icons.add_circle_outline,
            title: gr ? 'Νέα βλάβη' : 'New problem report',
            subtitle: gr ? 'Καταχώρισε νέο αίτημα σε αυτή την κατηγορία.' : 'Create a new report in this category.',
            onTap: busy ? () {} : () => _newReport(category),
          ),
          _actionCard(
            icon: Icons.track_changes_outlined,
            title: gr ? 'Παρακολούθηση' : 'Track reports',
            subtitle: gr ? 'Δες την κατάσταση παλιών και νέων αναφορών.' : 'Check the status of existing reports.',
            onTap: () => setState(() => _selectedMode = 'track'),
          ),
          _actionCard(
            icon: Icons.add_comment_outlined,
            title: gr ? 'Σχόλιο παλιάς βλάβης' : 'Comment on an existing report',
            subtitle: gr ? 'Επίλεξε παλιά αναφορά και πρόσθεσε ενημέρωση.' : 'Select an existing report and add an update.',
            onTap: () => setState(() => _selectedMode = 'comment'),
          ),
        ],
      );
    }
    final commentMode = _selectedMode == 'comment';
    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text(commentMode
                  ? (gr ? 'Δεν υπάρχουν παλιές αναφορές σε αυτή την κατηγορία.' : 'No existing reports in this category.')
                  : (gr ? 'Δεν υπάρχουν αναφορές σε αυτή την κατηγορία.' : 'No reports in this category.')),
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: rows.map((row) => _requestCard(row, commentMode: commentMode)).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = _selectedCategory;
    final title = category == null
        ? widget.propertyName
        : _selectedMode == 'menu'
            ? _serviceCategoryLabel(category)
            : _selectedMode == 'track'
                ? (gr ? 'Παρακολούθηση βλαβών' : 'Track reports')
                : (gr ? 'Σχόλια βλαβών' : 'Report comments');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          tooltip: gr ? 'Πίσω' : 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_selectedCategory == null) {
              Navigator.of(context).maybePop();
            } else if (_selectedMode != 'menu') {
              setState(() => _selectedMode = 'menu');
            } else {
              setState(() => _selectedCategory = null);
            }
          },
        ),
      ),
      body: category == null
          ? _categoryGrid()
          : FutureBuilder<List<Map<String, dynamic>>>(
              future: _requests,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(gr
                          ? 'Δεν ήταν δυνατή η φόρτωση των αναφορών.'
                          : 'Could not load reports.'),
                    ),
                  );
                }
                return _selectedCategoryView(snapshot.data ?? const []);
              },
            ),
    );
  }
}