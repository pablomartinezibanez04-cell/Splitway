import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../config/app_config.dart';
import '../../routing/app_router.dart';
import '../../services/auth/auth_service.dart';
import '../../services/garage/garage_service.dart';
import '../../services/garage/vehicle.dart';
import '../../services/profile/profile_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../home/home_shell.dart';
import 'vehicle_detail_screen.dart';
import 'widgets/vehicle_form_sheet.dart';
import 'widgets/vehicle_grid_tile.dart';
import 'widgets/vehicle_list_tile.dart';

class GarageScreen extends StatefulWidget {
  const GarageScreen({
    super.key,
    required this.garageService,
    required this.config,
    this.authService,
    this.profileService,
  });

  final GarageService garageService;
  final AppConfig config;
  final AuthService? authService;
  final ProfileService? profileService;

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

enum _ViewMode { list, grid }

class _GarageScreenState extends State<GarageScreen> {
  _ViewMode _viewMode = _ViewMode.list;

  @override
  void initState() {
    super.initState();
    widget.garageService.addListener(_onChange);
    widget.authService?.addListener(_onChange);
    widget.garageService.loadVehicles();
  }

  @override
  void dispose() {
    widget.garageService.removeListener(_onChange);
    widget.authService?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    // Defer setState to avoid calling it during the build phase when a
    // ChangeNotifier fires while the widget tree is still being built.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      if (mounted) setState(() {});
    }
  }

  Future<void> _onAddVehicle() async {
    // Auth guard: require login before adding a vehicle.
    final allowed = await requireAuth(
      context,
      widget.authService,
      message: AppLocalizations.of(context).loginBannerDefault,
    );
    if (!allowed || !mounted) return;

    final result = await showModalBottomSheet<VehicleFormResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const VehicleFormSheet(),
    );
    if (result == null || !mounted) return;

    final vehicle = await widget.garageService.addVehicle(
      name: result.name,
      type: result.type,
      model: result.model,
      year: result.year,
      horsepower: result.horsepower,
      torqueNm: result.torqueNm,
      weightKg: result.weightKg,
      drivetrain: result.drivetrain,
      notes: result.notes,
    );

    if (vehicle != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).garageVehicleSavedSnack),
        ),
      );
    }
  }

  void _openVehicleDetail(Vehicle vehicle) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VehicleDetailScreen(
        vehicle: vehicle,
        garageService: widget.garageService,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final svc = widget.garageService;

    return Scaffold(
      appBar: AppBar(
        leading: buildDrawerLeading(
          context,
          widget.authService,
          widget.profileService,
        ),
        title: Text(l.garageTitle),
        actions: [
          IconButton(
            tooltip: _viewMode == _ViewMode.list
                ? l.garageViewGrid
                : l.garageViewList,
            onPressed: () => setState(() {
              _viewMode = _viewMode == _ViewMode.list
                  ? _ViewMode.grid
                  : _ViewMode.list;
            }),
            icon: Icon(
              _viewMode == _ViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
          ),
          IconButton(
            tooltip: l.garageAddVehicleButton,
            onPressed: _onAddVehicle,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: svc.loading
          ? const Center(child: CircularProgressIndicator())
          : svc.vehicles.isEmpty
              ? EmptyState(
                  icon: Icons.garage_outlined,
                  title: l.garageNoVehiclesTitle,
                  message: l.garageNoVehiclesMessage,
                  action: FilledButton.icon(
                    onPressed: _onAddVehicle,
                    icon: const Icon(Icons.add),
                    label: Text(l.garageAddVehicleButton),
                  ),
                )
              : _viewMode == _ViewMode.list
                  ? _buildListView(svc)
                  : _buildGridView(svc),
    );
  }

  Widget _buildListView(GarageService svc) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: svc.vehicles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final vehicle = svc.vehicles[index];
        return VehicleListTile(
          vehicle: vehicle,
          onTap: () => _openVehicleDetail(vehicle),
        );
      },
    );
  }

  Widget _buildGridView(GarageService svc) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemCount: svc.vehicles.length,
      itemBuilder: (_, index) {
        final vehicle = svc.vehicles[index];
        return VehicleGridTile(
          vehicle: vehicle,
          onTap: () => _openVehicleDetail(vehicle),
        );
      },
    );
  }
}
