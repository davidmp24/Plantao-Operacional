import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'auth_service.dart';

enum TurnType { trabalho, folga }

/// Representa um turno dentro de um ciclo de escala
class TurnSlot {
  final TurnType type;
  final String label; // Ex: "Serviço Dia", "Serviço Noite", "Folga"
  final TimeOfDay start;
  final TimeOfDay end;
  final bool overnight; // turno vira a madrugada (ex: 19h→07h)
  final String colorId; // Google Calendar colorId

  const TurnSlot({
    required this.type,
    required this.label,
    required this.start,
    required this.end,
    this.overnight = false,
    required this.colorId,
  });
}

/// Tipos de escala automática suportados
enum ScheduleModel {
  misto_dia_noite_folga,   // Ciclo: D (07-19), N (19-07), F, D (07-19) — padrão do usuário
  cinco_por_dois_fixo,     // 5x2 com turno fixo
  cinco_por_dois_rotativo, // 5x2 com rotação semanal de turnos
}

/// Serviço de geração automática de escala de trabalho
class ScheduleService {
  final AuthService _authService;

  ScheduleService(this._authService);

  // ─────────────────────────────────────────────────────────────────────────
  // DEFINIÇÕES DE CICLOS
  // ─────────────────────────────────────────────────────────────────────────


  List<TurnSlot> get _cycleMistoDiaNoteiFolga => [
        const TurnSlot(
          type: TurnType.trabalho,
          label: 'Serviço Dia (07-19)',
          start: TimeOfDay(hour: 7, minute: 0),
          end: TimeOfDay(hour: 19, minute: 0),
          overnight: false,
          colorId: '11',
        ),
        const TurnSlot(
          type: TurnType.trabalho,
          label: 'Serviço Noite (19-07)',
          start: TimeOfDay(hour: 19, minute: 0),
          end: TimeOfDay(hour: 7, minute: 0),
          overnight: true,
          colorId: '9',
        ),
        const TurnSlot(
          type: TurnType.folga,
          label: 'Folga',
          start: TimeOfDay(hour: 0, minute: 0),
          end: TimeOfDay(hour: 0, minute: 0),
          colorId: '10',
        ),
        const TurnSlot(
          type: TurnType.folga,
          label: 'Folga',
          start: TimeOfDay(hour: 0, minute: 0),
          end: TimeOfDay(hour: 0, minute: 0),
          colorId: '10',
        ),
      ];

  // ─────────────────────────────────────────────────────────────────────────
  // GERAÇÃO DE DATAS DO CICLO
  // ─────────────────────────────────────────────────────────────────────────

  List<MapEntry<DateTime, TurnSlot>> generateSchedule({
    required DateTime startDate,
    required ScheduleModel model,
    required int months,
    TimeOfDay? customStartTime,
    bool isMorning5x2 = false,
  }) {
    final List<TurnSlot> cycle;
    switch (model) {
      case ScheduleModel.misto_dia_noite_folga:
        cycle = _cycleMistoDiaNoteiFolga;
        break;
      case ScheduleModel.cinco_por_dois_fixo:
        return _generate5x2Fixed(startDate, months, isMorning5x2);
      case ScheduleModel.cinco_por_dois_rotativo:
        return _generate5x2Rotativo(startDate, months);
    }

    final result = <MapEntry<DateTime, TurnSlot>>[];
    final endDate =
        DateTime(startDate.year, startDate.month + months, startDate.day);

    DateTime current =
        DateTime(startDate.year, startDate.month, startDate.day);
    int cycleIndex = 0;

    while (current.isBefore(endDate)) {
      final slot = cycle[cycleIndex % cycle.length];
      result.add(MapEntry(current, slot));
      current = current.add(const Duration(days: 1));
      cycleIndex++;
    }

    return result;
  }

  List<MapEntry<DateTime, TurnSlot>> _generate5x2Fixed(
      DateTime startDate, int months, bool isMorning) {
    final result = <MapEntry<DateTime, TurnSlot>>[];
    final endDate =
        DateTime(startDate.year, startDate.month + months, startDate.day);
    DateTime current =
        DateTime(startDate.year, startDate.month, startDate.day);

    final workSlot = TurnSlot(
      type: TurnType.trabalho,
      label: isMorning ? 'Serviço Manhã (07-15)' : 'Serviço (08-18)',
      start: isMorning
          ? const TimeOfDay(hour: 7, minute: 0)
          : const TimeOfDay(hour: 8, minute: 0),
      end: isMorning
          ? const TimeOfDay(hour: 15, minute: 0)
          : const TimeOfDay(hour: 18, minute: 0),
      colorId: '11',
    );
    const folga = TurnSlot(
      type: TurnType.folga,
      label: 'Folga',
      start: TimeOfDay(hour: 0, minute: 0),
      end: TimeOfDay(hour: 0, minute: 0),
      colorId: '10',
    );

    while (current.isBefore(endDate)) {
      final weekday = current.weekday;
      if (weekday >= DateTime.monday && weekday <= DateTime.friday) {
        result.add(MapEntry(current, workSlot));
      } else {
        result.add(MapEntry(current, folga));
      }
      current = current.add(const Duration(days: 1));
    }
    return result;
  }

  List<MapEntry<DateTime, TurnSlot>> _generate5x2Rotativo(
      DateTime startDate, int months) {
    final result = <MapEntry<DateTime, TurnSlot>>[];
    final endDate =
        DateTime(startDate.year, startDate.month + months, startDate.day);

    DateTime current =
        DateTime(startDate.year, startDate.month, startDate.day);
    while (current.weekday != DateTime.monday) {
      current = current.subtract(const Duration(days: 1));
    }

    final turnos = [
      const TurnSlot(
        type: TurnType.trabalho,
        label: 'Serviço Manhã (07-15)',
        start: TimeOfDay(hour: 7, minute: 0),
        end: TimeOfDay(hour: 15, minute: 0),
        colorId: '11',
      ),
      const TurnSlot(
        type: TurnType.trabalho,
        label: 'Serviço Tarde (15-23)',
        start: TimeOfDay(hour: 15, minute: 0),
        end: TimeOfDay(hour: 23, minute: 0),
        colorId: '5',
      ),
      const TurnSlot(
        type: TurnType.trabalho,
        label: 'Serviço Noite (23-07)',
        start: TimeOfDay(hour: 23, minute: 0),
        end: TimeOfDay(hour: 7, minute: 0),
        overnight: true,
        colorId: '9',
      ),
    ];

    const folga = TurnSlot(
      type: TurnType.folga,
      label: 'Folga',
      start: TimeOfDay(hour: 0, minute: 0),
      end: TimeOfDay(hour: 0, minute: 0),
      colorId: '10',
    );

    final weeksSinceStart = startDate.difference(current).inDays ~/ 7;
    int turnoIndex = weeksSinceStart % 3;

    while (current.isBefore(endDate)) {
      final weekday = current.weekday;

      if (weekday == DateTime.monday || weekday == DateTime.tuesday) {
        if (current.isAfter(startDate.subtract(const Duration(days: 1)))) {
          result.add(MapEntry(current, turnos[turnoIndex % 3]));
        }
      } else if (weekday == DateTime.wednesday ||
          weekday == DateTime.thursday) {
        if (current.isAfter(startDate.subtract(const Duration(days: 1)))) {
          result.add(MapEntry(current, turnos[(turnoIndex + 1) % 3]));
        }
      } else if (weekday == DateTime.friday ||
          weekday == DateTime.saturday) {
        if (current.isAfter(startDate.subtract(const Duration(days: 1)))) {
          result.add(MapEntry(current, turnos[(turnoIndex + 2) % 3]));
        }
      } else if (weekday == DateTime.sunday) {
        if (current.isAfter(startDate.subtract(const Duration(days: 1)))) {
          result.add(MapEntry(current, folga));
        }
        turnoIndex++;
      }

      current = current.add(const Duration(days: 1));
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLICAÇÃO NO GOOGLE CALENDAR
  // ─────────────────────────────────────────────────────────────────────────

  Future<({int success, int errors})> publishToCalendar({
    required List<MapEntry<DateTime, TurnSlot>> schedule,
    required String calendarId,
    void Function(double progress)? onProgress,
  }) async {
    final api = await _authService.getCalendarApi();
    if (api == null) return (success: 0, errors: schedule.length);

    int success = 0;
    int errors = 0;

    for (int i = 0; i < schedule.length; i++) {
      final entry = schedule[i];
      final date = entry.key;
      final slot = entry.value;

      onProgress?.call(i / schedule.length);

      try {
        gcal.EventDateTime startDt;
        gcal.EventDateTime endDt;

        if (slot.type == TurnType.folga) {
          startDt = gcal.EventDateTime(date: date);
          endDt = gcal.EventDateTime(
              date: date.add(const Duration(days: 1)));
        } else if (slot.overnight) {
          final startDateTime = DateTime(
            date.year, date.month, date.day, slot.start.hour, slot.start.minute,
          );
          final endDateTime = DateTime(
            date.year, date.month, date.day + 1, slot.end.hour, slot.end.minute,
          );
          startDt = gcal.EventDateTime(dateTime: startDateTime.toUtc());
          endDt = gcal.EventDateTime(dateTime: endDateTime.toUtc());
        } else {
          final startDateTime = DateTime(
            date.year, date.month, date.day, slot.start.hour, slot.start.minute,
          );
          final endDateTime = DateTime(
            date.year, date.month, date.day, slot.end.hour, slot.end.minute,
          );
          startDt = gcal.EventDateTime(dateTime: startDateTime.toUtc());
          endDt = gcal.EventDateTime(dateTime: endDateTime.toUtc());
        }

        final event = gcal.Event(
          summary: slot.label,
          colorId: slot.colorId,
          start: startDt,
          end: endDt,
          description: 'Gerado automaticamente pelo Plantão Operacional PRO',
        );

        await api.events.insert(event, calendarId);
        success++;
      } catch (e) {
        debugPrint('Error creating event for $date: $e');
        errors++;
      }

      await Future.delayed(const Duration(milliseconds: 100));
    }

    onProgress?.call(1.0);
    return (success: success, errors: errors);
  }
}
