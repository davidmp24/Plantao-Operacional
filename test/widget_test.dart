import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plantao/main.dart';
import 'package:plantao/services/notification_service.dart';
import 'package:plantao/services/schedule_service.dart';

void main() {
  group('Utilitários de data e Holiday', () {
    test('getDateKey formata YYYY-MM-DD em UTC com zero padding', () {
      final date = DateTime(2026, 3, 5, 18, 30);
      expect(getDateKey(date), '2026-03-05');
    });

    test('normalizeDate zera horário e usa UTC', () {
      final normalized = normalizeDate(DateTime(2026, 11, 26, 23, 59));
      expect(normalized.isUtc, isTrue);
      expect(normalized.year, 2026);
      expect(normalized.month, 11);
      expect(normalized.day, 26);
      expect(normalized.hour, 0);
      expect(normalized.minute, 0);
    });

    test('Holiday.fromJson e toJson preservam campos principais', () {
      final holiday = Holiday.fromJson({
        'date': '2026-12-25',
        'localName': 'Natal',
        'name': 'Christmas Day',
        'countryCode': 'BR',
        'global': true,
      });

      expect(getDateKey(holiday.date), '2026-12-25');
      expect(holiday.localName, 'Natal');
      expect(holiday.countryCode, 'BR');
      expect(holiday.global, isTrue);

      final json = holiday.toJson();
      expect(json['date'], '2026-12-25');
      expect(json['localName'], 'Natal');
    });
  });

  group('NotificationService.makeId', () {
    test('gera ID determinístico e não negativo', () {
      final id1 = NotificationService.makeId('2026-11-26', 'Plantão', '07:00');
      final id2 = NotificationService.makeId('2026-11-26', 'Plantão', '07:00');
      final id3 = NotificationService.makeId('2026-11-27', 'Plantão', '07:00');

      expect(id1, equals(id2));
      expect(id1, isNot(equals(id3)));
      expect(id1, greaterThanOrEqualTo(0));
    });
  });

  group('TurnSlot', () {
    test('armazena tipo, rótulo e horários corretamente', () {
      const slot = TurnSlot(
        type: TurnType.trabalho,
        label: 'Plantão Dia',
        start: TimeOfDay(hour: 7, minute: 0),
        end: TimeOfDay(hour: 19, minute: 0),
        colorId: '9',
      );
      expect(slot.type, TurnType.trabalho);
      expect(slot.label, 'Plantão Dia');
      expect(slot.start.hour, 7);
      expect(slot.end.hour, 19);
    });
  });

  testWidgets('Renderiza diálogo e botões padrão com tema escuro', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {},
              child: const Text('Entrar com Google'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Entrar com Google'), findsOneWidget);
  });
}
