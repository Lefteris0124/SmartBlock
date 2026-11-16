import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'property_details_screen.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({
    this.organizationId,
    this.organizationName,
    this.organizationApprovalStatus,
    required this.isGreek,
    super.key,
  });

  final String? organizationId;
  final String? organizationName;
  final String? organizationApprovalStatus;
  final bool isGreek;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _propertiesFuture;
  late bool _greek;

  @override
  void initState() {
    super.initState();
    _greek = widget.isGreek;
    _propertiesFuture = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    var query = _client
        .from('properties')
        .select(
          'id, name, property_type, other_description, address, city, country, management_model, approval_status, organization_id, created_by',
        );
    final userId = _client.auth.currentUser?.id;
    if (widget.organizationId != null && userId != null) {
      query = query.or(
        'created_by.eq.$userId,organization_id.eq.${widget.organizationId}',
      );
    } else if (widget.organizationId != null) {
      query = query.eq('organization_id', widget.organizationId!);
    } else if (userId != null) {
      query = query.eq('created_by', userId);
    }
    final rows = await query.order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    final pending = _load();
    setState(() => _propertiesFuture = pending);
    try {
      await pending;
    } catch (_) {}
  }

  Future<void> _createProperty() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController();
    final other = TextEditingController();
    final form = GlobalKey<FormState>();
    var type = 'apartment';
    var model = 'self_service';
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(_greek ? 'Νέο ακίνητο' : 'New property'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Τύπος ακινήτου' : 'Property type',
                      ),
                      items: [
                        _option(
                          'apartment',
                          _greek ? 'Διαμέρισμα' : 'Apartment',
                        ),
                        _option(
                          'building',
                          _greek ? 'Πολυκατοικία' : 'Apartment building',
                        ),
                        _option('house', _greek ? 'Κατοικία' : 'House'),
                        _option('shop', _greek ? 'Κατάστημα' : 'Shop'),
                        _option('office', _greek ? 'Γραφείο' : 'Office'),
                        _option('warehouse', _greek ? 'Αποθήκη' : 'Warehouse'),
                        _option('land', _greek ? 'Οικόπεδο' : 'Land'),
                        _option('other', _greek ? 'Άλλο' : 'Other'),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) setDialog(() => type = v);
                            },
                    ),
                    if (type == 'other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: other,
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Προσδιορίστε το άλλο είδος'
                              : 'Specify the property type',
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? (_greek
                                  ? 'Απαιτείται περιγραφή.'
                                  : 'Description is required.')
                            : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Όνομα ακινήτου' : 'Property name',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: address,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Διεύθυνση' : 'Address',
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: city,
                      decoration: InputDecoration(
                        labelText: _greek ? 'Πόλη' : 'City',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: model,
                      decoration: InputDecoration(
                        labelText: _greek
                            ? 'Μοντέλο διαχείρισης'
                            : 'Management model',
                      ),
                      items: [
                        _option(
                          'self_service',
                          _greek ? 'Αυτοδιαχείριση' : 'Self-service',
                        ),
                        _option(
                          'assisted',
                          _greek ? 'Υποβοηθούμενη' : 'Assisted',
                        ),
                        _option(
                          'managed',
                          _greek ? 'Πλήρης διαχείριση' : 'Managed',
                        ),
                      ],
                      onChanged: saving
                          ? null
                          : (v) {
                              if (v != null) setDialog(() => model = v);
                            },
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _greek
                          ? 'Πρώτα αποθηκεύεται το ακίνητο. Ο ιδιοκτήτης/οργανισμός προστίθεται έπειτα μέσα από τα στοιχεία του.'
                          : 'Save the property first. Add its owner organization afterward from the property details.',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx, false),
              child: Text(_greek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setDialog(() => saving = true);
                      try {
                        final id = await _client.rpc(
                          'create_property_draft',
                          params: {
                            'p_name': name.text.trim(),
                            'p_property_type': type,
                            'p_address': address.text.trim(),
                            'p_city': city.text.trim(),
                            'p_country': 'Cyprus',
                            'p_management_model': model,
                            'p_other_description': type == 'other'
                                ? other.text.trim()
                                : null,
                          },
                        );
                        if (ctx.mounted) Navigator.pop(ctx, id != null);
                      } on PostgrestException catch (e) {
                        if (ctx.mounted) {
                          setDialog(() => saving = false);
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(SnackBar(content: Text(e.message)));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_greek ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    address.dispose();
    city.dispose();
    other.dispose();
    if (saved == true && mounted) await _refresh();
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? (_greek ? 'Υποχρεωτικό πεδίο.' : 'Required field.')
      : null;
  DropdownMenuItem<String> _option(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(label));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.organizationName ??
            (_greek ? 'Τα ακίνητά μου' : 'My properties'),
      ),
      actions: [
        IconButton(
          onPressed: () => setState(() => _greek = !_greek),
          icon: const Icon(Icons.language),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _createProperty,
      icon: const Icon(Icons.add_home_work_outlined),
      label: Text(_greek ? 'Νέο ακίνητο' : 'New property'),
    ),
    body: RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _propertiesFuture,
        builder: (context, snapshot) {
          final properties = snapshot.data ?? const [];
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                _greek ? 'Ακίνητα' : 'Properties',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _greek
                    ? 'Δημιούργησε πρώτα το ακίνητο και σύνδεσε μετά τους ιδιοκτήτες με τον αριθμό τηλεφώνου τους.'
                    : 'Create the property first, then link its owners by phone number.',
              ),
              const SizedBox(height: 20),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                Text(snapshot.error.toString())
              else if (properties.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _greek
                        ? 'Δεν υπάρχουν ακίνητα ακόμη.'
                        : 'No properties yet.',
                  ),
                )
              else
                ...properties.map(
                  (p) => Card(
                    child: ListTile(
                      title: Text(p['name'] as String? ?? ''),
                      subtitle: Text(
                        [
                              p['property_type'] == 'other'
                                  ? p['other_description']
                                  : p['property_type'],
                              p['address'],
                              p['city'],
                              p['approval_status'],
                            ]
                            .whereType<String>()
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PropertyDetailsScreen(
                              property: p,
                              organizationId: p['organization_id'] as String?,
                              organizationName: widget.organizationName ?? '',
                              organizationApprovalStatus:
                                  widget.organizationApprovalStatus ??
                                  'pending_review',
                              isGreek: _greek,
                            ),
                          ),
                        );
                        await _refresh();
                      },
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
