import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/locale/locale_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.localeController});

  final LocaleController localeController;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.settingsTitle),
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/routes');
            }
          },
        ),
      ),
      body: ListenableBuilder(
        listenable: localeController,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                l.settingsLanguageSection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l.settingsLanguageDescription,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            RadioListTile<Locale>(
              title: Text(l.languageSpanish),
              value: const Locale('es'),
              groupValue: localeController.locale,
              onChanged: (value) {
                if (value != null) localeController.setLocale(value);
              },
            ),
            RadioListTile<Locale>(
              title: Text(l.languageEnglish),
              value: const Locale('en'),
              groupValue: localeController.locale,
              onChanged: (value) {
                if (value != null) localeController.setLocale(value);
              },
            ),
          ],
        ),
      ),
    );
  }
}
