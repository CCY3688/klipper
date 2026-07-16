enum LogLevel { debug, info, warn, error }

class LogEntry {
  final DateTime ts;
  final LogLevel level;
  final String tag;
  final String msg;

  LogEntry(this.level, this.tag, this.msg) : ts = DateTime.now();

  String toLine() =>
      '[${ts.toIso8601String()}] ${level.name.toUpperCase()} $tag: $msg';
}

class AppLogger {
  final List<LogEntry> _entries = [];
  List<LogEntry> get entries => List.unmodifiable(_entries);

  List<LogEntry> where(bool Function(LogEntry entry) test) {
    return List.unmodifiable(_entries.where(test));
  }

  void log(LogLevel level, String tag, String msg) {
    _entries.add(LogEntry(level, tag, msg));
    if (_entries.length > 2000) {
      _entries.removeRange(0, _entries.length - 2000);
    }
  }

  void clear() {
    _entries.clear();
  }

  String exportText() => _entries.map((e) => e.toLine()).join('\n');

  String exportWhere(bool Function(LogEntry entry) test) {
    return _entries.where(test).map((e) => e.toLine()).join('\n');
  }
}
