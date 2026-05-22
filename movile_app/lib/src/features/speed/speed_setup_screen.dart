import 'package:flutter/material.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/speed/speed_metric.dart';
import '../../services/speed/speed_metric_labels.dart';

enum SpeedView { list, grid }

class SpeedSetupResult {
  const SpeedSetupResult({
    required this.vehicle,
    required this.metrics,
    required this.countdownSeconds,
    required this.name,
    required this.view,
  });

  final Vehicle vehicle;
  final Set<SpeedMetric> metrics;
  final int countdownSeconds;
  final String? name;
  final SpeedView view;
}

class SpeedSetupScreen extends StatefulWidget {
  const SpeedSetupScreen({
    super.key,
    required this.garageService,
    required this.onContinue,
  });

  final GarageService? garageService;
  final void Function(SpeedSetupResult) onContinue;

  @override
  State<SpeedSetupScreen> createState() => _SpeedSetupScreenState();
}

class _SpeedSetupScreenState extends State<SpeedSetupScreen> {
  Vehicle? _vehicle;
  final Set<SpeedMetric> _metrics = {};
  int _countdown = 3;
  final TextEditingController _name = TextEditingController();
  SpeedView _view = SpeedView.list;

  @override
  void initState() {
    super.initState();
    widget.garageService?.addListener(_onGarageChange);
    widget.garageService?.loadVehicles();
  }

  @override
  void dispose() {
    widget.garageService?.removeListener(_onGarageChange);
    _name.dispose();
    super.dispose();
  }

  void _onGarageChange() {
    if (mounted) setState(() {});
  }

  bool get _canContinue => _vehicle != null && _metrics.isNotEmpty;

  List<Vehicle> get _availableVehicles {
    final vehicles = widget.garageService?.vehicles ?? const <Vehicle>[];
    return vehicles.where((v) => v.type != VehicleType.bicycle).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.speedSetupTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(l.speedSetupVehicleSection, _vehiclePicker(l)),
            _section(l.speedSetupMetricsSection, _metricChecks(l)),
            _section(l.speedSetupCountdownSection, _countdownChips(l)),
            _section(
              l.speedSetupNameSection,
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: l.speedSetupNameHint,
                ),
              ),
            ),
            _section(l.speedSetupViewSection, _viewChips(l)),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('speed-continue'),
              onPressed: _canContinue ? _go : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(l.speedSetupContinue),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vehiclePicker(AppLocalizations l) {
    final vehicles = _availableVehicles;
    if (vehicles.isEmpty) {
      return Text(
        l.speedSetupVehicleEmpty,
        style: TextStyle(color: Theme.of(context).hintColor),
      );
    }
    return DropdownButton<Vehicle>(
      value: _vehicle,
      isExpanded: true,
      hint: Text(l.speedSetupVehicleSection),
      items: vehicles
          .map(
            (v) => DropdownMenuItem(value: v, child: Text(v.name)),
          )
          .toList(),
      onChanged: (v) => setState(() => _vehicle = v),
    );
  }

  Widget _metricChecks(AppLocalizations l) {
    return Column(
      children: SpeedMetric.values.map((m) {
        return CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(m.label(l)),
          value: _metrics.contains(m),
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _metrics.add(m);
              } else {
                _metrics.remove(m);
              }
            });
          },
        );
      }).toList(),
    );
  }

  Widget _countdownChips(AppLocalizations l) {
    return Wrap(
      spacing: 8,
      children: [3, 5, 10].map((n) {
        return ChoiceChip(
          label: Text(l.speedSetupSecondsValue(n)),
          selected: _countdown == n,
          onSelected: (_) => setState(() => _countdown = n),
        );
      }).toList(),
    );
  }

  Widget _viewChips(AppLocalizations l) {
    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: Text(l.speedSetupViewList),
          selected: _view == SpeedView.list,
          onSelected: (_) => setState(() => _view = SpeedView.list),
        ),
        ChoiceChip(
          label: Text(l.speedSetupViewGrid),
          selected: _view == SpeedView.grid,
          onSelected: (_) => setState(() => _view = SpeedView.grid),
        ),
      ],
    );
  }

  Widget _section(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  void _go() {
    widget.onContinue(SpeedSetupResult(
      vehicle: _vehicle!,
      metrics: Set.unmodifiable(_metrics),
      countdownSeconds: _countdown,
      name: _name.text.trim().isEmpty ? null : _name.text.trim(),
      view: _view,
    ));
  }
}
