import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'backup_helper_mobile.dart' if (dart.library.html) 'backup_helper_web.dart';
import 'update_service.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/bill_service.dart';
import 'services/sharing_service.dart';
import 'services/widget_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

// --- Instância Global do Serviço de Atualização ---
final updateService = UpdateService();

// --- Enum para Modo de Seleção ---
enum SelectionMode { single, multi }

// --- Funções Utilitárias Globais ---
String getDateKey(DateTime date) {
  final utcDate = DateTime.utc(date.year, date.month, date.day);
  return '${utcDate.year.toString().padLeft(4, '0')}-${utcDate.month.toString().padLeft(2, '0')}-${utcDate.day.toString().padLeft(2, '0')}';
}

DateTime normalizeDate(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

Future<void> launchURL(String urlString, {BuildContext? context}) async {
  final Uri url = Uri.parse(urlString);
  if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o link: $urlString')),
      );
    }
  }
}

// --- Modelo de Dados para Feriado ---
class Holiday {
  final DateTime date;
  final String localName;
  final String name;
  final String countryCode;
  final bool global;

  Holiday({
    required this.date,
    required this.localName,
    required this.name,
    required this.countryCode,
    required this.global,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    try {
      return Holiday(
        date: normalizeDate(DateTime.parse(json['date'] as String)),
        localName: json['localName'] as String? ?? '',
        name: json['name'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? '',
        global: json['global'] as bool? ?? false,
      );
    } catch (e) {
      print("Erro ao parsear Holiday JSON: $e, Data: $json");
      return Holiday(date: DateTime.now(), localName: "Erro de Parse", name: "", countryCode: "", global: false);
    }
  }
}

// --- Main Function & App Initialization ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('pt_BR', null);
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await Hive.initFlutter();
    // Tratamento seguro para boxes do Hive (evita crash por corrupção em Xiaomi/Redmi)
    final boxes = ['commitments', 'templates', 'bills_templates', 'bills_paid_status', 'settings'];
    for (var boxName in boxes) {
      try {
        await Hive.openBox(boxName);
      } catch (e) {
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }
    await WidgetService.initialize();
    await NotificationService().init();
    runApp(const MyApp());
  } catch (e, stack) {
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red,
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Erro Crítico na Inicialização:\n\n$e\n\n$stack',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ),
    ));
  }
}

// --- Root Application Widget ---
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => BillService()),
        ChangeNotifierProxyProvider<AuthService, SharingService>(
          create: (ctx) => SharingService(ctx.read<AuthService>()),
          update: (ctx, auth, prev) => prev ?? SharingService(auth),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Plantão Operacional',
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [ Locale('pt', 'BR'), ],
        locale: const Locale('pt', 'BR'),
        theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: const Color(0xFF1E1E1E),
            primaryColor: const Color(0xFF10A37F),
            appBarTheme: const AppBarTheme( backgroundColor: Color(0xFF262626), foregroundColor: Colors.white,),
            textTheme: const TextTheme(
              bodyMedium: TextStyle(fontSize: 15, color: Colors.white70),
              bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white),
              headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
              titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10A37F), secondary: Color(0xFF10A37F), surface: Color(0xFF2C2C2C),
              background: Color(0xFF1E1E1E), onPrimary: Colors.white, onSecondary: Colors.white,
              onSurface: Colors.white, onBackground: Colors.white, error: Colors.redAccent, onError: Colors.white,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData( backgroundColor: Color(0xFF10A37F), foregroundColor: Colors.white,),
            popupMenuTheme: const PopupMenuThemeData( color: Color(0xFF2C2C2C), textStyle: TextStyle(color: Colors.white),),
            dialogTheme: const DialogThemeData(
              backgroundColor: Color(0xFF2C2C2C),
              titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            textButtonTheme: TextButtonThemeData( style: TextButton.styleFrom(foregroundColor: const Color(0xFF10A37F)),),
            cardTheme: CardThemeData(
              color: const Color(0xFF2C2C2C), elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[700]!),),
              enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[700]!),),
              focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10A37F)),),
              labelStyle: TextStyle(color: Colors.grey[400]), hintStyle: TextStyle(color: Colors.grey[600]),
            ),
            iconTheme: const IconThemeData( color: Colors.white70, ),
            checkboxTheme: CheckboxThemeData(
              fillColor: MaterialStateProperty.resolveWith((states) { if (states.contains(MaterialState.selected)) { return const Color(0xFF10A37F); } return Colors.grey[800]; }),
              checkColor: MaterialStateProperty.all(Colors.black), side: const BorderSide(color: Colors.white54),
            ),
            dividerTheme: const DividerThemeData( color: Colors.white24, thickness: 1, space: 1,)
        ),
        home: const _AppRoot(),
      ),
    );
  }
}

// --- Roteamento baseado em autenticação ---
class _AppRoot extends StatelessWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (auth.isInitializing) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF10A37F)),
        ),
      );
    }
    if (auth.isSignedIn) {
      return HomeScreen(agendaTab: _AgendaWrapper());
    }
    return const LoginScreen();
  }
}

// Wrapper para WeeklyViewPage dentro do HomeScreen
class _AgendaWrapper extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const WeeklyViewPage();
  }
}

// --- Weekly View Page Widget (Página Principal) ---
class WeeklyViewPage extends StatefulWidget {
  const WeeklyViewPage({super.key});

  @override
  _WeeklyViewPageState createState() => _WeeklyViewPageState();
}

class _WeeklyViewPageState extends State<WeeklyViewPage> with TickerProviderStateMixin {
  late Box _commitmentsBox;
  late Box _templatesBox;
  late Box _billsTemplatesBoxState;
  late Box _billsPaidStatusBoxState;

  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  late final ValueNotifier<List<dynamic>> _selectedCommitments;
  Map<String, List<dynamic>> _allCommitments = {};
  SelectionMode _selectionMode = SelectionMode.single;
  Set<DateTime> _multiSelectedDays = {};

  Map<int, List<Holiday>> _cachedHolidays = {};
  bool _isLoadingHolidays = false;
  Set<DateTime> _holidayDates = {};

  // --- Compartilhamento ---
  // Eventos do usuário seguido para o mês atual
  List<Map<String, dynamic>> _followedEvents = [];
  // subscription para Stream do Firestore
  dynamic _followedStreamSub;
  bool _isRefreshingShared = false;

  bool _isPerformingBackupRestore = false;
  bool _hasPendingBills = false;
  AnimationController? _pendingBillsAnimationController;
  Animation<Offset>? _pendingBillsOffsetAnimation;

  @override
  void initState() {
    super.initState();
    _commitmentsBox = Hive.box('commitments');
    _templatesBox = Hive.box('templates');
    _billsTemplatesBoxState = Hive.box('bills_templates');
    _billsPaidStatusBoxState = Hive.box('bills_paid_status');

    _selectedDate = normalizeDate(_focusedDay);
    _allCommitments = {};
    _selectedCommitments = ValueNotifier([]);
    _loadAllData();
    _fetchHolidaysForYear(_focusedDay.year);
    // Inicia escuta dos eventos do seguido
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _subscribeToFollowedEvents();
      // Sincroniza todos os compromissos locais existentes no Firestore
      // (para que quem já segue o usuário veja eventos anteriores ao compartilhamento)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncLocalToFirestore();
      });
    });

    // MUDANÇA: Agora chama o serviço da maneira correta.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        try {
          final updateInfo = await updateService.checkForUpdate();
          if (updateInfo != null && mounted) {
            updateService.showUpdateDialog(context, updateInfo);
          }
        } catch (e) {
          print("Verificação automática de atualização falhou, mas não mostraremos erro ao usuário no início.");
        }
      }
    });

    _pendingBillsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _pendingBillsOffsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, 0.1),
    ).animate(CurvedAnimation(
      parent: _pendingBillsAnimationController!,
      curve: Curves.elasticInOut,
    ));
  }

  @override
  void dispose() {
    _selectedCommitments.dispose();
    _pendingBillsAnimationController?.dispose();
    _followedStreamSub?.cancel();
    super.dispose();
  }

  String _getBillPaidStatusKeyForState(String billId, DateTime month) {
    final year = month.year;
    final monthPad = month.month.toString().padLeft(2, '0');
    return "${billId}_${year}-${monthPad}";
  }

  Future<void> _checkPendingBillsForMonth(DateTime month) async {
    if (!mounted) return;

    final List<Map<String, dynamic>> billTemplates = [];
    _billsTemplatesBoxState.toMap().forEach((key, value) {
      if (value is Map && key is String) {
        var t = Map<String, dynamic>.from(value);
        t['id'] = key;
        billTemplates.add(t);
      }
    });

    if (billTemplates.isEmpty) {
      if (_hasPendingBills == true && mounted) setState(() => _hasPendingBills = false);
      return;
    }

    bool foundPending = false;
    for (var billTemplate in billTemplates) {
      final billId = billTemplate['id'] as String;
      final paidStatusKey = _getBillPaidStatusKeyForState(billId, month);
      if (_billsPaidStatusBoxState.get(paidStatusKey) != true) {
        foundPending = true;
        break;
      }
    }

    if (mounted && _hasPendingBills != foundPending) {
      setState(() {
        _hasPendingBills = foundPending;
      });
      if (foundPending && _pendingBillsAnimationController?.isAnimating == false) {
        _pendingBillsAnimationController?.repeat(reverse: true);
      } else if (!foundPending && _pendingBillsAnimationController?.isAnimating == true) {
        _pendingBillsAnimationController?.stop();
      }
    }
  }

  void _loadAllData() {
    _loadAllCommitments();
    _updateHolidayDatesSet();
    _updateSelectedCommitments();
    _checkPendingBillsForMonth(_focusedDay);
    WidgetService.updateTodayWidget();
    print("Dados iniciais da WeeklyView carregados/recarregados.");
  }

  // ─── Compartilhamento ─────────────────────────────────────────────────────

  /// Inicia/reinicia a escuta em tempo real dos eventos do usuário seguido.
  void _subscribeToFollowedEvents() {
    _followedStreamSub?.cancel();
    final sharing = context.read<SharingService>();
    if (sharing.followedProfiles.isEmpty) {
      if (mounted) setState(() => _followedEvents = []);
      return;
    }
    // Segue apenas o primeiro usuário da lista (pode ser expandido)
    final firstUid = sharing.followedProfiles.first.uid;
    _followedStreamSub = sharing
        .getCommitmentsStream(firstUid, _focusedDay)
        .listen((commitments) {
      if (!mounted) return;
      setState(() {
        _followedEvents = commitments.map((c) {
          final dateKey = getDateKey(DateTime(c.date.year, c.date.month, c.date.day));
          return {
            'title': c.title,
            'hour': c.hour,
            'notes': c.notes,
            'color': c.colorValue,
            'isShared': true,
            'ownerName': c.ownerName,
            '_dateKey': dateKey,
          };
        }).toList();
        _updateSelectedCommitments();
      });
    });
  }

  /// Força refresh dos eventos do seguido (botão 🔄).
  Future<void> _refreshFollowedEvents() async {
    if (_isRefreshingShared || !mounted) return;
    setState(() => _isRefreshingShared = true);
    _subscribeToFollowedEvents();
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => _isRefreshingShared = false);
  }

  /// Auto-sync: publica um compromisso local no Firestore (fire-and-forget).
  void _autoSync(DateTime date, Map<String, dynamic> commitment) {
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn) return;
    final sharing = context.read<SharingService>();
    sharing.publishCommitment(
      date: date,
      title: commitment['title'] ?? '',
      hour: commitment['hour'] ?? '',
      notes: commitment['notes'] ?? '',
      colorValue: commitment['color'] ?? const Color(0xFF10A37F).value,
    ).then((ok) {
      if (!ok) debugPrint('Auto-sync falhou silenciosamente.');
    }).catchError((e) {
      debugPrint('Auto-sync erro: $e');
    });
  }

  /// Publica em lote todos os compromissos do Hive no Firestore (roda uma vez por sessão).
  /// Garante que eventos criados antes do compartilhamento fiquem visíveis para seguidores.
  bool _didSyncOnce = false;
  Future<void> _syncLocalToFirestore() async {
    if (_didSyncOnce) return;
    final auth = context.read<AuthService>();
    if (!auth.isSignedIn) return;
    _didSyncOnce = true;
    final sharing = context.read<SharingService>();
    // Aguarda o perfil estar pronto (pode ser necessário um pequeno delay pós-login)
    if (sharing.myProfile == null) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
    }
    final Map<String, List<dynamic>> snapshot = {};
    _commitmentsBox.toMap().forEach((key, value) {
      if (value is List && key is String) {
        snapshot[key] = List<dynamic>.from(value);
      }
    });
    await sharing.syncAllCommitments(snapshot);
  }

  /// Agenda notificação de lembrete para um compromisso (se tiver horário).
  void _scheduleNotification(DateTime date, Map<String, dynamic> commitment) {
    final hour = commitment['hour'] as String? ?? '';
    if (hour.isEmpty) return;
    final id = NotificationService.makeId(
      getDateKey(date),
      commitment['title'] ?? '',
      hour,
    );
    NotificationService().scheduleCommitmentNotification(
      id: id,
      title: commitment['title'] ?? 'Compromisso',
      hour: hour,
      date: date,
      notes: commitment['notes'],
    );
  }

  /// Cancela notificação de um compromisso removido.
  void _cancelNotification(DateTime date, Map<String, dynamic> commitment) {
    final hour = commitment['hour'] as String? ?? '';
    final id = NotificationService.makeId(
      getDateKey(date),
      commitment['title'] ?? '',
      hour,
    );
    NotificationService().cancelNotification(id);
  }

  void _loadAllCommitments() {
    final Map<String, List<dynamic>> loaded = {};
    _commitmentsBox.toMap().forEach((key, value) {
      if (value is List && key is String) {
        loaded[key] = List<dynamic>.from(value);
      }
    });
    _allCommitments = loaded;
    if(mounted) _updateSelectedCommitments();
  }

  List<dynamic> _getCommitmentsForDay(DateTime day) {
    final key = getDateKey(normalizeDate(day));
    return List<dynamic>.from(_allCommitments[key] ?? []);
  }

  /// Retorna os eventos do usuário seguido para um dia específico.
  List<Map<String, dynamic>> _getFollowedEventsForDay(DateTime day) {
    final key = getDateKey(normalizeDate(day));
    return _followedEvents.where((e) => e['_dateKey'] == key).toList();
  }

  List<Holiday> _getHolidaysForDay(DateTime day) {
    final normalizedDay = normalizeDate(day);
    return _cachedHolidays[normalizedDay.year]
        ?.where((h) => isSameDay(h.date, normalizedDay))
        .toList() ??
        [];
  }

  void _updateSelectedCommitments() {
    if (!mounted) return;
    final userCommitments = _getCommitmentsForDay(_selectedDate);
    final holidays = _getHolidaysForDay(_selectedDate);
    List<dynamic> combined = List.from(userCommitments);
    combined.addAll(holidays.map((h) => {
      'title': h.localName, 'isHoliday': true, 'notes': h.name,
      'hour': '', 'color': Colors.transparent.value
    }));
    // Adiciona eventos do usuário seguido para o dia selecionado (sem duplicar)
    final selKey = getDateKey(_selectedDate);
    final sharedForDay = _followedEvents.where((e) {
      return e['_dateKey'] == selKey;
    }).toList();
    for (final shared in sharedForDay) {
      final isDuplicate = combined.any((local) =>
        local is Map &&
        local['title'] == shared['title'] &&
        local['hour'] == shared['hour'] &&
        local['isShared'] != true);
      if (!isDuplicate) combined.add(shared);
    }

    combined.sort((a, b) {
      final aMap = a is Map ? a : <String, dynamic>{};
      final bMap = b is Map ? b : <String, dynamic>{};
      final isAHoliday = aMap['isHoliday'] == true; final isBHoliday = bMap['isHoliday'] == true;
      if (isAHoliday && !isBHoliday) return -1; if (!isAHoliday && isBHoliday) return 1;
      final isAFolga = aMap['title'] == 'Folga'; final isBFolga = bMap['title'] == 'Folga';
      if (isAFolga && !isBFolga) return 1; if (!isAFolga && isBFolga) return -1;
      final hourA = aMap['hour'] as String? ?? ''; final hourB = bMap['hour'] as String? ?? '';
      final hC = hourA.compareTo(hourB); if (hC != 0) return hC;
      final tA = aMap['title'] as String? ?? ''; final tB = bMap['title'] as String? ?? '';
      return tA.toLowerCase().compareTo(tB.toLowerCase());
    });
    _selectedCommitments.value = combined;
  }

  Future<void> _fetchHolidaysForYear(int year) async {
    if (_isLoadingHolidays || _cachedHolidays.containsKey(year)) {
      if (_cachedHolidays.containsKey(year)) _updateHolidayDatesSet();
      return;
    }
    if (!mounted) return;
    setState(() { _isLoadingHolidays = true; });
    const countryCode = 'BR';
    final url = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/$countryCode');
    List<Holiday> fetchedHolidays = [];
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        fetchedHolidays = (jsonDecode(response.body) as List).map((data) => Holiday.fromJson(data)).toList();
      } else {
        throw Exception('Status ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao buscar feriados.'), backgroundColor: Colors.red));
    }
    if (mounted) {
      setState(() {
        _cachedHolidays[year] = fetchedHolidays;
        _updateHolidayDatesSet();
        _isLoadingHolidays = false;
        _updateSelectedCommitments();
      });
    }
  }

  void _updateHolidayDatesSet() {
    final Set<DateTime> holidays = {};
    _cachedHolidays.values.expand((list) => list).forEach((holiday) { holidays.add(holiday.date); });
    if (mounted && !SetEquality().equals(_holidayDates, holidays)) {
      setState(() { _holidayDates = holidays; });
    }
  }

  void _toggleDayOffSingle(DateTime date) async {
    final normalizedDate = normalizeDate(date);
    final dateKey = getDateKey(normalizedDate);
    List<dynamic> existing = List<dynamic>.from(_commitmentsBox.get(dateKey, defaultValue: []));
    final isDayOff = existing.any((e) => e is Map && e['title'] == 'Folga');
    final folgaMap = {'title': 'Folga', 'color': Colors.grey.value, 'hour': '', 'notes': ''};
    if (isDayOff) {
      existing.removeWhere((e) => e is Map && e['title'] == 'Folga');
    } else {
      existing.add(folgaMap);
      _autoSync(normalizedDate, folgaMap);
    }
    await _commitmentsBox.put(dateKey, existing);
    _loadAllData();
  }

  Future<void> _toggleDayOffMultiple(Set<DateTime> days) async {
    if (!mounted || days.isEmpty) return;
    final addOrRemove = await showDialog<bool?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Folga para ${days.length} dia(s)'),
        content: const Text('Deseja MARCAR ou DESMARCAR folga?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('DESMARCAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('MARCAR')),
        ],
      ),
    );
    if (addOrRemove == null) return;
    for (DateTime day in days) {
      final dateKey = getDateKey(day);
      List<dynamic> existing = List<dynamic>.from(_commitmentsBox.get(dateKey, defaultValue: []));
      final isCurrentlyDayOff = existing.any((e) => e is Map && e['title'] == 'Folga');
      if (addOrRemove == true && !isCurrentlyDayOff) {
        existing.add({'title': 'Folga', 'color': Colors.grey.value, 'hour': '', 'notes': ''});
        await _commitmentsBox.put(dateKey, existing);
      } else if (addOrRemove == false && isCurrentlyDayOff) {
        existing.removeWhere((e) => e is Map && e['title'] == 'Folga');
        await _commitmentsBox.put(dateKey, existing);
      }
    }
  }

  Future<Map<String, dynamic>?> _openTemplateSelectorForMulti() async {
    if (!mounted) return null;
    return await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => TemplateSelectorPage()));
  }

  void _openTemplateSelectorForSingle() async {
    if (!mounted) return;
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => TemplateSelectorPage(selectedDate: _selectedDate)));
    if (result == true && mounted) _loadAllData();
  }

  void _openBillsPage() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BillsPage()));
    if (mounted) {
      _checkPendingBillsForMonth(_focusedDay);
    }
  }

  void _confirmRemove(int listIndex) async {
    if (_selectionMode != SelectionMode.single || !mounted) return;
    final List<dynamic> currentDisplayItems = List<dynamic>.from(_selectedCommitments.value);
    if (listIndex < 0 || listIndex >= currentDisplayItems.length) return;
    final item = currentDisplayItems[listIndex];
    if (item is! Map || item['isHoliday'] == true) return;
    final titleToRemove = item['title'] as String? ?? 'Compromisso';
    final dateKey = getDateKey(_selectedDate);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover Compromisso?'), content: Text('Deseja remover "$titleToRemove"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      List<dynamic> actualCommitments = List<dynamic>.from(_allCommitments[dateKey] ?? []);
      actualCommitments.removeWhere((hiveItem) =>
      hiveItem is Map && hiveItem['title'] == item['title'] && hiveItem['hour'] == item['hour'] &&
          hiveItem['notes'] == item['notes'] && hiveItem['color'] == item['color']);
      await _commitmentsBox.put(dateKey, actualCommitments);
      // Cancela a notificação do compromisso removido
      _cancelNotification(_selectedDate, Map<String, dynamic>.from(item));
      WidgetService.updateTodayWidget();
      _loadAllData();
    }
  }

  Future<void> _performBackupLocal() async {
    if (_isPerformingBackupRestore || !mounted) return;
    setState(() { _isPerformingBackupRestore = true; });

    final Box billsTemplatesBox = Hive.box('bills_templates');
    final Box billsPaidStatusBox = Hive.box('bills_paid_status');
    Map<String, dynamic> backupData = {
      'version': 1, 'backupDate': DateTime.now().toIso8601String(),
      'commitments': _commitmentsBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'templates': _templatesBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'bills_templates': billsTemplatesBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
      'bills_paid_status': billsPaidStatusBox.toMap().map((k, v) => MapEntry(k.toString(), v)),
    };
    String jsonBackup = jsonEncode(backupData);
    String defaultFileName = 'agenda_backup_local_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.json';

    try {
      if (kIsWeb) {
        await performWebBackup(defaultFileName, jsonBackup);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download do backup iniciado!'), duration: Duration(seconds: 4)));
      } else {
        final Uint8List fileBytes = Uint8List.fromList(utf8.encode(jsonBackup));
        String? outputFileSavePath = await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar Backup Local',
          fileName: defaultFileName,
          type: FileType.custom,
          allowedExtensions: ['json'],
          bytes: fileBytes,
        );

        if (outputFileSavePath != null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup local salvo em: $outputFileSavePath'), duration: const Duration(seconds: 4)));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup local cancelado.')));
        }
      }
    } catch (e) {
      print("Erro no backup local: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no backup local: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() { _isPerformingBackupRestore = false; });
    }
  }

  Future<void> _performRestoreLocal() async {
    if (_isPerformingBackupRestore || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar Backup Local?'),
        content: const Text('ATENÇÃO: Dados atuais serão substituídos. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restaurar', style: TextStyle(color: Colors.orange))),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() { _isPerformingBackupRestore = true; });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['json'], withData: kIsWeb,
      );
      if (result != null) {
        String jsonString;
        if (kIsWeb) {
          if (result.files.single.bytes == null) throw Exception("Falha ao ler bytes do arquivo na web.");
          jsonString = utf8.decode(result.files.single.bytes!);
        } else {
          if (result.files.single.path == null) throw Exception("Caminho do arquivo não encontrado.");
          final file = File(result.files.single.path!);
          jsonString = await file.readAsString();
        }

        final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
        if (backupData.containsKey('commitments') && backupData.containsKey('templates') &&
            backupData.containsKey('bills_templates') && backupData.containsKey('bills_paid_status')) {
          final Box billsTemplatesBox = Hive.box('bills_templates');
          final Box billsPaidStatusBox = Hive.box('bills_paid_status');

          await _commitmentsBox.clear(); await _templatesBox.clear();
          await billsTemplatesBox.clear(); await billsPaidStatusBox.clear();

          await _commitmentsBox.putAll(Map<dynamic, dynamic>.from(backupData['commitments']));
          await _templatesBox.putAll(Map<dynamic, dynamic>.from(backupData['templates']));
          await billsTemplatesBox.putAll(Map<dynamic, dynamic>.from(backupData['bills_templates']));
          await billsPaidStatusBox.putAll(Map<dynamic, dynamic>.from(backupData['bills_paid_status']));

          _loadAllData();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dados locais restaurados!')));
        } else {
          throw Exception("Arquivo de backup inválido.");
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restauração local cancelada.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao restaurar localmente: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() { _isPerformingBackupRestore = false; });
    }
  }

  Future<void> _editCommitmentNotes(int listIndex) async {
    if (_selectionMode != SelectionMode.single || !mounted) return;
    final List<dynamic> currentDisplayItems = List<dynamic>.from(_selectedCommitments.value);
    if (listIndex < 0 || listIndex >= currentDisplayItems.length) return;
    final item = currentDisplayItems[listIndex];
    if (item is! Map || item['isHoliday'] == true || item['title'] == 'Folga') return;

    final dateKey = getDateKey(_selectedDate);
    final List<dynamic> actualCommitments = List<dynamic>.from(_allCommitments[dateKey] ?? []);
    final int hiveIndex = actualCommitments.indexWhere((hiveItem) =>
    hiveItem is Map && hiveItem['title'] == item['title'] && hiveItem['hour'] == item['hour'] &&
        hiveItem['notes'] == item['notes'] && hiveItem['color'] == item['color']);

    if (hiveIndex == -1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao encontrar compromisso para editar.'), backgroundColor: Colors.red));
      return;
    }

    final Map<String, dynamic> commitmentMap = Map<String, dynamic>.from(actualCommitments[hiveIndex]);
    final notesController = TextEditingController(text: commitmentMap['notes'] as String? ?? '');

    final bool? noteSaved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Notas - ${commitmentMap['title'] ?? 'Compromisso'}'),
        content: TextField(controller: notesController, decoration: const InputDecoration(hintText: 'Adicione suas notas aqui...', border: OutlineInputBorder()), maxLines: 4, textCapitalization: TextCapitalization.sentences, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () { Navigator.pop(ctx, true); }, child: const Text('Salvar')),
        ],
      ),
    );

    if (noteSaved == true && mounted) {
      commitmentMap['notes'] = notesController.text.trim();
      actualCommitments[hiveIndex] = commitmentMap;
      try {
        await _commitmentsBox.put(dateKey, actualCommitments);
        _loadAllData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao salvar notas.'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildCellContent(DateTime day, DateTime focusedDay, {required bool isToday, required bool isSelected, required bool isOutside}) {
    final normalizedDay = normalizeDate(day);
    final commitments = _getCommitmentsForDay(normalizedDay).where((c) => c is Map && c['isHoliday'] != true).toList();
    final followedForDay = _getFollowedEventsForDay(normalizedDay);
    final allDayEvents = [...commitments, ...followedForDay];
    final bool isHoliday = _holidayDates.contains(normalizedDay);
    final List<Color> uniqueCommitmentColors = allDayEvents
        .where((c) => c is Map && c['title'] != 'Folga')
        .map((c) => (c['color'] is int) ? Color(c['color'] as int) : null)
        .whereType<Color>().toSet().take(4).toList();
    final bool isMultiSelected = _selectionMode == SelectionMode.multi && _multiSelectedDays.contains(normalizedDay);

    TextStyle textStyle = TextStyle(fontSize: 15, color: isOutside ? Colors.grey[700] : Colors.white);
    FontWeight fontWeight = (!isOutside && (isSelected || isToday || isHoliday)) ? FontWeight.bold : FontWeight.normal;

    Widget cellInnerContent;
    if (uniqueCommitmentColors.isNotEmpty && !isOutside) {
      cellInnerContent = Stack(alignment: Alignment.center, children: [
        Row(children: uniqueCommitmentColors.map((color) => Expanded(child: Container(color: color))).toList()),
        Text('${day.day}', style: textStyle.copyWith(fontWeight: fontWeight, color: Colors.white, shadows: [const Shadow(blurRadius: 1.5, color: Color.fromRGBO(0, 0, 0, 0.9), offset: Offset(0,0))])),
        if (isMultiSelected) Positioned(top: 2, left: 2, child: Icon(Icons.check_circle, color: Colors.white.withOpacity(0.8), size: 14)),
        if (isHoliday) Positioned(bottom: 2, right: 2, child: Icon(Icons.celebration_rounded, size: 12, color: Colors.white.withOpacity(0.9))),
      ]);
    } else if (isMultiSelected && !isOutside) {
      cellInnerContent = Stack(alignment: Alignment.center, children: [
        Container(decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.8), width: 1.5), shape: BoxShape.circle)),
        Text('${day.day}', style: textStyle.copyWith(fontWeight: fontWeight, color: Colors.white)),
        if (isHoliday) Positioned(bottom: 2, right: 2, child: Icon(Icons.celebration_rounded, size: 12, color: Theme.of(context).colorScheme.primary.withOpacity(0.9))),
      ]);
    } else if (isHoliday && !isOutside) {
      cellInnerContent = Stack(alignment: Alignment.center, children: [
        Text('${day.day}', style: textStyle.copyWith(fontWeight: fontWeight, color: Colors.amber[300])),
      ]);
    } else {
      Color finalTextColor = isOutside ? Colors.grey[700]! : Colors.white;
      if (!isOutside && (isSelected || isToday)) finalTextColor = Colors.white;
      cellInnerContent = Text('${day.day}', style: textStyle.copyWith(fontWeight: fontWeight, color: finalTextColor));
    }

    if (isToday && !isOutside) {
      return Container(
        margin: const EdgeInsets.all(2.0),
        decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 1.8), shape: BoxShape.circle),
        child: Center(child: cellInnerContent),
      );
    } else {
      return cellInnerContent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectionMode == SelectionMode.multi
            ? 'Seleção Múltipla (${_multiSelectedDays.length})'
            : 'Agenda Mensal'),
        actions: [
          // Botão: Seleção Única
          IconButton(
            icon: const Icon(Icons.crop_square), tooltip: 'Seleção Única',
            color: _selectionMode == SelectionMode.single ? Theme.of(context).colorScheme.primary : Colors.white54,
            onPressed: () {
              if (_selectionMode != SelectionMode.single) {
                setState(() {
                  _selectionMode = SelectionMode.single;
                  _multiSelectedDays.clear();
                  _selectedDate = normalizeDate(_focusedDay);
                  _updateSelectedCommitments();
                });
              }
            },
          ),
          // Botão: Seleção Múltipla
          IconButton(
            icon: const Icon(Icons.select_all), tooltip: 'Seleção Múltipla',
            color: _selectionMode == SelectionMode.multi ? Theme.of(context).colorScheme.primary : Colors.white54,
            onPressed: () {
              if (_selectionMode != SelectionMode.multi) {
                setState(() {
                  _selectionMode = SelectionMode.multi;
                  _multiSelectedDays.clear();
                  _multiSelectedDays.add(_selectedDate);
                });
              }
            },
          ),
          // Botão: Refresh dos eventos do seguido
          Consumer<SharingService>(
            builder: (ctx, sharing, _) {
              if (sharing.followedProfiles.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: _isRefreshingShared
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
                    : const Icon(Icons.sync_rounded),
                tooltip: 'Atualizar agenda compartilhada',
                color: const Color(0xFF10A37F),
                onPressed: _refreshFollowedEvents,
              );
            },
          ),
          // Botão: Menu de Compartilhamento
          Consumer<SharingService>(
            builder: (ctx, sharing, _) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.people_alt_outlined, color: Colors.white70),
                tooltip: 'Compartilhamento',
                color: Theme.of(context).popupMenuTheme.color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                itemBuilder: (_) => [
                  // Meu código
                  PopupMenuItem(
                    value: 'my_code',
                    child: ListTile(
                      leading: const Icon(Icons.qr_code_rounded, color: Color(0xFF10A37F)),
                      title: const Text('Meu Código de Compartilhamento'),
                      subtitle: sharing.myShareCode.isNotEmpty
                          ? Text(sharing.myShareCode,
                              style: const TextStyle(
                                  fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.bold, color: Color(0xFF10A37F)))
                          : const Text('Carregando...'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  // Seguir usuário
                  const PopupMenuItem(
                    value: 'follow',
                    child: ListTile(
                      leading: Icon(Icons.person_add_alt_1_rounded, color: Colors.white70),
                      title: Text('Seguir Usuário'),
                      subtitle: Text('Insira o código de 8 dígitos'),
                    ),
                  ),
                  // Lista de seguidos
                  if (sharing.followedProfiles.isNotEmpty) ...[
                    const PopupMenuDivider(),
                    ...sharing.followedProfiles.map((p) => PopupMenuItem(
                      value: 'unfollow_${p.uid}',
                      child: ListTile(
                        leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                        title: Text('Deixar de seguir'),
                        subtitle: Text(p.displayName),
                      ),
                    )),
                  ],
                ],
                onSelected: (value) async {
                  if (value == 'my_code') {
                    await _showMyCodeDialog(sharing.myShareCode);
                  } else if (value == 'follow') {
                    await _showFollowDialog(sharing);
                  } else if (value.startsWith('unfollow_')) {
                    final uid = value.replaceFirst('unfollow_', '');
                    await sharing.unfollow(uid);
                    _subscribeToFollowedEvents();
                  }
                },
              );
            },
          ),
        ],
      ),
      body: Stack(children: [
        Column(children: [
          Expanded(
            flex: 5,
            child: TableCalendar<dynamic>(
              locale: 'pt_BR',
              focusedDay: _focusedDay,
              firstDay: DateTime.utc(2000),
              lastDay: DateTime.utc(2100),
              selectedDayPredicate: (day) => _selectionMode == SelectionMode.single && isSameDay(_selectedDate, normalizeDate(day)),
              onDaySelected: (selectedDay, focusedDay) {
                final normalizedSelectedDay = normalizeDate(selectedDay);
                bool monthJustChanged = normalizeDate(focusedDay).month != normalizeDate(this._focusedDay).month ||
                    normalizeDate(focusedDay).year != normalizeDate(this._focusedDay).year;
                if (mounted) {
                  setState(() {
                    this._focusedDay = focusedDay;
                    _selectedDate = normalizedSelectedDay;
                    if (_selectionMode == SelectionMode.multi) {
                      if (_multiSelectedDays.contains(normalizedSelectedDay)) _multiSelectedDays.remove(normalizedSelectedDay);
                      else _multiSelectedDays.add(normalizedSelectedDay);
                    }
                    _updateSelectedCommitments();
                    if (monthJustChanged) {
                      _checkPendingBillsForMonth(this._focusedDay);
                    }
                  });
                }
              },
              onPageChanged: (focusedDay) {
                if (mounted) {
                  setState(() {
                    this._focusedDay = focusedDay;
                    _selectedDate = normalizeDate(focusedDay);
                    if (!_cachedHolidays.containsKey(focusedDay.year)) _fetchHolidaysForYear(focusedDay.year);
                    else _updateHolidayDatesSet();
                    _updateSelectedCommitments();
                    _checkPendingBillsForMonth(this._focusedDay);
                  });
                  // Recria o stream do seguido com o novo mês
                  _subscribeToFollowedEvents();
                }
              },
              eventLoader: (day) {
                final normDay = normalizeDate(day);
                return [..._getCommitmentsForDay(normDay), ..._getFollowedEventsForDay(normDay), ..._getHolidaysForDay(normDay)];
              },
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarStyle: CalendarStyle(
                outsideDaysVisible: true, defaultTextStyle: const TextStyle(fontSize: 15, color: Colors.white),
                weekendTextStyle: const TextStyle(fontSize: 15, color: Colors.white70),
                outsideTextStyle: TextStyle(fontSize: 14, color: Colors.grey[700]),
                selectedDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.7), shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), shape: BoxShape.circle),
                selectedTextStyle: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                todayTextStyle: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(fontSize: 18.0, color: Colors.white),
                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white), rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  final userEventsCount = events.where((e) => e is Map && e['isHoliday'] != true).length;
                  final hasHoliday = events.any((e) => e is Holiday || (e is Map && e['isHoliday'] == true));
                  final normalizedDay = normalizeDate(date);
                  final isOutside = normalizedDay.month != _focusedDay.month;
                  if (isOutside) return null;
                  List<Widget> markers = [];
                  if (userEventsCount > 0) {
                    markers.add(Positioned(right: 2, top: 2, child: Container(
                      padding: const EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.6)),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('$userEventsCount', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    )));
                  }
                  if (hasHoliday) markers.add(Positioned(bottom: 4, left: 4, child: Icon(Icons.celebration_rounded, size: 10, color: Colors.amber[600])));
                  if (markers.isEmpty) return null;
                  return Stack(children: markers);
                },
                defaultBuilder: (context, day, fDay) {
                  bool isToday = isSameDay(normalizeDate(day), normalizeDate(DateTime.now()));
                  bool isSelected = _selectionMode == SelectionMode.single && isSameDay(_selectedDate, normalizeDate(day));
                  return _buildCellContent(day, fDay, isToday: isToday, isSelected: isSelected, isOutside: false);
                },
                outsideBuilder: (context, day, fDay) => _buildCellContent(day, fDay, isToday: false, isSelected: false, isOutside: true),
                selectedBuilder: (context, day, fDay) {
                  final bool isToday = isSameDay(normalizeDate(day), normalizeDate(DateTime.now()));
                  return _buildCellContent(day, fDay, isToday: isToday, isSelected: true, isOutside: false);
                },
                todayBuilder: (context, day, fDay) {
                  final bool isSelected = _selectionMode == SelectionMode.single && isSameDay(_selectedDate, normalizeDate(day));
                  return _buildCellContent(day, fDay, isToday: true, isSelected: isSelected, isOutside: false);
                },
                disabledBuilder: (context, day, fDay) => Text('${day.day}', style: TextStyle(color: Colors.grey[800])),
              ),
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              "Itens para ${localizations.formatFullDate(_selectedDate)}",
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            flex: 4,
            child: ValueListenableBuilder<List<dynamic>>(
              valueListenable: _selectedCommitments,
              builder: (context, displayItems, _) {
                if (displayItems.isEmpty && _selectionMode == SelectionMode.single) {
                  return Center(child: Text("Nenhum item neste dia.", style: Theme.of(context).textTheme.bodyMedium));
                }
                if (_selectionMode == SelectionMode.multi && _multiSelectedDays.isEmpty) {
                  return Center(child: Text("Selecione dias no calendário.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
                }
                if (_selectionMode == SelectionMode.multi && _multiSelectedDays.isNotEmpty && displayItems.isEmpty) {
                  return Center(child: Text("Use '+' para ações nos ${_multiSelectedDays.length} dias selecionados.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium));
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80, left: 8, right: 8),
                  itemCount: displayItems.length,
                  itemBuilder: (_, index) {
                    final item = displayItems[index];
                    if (item is Map) {
                      final isHolidayItem = item['isHoliday'] == true;
                      final title = item['title'] as String? ?? 'Sem Título';
                      final notes = item['notes'] as String? ?? '';
                      final hour = item['hour'] as String? ?? '';
                      final isDayOff = !isHolidayItem && title == 'Folga';
                      final isShared = item['isShared'] == true;
                      final ownerName = item['ownerName'] as String? ?? '';
                      Color itemColor = Colors.transparent;
                      Widget? leadingIcon;

                      if (isHolidayItem) {
                        itemColor = Colors.amber[800]!;
                        leadingIcon = const Icon(Icons.celebration_rounded, color: Colors.white, size: 22);
                      } else if (isDayOff) {
                        itemColor = Color(item['color'] as int? ?? Colors.grey.value);
                        leadingIcon = const Icon(Icons.free_breakfast_outlined, size: 20, color: Colors.white70);
                      } else if (isShared) {
                        itemColor = Color(item['color'] as int? ?? Colors.orange.value);
                        leadingIcon = const Icon(Icons.people_rounded, size: 20, color: Colors.white);
                      } else {
                        itemColor = Color(item['color'] as int? ?? Theme.of(context).colorScheme.primary.value);
                      }
                      return Card(
                        // Borda sutil para eventos compartilhados
                        shape: isShared
                            ? RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFFF9800), width: 1.2))
                            : null,
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: itemColor, child: leadingIcon),
                          title: Text(
                            isHolidayItem ? title : (hour.isNotEmpty ? '[$hour] $title' : title),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              decoration: isDayOff ? TextDecoration.lineThrough : TextDecoration.none,
                              color: isDayOff ? Colors.grey[500] : (isHolidayItem ? Colors.amber[200] : Colors.white),
                              fontStyle: isHolidayItem ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (notes.isNotEmpty && !isHolidayItem)
                                Text(notes, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: isDayOff ? Colors.grey[600] : Colors.white70)),
                              if (isShared && ownerName.isNotEmpty)
                                Text('\ud83d\udc65 $ownerName',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFFFF9800))),
                            ],
                          ),
                          trailing: (!isHolidayItem && !isShared && _selectionMode == SelectionMode.single)
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                            if (!isDayOff)
                              IconButton(
                                  icon: const Icon(Icons.note_alt_outlined, size: 20),
                                  tooltip: 'Editar Notas',
                                  color: Colors.white54,
                                  onPressed: () => _editCommitmentNotes(index),
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.symmetric(horizontal: 4)),
                            IconButton(
                                icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.7)),
                                tooltip: "Remover",
                                onPressed: () => _confirmRemove(index),
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.symmetric(horizontal: 4)),
                          ])
                              : null,
                        ),
                      );
                    } else {
                      return const ListTile(title: Text("Inválido"));
                    }
                  },
                );
              },
            ),
          ),
        ]),

        if (_hasPendingBills && _pendingBillsOffsetAnimation != null)
          Positioned(
            bottom: 15, left: 0, right: 0,
            child: Center(
              child: SlideTransition(
                position: _pendingBillsOffsetAnimation!,
                child: GestureDetector(
                  onTap: () { _openBillsPage(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: const Offset(0, 2))],
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text("Contas pendentes este mês!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        if (_isLoadingHolidays || _isPerformingBackupRestore)
          Container(
            color: Colors.black.withOpacity(0.5),
            child: Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary))),
          ),

        // Tela de progresso de download global
        ValueListenableBuilder<bool>(
          valueListenable: updateService.isDownloading,
          builder: (context, isDownloading, child) {
            if (!isDownloading) return const SizedBox.shrink();

            return Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.7),
                child: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: updateService.downloadProgress,
                    builder: (context, progress, child) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(value: progress > 0 ? progress : null),
                          const SizedBox(height: 20),
                          Text(
                            progress > 0
                                ? 'Baixando atualização... ${(progress * 100).toStringAsFixed(0)}%'
                                : 'Iniciando download...',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: _selectionMode == SelectionMode.multi ? 'Ações para Selecionados' : 'Adicionar/Gerenciar',
        child: PopupMenuButton<String>(
          icon: Icon(_selectionMode == SelectionMode.multi && _multiSelectedDays.isNotEmpty ? Icons.playlist_add_check : Icons.add, color: Colors.white),
          offset: const Offset(0, -kToolbarHeight * 4.5),
          color: Theme.of(context).popupMenuTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (_) {
            List<PopupMenuEntry<String>> items = [];
            if (_selectionMode == SelectionMode.multi) {
              items.add(PopupMenuItem(value: 'add_multi', enabled: _multiSelectedDays.isNotEmpty, child: ListTile(leading: Icon(Icons.add_task, color: _multiSelectedDays.isNotEmpty ? Theme.of(context).iconTheme.color : Colors.grey), title: Text('Adicionar aos ${(_multiSelectedDays.length)} dias'))));
              items.add(PopupMenuItem(value: 'folga_multi', enabled: _multiSelectedDays.isNotEmpty, child: ListTile(leading: Icon(Icons.free_breakfast_outlined, color: _multiSelectedDays.isNotEmpty ? Theme.of(context).iconTheme.color : Colors.grey), title: Text('Folga nos ${(_multiSelectedDays.length)} dias'))));
            } else {
              items.add(PopupMenuItem(value: 'adicionar_single', child: ListTile(leading: Icon(Icons.add_task, color: Theme.of(context).iconTheme.color), title: const Text('Adicionar Compromisso'))));
              items.add(PopupMenuItem(value: 'folga_single', child: ListTile(leading: Icon(Icons.free_breakfast_outlined, color: Theme.of(context).iconTheme.color), title: const Text('Marcar/Desmarcar Folga'))));
            }
            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(value: 'ver_contas', child: ListTile(leading: Icon(Icons.request_quote_outlined, color: Theme.of(context).iconTheme.color), title: const Text('Ver Contas Mensais'))));

            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(value: 'show_info', child: ListTile(leading: Icon(Icons.info_outline, color: Theme.of(context).iconTheme.color), title: const Text('Sobre o App'))));

            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(value: 'backup_local', child: ListTile(leading: Icon(Icons.save_alt, color: Theme.of(context).iconTheme.color), title: const Text('Backup Local'))));
            items.add(PopupMenuItem(value: 'restore_local', child: ListTile(leading: Icon(Icons.restore_from_trash_outlined, color: Theme.of(context).iconTheme.color), title: const Text('Restaurar Local'))));
            items.add(const PopupMenuDivider());
            items.add(const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout_rounded, color: Colors.redAccent), title: Text('Sair da Conta', style: TextStyle(color: Colors.redAccent)))));
            return items;
          },
          onSelected: (value) async {
            if (value == 'ver_contas') {
              _openBillsPage();
            } else if (value == 'backup_local') {
              _performBackupLocal();
            } else if (value == 'restore_local') {
              _performRestoreLocal();
            } else if (value == 'show_info') {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const InfoPage()));
            } else if (_selectionMode == SelectionMode.single) {
              if (value == 'adicionar_single') _openTemplateSelectorForSingle();
              if (value == 'folga_single') _toggleDayOffSingle(_selectedDate);
            } else if (_selectionMode == SelectionMode.multi) {
              if (value == 'add_multi' && _multiSelectedDays.isNotEmpty) {
                final selectedTemplate = await _openTemplateSelectorForMulti();
                if (selectedTemplate != null && mounted) {
                  for (DateTime day in _multiSelectedDays) {
                    final dateKey = getDateKey(day);
                    List<dynamic> commitments = List<dynamic>.from(_commitmentsBox.get(dateKey, defaultValue: []));
                    commitments.add(Map<String, dynamic>.from(selectedTemplate));
                    await _commitmentsBox.put(dateKey, commitments);
                  }
                  if (mounted) {
                    setState(() { _multiSelectedDays.clear(); _selectionMode = SelectionMode.single; });
                    _loadAllData();
                  }
                }
              } else if (value == 'folga_multi' && _multiSelectedDays.isNotEmpty) {
                await _toggleDayOffMultiple(Set.from(_multiSelectedDays));
                if (mounted) {
                  setState(() { _multiSelectedDays.clear(); _selectionMode = SelectionMode.single; });
                  _loadAllData();
                }
              }
            } else if (value == 'logout') {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Sair da Conta?'),
                  content: const Text('Deseja desconectar sua conta Google?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Sair', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
              if (confirm == true && mounted) {
                await context.read<AuthService>().signOut();
              }
            }
          },
        ),
      ),
    );
  }
  // ─── Dialogs de Compartilhamento ──────────────────────────────────────────

  Future<void> _showMyCodeDialog(String code) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.qr_code_rounded, color: Color(0xFF10A37F)),
          SizedBox(width: 8),
          Text('Meu Código'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Compartilhe este código com quem deseja te seguir:',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF10A37F), width: 1.5),
              ),
              child: Text(
                code.isNotEmpty ? code : '...',
                style: const TextStyle(
                  fontSize: 26, letterSpacing: 8,
                  fontWeight: FontWeight.bold, color: Color(0xFF10A37F),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar'),
            onPressed: () {
              if (code.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: code));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Código copiado!'), duration: Duration(seconds: 2)),
                );
              }
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _showFollowDialog(SharingService sharing) async {
    final controller = TextEditingController();
    String? error;
    bool isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(children: [
            Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF10A37F)),
            SizedBox(width: 8),
            Text('Seguir Usuário'),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Insira o código de 8 caracteres do usuário:',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'Ex: A3F9B2D1',
                  errorText: error,
                  prefixIcon: const Icon(Icons.tag_rounded),
                ),
                onChanged: (v) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              if (isLoading) const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isLoading ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      final code = controller.text.trim().toUpperCase();
                      if (code.length != 8) {
                        setDialogState(() => error = 'O código deve ter 8 caracteres');
                        return;
                      }
                      setDialogState(() { isLoading = true; error = null; });
                      final result = await sharing.followByCode(code);
                      if (!ctx.mounted) return;
                      if (result.success) {
                        Navigator.pop(ctx);
                        _subscribeToFollowedEvents();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('✅ Agora seguindo ${result.profile?.displayName ?? code}!'),
                              backgroundColor: const Color(0xFF10A37F),
                            ),
                          );
                        }
                      } else {
                        setDialogState(() {
                          isLoading = false;
                          error = result.errorMsg ?? 'Código não encontrado';
                        });
                      }
                    },
              child: const Text('Seguir'),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Template Selector Page ---
class TemplateSelectorPage extends StatefulWidget {
  final DateTime? selectedDate;
  const TemplateSelectorPage({super.key, this.selectedDate});

  @override
  _TemplateSelectorPageState createState() => _TemplateSelectorPageState();
}

class _TemplateSelectorPageState extends State<TemplateSelectorPage> {
  late Box _templatesBox;
  late Box _commitmentsBox;
  List<Map<String, dynamic>> templates = [];
  bool _notifyMe = true;

  @override
  void initState() {
    super.initState();
    _templatesBox = Hive.box('templates');
    _commitmentsBox = Hive.box('commitments');
    _loadTemplates();
  }

  void _loadTemplates() {
    final List<Map<String, dynamic>> loadedTemplates = [];
    final templatesMap = _templatesBox.toMap();
    templatesMap.forEach((key, value) {
      if (value is Map) {
        var templateData = Map<String, dynamic>.from(value);
        loadedTemplates.add(templateData);
      }
    });
    loadedTemplates.sort((a, b) {
      final titleA = (a['title'] as String? ?? '').toLowerCase();
      final titleB = (b['title'] as String? ?? '').toLowerCase();
      return titleA.compareTo(titleB);
    });
    if (mounted) {
      setState(() { templates = loadedTemplates; });
    }
  }

  void _handleTemplateSelection(Map<String, dynamic> template) async {
    if (widget.selectedDate != null) {
      final dateKey = getDateKey(widget.selectedDate!);
      final List<dynamic> dayCommitments = List<dynamic>.from(_commitmentsBox.get(dateKey, defaultValue: []));
      final commitmentMap = Map<String, dynamic>.from(template);
      commitmentMap['notify'] = _notifyMe;
      dayCommitments.add(commitmentMap);
      await _commitmentsBox.put(dateKey, dayCommitments);

      // Auto-sync para o Firestore
      try {
        final auth = context.read<AuthService>();
        final sharing = context.read<SharingService>();
        if (auth.isSignedIn) {
          sharing.publishCommitment(
            date: widget.selectedDate!,
            title: commitmentMap['title'] ?? '',
            hour: commitmentMap['hour'] ?? '',
            notes: commitmentMap['notes'] ?? '',
            colorValue: commitmentMap['color'] ?? const Color(0xFF10A37F).value,
          );
        }
      } catch (e) {
        debugPrint('Auto-sync template: $e');
      }

      // Agenda notificação se o usuário optou por ser notificado
      if (_notifyMe) {
        try {
          final hour = commitmentMap['hour'] as String? ?? '';
          if (hour.isNotEmpty) {
            final id = NotificationService.makeId(dateKey, commitmentMap['title'] ?? '', hour);
            NotificationService().scheduleCommitmentNotification(
              id: id,
              title: commitmentMap['title'] ?? 'Compromisso',
              hour: hour,
              date: widget.selectedDate!,
              notes: commitmentMap['notes'],
            );
          }
        } catch (e) {
          debugPrint('Schedule notification: $e');
        }
      }

      // Atualiza o widget da tela inicial
      WidgetService.updateTodayWidget();

      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) Navigator.pop(context, template);
    }
  }

  void _navigateToTemplateManager() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TemplateManagerPage()));
    if (mounted) {
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectedDate != null ? 'Adicionar Compromisso' : 'Selecionar Modelo Comp.'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Gerenciar Modelos de Compromisso',
            onPressed: _navigateToTemplateManager,
          ),
        ],
      ),
      body: templates.isEmpty
          ? Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Nenhum modelo de compromisso criado.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text("Criar Novo Modelo"),
                  onPressed: _navigateToTemplateManager,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ))
          : Column(children: [
        if (widget.selectedDate != null)
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Notificar-me 30 min antes'),
            value: _notifyMe,
            onChanged: (v) => setState(() => _notifyMe = v),
          ),
        if (widget.selectedDate != null) const Divider(height: 1),
        Expanded(child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: templates.length,
        itemBuilder: (_, index) {
          final template = templates[index];
          final colorVal = template['color'] is int ? template['color'] : Colors.grey.value;
          final color = Color(colorVal);
          final title = template['title'] as String? ?? 'Sem Título';
          final hour = template['hour'] as String? ?? '';
          final notes = template['notes'] as String? ?? '';
          return Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: color),
                title: Text(hour.isNotEmpty ? '[$hour] $title' : title),
                subtitle: notes.isNotEmpty ? Text(notes, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                onTap: () => _handleTemplateSelection(Map<String, dynamic>.from(template)),
              ));
        },
      )),
      ]),
    );
  }
}

// --- Template Manager Page ---
class TemplateManagerPage extends StatefulWidget {
  const TemplateManagerPage({super.key});

  @override
  _TemplateManagerPageState createState() => _TemplateManagerPageState();
}

class _TemplateManagerPageState extends State<TemplateManagerPage> {
  late Box _templatesBox;
  List _templateKeys = [];

  @override
  void initState() {
    super.initState();
    _templatesBox = Hive.box('templates');
    _loadTemplateKeys();
  }

  void _loadTemplateKeys() {
    var keys = _templatesBox.keys.toList();
    keys.sort((a, b) {
      final valA = _templatesBox.get(a); final valB = _templatesBox.get(b);
      final tA = (valA is Map ? valA['title'] as String? : null) ?? '';
      final tB = (valB is Map ? valB['title'] as String? : null) ?? '';
      return tA.toLowerCase().compareTo(tB.toLowerCase());
    });
    if (mounted) {
      setState(() { _templateKeys = keys; });
    }
  }

  void _addOrEditTemplate({int? editIndex}) async {
    final bool isEditing = editIndex != null;
    Map<String, dynamic>? existingTemplate;
    dynamic existingKey;
    if (isEditing) {
      existingKey = _templateKeys[editIndex!];
      final rawData = _templatesBox.get(existingKey);
      if (rawData is Map) {
        existingTemplate = Map<String, dynamic>.from(rawData);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao carregar modelo.'), backgroundColor: Colors.red));
        return;
      }
    }
    Color selectedColor = isEditing ? Color(existingTemplate!['color'] as int? ?? Colors.blue.value) : const Color(0xFF10A37F);
    final controllerTitle = TextEditingController(text: isEditing ? existingTemplate!['title'] as String? ?? '' : '');
    final controllerHour = TextEditingController(text: isEditing ? existingTemplate!['hour'] as String? ?? '' : '');
    final controllerNotes = TextEditingController(text: isEditing ? existingTemplate!['notes'] as String? ?? '' : '');
    if (!mounted) return;

    await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(isEditing ? 'Editar Modelo Comp.' : 'Novo Modelo Comp.'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: controllerTitle, decoration: const InputDecoration(labelText: 'Título *', hintText: "Ex: Plantão"), maxLength: 50, textCapitalization: TextCapitalization.sentences),
              const SizedBox(height: 8),
              TextField(controller: controllerHour, decoration: const InputDecoration(labelText: 'Horário', hintText: "Ex: 08:00 - 18:00"), maxLength: 30),
              const SizedBox(height: 8),
              TextField(controller: controllerNotes, decoration: const InputDecoration(labelText: 'Notas', hintText: "Ex: Levar café"), maxLines: 3, maxLength: 100, textCapitalization: TextCapitalization.sentences),
              const SizedBox(height: 15),
              Text("Cor:", style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 10),
              BlockPicker(pickerColor: selectedColor, onColorChanged: (color) => selectedColor = color, availableColors: const [
                Colors.red, Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                Colors.brown, Colors.grey, Colors.blueGrey, Color(0xFF10A37F)
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            TextButton(onPressed: () async {
              if (controllerTitle.text.trim().isEmpty) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Título é obrigatório.'), backgroundColor: Colors.orange[800]));
                return;
              }
              final template = {'title': controllerTitle.text.trim(), 'hour': controllerHour.text.trim(), 'notes': controllerNotes.text.trim(), 'color': selectedColor.value};
              try {
                if (isEditing) await _templatesBox.put(existingKey, template);
                else await _templatesBox.add(template);
                _loadTemplateKeys();
                if (mounted) Navigator.pop(context, true);
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
              }
            }, child: const Text('Salvar')),
          ],
        ));
  }

  void _deleteTemplate(int index) async {
    if (index < 0 || index >= _templateKeys.length) return;
    final keyToDelete = _templateKeys[index];
    final rawData = _templatesBox.get(keyToDelete);
    String title = 'Modelo';
    if (rawData is Map) title = Map<String, dynamic>.from(rawData)['title'] as String? ?? title;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir Modelo?'), content: Text('Excluir o modelo "$title"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.redAccent))),
          ],
        ));
    if (confirm == true) {
      try {
        await _templatesBox.delete(keyToDelete);
        _loadTemplateKeys();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text('Gerenciar Modelos Comp.'), actions: [IconButton(onPressed: () => _addOrEditTemplate(), icon: const Icon(Icons.add_circle_outline), tooltip: "Adicionar Modelo")]),
        body: _templateKeys.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Nenhum modelo criado.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)))
            : ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80, left: 8, right: 8),
            itemCount: _templateKeys.length,
            itemBuilder: (_, index) {
              final key = _templateKeys[index];
              final item = _templatesBox.get(key);
              if (item is Map) {
                final template = Map<String, dynamic>.from(item);
                final colorValue = template['color'] is int ? template['color'] : Colors.grey.value;
                final color = Color(colorValue);
                final title = template['title'] as String? ?? 'Sem Título';
                final hour = template['hour'] as String? ?? '';
                final notes = template['notes'] as String? ?? '';
                List<String> subtitleParts = [];
                if (hour.isNotEmpty) subtitleParts.add('Hora: $hour');
                if (notes.isNotEmpty) subtitleParts.add('Notas: $notes');
                final subtitle = subtitleParts.join(' | ');
                return Card(child: ListTile(
                  leading: CircleAvatar(backgroundColor: color),
                  title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
                  subtitle: subtitle.isNotEmpty ? Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)) : null,
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: const Icon(Icons.edit_outlined, size: 22), color: Colors.white70, tooltip: 'Editar', onPressed: () => _addOrEditTemplate(editIndex: index), constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    IconButton(icon: Icon(Icons.delete_outline, size: 22), color: Colors.redAccent.withOpacity(0.8), tooltip: 'Excluir', onPressed: () => _deleteTemplate(index), constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ]),
                ));
              } else {
                return Card(child: ListTile(title: Text("Inválido (Chave: $key)")));
              }
            }));
  }
}

// --- Bill Manager Page ---
class BillManagerPage extends StatefulWidget {
  const BillManagerPage({super.key});

  @override
  _BillManagerPageState createState() => _BillManagerPageState();
}

class _BillManagerPageState extends State<BillManagerPage> {
  late Box _billsBox;
  List<Map<String, dynamic>> _billTemplates = [];
  final _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _billsBox = Hive.box('bills_templates');
    _loadBillTemplates();
  }

  void _loadBillTemplates() {
    final List<Map<String, dynamic>> loadedTemplates = [];
    _billsBox.toMap().forEach((key, value) {
      if (value is Map && key is String) {
        var t = Map<String, dynamic>.from(value);
        t['id'] = key;
        loadedTemplates.add(t);
      }
    });
    loadedTemplates.sort((a, b) {
      final dayA = a['dayOfMonth'] as int? ?? 99; final dayB = b['dayOfMonth'] as int? ?? 99;
      final dC = dayA.compareTo(dayB);
      if (dC != 0) return dC;
      final tA = a['title'] as String? ?? ''; final tB = b['title'] as String? ?? '';
      return tA.toLowerCase().compareTo(tB.toLowerCase());
    });
    if (mounted) {
      setState(() { _billTemplates = loadedTemplates; });
    }
  }

  void _addOrEditBill({String? editId}) async {
    final bool isEditing = editId != null;
    Map<String, dynamic>? existingBill;
    if (isEditing) {
      final rawData = _billsBox.get(editId);
      if (rawData is Map) {
        existingBill = Map<String, dynamic>.from(rawData);
        existingBill['id'] = editId;
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao carregar conta.'), backgroundColor: Colors.red));
        return;
      }
    }
    final controllerTitle = TextEditingController(text: isEditing ? existingBill!['title'] as String? ?? '' : '');
    final controllerDay = TextEditingController(text: isEditing ? (existingBill!['dayOfMonth'] as int?)?.toString() ?? '' : '');
    final controllerNotes = TextEditingController(text: isEditing ? existingBill!['notes'] as String? ?? '' : '');
    if (!mounted) return;
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEditing ? 'Editar Modelo Conta' : 'Novo Modelo Conta'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: controllerTitle, decoration: const InputDecoration(labelText: 'Título *', hintText: "Ex: Aluguel"), maxLength: 50, textCapitalization: TextCapitalization.sentences),
          const SizedBox(height: 8),
          TextField(controller: controllerDay, decoration: const InputDecoration(labelText: 'Dia Venc./Ref. *', hintText: "Ex: 5"), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 2),
          const SizedBox(height: 8),
          TextField(controller: controllerNotes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2, maxLength: 100, textCapitalization: TextCapitalization.sentences),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () async {
            final title = controllerTitle.text.trim(); final dayString = controllerDay.text.trim(); final notes = controllerNotes.text.trim();
            if (title.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Título obrigatório.'), backgroundColor: Colors.orange[800]));
              return;
            }
            if (dayString.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Dia obrigatório.'), backgroundColor: Colors.orange[800]));
              return;
            }
            final dayOfMonth = int.tryParse(dayString);
            if (dayOfMonth == null || dayOfMonth < 1 || dayOfMonth > 31) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Dia inválido (1-31).'), backgroundColor: Colors.orange[800]));
              return;
            }
            final billData = {'title': title, 'dayOfMonth': dayOfMonth, 'notes': notes};
            try {
              if (isEditing) await _billsBox.put(editId!, billData);
              else await _billsBox.put(_uuid.v4(), billData);
              _loadBillTemplates();
              if (mounted) Navigator.pop(context, true);
            } catch (e) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red));
            }
          }, child: const Text('Salvar')),
        ],
      ),
    );
  }

  void _deleteBill(String billId) async {
    final billDataRaw = _billsBox.get(billId);
    String title = 'Conta';
    if (billDataRaw is Map) title = Map<String, dynamic>.from(billDataRaw)['title'] as String? ?? title;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Modelo Conta?'), content: Text('Excluir o modelo "$title"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _billsBox.delete(billId);
        _loadBillTemplates();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao excluir: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gerenciar Modelos de Conta'), actions: [IconButton(onPressed: () => _addOrEditBill(), icon: const Icon(Icons.add_circle_outline), tooltip: "Adicionar Modelo Conta")]),
      body: _billTemplates.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Nenhum modelo de conta mensal.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)))
          : ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 80, left: 8, right: 8),
        itemCount: _billTemplates.length,
        itemBuilder: (_, index) {
          final bill = _billTemplates[index];
          final billId = bill['id'] as String;
          final title = bill['title'] as String? ?? 'Sem Título';
          final dayOfMonth = bill['dayOfMonth'] as int? ?? 0;
          final notes = bill['notes'] as String? ?? '';
          return Card(child: ListTile(
            leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.3), child: Icon(Icons.receipt_long_outlined, color: Theme.of(context).colorScheme.primary)),
            title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
            subtitle: Text('Dia $dayOfMonth${notes.isNotEmpty ? " - $notes" : ""}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit_outlined, size: 22), color: Colors.white70, tooltip: 'Editar', onPressed: () => _addOrEditBill(editId: billId), constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8)),
              IconButton(icon: Icon(Icons.delete_outline, size: 22), color: Colors.redAccent.withOpacity(0.8), tooltip: 'Excluir', onPressed: () => _deleteBill(billId), constraints: const BoxConstraints(), padding: const EdgeInsets.symmetric(horizontal: 8)),
            ]),
          ));
        },
      ),
    );
  }
}

// --- Bills Page ---
class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  _BillsPageState createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  late Box _billsTemplatesBox;
  late Box _billsPaidStatusBox;
  List<Map<String, dynamic>> _billTemplates = [];
  Set<String> _paidBillMonthKeys = {};
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _billsTemplatesBox = Hive.box('bills_templates');
    _billsPaidStatusBox = Hive.box('bills_paid_status');
    _loadBillTemplates();
    _loadPaidStatusesForMonth(_focusedMonth);
  }

  void _loadBillTemplates() {
    final List<Map<String, dynamic>> loadedTemplates = [];
    _billsTemplatesBox.toMap().forEach((key, value) {
      if (value is Map && key is String) {
        var t = Map<String, dynamic>.from(value);
        t['id'] = key;
        loadedTemplates.add(t);
      }
    });
    loadedTemplates.sort((a, b) {
      final dayA = a['dayOfMonth'] as int? ?? 99; final dayB = b['dayOfMonth'] as int? ?? 99;
      final dC = dayA.compareTo(dayB);
      if (dC != 0) return dC;
      final tA = a['title'] as String? ?? ''; final tB = b['title'] as String? ?? '';
      return tA.toLowerCase().compareTo(tB.toLowerCase());
    });
    if (mounted) {
      setState(() { _billTemplates = loadedTemplates; });
    }
  }

  void _loadPaidStatusesForMonth(DateTime month) {
    final year = month.year;
    final monthPad = month.month.toString().padLeft(2, '0');
    final monthSuffix = "_${year}-${monthPad}";
    final Set<String> paidKeys = {};
    for (var key in _billsPaidStatusBox.keys) {
      if (key is String && key.endsWith(monthSuffix) && _billsPaidStatusBox.get(key) == true) {
        paidKeys.add(key);
      }
    }
    if (mounted) {
      setState(() { _paidBillMonthKeys = paidKeys; });
    }
  }

  String _getBillPaidStatusKey(String billId, DateTime month) {
    final year = month.year; final monthPad = month.month.toString().padLeft(2, '0');
    return "${billId}_${year}-${monthPad}";
  }

  bool _isBillPaid(String billId, DateTime month) {
    return _paidBillMonthKeys.contains(_getBillPaidStatusKey(billId, month));
  }

  void _toggleBillPaidStatus(String billId, DateTime month) async {
    final key = _getBillPaidStatusKey(billId, month);
    final currentlyPaid = _isBillPaid(billId, month);
    try {
      if (currentlyPaid) {
        await _billsPaidStatusBox.delete(key);
        if (mounted) setState(() { _paidBillMonthKeys.remove(key); });
      } else {
        await _billsPaidStatusBox.put(key, true);
        if (mounted) setState(() { _paidBillMonthKeys.add(key); });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao atualizar status da conta.'), backgroundColor: Colors.red));
    }
  }

  void _navigateToPreviousMonth() {
    if (mounted) {
      setState(() {
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
        _loadPaidStatusesForMonth(_focusedMonth);
      });
    }
  }

  void _navigateToNextMonth() {
    if (mounted) {
      setState(() {
        _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
        _loadPaidStatusesForMonth(_focusedMonth);
      });
    }
  }

  void _openBillManager() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const BillManagerPage()));
    if (mounted) {
      _loadBillTemplates();
      _loadPaidStatusesForMonth(_focusedMonth);
    }
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contas Mensais'),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: 'Gerenciar Modelos de Conta', onPressed: _openBillManager),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: _navigateToPreviousMonth, tooltip: 'Mês Anterior'),
            Text(localizations.formatMonthYear(_focusedMonth), style: Theme.of(context).textTheme.titleLarge),
            IconButton(icon: const Icon(Icons.chevron_right), onPressed: _navigateToNextMonth, tooltip: 'Próximo Mês'),
          ]),
        ),
        const Divider(),
        Expanded(
          child: _billTemplates.isEmpty
              ? Center(child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Nenhum modelo de conta mensal cadastrado.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                icon: const Icon(Icons.settings_outlined), label: const Text("Gerenciar Modelos"),
                onPressed: _openBillManager,
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              )
            ]),
          ))
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 20, left: 4, right: 4),
            itemCount: _billTemplates.length,
            itemBuilder: (context, index) {
              final bill = _billTemplates[index];
              final billId = bill['id'] as String;
              final title = bill['title'] as String? ?? 'Sem Título';
              final dayOfMonth = bill['dayOfMonth'] as int? ?? 0;
              final isPaid = _isBillPaid(billId, _focusedMonth);
              final notes = bill['notes'] as String? ?? '';

              bool isOverdue = false;
              Color titleColor = Colors.white;
              Color dayLabelColor = Theme.of(context).colorScheme.primary;
              Color dayBackgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.2);

              if (!isPaid) {
                final now = DateTime.now();
                final todayNormalized = DateTime.utc(now.year, now.month, now.day);
                DateTime billDueDateInFocusedMonth;
                try {
                  billDueDateInFocusedMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month, dayOfMonth);
                } catch (e) {
                  final lastDayOfMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
                  billDueDateInFocusedMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month, lastDayOfMonth);
                  print("Dia de vencimento ($dayOfMonth) inválido para o mês ${_focusedMonth.month}, usando o último dia: $lastDayOfMonth");
                }

                if (todayNormalized.isAfter(billDueDateInFocusedMonth)) {
                  isOverdue = true;
                  titleColor = Colors.redAccent;
                  dayLabelColor = Colors.redAccent;
                  dayBackgroundColor = Colors.redAccent.withOpacity(0.15);
                }
              } else {
                titleColor = Colors.grey[600]!;
                dayLabelColor = Colors.grey[600]!;
                dayBackgroundColor = Colors.grey.shade800;
              }

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: InkWell(
                  onTap: () => _toggleBillPaidStatus(billId, _focusedMonth),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                    child: Row(children: [
                      Checkbox(
                        value: isPaid,
                        onChanged: (bool? value) => _toggleBillPaidStatus(billId, _focusedMonth),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        activeColor: isOverdue && !isPaid ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                        checkColor: Colors.black,
                        side: isOverdue && !isPaid ? const BorderSide(color: Colors.redAccent) : const BorderSide(color: Colors.white54),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(
                            decoration: isPaid ? TextDecoration.lineThrough : TextDecoration.none,
                            color: titleColor,
                            fontSize: 17, fontWeight: FontWeight.w500
                        ), overflow: TextOverflow.ellipsis),
                        if (notes.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(notes, style: TextStyle(
                              fontSize: 13,
                              color: isPaid ? Colors.grey[700] : (isOverdue ? Colors.redAccent.withOpacity(0.8) : Colors.white70),
                              fontStyle: FontStyle.italic,
                            ), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                      ])),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: dayBackgroundColor,
                            borderRadius: BorderRadius.circular(6)),
                        child: Text("Dia $dayOfMonth", style: TextStyle(
                            color: dayLabelColor,
                            fontSize: 14, fontWeight: FontWeight.w500
                        )),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// --- Página de Informações (Sobre) ---
class InfoPage extends StatefulWidget {
  const InfoPage({super.key});

  @override
  _InfoPageState createState() => _InfoPageState();
}

enum UpdateStatus { checking, upToDate, available, error }

class _InfoPageState extends State<InfoPage> {
  String _appVersion = 'Carregando...';
  UpdateStatus _updateStatus = UpdateStatus.checking;
  UpdateInfo? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadVersionInfo();
    _runUpdateCheck();
  }

  Future<void> _loadVersionInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = 'v${packageInfo.version}+${packageInfo.buildNumber}';
      });
    }
  }

  Future<void> _runUpdateCheck() async {
    // Garante que o estado de 'checking' seja exibido
    if(mounted) {
      setState(() {
        _updateStatus = UpdateStatus.checking;
      });
    }

    try {
      final updateInfo = await updateService.checkForUpdate();
      if (mounted) {
        setState(() {
          if (updateInfo != null) {
            _updateStatus = UpdateStatus.available;
            _updateInfo = updateInfo;
          } else {
            _updateStatus = UpdateStatus.upToDate;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updateStatus = UpdateStatus.error;
        });
      }
    }
  }

  // Widget que constrói a mensagem de status da atualização
  Widget _buildUpdateStatusWidget() {
    switch (_updateStatus) {
      case UpdateStatus.checking:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Verificando atualizações...', style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      case UpdateStatus.upToDate:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 8),
            Text('Você está com a versão mais recente.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      case UpdateStatus.error:
        return GestureDetector(
          onTap: _runUpdateCheck, // Permite tentar novamente
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text('Erro ao verificar. Toque para tentar novamente.', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        );
      case UpdateStatus.available:
        return GestureDetector(
          onTap: () {
            if (_updateInfo != null) {
              updateService.showUpdateDialog(context, _updateInfo!);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.system_update_alt_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Nova atualização disponível! Toque para atualizar.',
                  style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sobre o Plantão Operacional'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20.0),
        children: <Widget>[
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              child: Icon(
                Icons.calendar_month_rounded,
                size: 50,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Center(
            child: Text(
              'Plantão Operacional',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Center(
            child: Text(
              _appVersion,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),

          // --- INÍCIO DA CORREÇÃO ---
          // A chamada para o widget de status estava faltando aqui.
          const SizedBox(height: 10),
          _buildUpdateStatusWidget(),
          const SizedBox(height: 10),
          // --- FIM DA CORREÇÃO ---

          const Divider(color: Colors.white24),
          const SizedBox(height: 10),

          Text(
            'Objetivo do Aplicativo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            'O Plantão Operacional foi criado para ser seu assistente pessoal, simplificando a organização de plantões, turnos de trabalho, compromissos e o controle de contas a pagar em uma interface visual e fácil de usar.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24),
          const SizedBox(height: 10),

          Text(
            'Desenvolvimento',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),

          const ListTile(
            leading: Icon(Icons.calendar_today_rounded),
            title: Text('Data da Criação'),
            subtitle: Text('Junho de 2025'),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Contato do Desenvolvedor'),
            subtitle: const Text('davidmp2015@gmail.com'),
            onTap: () => launchURL('mailto:davidmp2015@gmail.com?subject=Contato sobre o App Plantão Operacional', context: context),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Código Fonte (GitHub)'),
            subtitle: const Text('github.com/davidmp24/Plantao-Operacional'),
            onTap: () => launchURL('https://github.com/davidmp24/Plantao-Operacional', context: context),
          ),
          ListTile(
            leading: SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: Text(
                  'X',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).iconTheme.color,
                  ),
                ),
              ),
            ),
            title: const Text('X (antigo Twitter)'),
            subtitle: const Text('@DavidMPrado'),
            onTap: () => launchURL('https://x.com/DavidMPrado', context: context),
          ),
        ],
      ),
    );
  }
}