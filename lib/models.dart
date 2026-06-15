/// models.dart
///
/// Contains all data models and enums used throughout the EverCal application.
/// This includes Theme settings, Weather units, and the core CalendarEvent class.

import 'package:flutter/material.dart'; // For IconData
import 'dart:convert';

// Enums
enum AppThemeSetting { dark, light, auto }
enum WeatherUnit { celsius, fahrenheit, kelvin }
enum CalendarViewMode { month, week }
enum EventSource { manual, imported, khal }

class WeatherData {
  final double temp;
  final String description;
  final IconData icon;
  const WeatherData(
      {required this.temp, required this.description, required this.icon});
}

class CalendarEvent {
  final String id; // stable ID given to each events
  final String title;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? description;
  final EventSource source;
  final String? sourceId; // For imports, the JSON filename
  final String? rrule; // Stores "FREQ=YEARLY" etc.
  final bool isGenerated; // True if this is a repeat instance
  final List<DateTime> exceptionDates; // List of dates to skip
  final bool isHidden; // Hides event in a reccuring event (instead of deleting)
  final bool allDay; // True for date-only events (no time component)

  const CalendarEvent({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    this.location,
    this.description,
    this.source = EventSource.manual,
    this.sourceId,
    this.rrule,
    this.isGenerated = false,
    this.exceptionDates = const [],
    this.isHidden = false, // DEFAULT FALSE
    this.allDay = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'location': location,
        'description': description,
        'rrule': rrule,
        'allDay': allDay,
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
      rrule: json['rrule'],
      allDay: json['allDay'] == true,
    );
  }

  // Helper copyWith
  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? startTime,
    DateTime? endTime,
    String? location,
    String? description,
    EventSource? source,
    String? sourceId,
    String? rrule,
    bool? isGenerated,
    List<DateTime>? exceptionDates,
    bool? isHidden,
    bool? allDay,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      description: description ?? this.description,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      rrule: rrule ?? this.rrule,
      isGenerated: isGenerated ?? this.isGenerated,
      exceptionDates: exceptionDates ?? this.exceptionDates,
      isHidden: isHidden ?? this.isHidden,
      allDay: allDay ?? this.allDay,
    );
  }
}