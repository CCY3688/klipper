enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime ts;
  final LogLevel level;
  final String tag;
  final String msg;

  LogEntry(this.level, this.tag, this.msg) : ts = DateTime.now();

  String toLine() => '[${ts.toIso8601String()}] ${level.name.toUpperCase()} $tag: $msg';
}

class AppLogger {
  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries);

  void log(LogLevel level, String tag, String msg) {
    _entries.add(LogEntry(level, tag, msg));
    if (_entries.length > 2000) {
      _entries.removeRange(0, _entries.length - 2000);
    }
  }

  String exportText() => _entries.map((e) => e.toLine()).join('\n');
}