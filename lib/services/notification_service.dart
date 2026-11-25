import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;

/// Serviço central de notificações locais (alarmes de compromissos)
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    // Define o fuso horário de Brasília
    tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Abre o app ao tocar na notificação — já é o comportamento padrão
        debugPrint('Notificação tocada: ${details.payload}');
      },
    );

    // Solicita permissão de notificação (Android 13+)
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();

    _initialized = true;
    debugPrint('NotificationService inicializado.');
  }

  /// Agenda uma notificação para 30 min antes do compromisso.
  /// [id] deve ser único por compromisso (usa hashCode de dateKey+title+hour).
  /// Retorna false se não conseguir agendar (ex: data no passado).
  Future<bool> scheduleCommitmentNotification({
    required int id,
    required String title,
    required String hour, // formato "HH:mm" ou "HH:mm → HH:mm"
    required DateTime date,
    String? notes,
  }) async {
    if (!_initialized) await init();

    // Tenta extrair o horário de início do campo hour
    final startTime = _parseStartTime(hour);
    if (startTime == null) return false;

    final commitmentDateTime = DateTime(
      date.year, date.month, date.day,
      startTime.hour, startTime.minute,
    );
    final notifyAt = commitmentDateTime.subtract(const Duration(minutes: 30));

    // Não agenda notificações no passado
    if (notifyAt.isBefore(DateTime.now())) return false;

    final tzNotifyAt = tz.TZDateTime.from(notifyAt, tz.local);

    final androidDetails = AndroidNotificationDetails(
      'compromissos_channel',
      'Compromissos',
      channelDescription: 'Lembretes de compromissos da sua agenda',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(
        notes?.isNotEmpty == true ? notes! : 'Começa às $hour',
      ),
    );

    try {
      await _plugin.zonedSchedule(
        id,
        '🔔 Lembrete: $title',
        'Em 30 minutos — $hour${notes?.isNotEmpty == true ? "\n$notes" : ""}',
        tzNotifyAt,
        NotificationDetails(android: androidDetails),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'commitment_$id',
      );
      debugPrint('Notificação $id agendada para $tzNotifyAt');
      return true;
    } catch (e) {
      debugPrint('Erro ao agendar notificação $id: $e');
      return false;
    }
  }

  /// Cancela uma notificação agendada pelo ID.
  Future<void> cancelNotification(int id) async {
    if (!_initialized) return;
    await _plugin.cancel(id);
    debugPrint('Notificação $id cancelada.');
  }

  /// Cancela todas as notificações.
  Future<void> cancelAll() async {
    if (!_initialized) return;
    await _plugin.cancelAll();
  }

  /// Gera um ID numérico estável a partir de dateKey + title + hour.
  static int makeId(String dateKey, String title, String hour) {
    return (dateKey + title + hour).hashCode.abs() % 2147483647;
  }

  /// Tenta extrair o horário de início do campo hour.
  /// Suporta formatos: "07:00", "07:00 - 19:00", "07:00 → 19:00"
  TimeOfDay? _parseStartTime(String hour) {
    if (hour.isEmpty) return null;
    final cleaned = hour
        .replaceAll('→', '-')
        .replaceAll('–', '-')
        .split('-')
        .first
        .trim();
    final parts = cleaned.split(':');
    if (parts.length < 2) return null;
    try {
      final h = int.parse(parts[0].trim());
      final m = int.parse(parts[1].trim().substring(0, 2));
      if (h < 0 || h > 23 || m < 0 || m > 59) return null;
      return TimeOfDay(hour: h, minute: m);
    } catch (_) {
      return null;
    }
  }
}
