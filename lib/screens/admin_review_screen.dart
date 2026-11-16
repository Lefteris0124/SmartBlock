import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({required this.isGreek, super.key});
  final bool isGreek;
  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> {
  final db = Supabase.instance.client;
  bool get gr => widget.isGreek;

  Future<List<Map<String, dynamic>>> load(String table) async =>
      List<Map<String, dynamic>>.from(
        await db
            .from(table)
            .select()
            .inFilter('approval_status', [
              'pending_review',
              'under_review',
              'changes_required',
            ])
            .order('created_at'),
      );

  Future<void> act(String function, String id, String status) async {
    try {
      await db.rpc(
        function,
        params: {
          function == 'review_property' ? 'p_property_id' : 'p_organization_id':
              id,
          'p_status': status,
          'p_review_notes': null,
        },
      );
      if (mounted) setState(() {});
    } on PostgrestException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Widget list(String table, String function) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: load(table),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError)
            return Center(child: Text(snapshot.error.toString()));
          final items = snapshot.data ?? [];
          if (items.isEmpty)
            return Center(
              child: Text(
                gr ? 'Δεν υπάρχουν εκκρεμότητες.' : 'No pending reviews.',
              ),
            );
          return ListView(
            children: items
                .map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(
                        (item['display_name'] ?? item['name'] ?? '').toString(),
                      ),
                      subtitle: Text(
                        '${item['approval_status']} · ${item['address'] ?? ''}',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: gr ? 'Έγκριση' : 'Approve',
                            onPressed: () =>
                                act(function, item['id'] as String, 'approved'),
                            icon: const Icon(Icons.check_circle_outline),
                          ),
                          IconButton(
                            tooltip: gr ? 'Αλλαγές' : 'Request changes',
                            onPressed: () => act(
                              function,
                              item['id'] as String,
                              'changes_required',
                            ),
                            icon: const Icon(Icons.edit_note),
                          ),
                          IconButton(
                            tooltip: gr ? 'Απόρριψη' : 'Reject',
                            onPressed: () =>
                                act(function, item['id'] as String, 'rejected'),
                            icon: const Icon(Icons.block_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      );

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(gr ? 'Διαχείριση SmartBlock' : 'SmartBlock admin'),
        bottom: TabBar(
          tabs: [
            Tab(text: gr ? 'Οργανισμοί' : 'Organizations'),
            Tab(text: gr ? 'Ακίνητα' : 'Properties'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          list('organizations', 'review_organization'),
          list('properties', 'review_property'),
        ],
      ),
    ),
  );
}
