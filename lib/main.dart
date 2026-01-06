import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

enum AppThemeSetting { dark, light, auto }

// Global Static Formatters
final DateFormat _fmtMonth = DateFormat('MMMM');
final DateFormat _fmtYear = DateFormat('yyyy');
final DateFormat _fmtDayNum = DateFormat('d');
final DateFormat _fmtDayName = DateFormat('EEE');
final DateFormat _fmtTime = DateFormat('h:mm a');
final DateFormat _fmtIcsTime = DateFormat('yyyyMMdd\'T\'HHmm00');
final DateFormat _fmtGridDay = DateFormat('MMM d');

void main() {
  runApp(const MyCalendarApp());
}

// Button based on M3 expressive guidelines
class ExpressiveButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color color;
  final bool isSelected;
  final double size;
  final BorderSide side;

  const ExpressiveButton({
    super.key,
    required this.child,
    this.onTap,
    required this.color,
    this.isSelected = false,
    this.size = 50,
    this.side = BorderSide.none,
  });

  @override
  State<ExpressiveButton> createState() => _ExpressiveButtonState();
}

class _ExpressiveButtonState extends State<ExpressiveButton> {
  bool _isPressed = false;

  late ShapeBorder _idleShape;
  late ShapeBorder _morphShape;

  static const BoxShadow _inactiveShadow = BoxShadow(
    color: Colors.transparent,
    blurRadius: 6,
    spreadRadius: -1,
    offset: Offset(0, 3),
  );

  static const BoxShadow _activeShadow = BoxShadow(
    color: Color(0x26000000),
    blurRadius: 6,
    spreadRadius: -1,
    offset: Offset(0, 3),
  );

  @override
  void initState() {
    super.initState();
    _rebuildShapes();
  }

  @override
  void didUpdateWidget(covariant ExpressiveButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.side != widget.side) {
      _rebuildShapes();
    }
  }

  void _rebuildShapes() {
    _idleShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: widget.side,
    );

    _morphShape = StarBorder(
      points: 8,
      innerRadiusRatio: 0.85,
      pointRounding: 0.5,
      valleyRounding: 0.5,
      side: widget.side,
    );
  }

  @override
  Widget build(BuildContext context) {
    final shape = _isPressed ? _morphShape : _idleShape;
    final shadow =
        (_isPressed || widget.isSelected) ? _activeShadow : _inactiveShadow;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        width: widget.size,
        height: widget.size,
        decoration: ShapeDecoration(
          color: widget.color,
          shape: shape,
          shadows: [shadow],
        ),
        alignment: Alignment.center,
        child: widget.child,
      ),
    );
  }
}

class MyCalendarApp extends StatefulWidget {
  const MyCalendarApp({super.key});

  @override
  State<MyCalendarApp> createState() => _MyCalendarAppState();
}

class _MyCalendarAppState extends State<MyCalendarApp> {
  AppThemeSetting _themeSetting = AppThemeSetting.auto;
  ThemeMode _effectiveThemeMode = ThemeMode.dark;
  StreamSubscription<FileSystemEvent>? _themeFileSubscription;

  String get _stateFilePath {
    final home = Platform.environment['HOME'] ?? '';
    return '$home/.cache/quickshell/theme_mode';
  }

  @override
  void initState() {
    super.initState();
    _initThemeOnBoot();
  }

  @override
  void dispose() {
    _stopWatchingTheme();
    super.dispose();
  }

  Future<void> _initThemeOnBoot() async {
    try {
      final file = File(_stateFilePath);

      final dirExists = await file.parent.exists();
      final fileExists = dirExists && await file.exists();

      if (!mounted) return;

      if (fileExists) {
        setState(() {
          _themeSetting = AppThemeSetting.auto;
          _effectiveThemeMode = ThemeMode.dark; // safe default until read
        });
        _startWatchingTheme();
      } else {
        // if no statefile = fall back to dark
        setState(() {
          _themeSetting = AppThemeSetting.dark;
          _effectiveThemeMode = ThemeMode.dark;
        });
        _stopWatchingTheme();
      }
    } catch (_) {
      if (!mounted) return;
      // Fail closed to dark
      setState(() {
        _themeSetting = AppThemeSetting.dark;
        _effectiveThemeMode = ThemeMode.dark;
      });
      _stopWatchingTheme();
    }
  }

  // Cycle theme
  void _cycleTheme() {
    setState(() {
      if (_themeSetting == AppThemeSetting.dark) {
        _themeSetting = AppThemeSetting.light;
        _updateManualTheme(ThemeMode.light);
      } else if (_themeSetting == AppThemeSetting.light) {
        _themeSetting = AppThemeSetting.auto;
        _startWatchingTheme(); // looks for theme change script (statefile)
      } else {
        _themeSetting = AppThemeSetting.dark;
        _updateManualTheme(ThemeMode.dark);
      }
    });
  }

  //  Manual theme Mode
  void _updateManualTheme(ThemeMode mode) {
    _stopWatchingTheme();
    setState(() {
      _effectiveThemeMode = mode;
    });
  }

  // Auto Mode (from File Watcher)
  void _startWatchingTheme() {
    // Read immediately
    _readStateFile();

    // Watch for changes
    final file = File(_stateFilePath);

    // Cancel existing if any
    _themeFileSubscription?.cancel();

    // if state file doesn't exist, fall back to dark (and don't watch)
    try {
      if (!file.existsSync()) {
        if (mounted) {
          setState(() => _effectiveThemeMode = ThemeMode.dark);
        }
        return;
      }

      // Watch for modifications
      _themeFileSubscription =
          file.watch(events: FileSystemEvent.modify).listen((event) async {
        // Small delay so that shell script is finished writing to the file
        await Future.delayed(const Duration(milliseconds: 50));
        if (mounted) {
          _readStateFile();
        }
      });
    } catch (_) {
      if (mounted) setState(() => _effectiveThemeMode = ThemeMode.dark);
    }
  }

  void _stopWatchingTheme() {
    _themeFileSubscription?.cancel();
    _themeFileSubscription = null;
  }

  Future<void> _readStateFile() async {
    try {
      final file = File(_stateFilePath);

      // Missing file = dark
      if (!await file.exists()) {
        setState(() => _effectiveThemeMode = ThemeMode.dark);
        return;
      }

      final content = await file.readAsString();
      final trimmed = content.trim().toLowerCase();

      setState(() {
        if (trimmed == 'light') {
          _effectiveThemeMode = ThemeMode.light;
        } else {
          // Default to dark for 'dark' or any error
          _effectiveThemeMode = ThemeMode.dark;
        }
      });
    } catch (_) {
      // Fail to dark if permissions/path error
      setState(() => _effectiveThemeMode = ThemeMode.dark);
    }
  }

  // HELPER: Get Icon based on setting
  IconData get _currentThemeIcon {
    switch (_themeSetting) {
      case AppThemeSetting.dark:
        return Icons.dark_mode_rounded;
      case AppThemeSetting.light:
        return Icons.light_mode_rounded;
      case AppThemeSetting.auto:
        return Icons.brightness_auto_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // DARK THEME
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: 'Manrope',
      colorScheme: const ColorScheme.dark(
        background: Color(0xFF232a2e),
        surface: Color(0xFF2d353b),
        surfaceVariant: Color(0xFF3d484f),
        onSurfaceVariant: Color(0xFF859289),
        primary: Color(0xFFa7c080),
        primaryContainer: Color(0xFF425047),
        secondary: Color(0xFFd699b6),
        tertiary: Color(0xFF7fbbb3),
        onBackground: Color(0xFFd3c6aa),
        onSurface: Color(0xFFd3c6aa),
        onPrimary: Color(0xFF2d353b),
        onPrimaryContainer: Color(0xFFd3c6aa),
        error: Color(0xFFe67e80),
        outline: Color(0xFF4b565c),
      ),
      scaffoldBackgroundColor: const Color(0xFF232a2e),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF3d484f).withOpacity(0.5),
        thickness: 1,
      ),
    );

    // LIGHT THEME
    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'Manrope',
      colorScheme: const ColorScheme.light(
        background: Color(0xFFbec5b2),
        surface: Color(0xFFeaedc8),
        surfaceVariant: Color(0xFFf0f2d4),
        onSurfaceVariant: Color(0xFF5C6A72),
        primary: Color(0xFF8da165),
        primaryContainer: Color(0xFFdce3b8),
        secondary: Color(0xFFd699b6),
        tertiary: Color(0xFF7fbbb3),
        onBackground: Color(0xFF1e2326),
        onSurface: Color(0xFF1e2326),
        onPrimary: Color(0xFFeaedc8),
        onPrimaryContainer: Color(0xFF1e2326),
        error: Color(0xFFe67e80),
        outline: Color(0xFF939f91),
      ),
      scaffoldBackgroundColor: const Color(0xFFbec5b2),
      dividerTheme: DividerThemeData(
        color: const Color(0xFF939f91).withOpacity(0.5),
        thickness: 1,
      ),
    );

    return MaterialApp(
      title: 'EverCal',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _effectiveThemeMode, // Mode from above
      home: CalendarHome(
        onThemeToggle: _cycleTheme,
        isDarkMode: _effectiveThemeMode == ThemeMode.dark,
        currentIcon: _currentThemeIcon,
      ),
    );
  }
}

class WeatherData {
  final double temp;
  final String description;
  final IconData icon; 
  const WeatherData(
      {required this.temp, required this.description, required this.icon});
}

enum EventSource { manual, imported, khal }

class CalendarEvent {
  final String id; // stable ID given to each events
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;
  final EventSource source;
  final String? sourceId; // For imports, the JSON filename

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
    this.source = EventSource.manual,
    this.sourceId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'description': description,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> json, String sourceId) {
    return CalendarEvent(
      id: (json['id'] ?? '').toString(),
      title: json['title'] ?? 'No Title',
      startTime: DateTime.parse(json['startTime']),
      endTime: DateTime.parse(json['endTime']),
      location: json['location'],
      description: json['description'],
      source: EventSource.imported,
      sourceId: sourceId,
    );
  }
}

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

  Map<DateTime, List<CalendarEvent>> _events = {};
  Map<DateTime, List<CalendarEvent>> _manualEvents = {};
  Map<DateTime, List<CalendarEvent>> _importedEvents = {};
  Map<DateTime, List<CalendarEvent>> _khalEvents = {};

  WeatherData? _weather;
  bool _isLoading = true;
  String? _errorMessage;

  bool _khalConnected = false;
  bool _khalEnabledByUser = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _loadEvents();
    _loadWeather();
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

  // Weather
  Future<void> _loadWeather() async {
    try {
      double? lat;
      double? lon;
      
      // Try loading user preference
      final settings = await _readSettings();
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

        if (code <= 1) { desc = 'Clear Sky'; icon = Icons.wb_sunny_rounded; }
        else if (code <= 3) { desc = 'Partly Cloudy'; icon = Icons.cloud_rounded; }
        else if (code <= 48) { desc = 'Foggy'; icon = Icons.dehaze_rounded; }
        else if (code <= 65) { desc = 'Rain'; icon = Icons.grain_rounded; }
        else if (code <= 75) { desc = 'Snow'; icon = Icons.ac_unit_rounded; }
        else if (code <= 99) { desc = 'Thunderstorm'; icon = Icons.thunderstorm_rounded; }

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
    } catch (_) { /* silent fail */ }
  }


  Future<void> _showLocationSearch() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Weather Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                labelText: 'City Name',
                labelStyle: TextStyle(fontSize: 10),
                hintText: 'e.g. Vancouver, Tokyo',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.search),
              ),
              autofocus: true,
              onSubmitted: (val) => Navigator.pop(context, val),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () async {
                // Reset to auto and remove keys from settings
                final settings = await _readSettings();
                settings.remove('weather_lat');
                settings.remove('weather_lon');
                await _writeSettings(settings);
                
                Navigator.pop(context, null);
                _loadWeather(); // Reload to trigger auto-detect
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected Auto-Location')));
                }
              },
              icon: const Icon(Icons.my_location),
              label: const Text('Use Auto-Detect'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Search'),
          ),
        ],
      ),
    ).then((cityName) async {
      if (cityName != null && cityName.toString().isNotEmpty) {
        try {
          // Open-Meteo Geocoding
          final url = 'https://geocoding-api.open-meteo.com/v1/search?name=$cityName&count=1&format=json';
          final res = await http.get(Uri.parse(url));
          if (res.statusCode == 200) {
            final data = json.decode(res.body);
            if (data['results'] != null && data['results'].isNotEmpty) {
              final loc = data['results'][0];
              final lat = loc['latitude'];
              final lon = loc['longitude'];
              final name = loc['name'];

              // Merge into existing settings
              final settings = await _readSettings();
              settings['weather_lat'] = lat;
              settings['weather_lon'] = lon;
              await _writeSettings(settings);

              await _loadWeather();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location set to $name')));
              }
            } else {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('City not found')));
            }
          }
        } catch (_) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Search failed')));
        }
      }
    });
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
        final files = await iDir.list(recursive: false, followLinks: false).toList();
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
                final date = DateTime(fixed.startTime.year, fixed.startTime.month,
                    fixed.startTime.day);
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

  Map<DateTime, List<CalendarEvent>> _mergeEventMaps(
    Map<DateTime, List<CalendarEvent>> a,
    Map<DateTime, List<CalendarEvent>> b,
  ) {
    if (a.isEmpty) return _sortedCopy(b);
    if (b.isEmpty) return _sortedCopy(a);

    final out = <DateTime, List<CalendarEvent>>{};

    for (final e in a.entries) {
      out[e.key] = List.of(e.value);
    }

    for (final e in b.entries) {
      if (out.containsKey(e.key)) {
        out[e.key]!.addAll(e.value);
      } else {
        out[e.key] = List.of(e.value);
      }
    }

    for (final list in out.values) {
      list.sort((x, y) => x.startTime.compareTo(y.startTime));
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
      if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;

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

        final ents =
            await dir.list(recursive: false, followLinks: false).toList();
        for (final ent in ents) {
          if (ent is! File) continue;
          if (!ent.path.toLowerCase().endsWith('.ics')) continue;

          try {
            final content = await ent.readAsString();
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
    final merged =
        _mergeEventMaps(_mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
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

    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      showDragHandle: true,
      builder: (context) => Container(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_calendar, color: theme.colorScheme.primary),
              title: const Text('Add Event Manually'),
              onTap: () {
                Navigator.pop(context);
                _showAddEventDialog();
              },
            ),
            ListTile(
              leading: Icon(Icons.file_upload_outlined, color: theme.colorScheme.secondary),
              title: const Text('Import ICS File'),
              onTap: () {
                Navigator.pop(context);
                Future.microtask(_importICS);
              },
            ),
            ListTile(
              leading: Icon(Icons.folder_open, color: theme.colorScheme.tertiary),
              title: const Text('View Imports'),
              onTap: () {
                Navigator.pop(context);
                _viewImports();
              },
            ),
            ListTile(
              leading: Icon(
                Icons.link,
                color: _khalConnected ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
              ),
              title: Text(_khalConnected ? 'Khal connected' : 'Connect to Khal'),
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
      ),
    );
  }

  Future<void> _viewImports() async {
    await _ensureDirs();
    final theme = Theme.of(context);
    final files =
        await _importsDir().list(recursive: false, followLinks: false).toList();
    files.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    final onlyJson =
        files.where((e) => e is File && e.path.toLowerCase().endsWith('.json')).toList();

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
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7)),
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
                    leading: Icon(Icons.description_outlined, color: theme.colorScheme.onSurfaceVariant),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      icon: Icon(Icons.close, color: theme.colorScheme.error),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete import?'),
                            content: Text('This will remove events from:\n$name'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          try {
                            await ent.delete();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import deleted')));
                            }
                            if (Navigator.canPop(context)) Navigator.pop(context);
                            await _loadEvents();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
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

  Future<void> _showAddEventDialog() async {
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();

    final now = DateTime.now();
    DateTime start =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, 0);
    DateTime end = start.add(const Duration(hours: 1));

    DateTime startDate = DateTime(start.year, start.month, start.day);
    TimeOfDay startTime = TimeOfDay(hour: start.hour, minute: start.minute);

    DateTime endDate = DateTime(end.year, end.month, end.day);
    TimeOfDay endTime = TimeOfDay(hour: end.hour, minute: end.minute);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            Future<void> pickDateTime(bool isStart) async {
              final initialDate = isStart ? startDate : endDate;
              final pickedDate = await showDatePicker(
                context: context,
                initialDate: initialDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (pickedDate != null) {
                final initialTime = isStart ? startTime : endTime;
                final pickedTime =
                    await showTimePicker(context: context, initialTime: initialTime);
                if (pickedTime != null) {
                  setStateDialog(() {
                    if (isStart) {
                      startDate = pickedDate;
                      startTime = pickedTime;
                    } else {
                      endDate = pickedDate;
                      endTime = pickedTime;
                    }
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('New Event'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                          labelText: 'Title', border: OutlineInputBorder()),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                          labelText: 'Location', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                          labelText: 'Description', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    _buildDateTimeSelector(context, 'Starts', startDate, startTime,
                        () => pickDateTime(true)),
                    const SizedBox(height: 12),
                    _buildDateTimeSelector(context, 'Ends', endDate, endTime,
                        () => pickDateTime(false)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.isEmpty) return;
                    final s = DateTime(startDate.year, startDate.month, startDate.day,
                        startTime.hour, startTime.minute);
                    final e = DateTime(endDate.year, endDate.month, endDate.day,
                        endTime.hour, endTime.minute);
                    if (!e.isAfter(s)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('End time must be after start time.')),
                      );
                      return;
                    }

                    final sig =
                        'manual|${titleController.text}|${s.toIso8601String()}|${e.toIso8601String()}|${locationController.text}|${descriptionController.text}';
                    final id = 'man_${_fnv1aHex(sig)}';

                    _addEvent(
                        s,
                        CalendarEvent(
                          id: id,
                          title: titleController.text,
                          startTime: s,
                          endTime: e,
                          location: locationController.text.isEmpty
                              ? null
                              : locationController.text,
                          description: descriptionController.text.isEmpty
                              ? null
                              : descriptionController.text,
                          source: EventSource.manual,
                          sourceId: 'manual',
                        ));
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDateTimeSelector(BuildContext context, String label, DateTime date,
      TimeOfDay time, VoidCallback onTap) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Text(_fmtGridDay.format(date)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    time.format(context),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addEvent(DateTime date, CalendarEvent event) async {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() {
      _manualEvents.putIfAbsent(normalized, () => []);
      _manualEvents[normalized] = [..._manualEvents[normalized]!, event];
      _manualEvents[normalized]!.sort((a, b) => a.startTime.compareTo(b.startTime));
      _events = _mergeEventMaps(_mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
    });
    await _saveManualEventsToDisk();
  }

  bool _sameEvent(CalendarEvent a, CalendarEvent b) => a.id == b.id;

  Future<void> _deleteEvent(DateTime date, CalendarEvent event) async {
    if (event.source == EventSource.khal) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Khal events cannot be deleted here. Please use khal/vdirsyncer.')),
        );
      }
      return;
    }

    final normalized = DateTime(date.year, date.month, date.day);
    bool changed = false;

    if (event.source == EventSource.manual) {
      final list = _manualEvents[normalized];
      if (list != null) {
        final int initialLen = list.length;
        list.removeWhere((e) => e.id == event.id);
        if (list.length < initialLen) {
          if (list.isEmpty) _manualEvents.remove(normalized);
          changed = true;
          await _saveManualEventsToDisk();
        }
      }
    } else if (event.source == EventSource.imported && event.sourceId != null) {
      final list = _importedEvents[normalized];
      if (list != null) {
        final int initialLen = list.length;
        list.removeWhere((e) => e.id == event.id);

        if (list.length < initialLen) {
          if (list.isEmpty) _importedEvents.remove(normalized);
          changed = true;

          try {
            final file = File(_joinPath([_importsDir().path, event.sourceId!]));
            if (await file.exists()) {
              final content = await file.readAsString();
              final List<dynamic> jsonList = json.decode(content);

              jsonList.removeWhere((item) => item is Map && item['id'] == event.id);

              await file.writeAsString(json.encode(jsonList));
            }
          } catch (_) {}

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Event deleted')));
          }
        }
      }
    }

    if (changed) {
      setState(() {
        _events = _mergeEventMaps(_mergeEventMaps(_manualEvents, _importedEvents), _khalEvents);
      });
    }
  }

  Future<void> _saveManualEventsToDisk() async {
    await _ensureDirs();
    final file = _manualFile();
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//EverCal Manual//EN');
    _manualEvents.forEach((date, events) {
      for (var event in events) {
        if (event.source != EventSource.manual) continue;
        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('SUMMARY:${event.title}');
        buffer.writeln('DTSTART:${_fmtIcsTime.format(event.startTime)}');
        buffer.writeln('DTEND:${_fmtIcsTime.format(event.endTime)}');
        if (event.location != null) buffer.writeln('LOCATION:${event.location}');
        if (event.description != null) buffer.writeln('DESCRIPTION:${event.description}');
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import cancelled')));
        return;
      }
      final picked = result.files.single;
      final path = picked.path;
      if (path == null) return;

      await _ensureDirs();
      final originalName = _sanitizeFilename(picked.name.isNotEmpty ? picked.name : 'import.ics');
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import Successful')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
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
    bool inEvent = false;

    // Deterministic disambiguation for same(identical) events just to be safe
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
      } else if (line == 'END:VEVENT' && inEvent) {
        if (currentSummary != null && currentStart != null) {
          final endTime = currentEnd ?? currentStart!.add(const Duration(hours: 1));

          final signature =
              '${sourceId ?? source.name}|${currentUid ?? ""}|${currentSummary!}|${currentStart!.toIso8601String()}|${endTime.toIso8601String()}|${currentLocation ?? ""}|${currentDescription ?? ""}';
          final baseHash = _fnv1aHex(signature);

          final seen = (sigCounts[baseHash] ?? 0) + 1;
          sigCounts[baseHash] = seen;

          final baseId = '${source.name}_${sourceId ?? "na"}_${baseHash}_$seen';

          final baseEvent = CalendarEvent(
            id: baseId,
            title: currentSummary!,
            startTime: currentStart!,
            endTime: endTime,
            location: currentLocation,
            description: currentDescription,
            source: source,
            sourceId: sourceId,
          );

          if (!baseEvent.startTime.isBefore(localMin) && !baseEvent.startTime.isAfter(localMax)) {
            _addEventToMap(events, currentStart!, baseEvent);
          }

          if (rrule != null) {
            _generateSafeRecurrences(events, baseEvent, rrule!, localMin, localMax);
          }
        }
        inEvent = false;
      } else if (inEvent) {
        final colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          final keyPart = line.substring(0, colonIndex).toUpperCase();
          final value = line.substring(colonIndex + 1);

          if (keyPart.startsWith('SUMMARY')) currentSummary = value;
          else if (keyPart.startsWith('DTSTART')) currentStart = _parseStrictDate(value);
          else if (keyPart.startsWith('DTEND')) currentEnd = _parseStrictDate(value);
          else if (keyPart.startsWith('LOCATION')) currentLocation = value;
          else if (keyPart.startsWith('DESCRIPTION')) {
            currentDescription = value.replaceAll('\\n', '\n').replaceAll('\\,', ',').replaceAll('\\;', ';');
          } else if (keyPart.startsWith('UID')) {
            currentUid = value;
          } else if (keyPart.startsWith('RRULE')) {
            rrule = value;
          }
        }
      }
    }
    return events;
  }

  void _addEventToMap(Map<DateTime, List<CalendarEvent>> events, DateTime start, CalendarEvent event) {
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
          if (isUtc) return DateTime.utc(year, month, day, hour, minute).toLocal();
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

   
  // SAFE Recurrence Generation 
   
  void _generateSafeRecurrences(
    Map<DateTime, List<CalendarEvent>> events,
    CalendarEvent original,
    String rrule,
    DateTime minViewable,
    DateTime maxDate,
  ) {
    // Parse RRULE into a map
    final parts = rrule.split(';');
    final map = <String, String>{};
    for (final p in parts) {
      final idx = p.indexOf('=');
      if (idx <= 0) continue;
      map[p.substring(0, idx).toUpperCase().trim()] = p.substring(idx + 1).trim();
    }

    final freq = (map['FREQ'] ?? '').toUpperCase();
    final interval = int.tryParse(map['INTERVAL'] ?? '1') ?? 1;
    final count = int.tryParse(map['COUNT'] ?? '');
    DateTime? until;
    if (map.containsKey('UNTIL')) {
      until = _parseStrictDate(map['UNTIL']!);
    }

    // Safety valve: cap instances no matter what
    const int maxInstances = 500;

    // COUNT includes the original event. 
    final int? maxAdditional = (count != null && count > 1) ? (count - 1) : null;

    DateTime nextStart = original.startTime;
    DateTime nextEnd = original.endTime;

    int generated = 0;
    while (generated < maxInstances) {
      // Advance by frequency
      if (freq == 'DAILY') {
        nextStart = nextStart.add(Duration(days: interval));
        nextEnd = nextEnd.add(Duration(days: interval));
      } else if (freq == 'WEEKLY') {
        nextStart = nextStart.add(Duration(days: 7 * interval));
        nextEnd = nextEnd.add(Duration(days: 7 * interval));
      } else if (freq == 'MONTHLY') {
        nextStart = DateTime(nextStart.year, nextStart.month + interval, nextStart.day, nextStart.hour, nextStart.minute);
        nextEnd = DateTime(nextEnd.year, nextEnd.month + interval, nextEnd.day, nextEnd.hour, nextEnd.minute);
      } else {
        // unsupported FREQ (YEARLY etc)
        break;
      }

      if (until != null && nextStart.isAfter(until)) break;
      if (nextStart.isAfter(maxDate)) break;

      generated++;

      if (maxAdditional != null && generated > maxAdditional) break;

      if (nextStart.isAfter(minViewable)) {
        _addEventToMap(
          events,
          nextStart,
          CalendarEvent(
            id: '${original.id}_r$generated',
            title: original.title,
            startTime: nextStart,
            endTime: nextEnd,
            location: original.location,
            description: original.description,
            source: original.source,
            sourceId: original.sourceId,
          ),
        );
      }
    }
  }

   
  // UI
   
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
    if (_errorMessage != null) return Scaffold(body: Center(child: Text(_errorMessage!)));

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
                          Expanded(child: _buildCalendarGrid(theme)),
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
                          Expanded(child: _buildCalendarGrid(theme)),
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
        color: isVariant ? theme.colorScheme.surfaceVariant : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }

  Widget _buildHeader(ThemeData theme, {required bool compact}) {
    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_fmtMonth.format(_focusedMonth),
                  style: compact ? theme.textTheme.headlineMedium : theme.textTheme.displayMedium),
              Text(
                _fmtYear.format(_focusedMonth),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onBackground.withOpacity(0.5),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ExpressiveButton(
                  size: 48,
                  color: theme.colorScheme.primaryContainer,
                  onTap: widget.onThemeToggle,
                  child: Icon(
                    widget.currentIcon,
                    //widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(ThemeData theme) {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday % 7;
    final totalCells = ((daysInMonth + startingWeekday) / 7).ceil() * 7;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double gridHeight = constraints.maxHeight;
        final double gridWidth = constraints.maxWidth;
        final double cellHeight = ((gridHeight - 32) / 6).clamp(1.0, double.infinity);
        final double cellWidth = (gridWidth - 16) / 7;
        final double childAspectRatio = cellWidth / cellHeight;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                    .map((d) => Expanded(
                          child: Center(
                            child: Text(
                              d,
                              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: childAspectRatio,
                ),
                itemCount: totalCells,
                itemBuilder: (context, index) {
                  final dayNumber = index - startingWeekday + 1;
                  if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox();
                  final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);

                  final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month && date.year == _selectedDate.year;
                  final isToday = date == today;
                  final events = _events[DateTime(date.year, date.month, date.day)] ?? const [];

                  return Center(
                    child: ExpressiveButton(
                      size: cellHeight < 50 ? cellHeight : 50,
                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                      isSelected: isSelected,
                      side: isToday && !isSelected ? BorderSide(color: theme.colorScheme.primary, width: 1) : BorderSide.none,
                      onTap: () => setState(() => _selectedDate = date),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$dayNumber',
                              style: TextStyle(
                                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
                                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (events.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    final normalizedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final events = _events[normalizedDate] ?? const [];
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
              border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1))),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fmtDayName.format(_selectedDate).toUpperCase(),
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
                          _fmtDayNum.format(_selectedDate),
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
                        decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // WEATHER WIDGET
                if (_weather != null)
                  InkWell(
                    onTap: _showLocationSearch, 
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? Colors.black12
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_weather!.icon,
                              size: 24,
                              color: theme.colorScheme.onPrimaryContainer),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_weather!.temp.round()}°C',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              Text(
                                _weather!.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant),
                              )
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: events.isEmpty
              ? Center(child: Text('No Events', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5))))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  itemCount: events.length,
                  itemBuilder: (context, index) => _EventCard(
                    event: events[index],
                    onDelete: () => _deleteEvent(_selectedDate, events[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _EventCard extends StatefulWidget {
  final CalendarEvent event;
  final VoidCallback onDelete;
  const _EventCard({required this.event, required this.onDelete});

  @override
  State<_EventCard> createState() => _EventCardState();
}

class _EventCardState extends State<_EventCard> {
  bool _expanded = false;

  Color _getRandomColor(String title) {
    const colors = [
      Color(0xFFe67e80),
      Color(0xFFe69875),
      Color(0xFFdbbc7f),
      Color(0xFFa7c080),
      Color(0xFF7fbbb3),
      Color(0xFFd699b6),
    ];
    return colors[title.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getRandomColor(widget.event.title);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            splashColor: color.withOpacity(0.3),
            highlightColor: color.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.event.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                            const SizedBox(height: 4),
                            Text(
                              '${_fmtTime.format(widget.event.startTime)} - ${_fmtTime.format(widget.event.endTime)}',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(Icons.expand_more, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        Divider(color: theme.colorScheme.outline.withOpacity(0.1)),
                        const SizedBox(height: 8),
                        if (widget.event.location != null && widget.event.location!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.location_on_outlined, size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(child: Text(widget.event.location!, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
                              ],
                            ),
                          ),
                        if (widget.event.description != null && widget.event.description!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.notes, size: 16, color: color),
                                const SizedBox(width: 8),
                                Expanded(child: Text(widget.event.description!, style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
                              ],
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: widget.onDelete,
                            icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                            label: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                          ),
                        ),
                      ],
                    ),
                    crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
