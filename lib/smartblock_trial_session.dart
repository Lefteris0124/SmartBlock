import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks a temporary role session and preserves the administrator session so
/// it can be restored when the trial ends.
class SmartBlockTrialSession {
  SmartBlockTrialSession._();

  static SupabaseClient? _client;
  static String? _role;
  static Session? _adminSession;
  static final ValueNotifier<bool> activeListenable = ValueNotifier<bool>(false);

  static SupabaseClient get client => _client ?? Supabase.instance.client;
  static bool get isActive => _client != null;
  static String? get role => _role;

  static Future<void> start({
    required SupabaseClient client,
    required String role,
    required Session? adminSession,
  }) async {
    await _client?.dispose();
    _client = client;
    _role = role;
    _adminSession = adminSession;
    activeListenable.value = true;
  }

  static Future<void> stop() async {
    final client = _client;
    final adminSession = _adminSession;
    try {
      if (adminSession != null) {
        await Supabase.instance.client.auth.setSession(
          adminSession.refreshToken,
          accessToken: adminSession.accessToken,
        );
      }
    } finally {
      _client = null;
      _role = null;
      _adminSession = null;
      activeListenable.value = false;
      await client?.dispose();
    }
  }

  static Future<void> restoreAfterFailedStart({
    required Session? adminSession,
    required SupabaseClient? trialClient,
  }) async {
    try {
      if (adminSession != null) {
        await Supabase.instance.client.auth.setSession(
          adminSession.refreshToken,
          accessToken: adminSession.accessToken,
        );
      }
    } finally {
      await trialClient?.dispose();
    }
  }
}

