import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Holds a separate in-memory Supabase session for the admin's test account.
/// It never replaces the normal, persisted administrator session.
class SmartBlockTrialSession {
  SmartBlockTrialSession._();

  static SupabaseClient? _client;
  static String? _role;
  static final ValueNotifier<bool> activeListenable = ValueNotifier<bool>(false);

  static SupabaseClient get client => _client ?? Supabase.instance.client;
  static bool get isActive => _client != null;
  static String? get role => _role;

  static Future<void> start({
    required SupabaseClient client,
    required String role,
  }) async {
    await _client?.auth.signOut();
    _client = client;
    _role = role;
    activeListenable.value = true;
  }

  static Future<void> stop() async {
    final client = _client;
    _client = null;
    _role = null;
    activeListenable.value = false;
    await client?.auth.signOut();
  }
}

