import 'package:flutter/material.dart' hide Text;
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../smartblock_trial_session.dart';

import 'property_details_screen.dart';
import 'admin_review_screen.dart';
import 'resident_service_requests_screen.dart';
import '../app_language.dart';
import '../smartblock_text.dart';

enum PropertiesViewMode { all, owner, resident }

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({
    this.organizationId,
    this.organizationName,
    this.organizationApprovalStatus,
    required this.isGreek,
    this.viewMode = PropertiesViewMode.all,
    super.key,
  });

  final String? organizationId;
  final String? organizationName;
  final String? organizationApprovalStatus;
  final bool isGreek;
  final PropertiesViewMode viewMode;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _client = SmartBlockTrialSession.client;
  late Future<List<Map<String, dynamic>>> _propertiesFuture;
  late bool _greek;
  late final VoidCallback _languageListener;

  @override
  void initState() {
    super.initState();
    final language = SmartBlockLanguageController.instance;
    _greek = language.selected.value.isGreek;
    _languageListener = () {
      if (mounted) setState(() => _greek = language.selected.value.isGreek);
    };
    language.selected.addListener(_languageListener);
    _propertiesFuture = _load();
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(_languageListener);
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = <Map<String, dynamic>>[];
    if (widget.viewMode != PropertiesViewMode.resident) {
      var query = _client
          .from('properties')
          .select(
            'id, name, property_type, building_model, portfolio_id, other_description, total_apartments, address, city, country, management_model, approval_status, organization_id, created_by, manager_user_id',
          );
      final userId = _client.auth.currentUser?.id;
      if (widget.organizationId != null && userId != null) {
        query = query.or(
          'created_by.eq.$userId,organization_id.eq.${widget.organizationId}',
        );
      } else if (widget.organizationId != null) {
        query = query.eq('organization_id', widget.organizationId!);
      }
      rows.addAll(
        List<Map<String, dynamic>>.from(
          await query.order('created_at', ascending: false),
        ),
      );
    }
    final fullAccessPropertyIds = rows
        .map((property) => property['id'] as String)
        .toSet();
    final residentRows = widget.viewMode == PropertiesViewMode.owner
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _client.rpc('list_my_resident_properties'),
          );
    for (final resident in residentRows) {
      final id = resident['property_id'] as String;
      if (fullAccessPropertyIds.contains(id)) continue;
      rows.add({
        'id': id,
        'name': resident['property_name'],
        'property_type': resident['property_type'],
        'address': resident['property_address'],
        'city': resident['property_city'],
        'total_apartments': resident['total_apartments'],
        'approval_status': 'approved',
        'organization_id': null,
        '_resident_only': true,
        '_resident_apartment_number': resident['apartment_number'],
      });
    }
    return rows;
  }

  Future<void> _refresh() async {
    final pending = _load();
    setState(() => _propertiesFuture = pending);
    try {
      await pending;
    } catch (_) {}
  }

  IconData _propertyIcon(String? type, {required bool resident}) {
    if (resident || type == 'apartment') return Icons.apartment_rounded;
    return switch (type) {
      'building' => Icons.domain_rounded,
      'house' => Icons.home_rounded,
      'shop' => Icons.storefront_rounded,
      'office' => Icons.business_center_rounded,
      'warehouse' => Icons.warehouse_rounded,
      'land' => Icons.landscape_rounded,
      _ => Icons.holiday_village_rounded,
    };
  }

  Future<void> _createProperty() async {
    final name = TextEditingController();
    final address = TextEditingController();
    final city = TextEditingController();
    final other = TextEditingController();
    final apartments = TextEditingController();
    final virtualUnitAddresses = <TextEditingController>[];
    final form = GlobalKey<FormState>();
    var type = 'apartment';
    var buildingModel = 'physical';
    var model = 'self_service';
    var saving = false;
    Map<String, dynamic>? matchingBuilding;
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
                    if (type == 'building') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: buildingModel,
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Μορφή πολυκατοικίας'
                              : 'Building type',
                        ),
                        items: [
                          _option(
                            'physical',
                            _greek
                                ? 'Πραγματική πολυκατοικία — 5 € ανά διαμέρισμα/μήνα'
                                : 'Physical building — €5 per apartment/month',
                          ),
                          _option(
                            'virtual',
                            _greek
                                ? 'Εικονική πολυκατοικία/χαρτοφυλάκιο — 5% στις πληρωμές'
                                : 'Virtual building/portfolio — 5% on payments',
                          ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialog(() {
                                    buildingModel = value;
                                    final count = value == 'virtual'
                                        ? int.tryParse(apartments.text.trim()) ?? 0
                                        : 0;
                                    while (virtualUnitAddresses.length < count) {
                                      virtualUnitAddresses.add(TextEditingController());
                                    }
                                    while (virtualUnitAddresses.length > count) {
                                      virtualUnitAddresses.removeLast().dispose();
                                    }
                                  });
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: apartments,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Συνολικά διαμερίσματα'
                              : 'Total apartments',
                        ),
                        validator: (v) => type != 'building'
                            ? null
                            : (int.tryParse((v ?? '').trim()) ?? 0) < 1
                            ? (_greek
                                  ? 'Βάλε τον αριθμό διαμερισμάτων.'
                                  : 'Enter the apartment count.')
                            : null,
                        onChanged: (v) {
                          if (buildingModel != 'virtual') return;
                          final count = int.tryParse(v.trim()) ?? 0;
                          if (count < 0 || count > 200) return;
                          setDialog(() {
                            while (virtualUnitAddresses.length < count) {
                              virtualUnitAddresses.add(TextEditingController());
                            }
                            while (virtualUnitAddresses.length > count) {
                              virtualUnitAddresses.removeLast().dispose();
                            }
                          });
                        },
                      ),
                      if (buildingModel == 'virtual') ...[
                        const SizedBox(height: 10),
                        Text(_greek
                            ? 'Διεύθυνση για κάθε εικονικό διαμέρισμα (για επαλήθευση)'
                            : 'Address for each virtual apartment (for verification)'),
                        ...List.generate(virtualUnitAddresses.length, (index) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextFormField(
                            controller: virtualUnitAddresses[index],
                            decoration: InputDecoration(
                              labelText: _greek ? 'Διαμέρισμα ${index + 1} — διεύθυνση' : 'Unit ${index + 1} — address',
                            ),
                            validator: (value) => buildingModel == 'virtual' &&
                                    (value == null || value.trim().isEmpty)
                                ? (_greek ? 'Συμπλήρωσε τη διεύθυνση.' : 'Enter this address.')
                                : null,
                          ),
                        )),
                      ],
                    ],
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
                      validator: _required,
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
                        if (type == 'building' || type == 'apartment') {
                          final matches = List<Map<String, dynamic>>.from(
                            await _client.rpc(
                              'find_matching_buildings',
                              params: {
                                'p_address': address.text.trim(),
                                'p_city': city.text.trim(),
                                'p_country': 'Cyprus',
                              },
                            ),
                          );
                          if (matches.isNotEmpty) {
                            matchingBuilding = matches.first;
                            if (ctx.mounted) Navigator.pop(ctx, false);
                            return;
                          }
                        }
                        final id = await _client.rpc(
                          'create_property_draft_with_units',
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
                            'p_total_apartments': type == 'building'
                                ? int.parse(apartments.text.trim())
                                : null,
                            'p_building_model': type == 'building'
                                ? buildingModel
                                : 'physical',
                          },
                        );
                        if (id != null && buildingModel == 'virtual') {
                          await _client.from('property_virtual_units').insert(
                            List.generate(virtualUnitAddresses.length, (index) => {
                              'property_id': id,
                              'unit_label': 'Unit ${index + 1}',
                              'address': virtualUnitAddresses[index].text.trim(),
                              'city': city.text.trim(),
                              'country': 'Cyprus',
                            }),
                          );
                        }
                        if (ctx.mounted) Navigator.pop(ctx, id != null);
                      } on PostgrestException catch (e) {
                        if ((type == 'building' || type == 'apartment') &&
                            e.code == '23505') {
                          try {
                            final matches = List<Map<String, dynamic>>.from(
                              await _client.rpc(
                                'find_matching_buildings',
                                params: {
                                  'p_address': address.text.trim(),
                                  'p_city': city.text.trim(),
                                  'p_country': 'Cyprus',
                                },
                              ),
                            );
                            if (matches.isNotEmpty) {
                              matchingBuilding = matches.first;
                              if (ctx.mounted) Navigator.pop(ctx, false);
                              return;
                            }
                          } catch (_) {}
                        }
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
    apartments.dispose();
    for (final controller in virtualUnitAddresses) {
      controller.dispose();
    }
    if (saved == true && mounted) await _refresh();
    if (matchingBuilding != null && mounted) {
      if (matchingBuilding!['property_type'] == 'building') {
        await _requestManagerClaim(matchingBuilding!);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _greek
                  ? 'Υπάρχει ήδη ακίνητο καταχωρημένο σε αυτή τη διεύθυνση. Δεν δημιουργήθηκε δεύτερη εγγραφή. Ζήτησε από τον διαχειριστή ή το SmartBlock να σε συνδέσει με την υπάρχουσα.'
                  : 'A property is already registered at this address. No duplicate was created. Ask its manager or SmartBlock to connect you to the existing record.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _requestManagerClaim(Map<String, dynamic> building) async {
    final status = building['approval_status'] as String?;
    if (status != 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Βρέθηκε ήδη καταχώριση για αυτή τη διεύθυνση. Είναι ακόμη υπό έλεγχο, οπότε δεν μπορεί να δημιουργηθεί δεύτερη.'
                : 'A building record already exists at this address. It is still under review, so a second record cannot be created.',
          ),
        ),
      );
      return;
    }
    if (building['has_manager'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Η πολυκατοικία υπάρχει ήδη και έχει επαληθευμένο διαχειριστή.'
                : 'This building already has a verified manager.',
          ),
        ),
      );
      return;
    }

    final authority = TextEditingController();
    final form = GlobalKey<FormState>();
    PlatformFile? proof;
    var sending = false;
    final sent = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) => AlertDialog(
          title: Text(_greek ? 'Αίτημα διαχειριστή' : 'Request manager access'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${building['name']}\n${building['address']}, ${building['city']}',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: authority,
                    minLines: 3,
                    maxLines: 5,
                    maxLength: 2000,
                    decoration: InputDecoration(
                      labelText: _greek
                          ? 'Πώς έχεις εξουσιοδοτηθεί να διαχειρίζεσαι το ακίνητο;'
                          : 'How are you authorized to manage this building?',
                      border: const OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 10
                        ? (_greek
                              ? 'Πρόσθεσε λίγες λεπτομέρειες.'
                              : 'Add a few details.')
                        : null,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: sending
                        ? null
                        : () async {
                            final file = await FilePicker.pickFile(
                              type: FileType.custom,
                              allowedExtensions: [
                                'pdf',
                                'jpg',
                                'jpeg',
                                'png',
                                'webp',
                              ],
                            );
                            if (file == null || !dialogContext.mounted) return;
                            final size = await file.length();
                            if (!dialogContext.mounted) return;
                            if (size == null || size > 10 * 1024 * 1024) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _greek
                                        ? 'Το έγγραφο πρέπει να είναι έως 10 MB.'
                                        : 'The document must be 10 MB or smaller.',
                                  ),
                                ),
                              );
                              return;
                            }
                            setDialog(() => proof = file);
                          },
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      proof?.name ??
                          (_greek
                              ? 'Επισύναψε αποδεικτικό ορισμού'
                              : 'Attach proof of appointment'),
                    ),
                  ),
                  Text(
                    _greek
                        ? 'Ο admin θα ελέγξει το έγγραφο πριν σου δώσει πρόσβαση διαχειριστή.'
                        : 'An admin will verify the document before granting manager access.',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(_greek ? 'Άκυρο' : 'Cancel'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      if (proof == null) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              _greek
                                  ? 'Επισύναψε το έγγραφο ορισμού.'
                                  : 'Attach your appointment document.',
                            ),
                          ),
                        );
                        return;
                      }
                      setDialog(() => sending = true);
                      String? path;
                      try {
                        final userId = _client.auth.currentUser!.id;
                        final propertyId = building['property_id'] as String;
                        final extension = (proof!.extension ?? '')
                            .toLowerCase();
                        final mime = switch (extension) {
                          'pdf' => 'application/pdf',
                          'png' => 'image/png',
                          'webp' => 'image/webp',
                          'jpg' || 'jpeg' => 'image/jpeg',
                          _ => throw StateError('Unsupported proof document.'),
                        };
                        final safeName = proof!.name.replaceAll(
                          RegExp(r'[^A-Za-z0-9._-]'),
                          '_',
                        );
                        path =
                            '$userId/$propertyId/'
                            '${DateTime.now().microsecondsSinceEpoch}_$safeName';
                        await _client.storage
                            .from('smartblock-manager-proofs')
                            .uploadBinary(
                              path,
                              await proof!.readAsBytes(),
                              fileOptions: FileOptions(contentType: mime),
                            );
                        await _client.rpc(
                          'request_property_manager',
                          params: {
                            'p_property_id': propertyId,
                            'p_authority_note': authority.text.trim(),
                            'p_authority_document_path': path,
                          },
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } on PostgrestException catch (error) {
                        if (path != null) {
                          try {
                            await _client.storage
                                .from('smartblock-manager-proofs')
                                .remove([path]);
                          } catch (_) {}
                        }
                        if (dialogContext.mounted) {
                          setDialog(() => sending = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error.message)),
                          );
                        }
                      } catch (error) {
                        if (path != null) {
                          try {
                            await _client.storage
                                .from('smartblock-manager-proofs')
                                .remove([path]);
                          } catch (_) {}
                        }
                        if (dialogContext.mounted) {
                          setDialog(() => sending = false);
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text(error.toString())),
                          );
                        }
                      }
                    },
              child: sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_greek ? 'Υποβολή' : 'Submit request'),
            ),
          ],
        ),
      ),
    );
    authority.dispose();
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _greek
                ? 'Το αίτημα στάλθηκε. Ο admin θα ελέγξει το αποδεικτικό και θα εγκρίνει έναν διαχειριστή.'
                : 'Request sent. An admin will verify the proof and approve one manager.',
          ),
        ),
      );
    }
  }

  String? _required(String? value) => value == null || value.trim().isEmpty
      ? (_greek ? 'Υποχρεωτικό πεδίο.' : 'Required field.')
      : null;

  String _propertyTypeLabel(String? type, String? otherDescription) {
    if (type == 'other' && (otherDescription ?? '').trim().isNotEmpty) {
      return otherDescription!.trim();
    }
    const greek = {
      'apartment': 'Διαμέρισμα',
      'building': 'Πολυκατοικία',
      'house': 'Κατοικία',
      'shop': 'Κατάστημα',
      'office': 'Γραφείο',
      'warehouse': 'Αποθήκη',
      'land': 'Οικόπεδο',
      'other': 'Άλλο ακίνητο',
    };
    const english = {
      'apartment': 'Apartment',
      'building': 'Apartment building',
      'house': 'House',
      'shop': 'Shop',
      'office': 'Office',
      'warehouse': 'Warehouse',
      'land': 'Land',
      'other': 'Other property',
    };
    return (_greek ? greek : english)[type] ?? (type ?? '');
  }

  String _approvalLabel(String? status) {
    if (!_greek) return (status ?? 'unknown').replaceAll('_', ' ');
    const labels = {
      'draft': 'Πρόχειρο',
      'pending_review': 'Σε αναμονή ελέγχου',
      'under_review': 'Υπό έλεγχο',
      'changes_required': 'Χρειάζονται αλλαγές',
      'approved': 'Εγκεκριμένο',
      'rejected': 'Απορρίφθηκε',
      'suspended': 'Σε αναστολή',
    };
    return labels[status] ?? 'Άγνωστη κατάσταση';
  }

  DropdownMenuItem<String> _option(String value, String label) =>
      DropdownMenuItem(value: value, child: Text(label));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.organizationName ??
            (widget.viewMode == PropertiesViewMode.resident
                ? (_greek ? 'Το διαμέρισμά μου' : 'My apartment')
                : (_greek ? 'Τα ακίνητά μου' : 'My properties')),
      ),
      actions: [
        const SmartBlockLanguageMenu(),
        FutureBuilder<dynamic>(
          future: _client.rpc('is_smartblock_staff'),
          builder: (context, snapshot) => snapshot.data == true
              ? IconButton(
                  tooltip: _greek
                      ? 'Κέντρο διαχείρισης'
                      : 'Admin control center',
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AdminReviewScreen(isGreek: _greek),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        IconButton(
          tooltip: _greek ? 'Αποσύνδεση' : 'Sign out',
          onPressed: () async => _client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    floatingActionButton: widget.viewMode == PropertiesViewMode.resident
        ? null
        : FloatingActionButton.extended(
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
                widget.viewMode == PropertiesViewMode.resident
                    ? (_greek ? 'Το ακίνητό σου' : 'Your property')
                    : (_greek ? 'Ακίνητα' : 'Properties'),
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _greek
                    ? 'Άνοιξε ένα ακίνητο για να δεις τους ιδιοκτήτες, τις ψηφοφορίες, τις ανακοινώσεις και τα οικονομικά του.'
                    : 'Open a property to see its owners, votes, notices and finances.',
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
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: Text(
                      _greek
                          ? 'Δεν φορτώθηκαν τα ακίνητα'
                          : 'Properties could not be loaded',
                    ),
                    subtitle: Text(
                      _greek
                          ? 'Έλεγξε τη σύνδεση και δοκίμασε ξανά.'
                          : 'Check your connection and try again.',
                    ),
                    trailing: IconButton(
                      tooltip: _greek ? 'Δοκιμή ξανά' : 'Try again',
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh),
                    ),
                  ),
                )
              else if (properties.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.apartment_outlined,
                          size: 42,
                          color: Color(0xFF176B87),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.viewMode == PropertiesViewMode.resident
                              ? (_greek
                                    ? 'Δεν έχει συνδεθεί ακόμη διαμέρισμα στον λογαριασμό σου.'
                                    : 'No apartment has been assigned to your account yet.')
                              : (_greek
                                    ? 'Ξεκίνα με το πρώτο σου ακίνητο'
                                    : 'Start with your first property'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (widget.viewMode == PropertiesViewMode.resident)
                          Text(
                            _greek
                                ? 'Ζήτησε από τον διαχειριστή να συνδέσει το email του λογαριασμού σου με το διαμέρισμά σου.'
                                : 'Ask your building manager to assign your account email to your apartment.',
                            textAlign: TextAlign.center,
                          )
                        else ...[
                          Text(
                            _greek
                                ? 'Πρόσθεσε διαμέρισμα ή πολυκατοικία. Έπειτα θα καταχωρίσεις τους ιδιοκτήτες μέσα στο ακίνητο.'
                                : 'Add an apartment or building. You can add its owners from the property page.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _createProperty,
                            icon: const Icon(Icons.add_home_work_outlined),
                            label: Text(
                              _greek ? 'Προσθήκη ακινήτου' : 'Add property',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              else
                ...properties.map(
                  (p) => Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primaryContainer,
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(
                          _propertyIcon(
                            p['property_type'] as String?,
                            resident: p['_resident_only'] == true,
                          ),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(p['name'] as String? ?? ''),
                      subtitle: Text(
                        p['_resident_only'] == true
                            ? [
                                    _greek
                                        ? 'Διαμέρισμα ${p['_resident_apartment_number']}'
                                        : 'Apartment ${p['_resident_apartment_number']}',
                                    p['address'],
                                    p['city'],
                                  ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · ')
                            : [
                                    _propertyTypeLabel(
                                      p['property_type'] as String?,
                                      p['other_description'] as String?,
                                    ),
                                    p['address'],
                                    p['city'],
                                    (p['total_apartments'] == null
                                        ? null
                                        : '${p['total_apartments']} ${_greek ? 'διαμερίσματα' : 'apartments'}'),
                                    _approvalLabel(
                                      p['approval_status'] as String?,
                                    ),
                                  ]
                                  .whereType<String>()
                                  .where((s) => s.isNotEmpty)
                                  .join(' · '),
                      ),
                      trailing: Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      onTap: () async {
                        if (p['_resident_only'] == true) {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => ResidentServiceRequestsScreen(
                                propertyId: p['id'] as String,
                                propertyName: p['name'] as String? ?? '',
                                apartmentNumber:
                                    p['_resident_apartment_number'] as String,
                                isGreek: _greek,
                              ),
                            ),
                          );
                          await _refresh();
                          return;
                        }
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
