import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams, XFile;
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/logging/log_entry.dart';
import '../../services/logging/log_level.dart';
import '../../services/logging/log_uploader.dart';
import '../../services/logging/sinks/local_sink.dart';
import '../../services/profile/profile_service.dart';
import 'log_detail_sheet.dart';
import 'widgets/log_filter_bar.dart';
import 'widgets/log_list_tile.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.sink,
    required this.uploader,
    this.profileService,
  });

  final LocalSink sink;
  final LogUploader uploader;
  final ProfileService? profileService;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel _level = LogLevel.debug;
  String? _tag;
  String _search = '';
  List<LogEntry> _entries = const [];
  int _pending = 0;
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    widget.profileService?.addListener(_onProfileChanged);
    _reload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkAccess();
    });
  }

  @override
  void dispose() {
    widget.profileService?.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) _checkAccess();
  }

  /// Defense in depth: the Settings entry is hidden for non-admins, but a
  /// deep link or a stale build could still land here. Bounce to /settings
  /// once we know the user is not an admin. Waits for the profile to load
  /// before deciding. When [widget.profileService] is null the gate is not
  /// wired (test harness / pre-init), so the screen renders normally.
  void _checkAccess() {
    if (_redirected) return;
    final p = widget.profileService;
    if (p == null) return;
    if (p.loading && p.profile == null) return;
    if (p.isAdmin) return;
    _redirected = true;
    if (!mounted) return;
    // GoRouter isn't guaranteed in every host (e.g. tests). Catch the lookup
    // error and fall back to rendering an empty placeholder.
    try {
      context.go('/settings');
    } catch (_) {
      // No router in scope — nothing to do; the (empty) tree stays put.
    }
  }

  Future<void> _reload() async {
    final entries = await widget.sink.list(
      level: _level,
      tag: _tag,
      search: _search,
      limit: 500,
    );
    final pending = await widget.sink.countPending();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _pending = pending;
    });
  }

  Future<void> _uploadNow() async {
    await widget.uploader.drain();
    await _reload();
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    final count = await widget.sink.countPending();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l.logsPending(count))),
    );
  }

  Future<void> _shareAll() async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'splitway-logs.txt'));
    final text = _entries.map(_format).join('\n---\n');
    await file.writeAsString(text);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  Future<void> _clearAll() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l.logsClearConfirmTitle),
        content: Text(l.logsClearConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.logsClearConfirmButton),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.sink.deleteAll();
      await _reload();
    }
  }

  String _format(LogEntry e) =>
      '[${e.level.name.toUpperCase()}] ${e.timestamp.toIso8601String()} ${e.tag} :: ${e.message}'
      '${e.error == null ? '' : '\n  error: ${e.error}'}';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.logsScreenTitle),
        actions: [
          IconButton(
            tooltip: l.logsUploadTooltip,
            icon: const Icon(Icons.cloud_upload),
            onPressed: _uploadNow,
          ),
          IconButton(
            tooltip: l.logsShareTooltip,
            icon: const Icon(Icons.share),
            onPressed: _shareAll,
          ),
          IconButton(
            tooltip: l.logsClearTooltip,
            icon: const Icon(Icons.delete_forever),
            onPressed: _clearAll,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Chip(label: Text(l.logsPending(_pending))),
          ),
          LogFilterBar(
            level: _level,
            tag: _tag,
            onLevelChanged: (v) {
              setState(() => _level = v);
              _reload();
            },
            onTagChanged: (v) {
              setState(() => _tag = v);
              _reload();
            },
            onSearchChanged: (v) {
              setState(() => _search = v);
              _reload();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _entries.isEmpty
                ? Center(child: Text(l.logsEmpty))
                : ListView.separated(
                    itemCount: _entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => LogListTile(
                      entry: _entries[i],
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => LogDetailSheet(entry: _entries[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
