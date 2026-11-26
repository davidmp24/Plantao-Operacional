import 'package:flutter/material.dart';
import 'schedule_generator_screen.dart';
// WeeklyViewPage está em main.dart e é passado via agendaTab

/// Tela principal PRO com 2 abas:
///   0 - Agenda (WeeklyViewPage existente — inclui compartilhamento)
///   1 - Escala (gerador automático de escala)
class HomeScreen extends StatefulWidget {
  /// Widget da aba Agenda — recebe WeeklyViewPage de main.dart
  final Widget agendaTab;
  const HomeScreen({super.key, required this.agendaTab});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      widget.agendaTab,
      const ScheduleGeneratorScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        backgroundColor: const Color(0xFF262626),
        indicatorColor: const Color(0xFF10A37F).withValues(alpha: 0.3),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month, color: Color(0xFF10A37F)),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_fix_high_outlined),
            selectedIcon: Icon(Icons.auto_fix_high_rounded, color: Color(0xFF10A37F)),
            label: 'Escala',
          ),
        ],
      ),
    );
  }
}
