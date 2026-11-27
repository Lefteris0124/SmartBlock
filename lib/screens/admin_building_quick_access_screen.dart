import 'package:flutter/material.dart' hide Text;

import '../smartblock_trial_session.dart';
import '../smartblock_text.dart';
import 'property_modules_screen.dart';

class AdminBuildingQuickAccessScreen extends StatefulWidget {
  const AdminBuildingQuickAccessScreen({required this.isGreek, super.key});

  final bool isGreek;

  @override
  State<AdminBuildingQuickAccessScreen> createState() =>
      _AdminBuildingQuickAccessScreenState();
}

class _AdminBuildingQuickAccessScreenState
    extends State<AdminBuildingQuickAccessScreen> {
  final _client = SmartBlockTrialSession.client;
  final _search = TextEditingController();
  late Future<List<Map<String, dynamic>>> _properties;

  bool get _gr => widget.isGreek;

  @override
  void initState() {
    super.initState();
    _properties = _loadProperties();
    _search.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadProperties() async {
    final byId = <String, Map<String, dynamic>>{};
    final rows = List<Map<String, dynamic>>.from(
      await _client
          .from('properties')
          .select('id,name,address,city')
          .order('name'),
    );
    for (final row in rows) {
      byId[row['id'].toString()] = row;
    }
    try {
      final residentRows = List<Map<String, dynamic>>.from(
        await _client.rpc('list_my_resident_properties'),
      );
      for (final row in residentRows) {
        final id = row['property_id']?.toString();
        if (id == null) continue;
        byId.putIfAbsent(id, () => {
          'id': id,
          'name': row['property_name'] ?? (_gr ? 'Πολυκατοικία' : 'Building'),
          'address': row['property_address'],
          'city': row['property_city'],
        });
      }
    } catch (_) {}
    final userId = _client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final unread = List<Map<String, dynamic>>.from(
          await _client
              .from('user_notifications')
              .select('property_id,notification_type')
              .eq('user_id', userId)
              .eq('is_read', false)
              .inFilter('notification_type', [
                'vote',
                'announcement',
                'community_update',
              ]),
        );
        for (final row in unread) {
          final property = byId[row['property_id']?.toString()];
          if (property == null) continue;
          final key = switch (row['notification_type']) {
            'vote' => '_unread_votes',
            'announcement' => '_unread_announcements',
            _ => '_unread_updates',
          };
          property[key] = ((property[key] as int?) ?? 0) + 1;
        }
      } catch (_) {}
    }
    for (final property in byId.values) {
      property['_unread_votes'] ??= 0;
      property['_unread_announcements'] ??= 0;
      property['_unread_updates'] ??= 0;
    }
    final result = byId.values.toList()
      ..sort((a, b) => (a['name'] ?? '')
          .toString()
          .toLowerCase()
          .compareTo((b['name'] ?? '').toString().toLowerCase()));
    return result;
  }

  Future<void> _openPropertyModule(
    Map<String, dynamic> property,
    int tab,
  ) async {
    final propertyId = property['id'].toString();
    final userId = _client.auth.currentUser?.id;
    if (userId != null && (tab == 0 || tab == 1 || tab == 2)) {
      try {
        await _client
            .from('user_notifications')
            .update({'is_read': true})
            .eq('user_id', userId)
            .eq('property_id', propertyId)
            .eq('is_read', false)
            .inFilter(
              'notification_type',
              switch (tab) {
                0 => ['vote'],
                1 => ['announcement'],
                _ => ['community_update'],
              },
            );
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PropertyModulesScreen(
          propertyId: propertyId,
          propertyName: (property['name'] ??
                  (_gr ? 'Πολυκατοικία' : 'Building'))
              .toString(),
          isGreek: _gr,
          initialTab: tab,
        ),
      ),
    );
    if (mounted) setState(() => _properties = _loadProperties());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(_gr ? 'Πολυκατοικίες' : 'Buildings'),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _properties,
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
                      Text(_gr
                          ? 'Δεν φορτώθηκε η λίστα πολυκατοικιών.'
                          : 'Could not load the building list.'),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () =>
                            setState(() => _properties = _loadProperties()),
                        child: Text(_gr ? 'Δοκίμασε ξανά' : 'Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final all = snapshot.data ?? const [];
            final query = _search.text.trim().toLowerCase();
            final filtered = all.where((property) {
              if (query.isEmpty) return true;
              final searchable = [
                property['name'],
                property['address'],
                property['city'],
              ].whereType<Object>().join(' ').toLowerCase();
              return searchable.contains(query);
            }).toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: _gr
                          ? 'Αναζήτηση με όνομα ή διεύθυνση'
                          : 'Search by name or address',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: _gr ? 'Καθαρισμός' : 'Clear',
                              onPressed: _search.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _gr
                          ? '${filtered.length} από ${all.length} πολυκατοικίες'
                          : '${filtered.length} of ${all.length} buildings',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(query.isEmpty
                                ? (_gr
                                    ? 'Δεν υπάρχουν διαθέσιμες πολυκατοικίες.'
                                    : 'No buildings are available.')
                                : (_gr
                                    ? 'Δεν βρέθηκε πολυκατοικία με αυτά τα στοιχεία.'
                                    : 'No building matched your search.')),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final property = filtered[index];
                            final name = (property['name'] ??
                                    (_gr ? 'Πολυκατοικία' : 'Building'))
                                .toString();
                            final address = [
                              property['address'],
                              property['city'],
                            ]
                                .where((part) =>
                                    part != null &&
                                    part.toString().trim().isNotEmpty)
                                .join(', ');
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: const Icon(
                                          Icons.apartment_rounded),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                      subtitle: address.isEmpty
                                          ? null
                                          : Text(address),
                                    ),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        ActionChip(
                                          avatar: Badge(
                                            backgroundColor: Colors.red,
                                            isLabelVisible:
                                                (property['_unread_votes'] as int? ?? 0) > 0,
                                            label: Text(
                                              (property['_unread_votes'] as int? ?? 0) > 9
                                                  ? '9+'
                                                  : '${property['_unread_votes'] ?? 0}',
                                            ),
                                            child: const Icon(
                                                Icons.how_to_vote_outlined,
                                                size: 18),
                                          ),
                                          label:
                                              Text(_gr ? 'Ψηφοφορίες' : 'Votes'),
                                          onPressed: () =>
                                              _openPropertyModule(property, 0),
                                        ),
                                        ActionChip(
                                          avatar: Badge(
                                            backgroundColor: Colors.red,
                                            isLabelVisible:
                                                (property['_unread_announcements'] as int? ?? 0) > 0,
                                            label: Text(
                                              (property['_unread_announcements'] as int? ?? 0) > 9
                                                  ? '9+'
                                                  : '${property['_unread_announcements'] ?? 0}',
                                            ),
                                            child: const Icon(Icons.campaign_outlined, size: 18),
                                          ),
                                          label: Text(_gr ? 'Ανακοινώσεις' : 'Announcements'),
                                          onPressed: () => _openPropertyModule(property, 1),
                                        ),
                                        ActionChip(
                                          avatar: Badge(
                                            backgroundColor: Colors.red,
                                            isLabelVisible:
                                                (property['_unread_updates'] as int? ?? 0) > 0,
                                            label: Text(
                                              (property['_unread_updates'] as int? ?? 0) > 9
                                                  ? '9+'
                                                  : '${property['_unread_updates'] ?? 0}',
                                            ),
                                            child: const Icon(Icons.chat_bubble_outline, size: 18),
                                          ),
                                          label: Text(_gr ? 'Ενημερώσεις' : 'Updates'),
                                          onPressed: () => _openPropertyModule(property, 2),
                                        ),
                                        ActionChip(
                                          avatar: const Icon(Icons.receipt_long_outlined, size: 18),
                                          label: Text(_gr
                                              ? 'Λογιστική κατάσταση'
                                              : 'Accounting statement'),
                                          onPressed: () => _openPropertyModule(property, 5),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      );
}
