import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class NavigationLogService {
  NavigationLogService._internal();

  static final NavigationLogService _instance = NavigationLogService._internal();
  factory NavigationLogService() => _instance;

  File? _file;
  bool _initialized = false;
  bool _isWriting = false;
  final List<String> _pendingLines = [];

  Future<void> init() async {
    if (_initialized) return;

    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final path = '${dir.path}/nav_log_$ts.csv';

    _file = File(path);
    // CSV header
    await _file!.writeAsString('timestamp,event_type,data\n', mode: FileMode.write);

    _initialized = true;

    // Flush anything that was queued before init
    if (_pendingLines.isNotEmpty) {
      final lines = _pendingLines.join('');
      _pendingLines.clear();
      await _appendRaw(lines);
    }

    // Optional: print path once so you see it in log while cable is attached
    // ignore: avoid_print
    print('📁 Navigation log file: $path');
  }

  Future<void> log(String eventType, Map<String, dynamic> data) async {
    final line = _buildCsvLine(eventType, data);

    if (!_initialized || _file == null) {
      _pendingLines.add(line);
      // Kick off init if not started
      if (!_initialized) {
        unawaited(init());
      }
      return;
    }

    _pendingLines.add(line);
    if (!_isWriting) {
      _flushQueue();
    }
  }

  // Build a simple CSV line with JSON-like data
  String _buildCsvLine(String eventType, Map<String, dynamic> data) {
    final now = DateTime.now().toIso8601String();
    final dataStr = data.entries
        .map((e) => '${e.key}=${e.value}')
        .join(';')
        .replaceAll('\n', ' ')
        .replaceAll(',', ' '); // avoid breaking CSV

    return '$now,$eventType,$dataStr\n';
  }

  Future<void> _flushQueue() async {
    if (_isWriting || _file == null || _pendingLines.isEmpty) return;

    _isWriting = true;
    try {
      final chunk = _pendingLines.join('');
      _pendingLines.clear();
      await _appendRaw(chunk);
    } finally {
      _isWriting = false;
      // If more were added meanwhile, flush again
      if (_pendingLines.isNotEmpty) {
        // ignore: discarded_futures
        _flushQueue();
      }
    }
  }

  Future<void> _appendRaw(String text) async {
    if (_file == null) return;
    await _file!.writeAsString(text, mode: FileMode.append, flush: false);
  }

  // Getter to access the current log file path (for sharing/export)
  String? get currentLogPath => _file?.path;
}

