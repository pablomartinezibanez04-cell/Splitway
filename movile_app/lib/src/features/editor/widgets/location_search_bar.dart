// movile_app/lib/src/features/editor/widgets/location_search_bar.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:splitway_core/splitway_core.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../../services/geocoding/forward_geocoding_service.dart';

class LocationSearchBar extends StatefulWidget {
  const LocationSearchBar({
    super.key,
    required this.accessToken,
    required this.onLocationSelected,
  });

  final String accessToken;
  final ValueChanged<GeoPoint> onLocationSelected;

  @override
  State<LocationSearchBar> createState() => _LocationSearchBarState();
}

class _LocationSearchBarState extends State<LocationSearchBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late final ForwardGeocodingService _service;
  Timer? _debounce;
  List<GeocodingResult> _results = const [];
  bool _loading = false;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _service = ForwardGeocodingService(accessToken: widget.accessToken);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _showResults = false;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await _service.search(value);
      if (!mounted) return;
      setState(() {
        _results = results;
        _showResults = true;
        _loading = false;
      });
    });
  }

  void _onResultTap(GeocodingResult result) {
    widget.onLocationSelected(result.coordinates);
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _results = const [];
      _showResults = false;
    });
  }

  void _onClear() {
    _controller.clear();
    _focusNode.unfocus();
    setState(() {
      _results = const [];
      _showResults = false;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(28),
          color: theme.colorScheme.surface,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: l.editorSearchLocationHint,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: _onClear,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              isDense: true,
            ),
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (_showResults)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface,
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l.editorSearchNoResults,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _results.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (_, index) {
                            final result = _results[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.place_outlined,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              title: Text(
                                result.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                              onTap: () => _onResultTap(result),
                            );
                          },
                        ),
            ),
          ),
      ],
    );
  }
}
