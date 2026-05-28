import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/logging/log_entry.dart';
import '../../services/logging/log_level.dart';
import '../../services/logging/log_uploader.dart';
import '../../services/logging/sinks/local_sink.dart';
import 'log_detail_sheet.dart';
import 'widgets/log_filter_bar.dart';
import 'widgets/log_list_tile.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({
    super.key,
    required this.sink,
    required this.uploader,
  });

  final LocalSink sink;
  final LogUploader uploader;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  LogLevel _level = LogLevel.debug;
  String? _tag;
  String _search = '';
  List<LogEntry> _entries = const [];
  int _pending = 0;

  @override
  void initState() {
    super.initState();
    _reload();
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
    await Share.shareXFiles([XFile(file.path)]);
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
