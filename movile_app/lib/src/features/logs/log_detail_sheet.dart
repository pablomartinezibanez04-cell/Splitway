import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show SharePlus, ShareParams;
import 'package:splitway_mobile/l10n/app_localizations.dart';

import '../../services/logging/log_entry.dart';

class LogDetailSheet extends StatelessWidget {
  const LogDetailSheet({super.key, required this.entry});

  final LogEntry entry;

  String _format() {
    final buf = StringBuffer()
      ..writeln('[${entry.level.name.toUpperCase()}] ${entry.timestamp.toIso8601String()}')
      ..writeln('tag: ${entry.tag}')
      ..writeln('app: ${entry.appVersion}  platform: ${entry.platform}  device: ${entry.deviceModel}')
      ..writeln('user: ${entry.userId ?? '(anon)'}')
      ..writeln()
      ..writeln('message:')
      ..writeln(entry.message);
    if (entry.error != null) {
      buf
        ..writeln()
        ..writeln('error:')
        ..writeln(entry.error);
    }
    if (entry.stackTrace != null) {
      buf
        ..writeln()
        ..writeln('stack:')
        ..writeln(entry.stackTrace);
    }
    if (entry.context != null && entry.context!.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('context:')
        ..writeln(const JsonEncoder.withIndent('  ').convert(entry.context));
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final text = _format();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: l.logsCopiedToClipboard,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l.logsCopiedToClipboard)),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.share),
                  tooltip: l.logsShareTooltip,
                  onPressed: () => SharePlus.instance.share(ShareParams(text: text)),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
