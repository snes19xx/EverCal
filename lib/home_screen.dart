/// home_screen.dart
///
/// Contains the main Stateful implementation of the Calendar:
/// file I/O, parsing (ICS/JSON/Khal), recurrence generation,
/// weather fetching, and layout management.

import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart'; // For LineSplitter

import 'models.dart';
import 'utils.dart';
import 'components.dart';
import 'calendar_views.dart';
import 'dialogs.dart';

class CalendarHome extends StatefulWidget {
  final VoidCallback onThemeToggle;
  final bool isDarkMode;
  final IconData currentIcon;

  const CalendarHome({
    super.key,
    required this.onThemeToggle,
    required this.isDarkMode,
    required this.currentIcon,
  });

  @override
  State<CalendarHome> createState() => _CalendarHomeState();
}

class _CalendarHomeState extends State<CalendarHome> {
  late DateTime _selectedDate;
  DateTime _focusedMonth = DateTime.now();
  CalendarViewMode _viewMode = CalendarViewMode.month; // Default view (month)

  Map<DateTime, List<CalendarEvent>> _events = {};
  Map<DateTime, List<CalendarEvent>> _manualEvents = {};
  Map<DateTime, List<CalendarEvent>> _importedEvents = {};
  Map<DateTime, List<CalendarEvent>> _khalEvents = {};

  WeatherData? _weather;
  bool _isLoading = true;
  String? _errorMessage;
  WeatherUnit _weatherUnit = WeatherUnit.celsius;

  bool _khalConnected = false;
  bool _khalEnabledByUser = false;
  // At Startup (the default scroll position)
  final ScrollController _weekScrollController =
      ScrollController(initialScrollOffset: 520); // 9 AM = 9 * 60

  // HELPER FUNCTION 

  void _updateMasterEvent(CalendarEvent oldMaster, CalendarEvent newMaster) {
    // Find where the master lives in the map
    final masterDate = DateTime(oldMaster.startTime.year,
        oldMaster.startTime.month, oldMaster.startTime.day);

    if (_manualEvents[masterDate] != null) {
      final index =
          _manualEvents[masterDate]!.indexWhere((e) => e.id == oldMaster.id);
      if (index != -1) {
        _manualEvents[masterDate]![index] = newMaster;
      }
    }

    // Clear all generated instances of this event from memory
    _manualEvents.forEach((d, list) {
      list.removeWhere((e) => e.id.startsWith('${oldMaster.id}_r'));
    });

    // Regenerate with new rules
    final now = DateTime.now();
    if (newMaster.rrule != null) {
      _generateSafeRecurrences(
          _manualEvents,
          newMaster,
          newMaster.rrule!,
          DateTime(now.year - 1),
          DateTime(now.year + 2));
    }
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadEvents();
    _loadWeather(); // Reads settings, so check view mode there
  }

  // Stable hash (FNV-1a 32-bit) for deterministic IDs
  String _fnv1aHex(String input) {
    const int fnvPrime = 16777619;
    const int offsetBasis = 2166136261;
    int hash = offsetBasis;

    final bytes = utf8.encode(input);
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  String _homeDir() => Platform.environment['HOME'] ?? '';

  String _joinPath(List<String> parts) {
    final sep = Platform.pathSeparator;
    return parts.where((p) => p.isNotEmpty).join(sep);
  }

  Directory _baseDir() =>
      Directory(_joinPath([_homeDir(), 'Documents', 'EverCal']));
  Directory _manualDir() => Directory(_joinPath([_baseDir().path, 'manual']));
  Directory _importsDir() => Directory(_joinPath([_baseDir().path, 'imports']));
  File _manualFile() => File(_joinPath([_manualDir().path, 'manual.ics']));
  File _settingsFile() => File(_joinPath([_baseDir().path, 'settings.json']));

  Future<void> _ensureDirs() async {
    if (!await _baseDir().exists()) await _baseDir().create(recursive: true);
    if (!await _manualDir().exists()) {
      await _manualDir().create(recursive: true);
    }
    if (!await _importsDir().exists()) {
      await _importsDir().create(recursive: true);
    }
  }

  String _basename(String path) {
    final sep = Platform.pathSeparator;
    final parts = path.split(sep);
    return parts.isEmpty ? path : parts.last;
  }

  String _sanitizeFilename(String name) {
    final bad = RegExp(r'[\\/:*?"<>|]');
    return name.replaceAll(bad, '_').trim();
  }

  Future<Map<String, dynamic>> _readSettings() async {
    try {
      final f = _settingsFile();
      if (!await f.exists()) return {};
      final raw = await f.readAsString();
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  Future<void> _writeSettings(Map<String, dynamic> settings) async {
    try {
      await _settingsFile().writeAsString(json.encode(settings));
    } catch (_) {}
  }

  // Toggle View Mode
  Future<void> _toggleViewMode() async {
    setState(() {
      _viewMode = _viewMode == CalendarViewMode.month
          ? CalendarViewMode.week
          : CalendarViewMode.month;
    });

    final settings = await _readSettings();
    settings['calendar_view'] = _viewMode.name;
    await _writeSettings(settings);
  }

  // Weather with configurable temperature units
  Future<void> _loadWeather() async {
    try {
      // Load Settings & Unit
      final settings = await _readSettings();

      // Load View Mode
      final savedView = settings['calendar_view'];
      if (savedView == 'week') {
        _viewMode = CalendarViewMode.week;
      } else {
        _viewMode = CalendarViewMode.month;
      }

      // Restore Unit
      final savedUnit = settings['weather_unit'];
      if (savedUnit == 'fahrenheit') {
        _weatherUnit = WeatherUnit.fahrenheit;
      } else if (savedUnit == 'kelvin') {
        _weatherUnit = WeatherUnit.kelvin;
      } else {
        _weatherUnit = WeatherUnit.celsius;
      }

      double? lat;
      double? lon;

      if (settings['weather_lat'] != null && settings['weather_lon'] != null) {
        lat = settings['weather_lat'];
        lon = settings['weather_lon'];
      } else {
        // Auto-detect via IP
        try {
          final ipRes = await http.get(Uri.parse('http://ip-api.com/json'));
          if (ipRes.statusCode == 200) {
            final data = json.decode(ipRes.body);
            lat = (data['lat'] as num).toDouble();
            lon = (data['lon'] as num).toDouble();
          }
        } catch (_) {}
      }

      // If nothing works enjoy Toronto's weather
      lat ??= 43.6617;
      lon ??= -79.3951;

      // Fetch Weather
      final url =
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&temperature_unit=celsius';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final code = data['current']['weather_code'];

        String desc = 'Clear';
        IconData icon = Icons.wb_sunny_rounded;

        if (code <= 1) {
          desc = 'Clear Sky';
          icon = Icons.wb_sunny_rounded;
        } else if (code <= 3) {
          desc = 'Partly Cloudy';
          icon = Icons.cloud_rounded;
        } else if (code <= 48) {
          desc = 'Foggy';
          icon = Icons.dehaze_rounded;
        } else if (code <= 65) {
          desc = 'Rain';
          icon = Icons.grain_rounded;
        } else if (code <= 75) {
          desc = 'Snow';
          icon = Icons.ac_unit_rounded;
        } else if (code <= 99) {
          desc = 'Thunderstorm';
          icon = Icons.thunderstorm_rounded;
        }

        if (mounted) {
          setState(() {
            _weather = WeatherData(
              temp: (temp as num).toDouble(),
              description: desc,
              icon: icon,
            );
          });
        }
      }
    } catch (_) {
      /* silent fail */
    }
  }

  Future<void> _showLocationSearch() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return LocationSettingsDialog(currentUnit: _weatherUnit);
        },
      ),
    );

    if (result == null) return;

    // PROCESS RESULTS
    final settings = await _readSettings();
    bool needsRefresh = false;

    // Save Unit
    if (result['unit'] is WeatherUnit) {
      _weatherUnit = result['unit'];
      settings['weather_unit'] = _weatherUnit.name;
      setState(() {});
    }

    // For Auto-Detect Flag
    if (result['useAuto'] == true) {
      settings.remove('weather_lat');
      settings.remove('weather_lon');
      needsRefresh = true;
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Set to Auto-Location')));
    }
    // City Search
    else if (result['city'] != null && result['city'].toString().isNotEmpty) {
      final cityName = result['city'];
      try {
        final url =
            'https://geocoding-api.open-meteo.com/v1/search?name=$cityName&count=1&format=json';
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          if (data['results'] != null && data['results'].isNotEmpty) {
            final loc = data['results'][0];
            settings['weather_lat'] = loc['latitude'];
            settings['weather_lon'] = loc['longitude'];
            needsRefresh = true;
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Location set to ${loc['name']}')));
          } else {
            if (mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('City not found')));
          }
        }
      } catch (_) {}
    }

    await _writeSettings(settings);
    if (needsRefresh) _loadWeather();
  }

  // Load + merge events
  Future<void> _loadEvents() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _ensureDirs();

      final settings = await _readSettings();
      _khalEnabledByUser = settings['khalEnabled'] == true;

      // Manual (ICS)
      _manualEvents = {};
      final mFile = _manualFile();
      if (await mFile.exists()) {
        final content = await mFile.readAsString();
        _manualEvents =
            _parseICS(content, source: EventSource.manual, sourceId: 'manual');
      }

      // Imports (JSON)
      _importedEvents = {};
      final iDir = _importsDir();
      if (await iDir.exists()) {
        final files =
            await iDir.list(recursive: false, followLinks: false).toList();
        for (final ent in files) {
          if (ent is! File) continue;
          if (!ent.path.toLowerCase().endsWith('.json')) continue;

          try {
            final content = await ent.readAsString();
            final List<dynamic> rawList = json.decode(content);
            final sourceId = _basename(ent.path);

            final loadedMap = <DateTime, List<CalendarEvent>>{};
            for (final item in rawList) {
              if (item is! Map<String, dynamic>) continue;
              final e = CalendarEvent.fromJson(item, sourceId);
              if (e.id.isEmpty) {
                // If an old JSON file somehow has no ids,
                final sig =
                    '${sourceId}|${e.title}|${e.startTime.toIso8601String()}|${e.endTime.toIso8601String()}|${e.location ?? ""}|${e.description ?? ""}';
                final fixed = CalendarEvent(
                  id: 'imp_${_fnv1aHex(sig)}',
                  title: e.title,
                  startTime: e.startTime,
                  endTime: e.endTime,
                  location: e.location,
                  description: e.description,
                  source: e.source,
                  sourceId: e.sourceId,
                );
                final date = DateTime(fixed.startTime.year,
                    fixed.startTime.month, fixed.startTime.day);
                loadedMap.putIfAbsent(date, () => []).add(fixed);
              } else {
                final date = DateTime(
                    e.startTime.year, e.startTime.month, e.startTime.day);
                loadedMap.putIfAbsent(date, () => []).add(e);
              }
            }

            _importedEvents = _mergeEventMaps(_importedEvents, loadedMap);
          } catch (_) {}
        }
      }

      // Khal
      _khalEvents = {};
      bool khalConnectedNow = false;
      if (_khalEnabledByUser) {
        khalConnectedNow = await _verifyKhalConnection();
        if (khalConnectedNow) {
          _khalEvents = await _loadKhalEventsFromVdir();
        } else {
          _khalEnabledByUser = false;
          await _writeSettings({'khalEnabled': false});
        }
      }
      _khalConnected = khalConnectedNow;

      _events = _mergeEventMaps(
          _mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error loading calendar: $e';
        _isLoading = false;
      });
    }
  }

  Map<DateTime, List<CalendarEvent>> _sortedCopy(
      Map<DateTime, List<CalendarEvent>> src) {
    final out = <DateTime, List<CalendarEvent>>{};
    for (final e in src.entries) {
      final list = List<CalendarEvent>.of(e.value);
      list.sort((x, y) => x.startTime.compareTo(y.startTime));
      out[e.key] = list;
    }
    return out;
  }

  // The UI sorts events 
  Map<DateTime, List<CalendarEvent>> _mergeEventMaps(
    Map<DateTime, List<CalendarEvent>> a,
    Map<DateTime, List<CalendarEvent>> b,
  ) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;

    final out = <DateTime, List<CalendarEvent>>{};

    // Add all from A
    for (final e in a.entries) {
      out[e.key] = List.of(e.value);
    }

    // Add from B, checking for duplicates
    for (final e in b.entries) {
      if (!out.containsKey(e.key)) {
        out[e.key] = List.of(e.value);
      } else {
        final existingList = out[e.key]!;
        // Create a set of existing IDs for fast lookup
        final existingIds = existingList.map((evt) => evt.id).toSet();
        
        for (final newEvent in e.value) {
          // Only add if ID doesn't exist in the list
          if (!existingIds.contains(newEvent.id)) {
            existingList.add(newEvent);
            existingIds.add(newEvent.id);
          }
        }
      }
    }
    return out;
  }

  // Khal Utils

  String _xdgConfigHome() {
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.trim().isNotEmpty) return xdg.trim();
    return _joinPath([_homeDir(), '.config']);
  }

  Future<File?> _findKhalConfigFile() async {
    final cfgHome = _xdgConfigHome();
    final candidates = [
      _joinPath([cfgHome, 'khal', 'config']),
      _joinPath([cfgHome, 'khal', 'config.ini']),
      _joinPath([_homeDir(), '.khal', 'khal.conf']),
    ];

    for (final p in candidates) {
      final f = File(p);
      if (await f.exists()) return f;
    }
    return null;
  }

  Future<bool> _verifyKhalConnection() async {
    try {
      final version = await Process.run('khal', ['--version']);
      if (version.exitCode != 0) return false;

      final cfgFile = await _findKhalConfigFile();
      if (cfgFile == null) return false;

      final raw = await cfgFile.readAsLines();
      final paths = _extractKhalCalendarPaths(raw);
      if (paths.isEmpty) return false;

      final expanded = <String>[];
      for (final p in paths) {
        expanded.addAll(await _expandCalendarPathPattern(p));
      }

      for (final p in expanded) {
        if (await Directory(p).exists()) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  List<String> _extractKhalCalendarPaths(List<String> lines) {
    final out = <String>[];
    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';'))
        continue;

      final m = RegExp(r'^\s*path\s*=\s*(.+)$', caseSensitive: false)
          .firstMatch(line);
      if (m != null) {
        var val = m.group(1)!.trim();
        if ((val.startsWith('"') && val.endsWith('"')) ||
            (val.startsWith("'") && val.endsWith("'"))) {
          val = val.substring(1, val.length - 1);
        }
        val = _expandHomeAndEnv(val);
        out.add(val);
      }
    }
    return out;
  }

  String _expandHomeAndEnv(String path) {
    var p = path.trim();
    final home = _homeDir();
    if (p.startsWith('~')) {
      p = home + p.substring(1);
    }
    p = p.replaceAll('\$HOME', home);
    p = p.replaceAll('{HOME}', home);
    p = p.replaceAll('\${HOME}', home);
    return p;
  }

  Future<List<String>> _expandCalendarPathPattern(String pathPattern) async {
    if (!pathPattern.contains('*') && !pathPattern.contains('?')) {
      return [pathPattern];
    }

    final sep = Platform.pathSeparator;
    final wildcardIndex = pathPattern.indexOf(RegExp(r'[\*\?]'));
    final lastSepBeforeWildcard = pathPattern.lastIndexOf(sep, wildcardIndex);
    if (lastSepBeforeWildcard == -1) return [];

    final parent = pathPattern.substring(0, lastSepBeforeWildcard);
    final patternSegment = pathPattern.substring(lastSepBeforeWildcard + 1);

    final parentDir = Directory(parent);
    if (!await parentDir.exists()) return [];

    final escaped = RegExp.escape(patternSegment)
        .replaceAll(r'\*', '.*')
        .replaceAll(r'\?', '.');
    final rx = RegExp('^$escaped\$');

    final matches = <String>[];
    final entries =
        await parentDir.list(recursive: false, followLinks: false).toList();
    for (final ent in entries) {
      final name = _basename(ent.path);
      if (rx.hasMatch(name) && ent is Directory) {
        matches.add(ent.path);
      }
    }
    return matches;
  }

  Future<Map<DateTime, List<CalendarEvent>>> _loadKhalEventsFromVdir() async {
    final events = <DateTime, List<CalendarEvent>>{};
    try {
      final cfgFile = await _findKhalConfigFile();
      if (cfgFile == null) return events;

      final raw = await cfgFile.readAsLines();
      final paths = _extractKhalCalendarPaths(raw);

      final expanded = <String>[];
      for (final p in paths) {
        expanded.addAll(await _expandCalendarPathPattern(p));
      }

      final now = DateTime.now();
      final minViewable = DateTime(now.year - 1, 1, 1);
      final maxDate = DateTime(now.year + 2, 12, 31);

      for (final calPath in expanded) {
        final dir = Directory(calPath);
        if (!await dir.exists()) continue;

        final ents = await dir.list(recursive: false, followLinks: false).toList();
        // Filter valid files first
        final validFiles = ents.whereType<File>().where((e) => e.path.toLowerCase().endsWith('.ics'));

        // Parallel read for contents
        final contents = await Future.wait(validFiles.map((f) => f.readAsString()));

        // Parse in memory
        for (String content in contents) {
          try {
            final parsed = _parseICS(
              content,
              source: EventSource.khal,
              sourceId: 'khal',
              minViewable: minViewable,
              maxDate: maxDate,
            );
            parsed.forEach((date, list) {
              events.putIfAbsent(date, () => []);
              events[date]!.addAll(list);
            });
          } catch (_) {}
        }
      }
      for (final date in events.keys) {
        events[date]!.sort((a, b) => a.startTime.compareTo(b.startTime));
      }
    } catch (_) {}
    return events;
  }

  Future<void> _connectToKhal() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final ok = await _verifyKhalConnection();
    if (!ok) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("You don't have khal or you haven't set it up.")),
        );
      }
      return;
    }
    _khalEnabledByUser = true;
    await _writeSettings({'khalEnabled': true});
    _khalConnected = true;
    _khalEvents = await _loadKhalEventsFromVdir();
    final merged = _mergeEventMaps(
        _mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
    if (mounted) {
      setState(() {
        _events = merged;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Khal connected')));
    }
  }

  Future<void> _refreshKhalConnectionState() async {
    if (!_khalEnabledByUser) return;
    final ok = await _verifyKhalConnection();
    if (!ok) {
      _khalEnabledByUser = false;
      _khalConnected = false;
      _khalEvents = {};
      await _writeSettings({'khalEnabled': false});
      final merged = _mergeEventMaps(_manualEvents, _importedEvents);
      if (mounted) setState(() => _events = merged);
    }
  }

  // Add / Import Menu

  Future<void> _showAddMenu() async {
    await _refreshKhalConnectionState();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) {
        // The theme inside the builder so it updates live
        final theme = Theme.of(context);

        return Container(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Theme Switch Tile
              ListTile(
                leading: Icon(widget.currentIcon,
                    color: theme.colorScheme.onSurfaceVariant),
                title: const Text('Switch Theme'),
                onTap: () {
                  widget.onThemeToggle();
                },
              ),
              const Divider(), //divider

              // Event Tile
              ListTile(
                leading:
                    Icon(Icons.edit_calendar, color: theme.colorScheme.primary),
                title: const Text('Add Event Manually'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddEventDialog();
                },
              ),

              // Import Tile
              ListTile(
                leading: Icon(Icons.file_upload_outlined,
                    color: theme.colorScheme.secondary),
                title: const Text('Import ICS File'),
                onTap: () {
                  Navigator.pop(context);
                  Future.microtask(_importICS);
                },
              ),

              // View Imports Tile
              ListTile(
                leading:
                    Icon(Icons.folder_open, color: theme.colorScheme.tertiary),
                title: const Text('View Imports'),
                onTap: () {
                  Navigator.pop(context);
                  _viewImports();
                },
              ),

              // Khal Tile
              ListTile(
                leading: Icon(
                  Icons.link,
                  color: _khalConnected
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.primary,
                ),
                title:
                    Text(_khalConnected ? 'Khal connected' : 'Connect to Khal'),
                enabled: !_khalConnected,
                onTap: _khalConnected
                    ? null
                    : () {
                        Navigator.pop(context);
                        _connectToKhal();
                      },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _viewImports() async {
    await _ensureDirs();
    final theme = Theme.of(context);
    final files =
        await _importsDir().list(recursive: false, followLinks: false).toList();
    files.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    final onlyJson = files
        .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
        .toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      showDragHandle: true,
      builder: (context) => Container(
        padding: const EdgeInsets.only(bottom: 24),
        child: onlyJson.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'No Imports',
                    style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant
                            .withOpacity(0.7)),
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: onlyJson.length,
                itemBuilder: (context, index) {
                  final ent = onlyJson[index] as File;
                  final name = _basename(ent.path);
                  return ListTile(
                    leading: Icon(Icons.description_outlined,
                        color: theme.colorScheme.onSurfaceVariant),
                    title: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: theme.colorScheme.error),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete import?'),
                            content:
                                Text('This will remove events from:\n$name'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await ent.delete();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('Import deleted')));
                            }
                            if (Navigator.canPop(context))
                              Navigator.pop(context);
                            await _loadEvents();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed: $e')));
                            }
                          }
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _showAddEventDialog({CalendarEvent? existing}) async {
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AddEventDialog(
              initialSelectedDate: _selectedDate,
              fnv1aHex: _fnv1aHex,
              onSave: _addEvent,
              existing: existing,
              onUpdate: _updateManualEvent,
            );
          },
        );
      },
    );
  }

  // Edit a non-recurring manual event: remove the old instance, add the new one.
  Future<void> _updateManualEvent(
      CalendarEvent oldEvent, CalendarEvent newEvent) async {
    final oldDate = DateTime(oldEvent.startTime.year, oldEvent.startTime.month,
        oldEvent.startTime.day);
    final newDate = DateTime(newEvent.startTime.year, newEvent.startTime.month,
        newEvent.startTime.day);

    _manualEvents[oldDate]?.removeWhere((e) => e.id == oldEvent.id);
    if (_manualEvents[oldDate]?.isEmpty ?? false) {
      _manualEvents.remove(oldDate);
    }
    _manualEvents.putIfAbsent(newDate, () => []).add(newEvent);

    setState(() {
      _events = _mergeEventMaps(
          _mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
    });

    _saveManualEventsToDisk();
  }

  Future<void> _addEvent(DateTime date, CalendarEvent event) async {
    final normalized = DateTime(date.year, date.month, date.day);
    
    // Update In-Memory Map Immediately
    if (_manualEvents[normalized] == null) _manualEvents[normalized] = [];
    _manualEvents[normalized]!.add(event);

    // Instant Feedback
    if (event.rrule != null) {
      final now = DateTime.now();
      // Generate repeats for the UI immediately without parsing ICS
      _generateSafeRecurrences(
        _manualEvents, 
        event, 
        event.rrule!, 
        DateTime(now.year - 1, 1, 1), 
        DateTime(now.year + 2, 12, 31)
      );
    }

    // Update the Main View OPtimistically
    setState(() {
      _events = _mergeEventMaps(
          _mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
    });

    // Save to disk in background
    _saveManualEventsToDisk(); 
  }

  bool _sameEvent(CalendarEvent a, CalendarEvent b) => a.id == b.id;

  Future<void> _deleteEvent(DateTime date, CalendarEvent event) async {
    // Khal Events cannot be deleted here (for now)
    if (event.source == EventSource.khal) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Khal events cannot be deleted here. Please use khal/vdirsyncer.')));
      }
      return;
    }

    // Check if Recurring
    bool isRecurring = (event.rrule != null && event.rrule!.isNotEmpty) ||
        event.isGenerated ||
        (event.source == EventSource.imported && event.id.contains('_r'));

    String result = 'all'; // Default for non-recurring

    // Show Dialog ONLY if recurring
    if (isRecurring) {
      final selection = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Recurring Event?'),
          content: const Text('How would you like to delete this event?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'one'),
              child: const Text('This Event Only'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'following'),
              child: const Text('All Following'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'all'),
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              child: const Text('All Events'),
            ),
          ],
        ),
      );

      if (selection == 'cancel' || selection == null) return;
      result = selection;
    } else {
      // If not recurring,
      result = 'one';
    }

    // MANUAL EVENTS
    if (event.source == EventSource.manual) {
      final masterId =
          event.id.contains('_r') ? event.id.split('_r')[0] : event.id;

      CalendarEvent? masterEvent;
      for (var list in _manualEvents.values) {
        try {
          masterEvent =
              list.firstWhere((e) => e.id == masterId && !e.isGenerated);
          break;
        } catch (_) {}
      }

      if (masterEvent != null) {
        if (result == 'one') {
          // A: THIS EVENT ONLY (with Exception)
          final newExceptions = List<DateTime>.from(masterEvent.exceptionDates);
          newExceptions.add(event.startTime);

          // Check if it is hiding the master itself
          bool masterNowHidden = newExceptions.any((ex) =>
              ex.year == masterEvent!.startTime.year &&
              ex.month == masterEvent.startTime.month &&
              ex.day == masterEvent.startTime.day);

          final updatedMaster = masterEvent.copyWith(
            exceptionDates: newExceptions,
            isHidden: masterNowHidden,
          );
          _updateMasterEvent(masterEvent, updatedMaster);

        } else if (result == 'following') {
          // B: ALL FOLLOWING (Truncate)
          final cutOffDate =
              event.startTime.subtract(const Duration(seconds: 1));
          final untillStr = fmtIcsTime.format(cutOffDate);

          String newRrule = masterEvent.rrule ?? "";
          if (newRrule.contains('UNTIL=')) {
            newRrule = newRrule.replaceAll(
                RegExp(r'UNTIL=[^;]+'), 'UNTIL=$untillStr');
          } else {
            newRrule += ';UNTIL=$untillStr';
          }
          if (newRrule.contains('COUNT=')) {
            newRrule = newRrule.replaceAll(RegExp(r';?COUNT=[^;]+'), '');
          }

          final updatedMaster = CalendarEvent(
            id: masterEvent.id,
            title: masterEvent.title,
            startTime: masterEvent.startTime,
            endTime: masterEvent.endTime,
            location: masterEvent.location,
            description: masterEvent.description,
            source: masterEvent.source,
            sourceId: masterEvent.sourceId,
            rrule: newRrule,
            isGenerated: false,
            exceptionDates: masterEvent.exceptionDates,
          );
          _updateMasterEvent(masterEvent, updatedMaster);

        } else if (result == 'all') {
          // C: DELETE ALL
          _manualEvents.forEach((_, list) {
            list.removeWhere(
                (e) => e.id == masterId || e.id.startsWith('${masterId}_r'));
          });
        }
      }

      setState(() {
        _events = _mergeEventMaps(
            _mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
      });
      _saveManualEventsToDisk();
    }

    // IMPORTED EVENTS 
    else if (event.source == EventSource.imported && event.sourceId != null) {
      final file = File(_joinPath([_importsDir().path, event.sourceId!]));
      
      // Identify the group ID (strip the _r suffix)
      final masterId = event.id.contains('_r') ? event.id.split('_r')[0] : event.id;

      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          final List<dynamic> jsonList = json.decode(content);
          final List<dynamic> keptList = [];
          bool listChanged = false;

          for (final item in jsonList) {
            if (item is! Map<String, dynamic>) continue;
            
            final String itemId = item['id'] ?? '';
            // Determine if this item belongs to the event group
            final bool isTargetGroup = (itemId == masterId || itemId.startsWith('${masterId}_r'));
            
            bool shouldDelete = false;

            if (isTargetGroup) {
              if (result == 'all') {
                shouldDelete = true;
              } else if (result == 'following') {
                // Parse time to compare
                final DateTime itemStart = DateTime.parse(item['startTime']);
                // Delete if it starts on or after the selected instance
                if (itemStart.isAtSameMomentAs(event.startTime) || itemStart.isAfter(event.startTime)) {
                  shouldDelete = true;
                }
              } else {
                // 'one' - only exact ID match
                if (itemId == event.id) {
                  shouldDelete = true;
                }
              }
            }

            if (shouldDelete) {
              listChanged = true;
            } else {
              keptList.add(item);
            }
          }

          if (listChanged) {
            await file.writeAsString(json.encode(keptList));
            // Reload events to refresh the UI and Maps completely
            await _loadEvents(); 
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Imported event(s) deleted')));
            }
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error deleting import: $e')));
          }
        }
      }
    }
  }



  Future<void> _saveManualEventsToDisk() async {
    await _ensureDirs();
    final file = _manualFile();
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//EverCal Manual//EN');

    final processedIds = <String>{};

    _manualEvents.forEach((date, events) {
      for (var event in events) {
        if (event.source != EventSource.manual) continue;
        if (event.isGenerated) continue; // SKIP generated instances
        if (processedIds.contains(event.id)) continue;

        processedIds.add(event.id);

        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('UID:${event.id}'); // Save stable ID
        buffer.writeln('SUMMARY:${icsEscape(event.title)}');
        if (event.allDay) {
          buffer.writeln('DTSTART;VALUE=DATE:${fmtIcsDate.format(event.startTime)}');
          buffer.writeln('DTEND;VALUE=DATE:${fmtIcsDate.format(event.endTime)}');
        } else {
          buffer.writeln('DTSTART:${fmtIcsTime.format(event.startTime)}');
          buffer.writeln('DTEND:${fmtIcsTime.format(event.endTime)}');
        }
        if (event.location != null)
          buffer.writeln('LOCATION:${icsEscape(event.location!)}');
        if (event.description != null)
          buffer.writeln('DESCRIPTION:${icsEscape(event.description!)}');
        if (event.rrule != null)
          buffer.writeln('RRULE:${event.rrule}'); // Save Rule
          // Exception Dates
        if (event.exceptionDates.isNotEmpty) {
          for (final ex in event.exceptionDates) {
            buffer.writeln('EXDATE:${fmtIcsTime.format(ex)}');
          }
        }
        buffer.writeln('END:VEVENT');
      }
    });
    buffer.writeln('END:VCALENDAR');
    await file.writeAsString(buffer.toString());
  }

  // ICS to JSON [IMPORT]
  Future<void> _importICS() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ics'],
        dialogTitle: 'Import ICS',
      );
      if (result == null) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Import cancelled')));
        return;
      }
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) return;

      await _ensureDirs();
      final originalName =
          _sanitizeFilename(picked.name.isNotEmpty ? picked.name : 'import.ics');
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());

      final destName = originalName.toLowerCase().endsWith('.ics')
          ? '${originalName.substring(0, originalName.length - 4)}_$stamp.json'
          : '${originalName}_$stamp.json';
      final destPath = _joinPath([_importsDir().path, destName]);

      final content = await File(path).readAsString();

      final now = DateTime.now();
      final minView = DateTime(now.year - 5, 1, 1);
      final maxView = DateTime(now.year + 5, 12, 31);

      final parsedMap = _parseICS(
        content,
        source: EventSource.imported,
        sourceId: destName, // owning file id
        minViewable: minView,
        maxDate: maxView,
      );

      final flatList = parsedMap.values.expand((x) => x).toList();
      final jsonStr = json.encode(flatList.map((e) => e.toJson()).toList());

      await File(destPath).writeAsString(jsonStr);

      await _loadEvents();
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Import Successful')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  // ICS Parsing

  List<String> _unfoldLines(String content) {
    if (content.isEmpty) return const [];
    final unfolded = <String>[];

    for (final raw in LineSplitter.split(content)) {
      var line = raw.replaceAll('\r', '');
      if (line.isEmpty) continue;

      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (unfolded.isNotEmpty) unfolded.last += line.trimLeft();
      } else {
        unfolded.add(line.trim());
      }
    }
    return unfolded;
  }

  Map<DateTime, List<CalendarEvent>> _parseICS(
    String content, {
    required EventSource source,
    String? sourceId,
    DateTime? minViewable,
    DateTime? maxDate,
  }) {
    final events = <DateTime, List<CalendarEvent>>{};
    final lines = _unfoldLines(content);

    String? currentSummary;
    DateTime? currentStart;
    DateTime? currentEnd;
    String? currentLocation;
    String? currentDescription;
    String? currentUid;
    String? rrule;
    bool currentAllDay = false;

    List<DateTime> currentExDates = []; //
    bool inEvent = false;

    // Deterministic disambiguation
    final sigCounts = <String, int>{};

    final now = DateTime.now();
    final localMin = minViewable ?? DateTime(now.year - 1, 1, 1);
    final localMax = maxDate ?? DateTime(now.year + 2, 12, 31);

    for (var line in lines) {
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        currentSummary = null;
        currentStart = null;
        currentEnd = null;
        currentLocation = null;
        currentDescription = null;
        currentUid = null;
        rrule = null;
        currentAllDay = false;

        // RESET IT FOR EVERY NEW EVENT
        currentExDates = [];
        
      } else if (line == 'END:VEVENT' && inEvent) {
        if (currentSummary != null && currentStart != null) {
          final endTime =
              currentEnd ?? currentStart!.add(const Duration(hours: 1));

          final signature =
              '${sourceId ?? source.name}|${currentUid ?? ""}|${currentSummary!}|${currentStart!.toIso8601String()}|${endTime.toIso8601String()}|${currentLocation ?? ""}|${currentDescription ?? ""}';
          final baseHash = _fnv1aHex(signature);

          final seen = (sigCounts[baseHash] ?? 0) + 1;
          sigCounts[baseHash] = seen;

          final baseId = '${source.name}_${sourceId ?? "na"}_${baseHash}_$seen';

          // Check if the Master Event itself is an exception
          bool isMasterExcluded = currentExDates.any((ex) =>
              ex.year == currentStart!.year &&
              ex.month == currentStart!.month &&
              ex.day == currentStart!.day); 

          final baseEvent = CalendarEvent(
            id: baseId,
            title: currentSummary!,
            startTime: currentStart!,
            endTime: endTime,
            location: currentLocation,
            description: currentDescription,
            source: source,
            sourceId: sourceId,
            rrule: rrule,
            isGenerated: false,
            exceptionDates: currentExDates,
            isHidden: isMasterExcluded, // MARK HIDDEN IF EXCLUDED
            allDay: currentAllDay,
          );

          if (!baseEvent.startTime.isBefore(localMin) &&
              !baseEvent.startTime.isAfter(localMax)) {
            _addEventToMap(events, currentStart!, baseEvent);
          }

          if (rrule != null) {
            _generateSafeRecurrences(
                events, baseEvent, rrule!, localMin, localMax);
          }
        }
        inEvent = false;
      } else if (inEvent) {
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          final keyPart = line.substring(0, colonIndex).toUpperCase();
          final value = line.substring(colonIndex + 1);

          if (keyPart.startsWith('SUMMARY'))
            currentSummary = icsUnescape(value);
          else if (keyPart.startsWith('DTSTART')) {
            currentStart = _parseStrictDate(value);
            currentAllDay = isDateOnly(value);
          } else if (keyPart.startsWith('DTEND'))
            currentEnd = _parseStrictDate(value);
          else if (keyPart.startsWith('LOCATION'))
            currentLocation = icsUnescape(value);
          else if (keyPart.startsWith('DESCRIPTION')) {
            currentDescription = icsUnescape(value);
          } else if (keyPart.startsWith('UID')) {
            currentUid = value;
          } else if (keyPart.startsWith('RRULE')) {
            final val = value.trim();
            if (val.isNotEmpty) rrule = val;
          }
          
          // PARSE THE EXDATE LINE
          else if (keyPart.startsWith('EXDATE')) { 
             // If keyPart has parameters (like ;TZID=...), value is just the date.
             final datePart = value.trim();
             final dt = _parseStrictDate(datePart);
             if (dt != null) currentExDates.add(dt);
          }
        }
      }
    }
    return events;
  }

  void _addEventToMap(Map<DateTime, List<CalendarEvent>> events, DateTime start,
      CalendarEvent event) {
    final date = DateTime(start.year, start.month, start.day);
    events.putIfAbsent(date, () => []).add(event);
  }

  DateTime? _parseStrictDate(String value) {
    try {
      String dateStr = value.trim();
      bool isUtc = dateStr.endsWith('Z');
      if (isUtc) dateStr = dateStr.substring(0, dateStr.length - 1);

      if (dateStr.contains('T')) {
        final parts = dateStr.split('T');
        final d = parts[0];
        final t = parts[1];
        if (d.length == 8 && t.length >= 4) {
          final year = int.parse(d.substring(0, 4));
          final month = int.parse(d.substring(4, 6));
          final day = int.parse(d.substring(6, 8));
          final hour = int.parse(t.substring(0, 2));
          final minute = int.parse(t.substring(2, 4));
          if (isUtc)
            return DateTime.utc(year, month, day, hour, minute).toLocal();
          return DateTime(year, month, day, hour, minute);
        }
      }

      if (dateStr.length == 8) {
        return DateTime(
          int.parse(dateStr.substring(0, 4)),
          int.parse(dateStr.substring(4, 6)),
          int.parse(dateStr.substring(6, 8)),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  int _getWeekdayIndex(String day) {
    switch (day.toUpperCase()) {
      case 'MO': return DateTime.monday;
      case 'TU': return DateTime.tuesday;
      case 'WE': return DateTime.wednesday;
      case 'TH': return DateTime.thursday;
      case 'FR': return DateTime.friday;
      case 'SA': return DateTime.saturday;
      case 'SU': return DateTime.sunday;
      default: return DateTime.monday;
    }
  }

  // Recurrences
  void _generateSafeRecurrences(
    Map<DateTime, List<CalendarEvent>> events,
    CalendarEvent original,
    String rrule,
    DateTime minViewable,
    DateTime maxDate,
  ) {
    // Parse RRULE
    final parts = rrule.split(';');
    final map = <String, String>{};
    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      map[p.substring(0, idx).toUpperCase().trim()] =
          p.substring(idx + 1).trim();
    }

    final freq = (map['FREQ'] ?? '').toUpperCase();
    final interval = int.tryParse(map['INTERVAL'] ?? '1') ?? 1;
    final countLimit = int.tryParse(map['COUNT'] ?? '');
    DateTime? until;
    if (map.containsKey('UNTIL')) {
      until = _parseStrictDate(map['UNTIL']!);
    }

    // Parse BYDAY (e.g. "MO,WE,FR" or "1FR")
    final List<String> byDayParts =
        map.containsKey('BYDAY') ? map['BYDAY']!.split(',') : [];

    // Cap instances hard limit
    const int maxInstances = 500;

    // Setup Cursor
    DateTime cursor = original.startTime;
    final Duration duration = original.endTime.difference(original.startTime);

    int generatedCount = 0;
    int safetyLoop = 0;

    // **Need to improve**
    while (generatedCount < maxInstances && safetyLoop < 1000) {
      safetyLoop++;

      // Stop if cursor goes beyond max limits
      if (cursor.isAfter(maxDate)) break;

      // Generate Candidates for this Interval
      List<DateTime> candidates = [];

      if (freq == 'WEEKLY' && byDayParts.isNotEmpty) {
        // Find the Monday of this week, then add offsets
        final int currentWeekday = cursor.weekday;
        final DateTime monday =
            cursor.subtract(Duration(days: currentWeekday - 1));

        for (final part in byDayParts) {
          final wdIndex = _getWeekdayIndex(part);
          DateTime candidate = monday.add(Duration(days: wdIndex - 1));

          // Restore Time
          candidate = DateTime(candidate.year, candidate.month, candidate.day,
              original.startTime.hour, original.startTime.minute);

          candidates.add(candidate);
        }
      } else if (freq == 'MONTHLY' && byDayParts.isNotEmpty) {
        // Expand Nth Weekday (e.g. 1FR, -1MO)
        for (final part in byDayParts) {
          final RegExp reg = RegExp(r'^([-\d]+)?([A-Z]{2})$');
          final match = reg.firstMatch(part);
          if (match != null) {
            final posStr = match.group(1);
            final dayStr = match.group(2)!;
            final targetWd = _getWeekdayIndex(dayStr);

            if (posStr != null) {
              // Nth occurrence
              final int pos = int.parse(posStr);
              List<DateTime> monthDays = [];
              DateTime d = DateTime(cursor.year, cursor.month, 1,
                  original.startTime.hour, original.startTime.minute);
              while (d.month == cursor.month) {
                if (d.weekday == targetWd) monthDays.add(d);
                d = d.add(const Duration(days: 1));
              }

              if (pos > 0) {
                if (pos <= monthDays.length) candidates.add(monthDays[pos - 1]);
              } else if (pos < 0) {
                if (monthDays.length + pos >= 0)
                  candidates.add(monthDays[monthDays.length + pos]);
              }
            } else {
              // No position -> implied "Every X"
              DateTime d = DateTime(cursor.year, cursor.month, 1,
                  original.startTime.hour, original.startTime.minute);
              while (d.month == cursor.month) {
                if (d.weekday == targetWd) candidates.add(d);
                d = d.add(const Duration(days: 1));
              }
            }
          }
        }
      } else {
        // Default: Just the cursor itself
        candidates.add(cursor);
      }

      // Validate and Add Candidates
      candidates.sort();

      for (final start in candidates) {
        if (until != null && start.isAfter(until)) return;
        if (countLimit != null && generatedCount >= countLimit) return;
        if (start.isBefore(original.startTime)) continue;

        bool isExcluded = original.exceptionDates.any((ex) =>
            ex.year == start.year &&
            ex.month == start.month &&
            ex.day == start.day);

        generatedCount++;

        if (isExcluded) continue;

        if (start.isAfter(minViewable) && start.isBefore(maxDate)) {
          // Skip if it's the exact original instance
          if (start.isAtSameMomentAs(original.startTime)) continue;

          _addEventToMap(
            events,
            start,
            CalendarEvent(
              id: '${original.id}_r$generatedCount',
              title: original.title,
              startTime: start,
              endTime: start.add(duration),
              location: original.location,
              description: original.description,
              source: original.source,
              sourceId: original.sourceId,
              rrule: original.rrule,
              isGenerated: true,
              allDay: original.allDay,
            ),
          );
        }
      }

      // Advance Cursor
      if (freq == 'DAILY') {
        cursor = cursor.add(Duration(days: interval));
      } else if (freq == 'WEEKLY') {
        cursor = cursor.add(Duration(days: 7 * interval));
      } else if (freq == 'MONTHLY') {
        int newMonth = cursor.month + interval;
        int newYear = cursor.year + ((newMonth - 1) ~/ 12);
        newMonth = ((newMonth - 1) % 12) + 1;
        int newDay = cursor.day;
        final daysInNewMonth = DateTime(newYear, newMonth + 1, 0).day;
        if (newDay > daysInNewMonth) newDay = daysInNewMonth;
        cursor =
            DateTime(newYear, newMonth, newDay, cursor.hour, cursor.minute);
      } else if (freq == 'YEARLY') {
        cursor = DateTime(cursor.year + interval, cursor.month, cursor.day,
            cursor.hour, cursor.minute);
      } else {
        break;
      }
    }
  }

  // UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading)
      return Scaffold(
          body: Center(
              child: CircularProgressIndicator(
                  color: theme.colorScheme.primary)));
    if (_errorMessage != null)
      return Scaffold(body: Center(child: Text(_errorMessage!)));

    return Scaffold(
      floatingActionButton: ExpressiveButton(
        size: 56,
        color: theme.colorScheme.primary,
        onTap: _showAddMenu,
        child: Icon(Icons.add, color: theme.colorScheme.onPrimary),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7,
                    child: _buildCard(
                      theme,
                      Column(
                        children: [
                          _buildHeader(theme, compact: false),
                          // TOGGLE BETWEEN GRIDS
                          Expanded(
                            child: _viewMode == CalendarViewMode.month
                                ? MonthView(
                                    focusedMonth: _focusedMonth,
                                    selectedDate: _selectedDate,
                                    events: _events,
                                    onDateSelected: (d) => setState(() => _selectedDate = d),
                                  )
                                : WeekView(
                                    focusedMonth: _focusedMonth,
                                    selectedDate: _selectedDate,
                                    events: _events,
                                    scrollController: _weekScrollController,
                                    onDateSelected: (d) => setState(() => _selectedDate = d),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: _buildCard(
                      theme,
                      _buildSidebar(theme),
                      isVariant: true,
                    ),
                  ),
                ],
              ),
            );
          } else {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 450,
                    child: _buildCard(
                      theme,
                      Column(
                        children: [
                          _buildHeader(theme, compact: true),
                          Expanded(
                            child: _viewMode == CalendarViewMode.month
                                ? MonthView(
                                    focusedMonth: _focusedMonth,
                                    selectedDate: _selectedDate,
                                    events: _events,
                                    onDateSelected: (d) => setState(() => _selectedDate = d),
                                  )
                                : WeekView(
                                    focusedMonth: _focusedMonth,
                                    selectedDate: _selectedDate,
                                    events: _events,
                                    scrollController: _weekScrollController,
                                    onDateSelected: (d) => setState(() => _selectedDate = d),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 450,
                    child: _buildCard(
                      theme,
                      _buildSidebar(theme),
                      isVariant: true,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildCard(ThemeData theme, Widget child, {bool isVariant = false}) {
    return Container(
      decoration: BoxDecoration(
        color: isVariant
            ? theme.colorScheme.surfaceVariant
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }

  Widget _buildHeader(ThemeData theme, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.only(
        left: compact ? 16 : 32,
        top: compact ? 16 : 32,
        right: compact ? 16 : 32,
        // In Month mode keep 32/16. In Week mode, cut it to 0 or 8.
        bottom: _viewMode == CalendarViewMode.week ? 8 : (compact ? 16 : 32),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // CLICKABLE TITLE TO TOGGLE VIEW (will probably add a button in the futre)
          ViewSwitcher(
            title: fmtMonth.format(_focusedMonth),
            subtitle: fmtYear.format(_focusedMonth),
            isMonthView: _viewMode == CalendarViewMode.month,
            compact: compact, // 
            onTap: _toggleViewMode,
            theme: theme,
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Today',
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _focusedMonth = _viewMode == CalendarViewMode.month
                        ? DateTime(now.year, now.month)
                        : DateTime(now.year, now.month, now.day);
                    _selectedDate = DateTime(now.year, now.month, now.day);
                  });
                },
                icon: const Icon(Icons.today_outlined),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_viewMode == CalendarViewMode.month) {
                      _focusedMonth = DateTime(
                          _focusedMonth.year, _focusedMonth.month - 1);
                    } else {
                      // Week View: Go back 7 days
                      _focusedMonth =
                          _focusedMonth.subtract(const Duration(days: 7));
                    }
                  });
                },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    if (_viewMode == CalendarViewMode.month) {
                      _focusedMonth = DateTime(
                          _focusedMonth.year, _focusedMonth.month + 1);
                    } else {
                      // Week View: Go forward 7 days
                      _focusedMonth =
                          _focusedMonth.add(const Duration(days: 7));
                    }
                  });
                },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

//-----------------------------------------------------------------------------------------------------------------------------------

  Widget _buildSidebar(ThemeData theme) {
    final normalizedDate =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final events = (_events[normalizedDate] ?? const [])
        .where((e) => !e.isHidden)
        .toList();
    final isToday = _selectedDate.day == DateTime.now().day &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.year == DateTime.now().year;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          flex: 0,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.1))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fmtDayName.format(_selectedDate).toUpperCase(),
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.0,
                    fontSize: 24,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          fmtDayNum.format(_selectedDate),
                          style: TextStyle(
                            fontSize: 80,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onBackground,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ),
                    if (isToday)
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // WEATHER WIDGET
                if (_weather != null)
                  Builder(builder: (context) {
                    // include units
                    double displayTemp = _weather!.temp;
                    String unitSym = '°C';

                    if (_weatherUnit == WeatherUnit.fahrenheit) {
                      displayTemp = (displayTemp * 9 / 5) + 32;
                      unitSym = '°F';
                    } else if (_weatherUnit == WeatherUnit.kelvin) {
                      displayTemp = displayTemp + 273.15;
                      unitSym = 'K';
                    }

                    return Padding(
                      padding: const EdgeInsets.only(
                          bottom: 16), // Add spacing before the list
                      child: Material(
                        color: theme.brightness == Brightness.dark
                            ? Colors.black12
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _showLocationSearch,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_weather!.icon,
                                    size: 24,
                                    color:
                                        theme.colorScheme.onPrimaryContainer),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${displayTemp.round()}$unitSym',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: theme
                                            .colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                    Text(
                                      _weather!.description,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant),
                                    )
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(
                  child: Text('No Events',
                      style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant
                              .withOpacity(0.5))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  itemCount: events.length,
                  itemBuilder: (context, index) => EventCard(
                    event: events[index],
                    onDelete: () =>
                        _deleteEvent(_selectedDate, events[index]),
                    onEdit: (events[index].source == EventSource.manual &&
                            (events[index].rrule == null ||
                                events[index].rrule!.isEmpty))
                        ? () => _showAddEventDialog(existing: events[index])
                        : null,
                  ),
                ),
        ),
      ],
    );
  }
}