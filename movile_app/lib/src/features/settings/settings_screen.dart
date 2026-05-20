import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/local_draft_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/locale/locale_controller.dart';
import '../../services/settings/app_settings_controller.dart';

/// Wraps a CSV cell value in double-quotes and escapes internal double-quotes.
String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.localeController,
    required this.settingsController,
    this.authService,
    required this.repository,
    this.garageService,
  });

  final LocaleController localeController;
  final AppSettingsController settingsController;
  final AuthService? authService;
  final LocalDraftRepository repository;
  final GarageService? garageService;

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
        listenable: Listenable.merge([localeController, settingsController]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            // ── Language ────────────────────────────────────────────────
            _SectionHeader(l.settingsLanguageSection),
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
              onChanged: (v) {
                if (v != null) localeController.setLocale(v);
              },
            ),
            RadioListTile<Locale>(
              title: Text(l.languageEnglish),
              value: const Locale('en'),
              groupValue: localeController.locale,
              onChanged: (v) {
                if (v != null) localeController.setLocale(v);
              },
            ),

            // ── Appearance ───────────────────────────────────────────────
            _SectionHeader(l.settingsAppearanceSection),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeSystem),
              value: AppThemeMode.system,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeLight),
              value: AppThemeMode.light,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),
            RadioListTile<AppThemeMode>(
              title: Text(l.settingsThemeDark),
              value: AppThemeMode.dark,
              groupValue: settingsController.themeMode,
              onChanged: (v) {
                if (v != null) settingsController.setThemeMode(v);
              },
            ),

            // ── Measurement ──────────────────────────────────────────────
            _SectionHeader(l.settingsMeasurementSection),
            RadioListTile<UnitSystem>(
              title: Text(l.settingsUnitMetric),
              value: UnitSystem.metric,
              groupValue: settingsController.unitSystem,
              onChanged: (v) {
                if (v != null) settingsController.setUnitSystem(v);
              },
            ),
            RadioListTile<UnitSystem>(
              title: Text(l.settingsUnitImperial),
              value: UnitSystem.imperial,
              groupValue: settingsController.unitSystem,
              onChanged: (v) {
                if (v != null) settingsController.setUnitSystem(v);
              },
            ),
            const Divider(indent: 16, endIndent: 16, height: 8),
            RadioListTile<bool>(
              title: Text(l.settingsTimeFormatDot),
              value: true,
              groupValue: settingsController.timeFormatDot,
              onChanged: (v) {
                if (v != null) settingsController.setTimeFormatDot(v);
              },
            ),
            RadioListTile<bool>(
              title: Text(l.settingsTimeFormatComma),
              value: false,
              groupValue: settingsController.timeFormatDot,
              onChanged: (v) {
                if (v != null) settingsController.setTimeFormatDot(v);
              },
            ),

            // ── Session behaviour ────────────────────────────────────────
            _SectionHeader(l.settingsSessionSection),
            SwitchListTile(
              title: Text(l.settingsKeepScreenAwakeLabel),
              subtitle: Text(l.settingsKeepScreenAwakeDesc),
              value: settingsController.keepScreenAwake,
              onChanged: settingsController.setKeepScreenAwake,
            ),
            SwitchListTile(
              title: Text(l.settingsHapticFeedbackLabel),
              subtitle: Text(l.settingsHapticFeedbackDesc),
              value: settingsController.hapticFeedback,
              onChanged: settingsController.setHapticFeedback,
            ),
            SwitchListTile(
              title: Text(l.settingsAudioAlertsLabel),
              subtitle: Text(l.settingsAudioAlertsDesc),
              value: settingsController.audioAlerts,
              onChanged: settingsController.setAudioAlerts,
            ),
            ListTile(
              title: Text(l.settingsGpsSamplingLabel),
              trailing: DropdownButton<GpsSamplingInterval>(
                value: settingsController.gpsSamplingInterval,
                underline: const SizedBox(),
                onChanged: (v) {
                  if (v != null) settingsController.setGpsSamplingInterval(v);
                },
                items: [
                  DropdownMenuItem(
                    value: GpsSamplingInterval.oneSecond,
                    child: Text(l.settingsGpsSampling1s),
                  ),
                  DropdownMenuItem(
                    value: GpsSamplingInterval.twoSeconds,
                    child: Text(l.settingsGpsSampling2s),
                  ),
                  DropdownMenuItem(
                    value: GpsSamplingInterval.fiveSeconds,
                    child: Text(l.settingsGpsSampling5s),
                  ),
                ],
              ),
            ),

            // ── Routes ──────────────────────────────────────────────────
            _SectionHeader(l.settingsRoutesSection),
            ListTile(
              title: Text(l.settingsDefaultRoutingProfileLabel),
              trailing: DropdownButton<String>(
                value: settingsController.defaultRoutingProfile,
                underline: const SizedBox(),
                onChanged: (v) {
                  if (v != null) settingsController.setDefaultRoutingProfile(v);
                },
                items: [
                  DropdownMenuItem(value: 'driving', child: Text(l.settingsRoutingProfileRoad)),
                  DropdownMenuItem(value: 'walking', child: Text(l.settingsRoutingProfileTrail)),
                  DropdownMenuItem(value: 'cycling', child: Text(l.settingsRoutingProfileCycling)),
                ],
              ),
            ),

            // ── Garage ──────────────────────────────────────────────────────────────
            if (garageService != null) ...[
              _SectionHeader(l.settingsGarageSection),
              ListenableBuilder(
                listenable: garageService!,
                builder: (context, _) {
                  final vehicles = garageService!.vehicles;
                  // Resolve: fall back to null if the stored ID no longer exists in the garage
                  final currentId = settingsController.defaultVehicleId;
                  final resolvedId = vehicles.any((v) => v.id == currentId) ? currentId : null;
                  return ListTile(
                    title: Text(l.settingsDefaultVehicleLabel),
                    trailing: DropdownButton<String?>(
                      value: resolvedId,
                      underline: const SizedBox(),
                      onChanged: (v) => settingsController.setDefaultVehicleId(v),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l.settingsDefaultVehicleNone),
                        ),
                        for (final v in vehicles)
                          DropdownMenuItem<String?>(
                            value: v.id,
                            child: Text(v.name),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],

            // ── Account ──────────────────────────────────────────────────
            if (authService?.isLoggedIn == true) ...[
              _SectionHeader(l.settingsAccountSection),
              if (authService!.currentUser?.appMetadata['provider'] == 'email')
                ListTile(
                  title: Text(l.settingsChangePasswordLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showChangePasswordDialog(context, l),
                ),
              ListTile(
                title: Text(
                  l.settingsDeleteAccountLabel,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.error,
                ),
                onTap: () => _confirmDeleteAccount(context, l),
              ),
            ],

            // ── Data ─────────────────────────────────────────────────────
            _SectionHeader(l.settingsDataSection),
            ListTile(
              title: Text(l.settingsExportHistoryLabel),
              subtitle: Text(l.settingsExportHistoryDesc),
              trailing: const Icon(Icons.download_outlined),
              onTap: () => _exportHistory(context, l),
            ),
            ListTile(
              title: Text(l.settingsClearCacheLabel),
              subtitle: Text(l.settingsClearCacheDesc),
              trailing: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              onTap: () => _confirmClearCache(context, l),
            ),
          ],
        ),
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        authService: authService!,
        l: l,
      ),
    );
  }

  void _confirmDeleteAccount(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsDeleteAccountConfirmTitle),
        content: Text(l.settingsDeleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteAccount(context, l);
            },
            child: Text(l.settingsDeleteAccountConfirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, AppLocalizations l) async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) return;

      final response = await Supabase.instance.client.functions.invoke(
        'delete-user',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      if (response.status != 200) throw Exception('status ${response.status}');

      // Sign out locally (the account is already gone server-side)
      await authService!.signOut();

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsDeleteAccountSuccess)),
      );
      context.go('/routes');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsDeleteAccountError)),
      );
    }
  }

  Future<void> _exportHistory(BuildContext context, AppLocalizations l) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.settingsExportSharing)),
    );

    final routes = await repository.getAllRoutes();
    final sessions = await repository.getAllSessions();
    final freeRides = await repository.getAllFreeRides();

    final routeIndex = {for (final r in routes) r.id: r.name};

    final buffer = StringBuffer();
    buffer.writeln(
      'type,date,route,laps,best_lap_ms,distance_m,max_speed_mps,avg_speed_mps,vehicle_id',
    );

    for (final s in sessions) {
      final bestMs = s.laps.isEmpty
          ? ''
          : s.laps
              .map((lap) => lap.duration.inMilliseconds)
              .reduce((a, b) => a < b ? a : b)
              .toString();
      buffer.writeln([
        'session',                                                     // type — no quotes needed (no special chars)
        _csvCell(s.startedAt.toIso8601String()),                       // date
        _csvCell(routeIndex[s.routeTemplateId] ?? s.routeTemplateId), // route name (user-defined, must escape)
        s.laps.length,                                                 // laps — numeric
        bestMs,                                                        // best_lap_ms — numeric or empty
        s.totalDistanceMeters.toStringAsFixed(0),                      // distance_m — numeric
        s.maxSpeedMps.toStringAsFixed(2),                              // max_speed_mps — numeric
        s.avgSpeedMps.toStringAsFixed(2),                              // avg_speed_mps — numeric
        _csvCell(s.vehicleId ?? ''),                                   // vehicle_id — may be UUID or empty
      ].join(','));
    }

    for (final r in freeRides) {
      buffer.writeln([
        'free_ride',
        _csvCell(r.startedAt.toIso8601String()),
        '',   // route — always empty for free rides
        '',   // laps
        '',   // best_lap_ms
        r.totalDistanceMeters.toStringAsFixed(0),
        r.maxSpeedMps.toStringAsFixed(2),
        r.avgSpeedMps.toStringAsFixed(2),
        _csvCell(r.vehicleId ?? ''),
      ].join(','));
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/splitway_history.csv');
    await file.writeAsString(buffer.toString());

    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Splitway history export',
    );
  }

  void _confirmClearCache(BuildContext context, AppLocalizations l) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.settingsClearCacheConfirmTitle),
        content: Text(l.settingsClearCacheConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _clearCache(context, l);
            },
            child: Text(l.settingsClearCacheConfirmButton),
          ),
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, AppLocalizations l) async {
    try {
      final sessions = await repository.getAllSessions();
      for (final s in sessions) {
        await repository.deleteSession(s.id);
      }

      final rides = await repository.getAllFreeRides();
      for (final r in rides) {
        await repository.deleteFreeRide(r.id);
      }

      final routes = await repository.getAllRoutes();
      for (final r in routes) {
        await repository.deleteRoute(r.id);
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.settingsClearCacheDone)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.profileErrorUnexpected)),
      );
    }
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

// ── Change password dialog ──────────────────────────────────────────────────

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.authService, required this.l});

  final AuthService authService;
  final AppLocalizations l;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newCtrl.text),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l.settingsChangePasswordSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = widget.l.settingsChangePasswordError;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return AlertDialog(
      title: Text(l.settingsChangePasswordLabel),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextFormField(
              controller: _newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.settingsChangePasswordNewLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return l.settingsChangePasswordTooShort;
                if (v.length < 6) return l.settingsChangePasswordTooShort;
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: l.settingsChangePasswordConfirmLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (v) {
                if (v != _newCtrl.text) return l.settingsChangePasswordMismatch;
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : () => Navigator.pop(context),
          child: Text(l.commonCancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _submit,
          child: _loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l.settingsChangePasswordButton),
        ),
      ],
    );
  }
}
