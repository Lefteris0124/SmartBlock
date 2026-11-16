import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'property_owners_screen.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({
    required this.organizationId,
    required this.organizationName,
    required this.organizationApprovalStatus,
    required this.isGreek,
    super.key,
  });

  final String organizationId;
  final String organizationName;
  final String organizationApprovalStatus;
  final bool isGreek;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  late Future<List<Map<String, dynamic>>> _propertiesFuture;
  late bool _isGreek;

  @override
  void initState() {
    super.initState();
    _isGreek = widget.isGreek;
    _propertiesFuture = _loadProperties();
  }

  Future<List<Map<String, dynamic>>> _loadProperties() async {
    final rows = await _client
        .from('properties')
        .select(
          'id, name, property_type, address, city, country, management_model, approval_status',
        )
        .eq('organization_id', widget.organizationId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _refresh() async {
    final future = _loadProperties();
    setState(() => _propertiesFuture = future);
    try {
      await future;
    } catch (_) {
      // The page shows a retry action for query errors.
    }
  }

  Future<void> _createProperty() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final cityController = TextEditingController();
    final ownershipController = TextEditingController(text: '100');
    final formKey = GlobalKey<FormState>();
    var propertyType = 'house';
    var managementModel = 'self_service';
    var isSaving = false;

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_isGreek ? 'Νέο ακίνητο' : 'New property'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: propertyType,
                      decoration: InputDecoration(
                        labelText: _isGreek
                            ? 'Τύπος ακινήτου'
                            : 'Property type',
                      ),
                      items: [
                        _typeOption('house', _isGreek ? 'Κατοικία' : 'House'),
                        _typeOption('shop', _isGreek ? 'Κατάστημα' : 'Shop'),
                        _typeOption('office', _isGreek ? 'Γραφείο' : 'Office'),
                        _typeOption(
                          'warehouse',
                          _isGreek ? 'Αποθήκη' : 'Warehouse',
                        ),
                        _typeOption('land', _isGreek ? 'Οικόπεδο' : 'Land'),
                        _typeOption('other', _isGreek ? 'Άλλο' : 'Other'),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() => propertyType = value);
                              }
                            },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _isGreek
                            ? 'Όνομα ακινήτου'
                            : 'Property name',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? (_isGreek ? 'Συμπλήρωσε όνομα.' : 'Enter a name.')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _isGreek ? 'Διεύθυνση' : 'Address',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? (_isGreek
                                ? 'Η διεύθυνση είναι υποχρεωτική.'
                                : 'Address is required.')
                          : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: cityController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _isGreek ? 'Πόλη' : 'City',
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: managementModel,
                      decoration: InputDecoration(
                        labelText: _isGreek
                            ? 'Μοντέλο διαχείρισης'
                            : 'Management model',
                      ),
                      items: [
                        _typeOption(
                          'self_service',
                          _isGreek ? 'Αυτοδιαχείριση' : 'Self-service',
                        ),
                        _typeOption(
                          'assisted',
                          _isGreek ? 'Υποβοηθούμενη' : 'Assisted',
                        ),
                        _typeOption(
                          'managed',
                          _isGreek ? 'Πλήρης διαχείριση' : 'Managed',
                        ),
                      ],
                      onChanged: isSaving
                          ? null
                          : (value) {
                              if (value != null) {
                                setDialogState(() => managementModel = value);
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: ownershipController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _isGreek
                            ? 'Μερίδιο οργανισμού'
                            : 'Organization ownership share',
                        suffixText: '%',
                      ),
                      validator: (value) {
                        final percentage = double.tryParse(
                          (value ?? '').trim().replaceAll(',', '.'),
                        );
                        if (percentage == null ||
                            percentage <= 0 ||
                            percentage > 100) {
                          return _isGreek
                              ? 'Το ποσοστό πρέπει να είναι από 0,01 έως 100.'
                              : 'Enter a share between 0.01 and 100.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isGreek
                          ? 'Το μερίδιο του οργανισμού θα καταχωριστεί ως αρχική ιδιοκτησία. Μπορείς να αφήσεις υπόλοιπο για συνιδιοκτήτες.'
                          : 'The organization share is saved as the initial ownership record. Leave a remainder for co-owners if needed.',
                      style: Theme.of(dialogContext).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(_isGreek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final user = _client.auth.currentUser;
                      if (user == null) {
                        Navigator.pop(dialogContext, false);
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        await _client.rpc(
                          'create_property_with_initial_ownership',
                          params: {
                            'p_organization_id': widget.organizationId,
                            'p_name': nameController.text.trim(),
                            'p_property_type': propertyType,
                            'p_address': addressController.text.trim(),
                            'p_city': cityController.text.trim(),
                            'p_management_model': managementModel,
                            'p_ownership_percentage': double.parse(
                              ownershipController.text.trim().replaceAll(
                                ',',
                                '.',
                              ),
                            ),
                          },
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on PostgrestException catch (error) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(
                          dialogContext,
                        ).showSnackBar(SnackBar(content: Text(error.message)));
                      } catch (_) {
                        if (!dialogContext.mounted) return;
                        setDialogState(() => isSaving = false);
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              _isGreek
                                  ? 'Δεν ήταν δυνατή η αποθήκευση.'
                                  : 'Could not save the property.',
                            ),
                          ),
                        );
                      }
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isGreek ? 'Αποθήκευση' : 'Save'),
            ),
          ],
        ),
      ),
    );

    nameController.dispose();
    addressController.dispose();
    cityController.dispose();
    ownershipController.dispose();
    if (created == true && mounted) await _refresh();
  }

  DropdownMenuItem<String> _typeOption(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(label));

  String _typeLabel(String? type) {
    final labels = _isGreek
        ? const {
            'house': 'Κατοικία',
            'shop': 'Κατάστημα',
            'office': 'Γραφείο',
            'warehouse': 'Αποθήκη',
            'land': 'Οικόπεδο',
            'other': 'Άλλο',
          }
        : const {
            'house': 'House',
            'shop': 'Shop',
            'office': 'Office',
            'warehouse': 'Warehouse',
            'land': 'Land',
            'other': 'Other',
          };
    return labels[type] ?? (type ?? '');
  }

  String _modelLabel(String? model) {
    final labels = _isGreek
        ? const {
            'managed': 'Πλήρης διαχείριση',
            'assisted': 'Υποβοηθούμενη',
            'self_service': 'Αυτοδιαχείριση',
          }
        : const {
            'managed': 'Managed',
            'assisted': 'Assisted',
            'self_service': 'Self-service',
          };
    return labels[model] ?? (model ?? '');
  }

  String _statusLabel(String? status) {
    if (_isGreek) {
      switch (status) {
        case 'draft':
          return 'Πρόχειρο';
        case 'pending_review':
          return 'Σε αναμονή έγκρισης';
        case 'under_review':
          return 'Υπό εξέταση';
        case 'changes_required':
          return 'Απαιτούνται αλλαγές';
        case 'approved':
          return 'Εγκεκριμένο';
        case 'rejected':
          return 'Απορρίφθηκε';
        case 'suspended':
          return 'Σε αναστολή';
      }
    }
    return (status ?? 'unknown').replaceAll('_', ' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.organizationName),
        actions: [
          IconButton(
            tooltip: _isGreek ? 'English' : 'Ελληνικά',
            onPressed: () => setState(() => _isGreek = !_isGreek),
            icon: const Icon(Icons.language),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createProperty,
        icon: const Icon(Icons.add_home_work_outlined),
        label: Text(_isGreek ? 'Νέο ακίνητο' : 'New property'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _propertiesFuture,
          builder: (context, snapshot) {
            final properties = snapshot.data ?? const [];
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
              children: [
                Text(
                  _isGreek ? 'Ακίνητα οργανισμού' : 'Organization properties',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF17324D),
                  ),
                ),
                const SizedBox(height: 8),
                if (organizationApprovalStatus == 'pending_review' ||
                    organizationApprovalStatus == 'under_review' ||
                    organizationApprovalStatus == 'changes_required')
                  Card(
                    elevation: 0,
                    color: Theme.of(context).colorScheme.tertiaryContainer,
                    child: ListTile(
                      leading: const Icon(Icons.hourglass_top_rounded),
                      title: Text(
                        _isGreek
                            ? 'Εκκρεμεί η έγκριση του οργανισμού'
                            : 'Organization review is in progress',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        _isGreek
                            ? 'Μπορείς να προετοιμάσεις ακίνητα τώρα. Θα αποθηκευτούν ως πρόχειρα μέχρι να ολοκληρωθεί ο έλεγχος.'
                            : 'You can prepare property records now. They will remain drafts until the review is complete.',
                      ),
                    ),
                  )
                else
                  Text(
                    _isGreek
                        ? 'Τα ακίνητα παραμένουν σε πρόχειρη κατάσταση μέχρι να εγκριθούν.'
                        : 'Properties remain drafts until they are reviewed.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 24),
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (snapshot.hasError)
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isGreek
                                ? 'Δεν φορτώθηκαν τα ακίνητα'
                                : 'Could not load properties',
                          ),
                          const SizedBox(height: 8),
                          Text(snapshot.error.toString()),
                          TextButton.icon(
                            onPressed: _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(
                              _isGreek ? 'Δοκίμασε ξανά' : 'Try again',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (properties.isEmpty)
                  Card(
                    elevation: 0,
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.home_work_outlined,
                            size: 48,
                            color: Color(0xFF176B87),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _isGreek
                                ? 'Δεν υπάρχουν ακίνητα ακόμη'
                                : 'No properties yet',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _isGreek
                                ? 'Πρόσθεσε το πρώτο ακίνητο σε αυτόν τον οργανισμό.'
                                : 'Add the first property to this organization.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...properties.map((property) {
                    final location = [property['address'], property['city']]
                        .whereType<String>()
                        .where((part) => part.isNotEmpty)
                        .join(', ');
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PropertyOwnersScreen(
                              propertyId: property['id'] as String,
                              propertyName: property['name'] as String? ?? '',
                              organizationId: widget.organizationId,
                              isGreek: _isGreek,
                            ),
                          ),
                        ),
                        leading: const CircleAvatar(
                          backgroundColor: Color(0x1F176B87),
                          foregroundColor: Color(0xFF176B87),
                          child: Icon(Icons.home_work_outlined),
                        ),
                        title: Text(
                          property['name'] as String? ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            [
                              _typeLabel(property['property_type'] as String?),
                              if (location.isNotEmpty) location,
                              _modelLabel(
                                property['management_model'] as String?,
                              ),
                              _statusLabel(
                                property['approval_status'] as String?,
                              ),
                            ].join(' · '),
                          ),
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                      ),
                    );
                  }),
              ],
            );
          },
        ),
      ),
    );
  }
}
