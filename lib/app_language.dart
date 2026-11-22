import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'smartblock_trial_session.dart';

class SmartBlockLanguage {
  const SmartBlockLanguage(this.code, this.nativeName);
  final String code;
  final String nativeName;

  Locale get locale => Locale(code);
  bool get isRtl => code == 'he';
  bool get isGreek => code == 'el';
}

class SmartBlockLanguages {
  static const supported = <SmartBlockLanguage>[
    SmartBlockLanguage('el', 'Ελληνικά'),
    SmartBlockLanguage('en', 'English'),
    SmartBlockLanguage('ru', 'Русский'),
    SmartBlockLanguage('uk', 'Українська'),
    SmartBlockLanguage('ro', 'Română'),
    SmartBlockLanguage('he', 'עברית'),
  ];

  static SmartBlockLanguage fromCode(String? code) => supported.firstWhere(
    (language) => language.code == code,
    orElse: () => supported.first,
  );
}

class SmartBlockLanguageController {
  SmartBlockLanguageController._();
  static final instance = SmartBlockLanguageController._();
  static const _preferenceKey = 'smartblock_language';
  final ValueNotifier<SmartBlockLanguage> selected = ValueNotifier(
    SmartBlockLanguages.supported.first,
  );

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final accountChoice =
        Supabase
                .instance
                .client
                .auth
                .currentUser
                ?.userMetadata?['preferred_language']
            as String?;
    final savedChoice = accountChoice ?? preferences.getString(_preferenceKey);
    final systemCode =
        WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    selected.value = SmartBlockLanguages.fromCode(savedChoice ?? systemCode);
    await preferences.setString(_preferenceKey, selected.value.code);
  }

  Future<void> select(String code) async {
    final language = SmartBlockLanguages.fromCode(code);
    selected.value = language;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, language.code);
    final user = SmartBlockTrialSession.client.auth.currentUser;
    if (user != null) {
      try {
        await SmartBlockTrialSession.client.auth.updateUser(
          UserAttributes(data: {'preferred_language': language.code}),
        );
      } catch (error) {
        debugPrint('Could not save language to the account: $error');
      }
    }
  }

  Future<void> syncAfterSignIn() async {
    final user = SmartBlockTrialSession.client.auth.currentUser;
    if (user == null) return;
    final accountCode = user.userMetadata?['preferred_language'] as String?;
    if (accountCode != null &&
        SmartBlockLanguages.supported.any((item) => item.code == accountCode)) {
      selected.value = SmartBlockLanguages.fromCode(accountCode);
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, accountCode);
    } else {
      try {
        await SmartBlockTrialSession.client.auth.updateUser(
          UserAttributes(data: {'preferred_language': selected.value.code}),
        );
      } catch (error) {
        debugPrint('Could not save language to the account: $error');
      }
    }
  }
}

class SmartBlockLanguageMenu extends StatelessWidget {
  const SmartBlockLanguageMenu({this.iconOnly = true, super.key});
  final bool iconOnly;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<SmartBlockLanguage>(
        valueListenable: SmartBlockLanguageController.instance.selected,
        builder: (context, language, _) => PopupMenuButton<String>(
          tooltip: 'Language',
          initialValue: language.code,
          onSelected: (code) =>
              SmartBlockLanguageController.instance.select(code),
          itemBuilder: (context) => SmartBlockLanguages.supported
              .map(
                (item) => PopupMenuItem<String>(
                  value: item.code,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: item.code == language.code
                            ? const Icon(Icons.check, size: 18)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(item.nativeName),
                    ],
                  ),
                ),
              )
              .toList(),
          child: iconOnly
              ? const Icon(Icons.language)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language),
                    const SizedBox(width: 8),
                    Text(language.nativeName),
                  ],
                ),
        ),
      );
}
