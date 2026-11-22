import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide Text;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../app_language.dart';
import '../smartblock_text.dart';

class PropertyOwnersScreen extends StatefulWidget {
  const PropertyOwnersScreen({
    required this.propertyId,
    required this.propertyName,
    this.organizationId,
    required this.isGreek,
    super.key,
  });
  final String propertyId;
  final String propertyName;
  final String? organizationId;
  final bool isGreek;
  @override
  State<PropertyOwnersScreen> createState() => _PropertyOwnersScreenState();
}

class _PropertyOwnersScreenState extends State<PropertyOwnersScreen> {
  final _db = Supabase.instance.client;
  final _picker = ImagePicker();
  late Future<List<Map<String, dynamic>>> _future;
  late bool _greek;
  bool _isAdmin = false;
  bool _isPropertyCreator = false;
  bool _isPropertyManager = false;
  int? _totalApartments;
  Set<String> _manageableOrganizations = {};
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
    _future = _load();
    _loadAccess();
  }

  @override
  void dispose() {
    SmartBlockLanguageController.instance.selected.removeListener(_languageListener);
    super.dispose();
  }

  Future<void> _loadAccess() async {
    try {
      final isAdmin = await _db.rpc('is_smartblock_admin');
      final manageableOrganizations = await _db.rpc('my_manageable_organization_ids');
      final property = await _db
          .from('properties')
          .select('created_by, total_apartments, manager_user_id')
          .eq('id', widget.propertyId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin == true;
          _manageableOrganizations = (manageableOrganizations as List)
              .map((v) => v.toString())
              .toSet();
          _isPropertyCreator = property?['created_by'] == _db.auth.currentUser?.id;
          _isPropertyManager = property?['manager_user_id'] == _db.auth.currentUser?.id;
          _totalApartments = (property?['total_apartments'] as num?)?.toInt();
        });
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final owners = List<Map<String, dynamic>>.from(
      await _db
          .from('property_owners')
          .select(
            'id, organization_id, ownership_percentage, apartment_count, area_sqm, title_deed_photo_path, area_declaration_confirmed_at, is_primary_representative, ownership_status, organizations(display_name, phone_e164, approval_status)',
          )
          .eq('property_id', widget.propertyId)
          .order('created_at'),
    );
    List<Map<String, dynamic>> accountLinks = [];
    var accountLinksKnown = true;
    try {
      accountLinks = List<Map<String, dynamic>>.from(await _db.rpc(
        'list_property_owner_account_links',
        params: {'p_property_id': widget.propertyId},
      ));
    } catch (_) {
      // Non-managers can still see the owner roster without private account details.
      accountLinksKnown = false;
    }
    return owners.map((owner) {
      final ownerId = owner['id'].toString();
      return {
        ...owner,
        '_account_links_known': accountLinksKnown,
        'registered_accounts': accountLinks
            .where((link) => link['owner_id'].toString() == ownerId)
            .toList(),
      };
    }).toList();
  }

  Future<void> _linkRegisteredAccount(Map<String, dynamic> owner) async {
    final searchController = TextEditingController();
    var accounts = <Map<String, dynamic>>[];
    var searching = false;
    var hasSearched = false;
    var searchVersion = 0;
    Timer? searchDebounce;
    var dialogOpen = true;
    String? searchError;
    String? selectedUserId;
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialog) {
          Future<void> searchAccounts() async {
            searchDebounce?.cancel();
            final requestVersion = ++searchVersion;
            final query = searchController.text.trim();
            if (query.length < 3) {
              setDialog(() {
                searchError = _greek
                    ? 'Γράψε τουλάχιστον 3 χαρακτήρες.'
                    : 'Enter at least 3 characters.';
                accounts = [];
                searching = false;
                hasSearched = false;
              });
              return;
            }
            setDialog(() {
              searching = true;
              searchError = null;
              selectedUserId = null;
            });
            try {
              final result = await _db.rpc(
                'list_registered_property_owner_accounts',
                params: {
                  'p_property_id': widget.propertyId,
                  'p_search': query,
                },
              );
              if (dialogOpen && requestVersion == searchVersion) {
                setDialog(() {
                  accounts = List<Map<String, dynamic>>.from(result);
                  hasSearched = true;
                });
              }
            } on PostgrestException catch (error) {
              if (requestVersion == searchVersion) {
                setDialog(() {
                  searchError = error.message;
                  accounts = [];
                  hasSearched = true;
                });
              }
            } finally {
              if (requestVersion == searchVersion) {
                setDialog(() => searching = false);
              }
            }
          }

          return AlertDialog(
            title: Text(_greek
                ? 'Σύνδεση με εγγεγραμμένο ιδιοκτήτη'
                : 'Link a registered owner'),
            content: SizedBox(
              width: 460,
              height: 430,
              child: Column(
                children: [
                  Text(_greek
                      ? 'Πληκτρολόγησε τα πρώτα 3 γράμματα του email για να εμφανιστούν σχετικά αποτελέσματα αυτόματα. Μπορείς επίσης να ψάξεις με όνομα ή τηλέφωνο. Εμφανίζονται μόνο εγκεκριμένοι ιδιοκτήτες.'
                      : 'Type the first 3 characters of the email to see matching accounts automatically. You can also search by name or phone. Only approved owners are shown.'),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        autofocus: true,
                        onChanged: (value) {
                          searchDebounce?.cancel();
                          searchVersion++;
                          selectedUserId = null;
                          final query = value.trim();
                          setDialog(() {
                            searchError = null;
                            accounts = [];
                            hasSearched = false;
                            searching = query.length >= 3;
                          });
                          if (query.length >= 3) {
                            searchDebounce = Timer(
                              const Duration(milliseconds: 350),
                              searchAccounts,
                            );
                          }
                        },
                        onSubmitted: (_) => searchAccounts(),
                        decoration: InputDecoration(
                          labelText: _greek
                              ? 'Αρχικά email, όνομα ή τηλέφωνο'
                              : 'Email prefix, name or phone',
                          hintText: _greek
                              ? 'π.χ. lef'
                              : 'e.g. joh',
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _greek ? 'Αναζήτηση' : 'Search',
                      onPressed: searching ? null : searchAccounts,
                      icon: const Icon(Icons.search),
                    ),
                  ]),
                  if (searchError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(searchError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: searching
                        ? const Center(child: CircularProgressIndicator())
                        : !hasSearched
                            ? Center(
                                child: Text(_greek
                                    ? 'Ο ιδιοκτήτης πρέπει να έχει εγγραφεί ως ιδιοκτήτης και να έχει εγκριθεί από το SmartBlock.'
                                    : 'The owner must sign up as an owner and be approved by SmartBlock.'),
                              )
                            : accounts.isEmpty
                                ? Center(
                                    child: Text(_greek
                                        ? 'Δεν βρέθηκαν εγκεκριμένοι ιδιοκτήτες.'
                                        : 'No approved owner accounts matched.'),
                                  )
                                : ListView.builder(
                                    itemCount: accounts.length,
                                    itemBuilder: (context, index) {
                                      final account = accounts[index];
                                      final userId =
                                          account['user_id'].toString();
                                      final fullName =
                                          (account['full_name'] as String?)
                                                  ?.trim() ??
                                              '';
                                      final email =
                                          account['email'] as String? ?? '';
                                      final phone =
                                          account['phone'] as String? ?? '';
                                      return ListTile(
                                        selected: selectedUserId == userId,
                                        leading: Icon(selectedUserId == userId
                                            ? Icons.radio_button_checked
                                            : Icons.radio_button_off),
                                        title: Text(
                                            fullName.isEmpty ? email : fullName),
                                        subtitle: Text([
                                          email,
                                          if (phone.isNotEmpty) phone,
                                        ].join(' · ')),
                                        onTap: () => setDialog(
                                            () => selectedUserId = userId),
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
                onPressed: selectedUserId == null
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          accounts.firstWhere((account) =>
                              account['user_id'].toString() == selectedUserId),
                        ),
                child: Text(_greek ? 'Σύνδεση' : 'Link account'),
              ),
            ],
          );
        },
      ),
    );
    dialogOpen = false;
    searchDebounce?.cancel();
    searchVersion++;
    searchController.dispose();
    if (selected == null) return;
    try {
      await _db.rpc('link_property_owner_account', params: {
        'p_owner_id': owner['id'],
        'p_user_id': selected['user_id'],
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_greek
              ? 'Ο ιδιοκτήτης συνδέθηκε με τον λογαριασμό.'
              : 'Owner linked to the account.'),
        ));
        await _refresh();
      }
    } on PostgrestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  Future<XFile?> _pickDeed() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(_greek ? 'Λήψη φωτογραφίας' : 'Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(_greek ? 'Επιλογή φωτογραφίας' : 'Choose a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (source == null) return null;
    return _picker.pickImage(source: source, imageQuality: 86, maxWidth: 2200);
  }

  String _extension(XFile file) {
    final type = file.mimeType?.toLowerCase();
    if (type == 'image/png') return 'png';
    if (type == 'image/webp') return 'webp';
    final byName = file.name.split('.').last.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp'].contains(byName) ? byName : 'jpg';
  }

  Future<void> _saveDeedDeclaration({
    required String ownerId,
    required int apartmentCount,
    required double area,
    required XFile photo,
    bool removeUploadOnFailure = false,
  }) async {
    final Uint8List bytes = await photo.readAsBytes();
    if (bytes.length > 10 * 1024 * 1024) {
      throw Exception(_greek
          ? 'Η φωτογραφία πρέπει να είναι μικρότερη από 10 MB.'
          : 'The photo must be smaller than 10 MB.');
    }
    final path = '${widget.propertyId}/$ownerId/deed.${_extension(photo)}';
    final contentType = photo.mimeType ?? switch (_extension(photo)) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _db.storage.from('smartblock-title-deeds').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    try {
      await _db.rpc('save_property_owner_area_declaration', params: {
        'p_owner_id': ownerId,
        'p_apartment_count': apartmentCount,
        'p_area_sqm': area,
        'p_title_deed_photo_path': path,
      });
    } catch (_) {
      if (removeUploadOnFailure) {
        try { await _db.storage.from('smartblock-title-deeds').remove([path]); } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> _addOwner() async {
    final phone = TextEditingController();
    final name = TextEditingController();
    final apartments = TextEditingController();
    final area = TextEditingController();
    final form = GlobalKey<FormState>();
    var orgType = 'individual';
    var primary = false;
    var confirmed = false;
    XFile? photo;
    var saving = false;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(_greek ? 'Προσθήκη ιδιοκτήτη' : 'Add owner'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: _greek ? 'Τηλέφωνο ιδιοκτήτη' : 'Owner phone',
                      hintText: '+35799123456',
                    ),
                    validator: (v) => v == null ||
                            !RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(v.trim())
                        ? (_greek ? 'Χρησιμοποίησε μορφή +357…' : 'Use international format, e.g. +357…')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: name,
                    decoration: InputDecoration(
                      labelText: _greek ? 'Ονοματεπώνυμο / οργανισμός' : 'Owner / organization name',
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? (_greek ? 'Συμπλήρωσε το όνομα.' : 'Enter the owner name.')
                        : null,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: orgType,
                    decoration: InputDecoration(labelText: _greek ? 'Τύπος' : 'Type'),
                    items: [
                      DropdownMenuItem(value: 'individual', child: Text(_greek ? 'Ιδιώτης' : 'Individual')),
                      DropdownMenuItem(value: 'company', child: Text(_greek ? 'Εταιρεία / οργανισμός' : 'Company / organization')),
                    ],
                    onChanged: (v) { if (v != null) setDialog(() => orgType = v); },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: apartments,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: _greek ? 'Διαμερίσματα που κατέχει' : 'Apartments owned'),
                    validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1
                        ? (_greek ? 'Βάλε τουλάχιστον 1.' : 'Enter at least 1.') : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: area,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: _greek ? 'Συνολικά τετραγωνικά' : 'Total area', suffixText: 'm²'),
                    validator: (v) {
                      final n = double.tryParse((v ?? '').replaceAll(',', '.'));
                      return n == null || n <= 0 ? (_greek ? 'Βάλε έγκυρα τετραγωνικά.' : 'Enter a valid area.') : null;
                    },
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: saving ? null : () async {
                      try {
                        final picked = await _pickDeed();
                        if (picked != null) setDialog(() => photo = picked);
                      } catch (e) {
                        if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.toString())));
                      }
                    },
                    icon: Icon(photo == null ? Icons.add_a_photo_outlined : Icons.check_circle_outline),
                    label: Text(photo?.name ?? (_greek ? 'Φωτογραφία τίτλου εγγραφής' : 'Title deed photo')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: confirmed,
                    onChanged: (v) => setDialog(() => confirmed = v ?? false),
                    title: Text(_greek ? 'Επιβεβαιώνω ότι τα τετραγωνικά συμφωνούν με τον τίτλο' : 'I confirm the area matches the title deed'),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: primary,
                    onChanged: (v) => setDialog(() => primary = v ?? false),
                    title: Text(_greek ? 'Κύριος εκπρόσωπος' : 'Primary representative'),
                  ),
                  Text(
                    _greek ? 'Το ποσοστό ιδιοκτησίας θα υπολογιστεί αυτόματα από τα τετραγωνικά όλων των ιδιοκτητών.' : 'Ownership share is calculated from this area and the total area of all owners.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ]),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(_greek ? 'Άκυρο' : 'Cancel')),
            FilledButton(
              onPressed: saving ? null : () async {
                if (!form.currentState!.validate()) return;
                if (photo == null || !confirmed) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(_greek ? 'Πρόσθεσε φωτογραφία και επιβεβαίωσε τα τετραγωνικά.' : 'Add a photo and confirm the area.')));
                  return;
                }
                setDialog(() => saving = true);
                String? ownerId;
                try {
                  final result = await _db.rpc('create_property_owner_registration', params: {
                    'p_property_id': widget.propertyId,
                    'p_phone_e164': phone.text.trim(),
                    'p_display_name': name.text.trim(),
                    'p_organization_type': orgType,
                    'p_is_primary_representative': primary,
                  });
                  ownerId = (result as Map)['owner_id'].toString();
                  await _saveDeedDeclaration(
                    ownerId: ownerId,
                    apartmentCount: int.parse(apartments.text.trim()),
                    area: double.parse(area.text.replaceAll(',', '.')),
                    photo: photo!,
                    removeUploadOnFailure: true,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (ownerId != null) {
                    try { await _db.rpc('rollback_property_owner_registration', params: {'p_owner_id': ownerId}); } catch (_) {}
                  }
                  if (ctx.mounted) {
                    setDialog(() => saving = false);
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : e.toString())));
                  }
                }
              },
              child: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_greek ? 'Αποθήκευση ιδιοκτήτη' : 'Save owner'),
            ),
          ],
        ),
      ),
    );
    phone.dispose(); name.dispose(); apartments.dispose(); area.dispose();
    if (added == true && mounted) await _refresh();
  }

  Future<void> _declareArea(Map<String, dynamic> owner) async {
    final apartments = TextEditingController(text: '${owner['apartment_count'] ?? ''}');
    final area = TextEditingController(text: '${owner['area_sqm'] ?? ''}');
    final form = GlobalKey<FormState>();
    XFile? photo;
    var confirmed = false;
    var saving = false;
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text(_greek ? 'Δήλωση τετραγωνικών' : 'Area declaration'),
        content: SizedBox(width: 420, child: Form(key: form, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(controller: apartments, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _greek ? 'Διαμερίσματα' : 'Apartments'), validator: (v) => (int.tryParse((v ?? '').trim()) ?? 0) < 1 ? (_greek ? 'Βάλε τουλάχιστον 1.' : 'Enter at least 1.') : null),
          TextFormField(controller: area, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: _greek ? 'Συνολικά τετραγωνικά' : 'Total area', suffixText: 'm²'), validator: (v) { final n = double.tryParse((v ?? '').replaceAll(',', '.')); return n == null || n <= 0 ? (_greek ? 'Βάλε έγκυρα τετραγωνικά.' : 'Enter a valid area.') : null; }),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: saving ? null : () async { final picked = await _pickDeed(); if (picked != null) setDialog(() => photo = picked); }, icon: Icon(photo == null ? Icons.add_a_photo_outlined : Icons.check_circle), label: Text(photo?.name ?? (_greek ? 'Νέα φωτογραφία τίτλου' : 'New title deed photo'))),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: confirmed, onChanged: (v) => setDialog(() => confirmed = v ?? false), title: Text(_greek ? 'Επιβεβαιώνω τα τετραγωνικά βάσει τίτλου' : 'I confirm the area matches the title deed')),
        ])))),
        actions: [
          TextButton(onPressed: saving ? null : () => Navigator.pop(ctx, false), child: Text(_greek ? 'Άκυρο' : 'Cancel')),
          FilledButton(onPressed: saving ? null : () async {
            if (!form.currentState!.validate() || photo == null || !confirmed) { ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(_greek ? 'Συμπλήρωσε τα στοιχεία, βάλε φωτογραφία και επιβεβαίωσε.' : 'Complete the fields, add a photo and confirm.'))); return; }
            setDialog(() => saving = true);
            try {
              await _saveDeedDeclaration(ownerId: owner['id'].toString(), apartmentCount: int.parse(apartments.text.trim()), area: double.parse(area.text.replaceAll(',', '.')), photo: photo!);
              if (ctx.mounted) Navigator.pop(ctx, true);
            } catch (e) { if (ctx.mounted) { setDialog(() => saving = false); ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : e.toString()))); } }
          }, child: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_greek ? 'Αποθήκευση' : 'Save')),
        ],
      ),
    ));
    apartments.dispose(); area.dispose();
    if (saved == true && mounted) await _refresh();
  }

  Future<void> _viewDeed(String path) async {
    try {
      final url = await _db.storage.from('smartblock-title-deeds').createSignedUrl(path, 300);
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (ctx) => AlertDialog(
        title: Text(_greek ? 'Τίτλος εγγραφής' : 'Title deed'),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600), child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_greek ? 'Κλείσιμο' : 'Close'))],
      ));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e is PostgrestException ? e.message : e.toString()))); }
  }

  Future<void> _manageOwner(Map<String, dynamic> owner) async {
    var status = owner['ownership_status'] as String? ?? 'active';
    var primary = owner['is_primary_representative'] == true;
    final save = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text(_greek ? 'Διαχείριση ιδιοκτησίας' : 'Manage ownership'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: status, decoration: InputDecoration(labelText: _greek ? 'Κατάσταση' : 'Status'), items: ['active', 'transferred', 'inactive'].map((s) => DropdownMenuItem(value: s, child: Text(switch (s) { 'active' => _greek ? 'Ενεργή' : 'Active', 'transferred' => _greek ? 'Μεταβιβάστηκε' : 'Transferred', _ => _greek ? 'Ανενεργή' : 'Inactive' }))).toList(), onChanged: (v) { if (v != null) setDialog(() => status = v); }),
        SwitchListTile(title: Text(_greek ? 'Κύριος εκπρόσωπος' : 'Primary representative'), value: primary, onChanged: (v) => setDialog(() => primary = v)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_greek ? 'Άκυρο' : 'Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_greek ? 'Αποθήκευση' : 'Save'))],
    )));
    if (save != true) return;
    try {
      await _db.from('property_owners').update({'ownership_status': status, 'is_primary_representative': primary, 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', owner['id']);
      await _refresh();
    } on PostgrestException catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message))); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_greek ? 'Ιδιοκτήτες' : 'Owners'), actions: [const SmartBlockLanguageMenu()]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _addOwner, icon: const Icon(Icons.person_add_alt_1), label: Text(_greek ? 'Προσθήκη ιδιοκτήτη' : 'Add owner')),
    body: RefreshIndicator(onRefresh: _refresh, child: FutureBuilder<List<Map<String, dynamic>>>(future: _future, builder: (ctx, snap) {
      final owners = snap.data ?? [];
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text(snap.error.toString()))]);
      final activeOwners = owners.where((owner) => owner['ownership_status'] == 'active').toList();
      final allDeclared = activeOwners.isNotEmpty && activeOwners.every((owner) => owner['area_sqm'] != null && owner['title_deed_photo_path'] != null && owner['area_declaration_confirmed_at'] != null);
      final declaredApartments = activeOwners.fold<int>(0, (sum, owner) => sum + ((owner['apartment_count'] as num?)?.toInt() ?? 0));
      final sharesReady = allDeclared && (_totalApartments == null || declaredApartments == _totalApartments);
      return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(16), children: [
        Text(widget.propertyName, style: Theme.of(ctx).textTheme.titleLarge),
        Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_greek ? 'Το ποσοστό υπολογίζεται αυτόματα: τετραγωνικά ιδιοκτήτη ÷ συνολικά δηλωμένα τετραγωνικά.' : 'Share is calculated automatically: owner area ÷ total declared area.')),
        if (owners.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Text(_greek ? 'Δεν έχει προστεθεί ιδιοκτήτης.' : 'No owners have been added.')),
        ...owners.map((owner) {
          final org = owner['organizations'] as Map<String, dynamic>? ?? {};
          final area = (owner['area_sqm'] as num?)?.toDouble();
          final share = (owner['ownership_percentage'] as num?)?.toDouble() ?? 0;
          final orgId = owner['organization_id']?.toString();
          final canManage = _isAdmin || _isPropertyCreator || _isPropertyManager || _manageableOrganizations.contains(orgId);
          final deed = owner['title_deed_photo_path'] as String?;
          final declarationDone = area != null && deed != null && owner['area_declaration_confirmed_at'] != null;
          final accountLinksKnown = owner['_account_links_known'] == true;
          final registeredAccounts = List<Map<String, dynamic>>.from(
              (owner['registered_accounts'] as List?) ?? const []);
          final linkedAccountLabel = registeredAccounts.map((account) {
            final fullName = (account['full_name'] as String?)?.trim() ?? '';
            final email = account['email'] as String? ?? '';
            return fullName.isEmpty ? email : '$fullName · $email';
          }).join(', ');
          return Card(child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 8), leading: Icon(owner['is_primary_representative'] == true ? Icons.verified_user_outlined : Icons.person_outline), title: Text(org['display_name'] as String? ?? ''), subtitle: Text('${org['phone_e164'] ?? ''} · ${switch (owner['ownership_status']) { 'active' => _greek ? 'Ενεργός' : 'Active', 'transferred' => _greek ? 'Μεταβιβάστηκε' : 'Transferred', _ => _greek ? 'Ανενεργός' : 'Inactive' }}'), trailing: _isAdmin ? PopupMenuButton<String>(onSelected: (action) { if (action == 'edit') _manageOwner(owner); }, itemBuilder: (ctx) => [PopupMenuItem(value: 'edit', child: Text(_greek ? 'Επεξεργασία' : 'Edit'))]) : (org['approval_status'] == 'approved' ? const Icon(Icons.verified_outlined) : const Icon(Icons.hourglass_top))),
            if (accountLinksKnown || canManage)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Icon(!accountLinksKnown
                      ? Icons.lock_outline
                      : registeredAccounts.isEmpty
                          ? Icons.person_add_alt_1_outlined
                          : Icons.verified_user_outlined,
                      size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(!accountLinksKnown
                      ? (_greek
                          ? 'Η κατάσταση σύνδεσης λογαριασμού είναι ιδιωτική'
                          : 'Account link status is private')
                      : registeredAccounts.isEmpty
                          ? (_greek
                              ? 'Δεν έχει συνδεθεί εγγεγραμμένος λογαριασμός'
                              : 'No registered account linked')
                          : '${_greek ? 'Λογαριασμός' : 'Account'}: $linkedAccountLabel')),
                ]),
              ),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('${owner['apartment_count'] ?? '—'} ${_greek ? 'διαμερίσματα' : 'apartments'} · ${area == null ? '—' : area.toStringAsFixed(2)} m² · ${!sharesReady ? (_greek ? 'ποσοστό σε εκκρεμότητα' : 'share pending') : '${share.toStringAsFixed(2)}%'}')),
            Wrap(spacing: 8, children: [
              if (canManage && registeredAccounts.isEmpty)
                TextButton.icon(
                  onPressed: () => _linkRegisteredAccount(owner),
                  icon: const Icon(Icons.link),
                  label: Text(_greek ? 'Σύνδεση εγγραφής' : 'Link registration'),
                ),
              if (canManage) TextButton.icon(onPressed: () => _declareArea(owner), icon: const Icon(Icons.edit_note), label: Text(declarationDone ? (_greek ? 'Ενημέρωση στοιχείων' : 'Update declaration') : (_greek ? 'Δήλωση τετραγωνικών' : 'Declare area'))),
              if (canManage && deed != null) TextButton.icon(onPressed: () => _viewDeed(deed), icon: const Icon(Icons.description_outlined), label: Text(_greek ? 'Προβολή τίτλου' : 'View deed')),
            ]),
          ])));
        }),
      ]);
    })),
  );
}


