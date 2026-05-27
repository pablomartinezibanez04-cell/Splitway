import '../log_entry.dart';
import '../log_uploader.dart';
import 'log_sink.dart';

/// Trigger-only sink. Persistence happens in [LocalSink] (the caller wires
/// both sinks into `AppLogger`); this sink just nudges the uploader.
class RemoteSink implements LogSink {
  const RemoteSink(this._uploader);

  final LogUploader _uploader;

  @override
  Future<void> write(LogEntry entry) async {
    _uploader.scheduleDrain();
  }
}
