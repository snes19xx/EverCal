import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyCalendarApp());
}

class MyCalendarApp extends StatelessWidget {
  const MyCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EverCal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        fontFamily: 'Manrope',
        colorScheme: const ColorScheme.dark(
          background: Color(0xFF232a2e), // Everforest Hard Dark
          surface: Color(0xFF2d353b), // Everforest Background
          surfaceVariant: Color(0xFF3d484f), // Lighter surface
          onSurfaceVariant: Color(0xFF859289),
          primary: Color(0xFFa7c080), // Green Accent
          secondary: Color(0xFFd699b6), // Pink Accent
          tertiary: Color(0xFF7fbbb3), // Blue Accent
          onBackground: Color(0xFFd3c6aa), // Foreground text
          onSurface: Color(0xFFd3c6aa),
          onPrimary: Color(0xFF2d353b), // Dark text on Green
          error: Color(0xFFe67e80), // Red
          outline: Color(0xFF4b565c),
        ),
        scaffoldBackgroundColor: const Color(0xFF232a2e),
        dividerTheme: DividerThemeData(
          color: const Color(0xFF3d484f).withOpacity(0.5),
          thickness: 1,
        ),
      ),
      home: const CalendarHome(),
    );
  }
}

class WeatherData {
  final double temp;
  final String description;
  final String icon;
  WeatherData({required this.temp, required this.description, required this.icon});
}

class CalendarEvent {
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;

  CalendarEvent({
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
  });
}

class CalendarHome extends StatefulWidget {
  const CalendarHome({super.key});

  @override
  State<CalendarHome> createState() => _CalendarHomeState();
}

class _CalendarHomeState extends State<CalendarHome> with TickerProviderStateMixin {
  late DateTime _selectedDate;
  DateTime _focusedMonth = DateTime.now();
  Map<DateTime, List<CalendarEvent>> _events = {};
  WeatherData? _weather;
  bool _isLoading = true;
  String? _errorMessage;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _loadEvents();
    _loadWeather();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadWeather() async {
    try {
      const lat = 43.6617;
      const lon = -79.3951;
      final url = 'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m,weather_code&temperature_unit=celsius';
      
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final temp = data['current']['temperature_2m'];
        final code = data['current']['weather_code'];
        
        String desc = 'Clear';
        String icon = '☀️';
        if (code <= 1) { desc = 'Clear Sky'; icon = '☀️'; }
        else if (code <= 3) { desc = 'Partly Cloudy'; icon = '⛅'; }
        else if (code <= 48) { desc = 'Foggy'; icon = '🌫️'; }
        else if (code <= 65) { desc = 'Rain'; icon = '🌧️'; }
        else if (code <= 75) { desc = 'Snow'; icon = '❄️'; }
        else if (code <= 99) { desc = 'Thunderstorm'; icon = '⛈️'; }
        
        if (mounted) {
          setState(() {
            _weather = WeatherData(temp: temp.toDouble(), description: desc, icon: icon);
          });
        }
      }
    } catch (e) { /* silent fail */ }
  }

  Future<void> _loadEvents() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final icsPath = '$homeDir/Documents/Cal/gcal.ics';
      
      final file = File(icsPath);
      if (!await file.exists()) {
        setState(() { _events = {}; _isLoading = false; });
        _fadeController.forward();
        return;
      }

      final content = await file.readAsString();
      final events = _parseICS(content);

      setState(() { _events = events; _isLoading = false; });
      _fadeController.forward();
    } catch (e) {
      setState(() { _errorMessage = 'Error loading calendar: $e'; _isLoading = false; });
    }
  }

  Future<void> _showAddMenu() async {
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
              onTap: () { Navigator.pop(context); _showAddEventDialog(); },
            ),
            ListTile(
              leading: Icon(Icons.file_upload_outlined, color: theme.colorScheme.secondary),
              title: const Text('Import ICS File'),
              onTap: () { Navigator.pop(context); _importICS(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddEventDialog() async {
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    final descriptionController = TextEditingController();
    
    DateTime startDate = _selectedDate;
    TimeOfDay startTime = TimeOfDay.now().replacing(minute: 0);
    DateTime endDate = _selectedDate;
    TimeOfDay endTime = TimeOfDay.now().replacing(hour: TimeOfDay.now().hour + 1, minute: 0);

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
                final pickedTime = await showTimePicker(context: context, initialTime: initialTime);
                if (pickedTime != null) {
                  setStateDialog(() {
                    if (isStart) { startDate = pickedDate; startTime = pickedTime; }
                    else { endDate = pickedDate; endTime = pickedTime; }
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
                      decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Location', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    _buildDateTimeSelector(context, 'Starts', startDate, startTime, () => pickDateTime(true)),
                    const SizedBox(height: 12),
                    _buildDateTimeSelector(context, 'Ends', endDate, endTime, () => pickDateTime(false)),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      final start = DateTime(startDate.year, startDate.month, startDate.day, startTime.hour, startTime.minute);
                      final end = DateTime(endDate.year, endDate.month, endDate.day, endTime.hour, endTime.minute);
                      _addEvent(start, CalendarEvent(
                        title: titleController.text, 
                        startTime: start, 
                        endTime: end, 
                        location: locationController.text.isEmpty ? null : locationController.text,
                        description: descriptionController.text.isEmpty ? null : descriptionController.text
                      ));
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      }
    );
  }

  Widget _buildDateTimeSelector(BuildContext context, String label, DateTime date, TimeOfDay time, VoidCallback onTap) {
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
                Text(DateFormat('MMM d').format(date)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    time.format(context),
                    style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  Future<void> _pushToKhal(CalendarEvent event) async {
     // IMPORTANT: Change 'personal' to your actual calendar name!
    // Run 'khal printcalendars' in terminal to find the valid name.
    const calendarName = 'XXXXXXXXXX'; 

    try {
      final startFmt = DateFormat('yyyy-MM-dd HH:mm').format(event.startTime);
      final endFmt = DateFormat('yyyy-MM-dd HH:mm').format(event.endTime);

      final args = ['new', '-a', calendarName, startFmt, endFmt, event.title];
      
      if (event.location != null && event.location!.isNotEmpty) {
        args.add('-l');
        args.add(event.location!);
      }

      if (event.description != null && event.description!.isNotEmpty) {
        args.add('::');
        args.add(event.description!);
      }

      final result = await Process.run('khal', args);
      
      if (result.exitCode != 0) {
        print('Khal Error: ${result.stderr}');
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
               content: Text('Saved locally, but Khal failed: ${result.stderr}'), 
               backgroundColor: Colors.orange,
               duration: const Duration(seconds: 5),
             )
           );
        }
      } else {
        print('Successfully added to Khal');
      }
    } catch (e) {
      print('Khal Exception: $e');
    }
  }

  Future<void> _addEvent(DateTime date, CalendarEvent event) async {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() {
      _events[normalized] = [...(_events[normalized] ?? []), event];
      _events[normalized]!.sort((a, b) => a.startTime.compareTo(b.startTime));
    });
    
    await _saveEventsToDisk();
    await _pushToKhal(event);
  }

  Future<void> _importICS() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null) {
      try {
        File file = File(result.files.single.path!);
        final content = await file.readAsString();
        final newEvents = _parseICS(content);
        final mergedEvents = Map<DateTime, List<CalendarEvent>>.from(_events);
        newEvents.forEach((date, list) {
          if (mergedEvents.containsKey(date)) mergedEvents[date]!.addAll(list);
          else mergedEvents[date] = list;
          mergedEvents[date]!.sort((a, b) => a.startTime.compareTo(b.startTime));
        });
        setState(() { _events = mergedEvents; });
        await _saveEventsToDisk();
        
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import Successful')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }

  Future<void> _deleteEvent(DateTime date, CalendarEvent event) async {
    final normalized = DateTime(date.year, date.month, date.day);
    setState(() {
      _events[normalized]?.remove(event);
      if (_events[normalized]?.isEmpty ?? false) _events.remove(normalized);
    });
    await _saveEventsToDisk();
  }

  Future<void> _saveEventsToDisk() async {
    final homeDir = Platform.environment['HOME'] ?? '';
    final icsPath = '$homeDir/Documents/Cal/gcal.ics';
    final file = File(icsPath);
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//My Beautiful Linux Calendar//EN');
    _events.forEach((date, events) {
      for (var event in events) {
        buffer.writeln('BEGIN:VEVENT');
        buffer.writeln('SUMMARY:${event.title}');
        buffer.writeln('DTSTART:${DateFormat('yyyyMMdd\'T\'HHmm00').format(event.startTime)}');
        buffer.writeln('DTEND:${DateFormat('yyyyMMdd\'T\'HHmm00').format(event.endTime)}');
        if (event.location != null) buffer.writeln('LOCATION:${event.location}');
        if (event.description != null) buffer.writeln('DESCRIPTION:${event.description}');
        buffer.writeln('END:VEVENT');
      }
    });
    buffer.writeln('END:VCALENDAR');
    await file.writeAsString(buffer.toString());
  }

  List<String> _unfoldLines(String content) {
    final rawLines = content.split('\n');
    final unfolded = <String>[];
    for (var line in rawLines) {
      line = line.replaceAll('\r', '');
      if (line.isEmpty) continue;
      if (line.startsWith(' ') || line.startsWith('\t')) {
        if (unfolded.isNotEmpty) unfolded.last += line.trimLeft();
      } else {
        unfolded.add(line.trim());
      }
    }
    return unfolded;
  }

  Map<DateTime, List<CalendarEvent>> _parseICS(String content) {
    final events = <DateTime, List<CalendarEvent>>{};
    final lines = _unfoldLines(content);
    
    String? currentSummary;
    DateTime? currentStart;
    DateTime? currentEnd;
    String? currentLocation;
    String? currentDescription;
    String? rrule;
    bool inEvent = false;
    
    for (var line in lines) {
      if (line == 'BEGIN:VEVENT') {
        inEvent = true;
        currentSummary = null; currentStart = null; currentEnd = null; currentLocation = null; currentDescription = null; rrule = null;
      } else if (line == 'END:VEVENT' && inEvent) {
        if (currentSummary != null && currentStart != null) {
          final endTime = currentEnd ?? currentStart.add(const Duration(hours: 1));
          final baseEvent = CalendarEvent(
            title: currentSummary, 
            startTime: currentStart, 
            endTime: endTime, 
            location: currentLocation,
            description: currentDescription
          );
          
          _addEventToMap(events, currentStart, baseEvent);
          if (rrule != null) _generateSafeRecurrences(events, baseEvent, rrule);
        }
        inEvent = false;
      } else if (inEvent) {
        int colonIndex = line.indexOf(':');
        if (colonIndex != -1) {
          String keyPart = line.substring(0, colonIndex).toUpperCase();
          String value = line.substring(colonIndex + 1);
          
          if (keyPart.startsWith('SUMMARY')) currentSummary = value;
          else if (keyPart.startsWith('DTSTART')) currentStart = _parseStrictDate(value);
          else if (keyPart.startsWith('DTEND')) currentEnd = _parseStrictDate(value);
          else if (keyPart.startsWith('LOCATION')) currentLocation = value;
          else if (keyPart.startsWith('DESCRIPTION')) {
            currentDescription = value.replaceAll('\\n', '\n').replaceAll('\\,', ',').replaceAll('\\;', ';');
          }
          else if (keyPart.startsWith('RRULE')) rrule = value;
        }
      }
    }
    
    for (final date in events.keys) {
      events[date]!.sort((a, b) => a.startTime.compareTo(b.startTime));
    }
    return events;
  }

  void _addEventToMap(Map<DateTime, List<CalendarEvent>> events, DateTime start, CalendarEvent event) {
    final date = DateTime(start.year, start.month, start.day);
    if (!events.containsKey(date)) events[date] = [];
    events[date]!.add(event);
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
          int year = int.parse(d.substring(0, 4));
          int month = int.parse(d.substring(4, 6));
          int day = int.parse(d.substring(6, 8));
          int hour = int.parse(t.substring(0, 2));
          int minute = int.parse(t.substring(2, 4));
          if (isUtc) return DateTime.utc(year, month, day, hour, minute).toLocal();
          return DateTime(year, month, day, hour, minute);
        }
      }
      if (dateStr.length == 8) {
         return DateTime(
           int.parse(dateStr.substring(0, 4)),
           int.parse(dateStr.substring(4, 6)),
           int.parse(dateStr.substring(6, 8))
         );
      }
    } catch (e) { return null; }
    return null;
  }

  void _generateSafeRecurrences(Map<DateTime, List<CalendarEvent>> events, CalendarEvent original, String rrule) {
    DateTime? untilDate;
    final rruleParts = rrule.split(';');
    for (var part in rruleParts) {
      if (part.trim().startsWith('UNTIL=')) {
        untilDate = _parseStrictDate(part.trim().substring(6));
      }
    }

    final now = DateTime.now();
    final maxDate = DateTime(now.year + 2, 12, 31);
    
    DateTime nextStart = original.startTime;
    DateTime nextEnd = original.endTime;

    while (true) {
      if (rrule.contains('FREQ=WEEKLY')) {
         nextStart = nextStart.add(const Duration(days: 7));
         nextEnd = nextEnd.add(const Duration(days: 7));
      } else if (rrule.contains('FREQ=MONTHLY')) {
         nextStart = DateTime(nextStart.year, nextStart.month + 1, nextStart.day, nextStart.hour, nextStart.minute);
         nextEnd = DateTime(nextEnd.year, nextEnd.month + 1, nextEnd.day, nextEnd.hour, nextEnd.minute);
      } else {
        break;
      }

      if (untilDate != null && nextStart.isAfter(untilDate)) break;
      if (nextStart.isAfter(maxDate)) break;

      final minViewable = DateTime(now.year - 1, 1, 1);
      if (nextStart.isAfter(minViewable)) {
        _addEventToMap(events, nextStart, CalendarEvent(
          title: original.title,
          startTime: nextStart,
          endTime: nextEnd,
          location: original.location,
          description: original.description
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) return Scaffold(body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)));
    if (_errorMessage != null) return Scaffold(body: Center(child: Text(_errorMessage!)));

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        child: const Icon(Icons.add),
      ),
      // --- ELASTIC LAYOUT ---
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Breakpoint lowered to 600. 
          // This forces SIDE-BY-SIDE layout on your 800px floating window.
          final isWide = constraints.maxWidth > 600;

          if (isWide) {
            // WIDE MODE: Side-by-Side with Expanded (Elastic) children.
            // NO SizedBox heights. NO FittedBox constraints.
            // It naturally fills available space.
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 7, 
                    child: _buildCard(
                      theme, 
                      // Calendar Column uses Expanded to fill vertical space
                      Column(
                        children: [
                          _buildHeader(theme, compact: false), 
                          Expanded(child: _buildCalendarGrid(theme)) 
                        ]
                      )
                    )
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3, 
                    child: _buildCard(
                      theme, 
                      // Sidebar uses a LayoutBuilder to handle vertical squish
                      _buildSidebar(theme), 
                      isVariant: true
                    )
                  ),
                ],
              ),
            );
          } else {
            // NARROW MODE: Vertical Stack
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 450, // Reduced height for mobile view
                    child: _buildCard(
                      theme, 
                      Column(
                        children: [
                          _buildHeader(theme, compact: true), 
                          Expanded(child: _buildCalendarGrid(theme))
                        ]
                      )
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 450, 
                    child: _buildCard(
                      theme, 
                      _buildSidebar(theme), 
                      isVariant: true
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
              Text(DateFormat('MMMM').format(_focusedMonth), style: compact ? theme.textTheme.headlineMedium : theme.textTheme.displayMedium),
              Text(DateFormat('yyyy').format(_focusedMonth), style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onBackground.withOpacity(0.5))),
            ],
          ),
          Row(
            children: [
              IconButton(onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1)), icon: const Icon(Icons.chevron_left)),
              IconButton(onPressed: () => setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1)), icon: const Icon(Icons.chevron_right)),
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
    
    // Using LayoutBuilder to dynamically adjust cell height
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate aspect ratio so rows fit exactly into available height
        final double gridHeight = constraints.maxHeight;
        final double gridWidth = constraints.maxWidth;
        
        // 5 rows usually, sometimes 6. Let's assume 6 to be safe.
        // Aspect Ratio = Width / Height
        final double cellHeight = (gridHeight - 32) / 6; // -32 for header/padding
        final double cellWidth = (gridWidth - 16) / 7;
        final double childAspectRatio = cellWidth / cellHeight;

        return Column(
          children: [
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Row(children: ['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d) => Expanded(child: Center(child: Text(d, style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold))))).toList())),
            Expanded(child: GridView.builder(
              padding: const EdgeInsets.all(8), physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7, 
                childAspectRatio: childAspectRatio // DYNAMIC RATIO
              ),
              itemCount: totalCells,
              itemBuilder: (context, index) {
                final dayNumber = index - startingWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) return const SizedBox();
                final date = DateTime(_focusedMonth.year, _focusedMonth.month, dayNumber);
                final isSelected = date.day == _selectedDate.day && date.month == _selectedDate.month && date.year == _selectedDate.year;
                final isToday = date.day == DateTime.now().day && date.month == DateTime.now().month && date.year == DateTime.now().year;
                final events = _events[DateTime(date.year, date.month, date.day)] ?? [];
                
                // Using FittedBox on day numbers to ensure they shrink if cells get tiny
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = date),
                  child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isToday && !isSelected ? Border.all(color: theme.colorScheme.primary) : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('$dayNumber', style: TextStyle(color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface, fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal)),
                        ),
                        if (events.isNotEmpty) Container(margin: const EdgeInsets.only(top: 4), width: 4, height: 4, decoration: BoxDecoration(color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary, shape: BoxShape.circle)),
                      ],
                    ),
                  ),
                );
              },
            )),
          ],
        );
      }
    );
  }

  Widget _buildSidebar(ThemeData theme) {
    final normalizedDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final events = _events[normalizedDate] ?? [];
    final isToday = _selectedDate.day == DateTime.now().day && _selectedDate.month == DateTime.now().month && _selectedDate.year == DateTime.now().year;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top section (Date & Weather)
        // Wrapped in Flexible so it can shrink if needed
        Flexible(
          flex: 0,
          child: Container(
            width: double.infinity, padding: const EdgeInsets.all(24), // Reduced padding slightly
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1)))),
            child: Column(
              mainAxisSize: MainAxisSize.min, // shrink wrap
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEE').format(_selectedDate).toUpperCase(), style: theme.textTheme.displaySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500, letterSpacing: 2.0, fontSize: 24)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
                  children: [
                    // FittedBox ensures huge date number shrinks if sidebar is narrow
                    Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(DateFormat('d').format(_selectedDate), style: TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: theme.colorScheme.onBackground, height: 1.0)))),
                    if (isToday) Container(width: 12, height: 12, margin: const EdgeInsets.only(left: 4), decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 16),
                if (_weather != null) Container(
                  padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_weather!.icon, style: const TextStyle(fontSize: 24)), 
                      const SizedBox(width: 12), 
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_weather!.temp.round()}°C', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)), 
                        Text(_weather!.description, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                      ])
                    ]
                  )
                ),
              ],
            ),
          ),
        ),
        
        // Event List (Takes remaining space)
        Expanded(
          child: events.isEmpty
            ? Center(child: Text('No Events', style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5))))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), itemCount: events.length,
                itemBuilder: (context, index) => _EventCard(event: events[index], onDelete: () => _deleteEvent(_selectedDate, events[index])),
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
    final colors = [
      const Color(0xFFe67e80), // Red
      const Color(0xFFe69875), // Orange
      const Color(0xFFdbbc7f), // Yellow
      const Color(0xFFa7c080), // Green
      const Color(0xFF7fbbb3), // Blue
      const Color(0xFFd699b6), // Purple
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
                              '${DateFormat('h:mm a').format(widget.event.startTime)} - ${DateFormat('h:mm a').format(widget.event.endTime)}',
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