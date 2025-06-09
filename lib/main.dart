import 'dart:convert'; // Para JSON encode/decode
import 'dart:io'; // Para File IO
import 'dart:typed_data'; // Para Uint8List
import 'package:collection/collection.dart'; // Para SetEquality
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Para input formatters
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:ui' show Shadow;
import 'package:uuid/uuid.dart'; // Para IDs de contas
import 'package:file_picker/file_picker.dart'; // Para Backup/Restore

// Importação condicional para separar o código da web do código nativo.
import 'backup_helper_mobile.dart' if (dart.library.html) 'backup_helper_web.dart';

import 'package:intl/intl.dart'; // Para formatar data no nome do arquivo
import 'package:http/http.dart' as http; // Para buscar feriados da API (ainda necessário)
import 'package:flutter/foundation.dart' show kIsWeb;

// Imports do Google Drive REMOVIDOS
// import 'package:google_sign_in/google_sign_in.dart';
// import 'package:googleapis_auth/auth_io.dart' as auth;
// import 'package:googleapis/drive/v3.dart' as drive;

// --- Enum para Modo de Seleção ---
enum SelectionMode { single, multi }

// --- Função Utilitária para Chave de Data (Baseada em UTC) ---
String getDateKey(DateTime date) {
  final utcDate = DateTime.utc(date.year, date.month, date.day);
  return '${utcDate.year.toString().padLeft(4, '0')}-${utcDate.month.toString().padLeft(2, '0')}-${utcDate.day.toString().padLeft(2, '0')}';
}

// --- Função Utilitária para Normalizar Data (Remove hora, usa UTC) ---
DateTime normalizeDate(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
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

  @override
  String toString() {
    return 'Holiday(date: $date, localName: $localName, global: $global)';
  }
}


// --- Main Function & App Initialization ---
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('commitments');
  await Hive.openBox('templates');
  await Hive.openBox('bills_templates');
  await Hive.openBox('bills_paid_status');
  await initializeDateFormatting('pt_BR', null);
  runApp(MyApp());
}

// --- Root Application Widget ---
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Plantão Operacional',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [ const Locale('pt', 'BR'), ],
      locale: const Locale('pt', 'BR'),
      theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Color(0xFF1E1E1E),
          primaryColor: Color(0xFF10A37F),
          appBarTheme: AppBarTheme( backgroundColor: Color(0xFF262626), foregroundColor: Colors.white,),
          textTheme: TextTheme(
            bodyMedium: TextStyle(fontSize: 15, color: Colors.white70),
            bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: Colors.white),
            headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
          ),
          colorScheme: ColorScheme.dark(
            primary: Color(0xFF10A37F), secondary: Color(0xFF10A37F), surface: Color(0xFF2C2C2C),
            background: Color(0xFF1E1E1E), onPrimary: Colors.white, onSecondary: Colors.white,
            onSurface: Colors.white, onBackground: Colors.white, error: Colors.redAccent, onError: Colors.white,
          ),
          floatingActionButtonTheme: FloatingActionButtonThemeData( backgroundColor: Color(0xFF10A37F), foregroundColor: Colors.white,),
          popupMenuTheme: PopupMenuThemeData( color: Color(0xFF2C2C2C), textStyle: TextStyle(color: Colors.white),),
          dialogTheme: DialogThemeData(
            backgroundColor: Color(0xFF2C2C2C),
            titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            contentTextStyle: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          textButtonTheme: TextButtonThemeData( style: TextButton.styleFrom(foregroundColor: Color(0xFF10A37F)),),
          cardTheme: CardThemeData(
            color: Color(0xFF2C2C2C), elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[700]!),),
            enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey[700]!),),
            focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Color(0xFF10A37F)),),
            labelStyle: TextStyle(color: Colors.grey[400]), hintStyle: TextStyle(color: Colors.grey[600]),
          ),
          iconTheme: IconThemeData( color: Colors.white70, ),
          checkboxTheme: CheckboxThemeData(
            fillColor: MaterialStateProperty.resolveWith((states) { if (states.contains(MaterialState.selected)) { return Color(0xFF10A37F); } return Colors.grey[800]; }),
            checkColor: MaterialStateProperty.all(Colors.black), side: BorderSide(color: Colors.white54),
          ),
          dividerTheme: DividerThemeData( color: Colors.white24, thickness: 1, space: 1,)
      ),
      home: WeeklyViewPage(),
    );
  }
}

// --- Weekly View Page Widget (Página Principal) ---
class WeeklyViewPage extends StatefulWidget {
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

  bool _isPerformingBackupRestore = false;
  bool _hasPendingBills = false;
  AnimationController? _pendingBillsAnimationController;
  Animation<Offset>? _pendingBillsOffsetAnimation;
  final String _versionCheckUrl = "https://gist.githubusercontent.com/davidmp24/3bfcf2fd1b620b6a4b8b4994dcc4ee1c/raw/b75de313b5fc08e48503b44bb1a5e70a1be28378/gistfile1.txt";

  // Variáveis do Google Drive REMOVIDAS
  // static const String _googleDriveWebClientId = "...";
  // GoogleSignIn _googleSignIn = GoogleSignIn(...);
  // GoogleSignInAccount? _currentUser;
  // auth.AuthClient? _googleDriveAuthClient;

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

    // Lógica de inicialização e listeners do GoogleSignIn REMOVIDOS
    // _googleSignIn.onCurrentUserChanged.listen(...);
    // _googleSignIn.signInSilently().catchError(...);

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
    super.dispose();
  }

  // Funções do Google Drive REMOVIDAS:
  // _getHttpClient()
  // _handleGoogleSignIn()
  // _handleGoogleSignOut()
  // _performBackupGoogleDrive()
  // _performRestoreGoogleDrive()

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
    print("Dados iniciais da WeeklyView carregados/recarregados.");
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
    final countryCode = 'BR';
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
    if (isDayOff) {
      existing.removeWhere((e) => e is Map && e['title'] == 'Folga');
    } else {
      existing.add({'title': 'Folga', 'color': Colors.grey.value, 'hour': '', 'notes': ''});
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
        content: Text('Deseja MARCAR ou DESMARCAR folga?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('DESMARCAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('MARCAR')),
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
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BillsPage()));
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
        title: Text('Remover Compromisso?'), content: Text('Deseja remover "$titleToRemove"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Remover', style: TextStyle(color: Colors.redAccent))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      List<dynamic> actualCommitments = List<dynamic>.from(_allCommitments[dateKey] ?? []);
      actualCommitments.removeWhere((hiveItem) =>
      hiveItem is Map && hiveItem['title'] == item['title'] && hiveItem['hour'] == item['hour'] &&
          hiveItem['notes'] == item['notes'] && hiveItem['color'] == item['color']);
      await _commitmentsBox.put(dateKey, actualCommitments);
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download do backup iniciado!'), duration: Duration(seconds: 4)));
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
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup local salvo em: $outputFileSavePath'), duration: Duration(seconds: 4)));
        } else {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Backup local cancelado.')));
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
        title: Text('Restaurar Backup Local?'),
        content: Text('ATENÇÃO: Dados atuais serão substituídos. Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Restaurar', style: TextStyle(color: Colors.orange))),
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
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dados locais restaurados!')));
        } else {
          throw Exception("Arquivo de backup inválido.");
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Restauração local cancelada.')));
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao encontrar compromisso para editar.'), backgroundColor: Colors.red));
      return;
    }

    final Map<String, dynamic> commitmentMap = Map<String, dynamic>.from(actualCommitments[hiveIndex]);
    final notesController = TextEditingController(text: commitmentMap['notes'] as String? ?? '');

    final bool? noteSaved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar Notas - ${commitmentMap['title'] ?? 'Compromisso'}'),
        content: TextField(controller: notesController, decoration: InputDecoration(hintText: 'Adicione suas notas aqui...', border: OutlineInputBorder()), maxLines: 4, textCapitalization: TextCapitalization.sentences, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          TextButton(onPressed: () { Navigator.pop(ctx, true); }, child: Text('Salvar')),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar notas.'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _buildCellContent(DateTime day, DateTime focusedDay, {required bool isToday, required bool isSelected, required bool isOutside}) {
    final normalizedDay = normalizeDate(day);
    final commitments = _getCommitmentsForDay(normalizedDay).where((c) => c is Map && c['isHoliday'] != true).toList();
    final bool isHoliday = _holidayDates.contains(normalizedDay);
    final List<Color> uniqueCommitmentColors = commitments
        .where((c) => c['title'] != 'Folga')
        .map((c) => (c['color'] is int) ? Color(c['color']) : null)
        .whereType<Color>().toSet().take(4).toList();
    final bool isMultiSelected = _selectionMode == SelectionMode.multi && _multiSelectedDays.contains(normalizedDay);

    TextStyle textStyle = TextStyle(fontSize: 15, color: isOutside ? Colors.grey[700] : Colors.white);
    FontWeight fontWeight = (!isOutside && (isSelected || isToday || isHoliday)) ? FontWeight.bold : FontWeight.normal;

    Widget cellInnerContent;
    if (uniqueCommitmentColors.isNotEmpty && !isOutside) {
      cellInnerContent = Stack(alignment: Alignment.center, children: [
        Row(children: uniqueCommitmentColors.map((color) => Expanded(child: Container(color: color))).toList()),
        Text('${day.day}', style: textStyle.copyWith(fontWeight: fontWeight, color: Colors.white, shadows: [Shadow(blurRadius: 1.5, color: Colors.black.withOpacity(0.9), offset: Offset(0,0))])),
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
        title: Text(_selectionMode == SelectionMode.multi ? 'Seleção Múltipla (${_multiSelectedDays.length})' : 'Agenda Mensal'),
        actions: [
          IconButton(
            icon: Icon(Icons.crop_square), tooltip: 'Seleção Única',
            color: _selectionMode == SelectionMode.single ? Theme.of(context).colorScheme.primary : Colors.white54,
            onPressed: () {
              if (_selectionMode != SelectionMode.single) {
                setState(() {
                  _selectionMode = SelectionMode.single; _multiSelectedDays.clear();
                  _selectedDate = normalizeDate(_focusedDay); _updateSelectedCommitments();
                });
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.select_all), tooltip: 'Seleção Múltipla',
            color: _selectionMode == SelectionMode.multi ? Theme.of(context).colorScheme.primary : Colors.white54,
            onPressed: () {
              if (_selectionMode != SelectionMode.multi) {
                setState(() {
                  _selectionMode = SelectionMode.multi; _multiSelectedDays.clear();
                  _multiSelectedDays.add(_selectedDate);
                });
              }
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
                }
              },
              eventLoader: (day) {
                final normDay = normalizeDate(day);
                return [..._getCommitmentsForDay(normDay), ..._getHolidaysForDay(normDay)];
              },
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              calendarStyle: CalendarStyle(
                outsideDaysVisible: true, defaultTextStyle: TextStyle(fontSize: 15, color: Colors.white),
                weekendTextStyle: TextStyle(fontSize: 15, color: Colors.white70),
                outsideTextStyle: TextStyle(fontSize: 14, color: Colors.grey[700]),
                selectedDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.7), shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withOpacity(0.4), shape: BoxShape.circle),
                selectedTextStyle: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                todayTextStyle: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              headerStyle: HeaderStyle(
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
                      padding: EdgeInsets.all(2), decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.6)),
                      constraints: BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text('$userEventsCount', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
                  padding: EdgeInsets.only(bottom: 80, left: 8, right: 8),
                  itemCount: displayItems.length,
                  itemBuilder: (_, index) {
                    final item = displayItems[index];
                    if (item is Map) {
                      final isHolidayItem = item['isHoliday'] == true;
                      final title = item['title'] as String? ?? 'Sem Título';
                      final notes = item['notes'] as String? ?? '';
                      final hour = item['hour'] as String? ?? '';
                      final isDayOff = !isHolidayItem && title == 'Folga';
                      Color itemColor = Colors.transparent;
                      Widget? leadingIcon;

                      if (isHolidayItem) {
                        itemColor = Colors.amber[800]!;
                        leadingIcon = Icon(Icons.celebration_rounded, color: Colors.white, size: 22);
                      } else if (isDayOff) {
                        itemColor = Color(item['color'] as int? ?? Colors.grey.value);
                        leadingIcon = Icon(Icons.free_breakfast_outlined, size: 20, color: Colors.white70);
                      } else {
                        itemColor = Color(item['color'] as int? ?? Theme.of(context).colorScheme.primary.value);
                      }
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: itemColor, child: leadingIcon),
                          title: Text(
                            isHolidayItem ? "$title" : (hour.isNotEmpty ? '[$hour] $title' : title),
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              decoration: isDayOff ? TextDecoration.lineThrough : TextDecoration.none,
                              color: isDayOff ? Colors.grey[500] : (isHolidayItem ? Colors.amber[200] : Colors.white),
                              fontStyle: isHolidayItem ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                          subtitle: notes.isNotEmpty && !isHolidayItem
                              ? Text(notes, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isDayOff ? Colors.grey[600] : Colors.white70))
                              : null,
                          trailing: (!isHolidayItem && _selectionMode == SelectionMode.single)
                              ? Row(mainAxisSize: MainAxisSize.min, children: [
                            if (!isDayOff)
                              IconButton(
                                  icon: Icon(Icons.note_alt_outlined, size: 20),
                                  tooltip: 'Editar Notas',
                                  color: Colors.white54,
                                  onPressed: () => _editCommitmentNotes(index),
                                  constraints: BoxConstraints(),
                                  padding: EdgeInsets.symmetric(horizontal: 4)),
                            IconButton(
                                icon: Icon(Icons.delete_outline, color: Colors.redAccent.withOpacity(0.7)),
                                tooltip: "Remover",
                                onPressed: () => _confirmRemove(index),
                                constraints: BoxConstraints(),
                                padding: EdgeInsets.symmetric(horizontal: 4)),
                          ])
                              : null,
                        ),
                      );
                    } else {
                      return ListTile(title: Text("Inválido"));
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
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 5, offset: Offset(0, 2))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
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
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: _selectionMode == SelectionMode.multi ? 'Ações para Selecionados' : 'Adicionar/Gerenciar',
        child: PopupMenuButton<String>(
          icon: Icon(_selectionMode == SelectionMode.multi && _multiSelectedDays.isNotEmpty ? Icons.playlist_add_check : Icons.add, color: Colors.white),
          offset: Offset(0, -kToolbarHeight * 3.5), // Ajustado para não cobrir tanto
          color: Theme.of(context).popupMenuTheme.color,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          itemBuilder: (_) {
            List<PopupMenuEntry<String>> items = [];
            if (_selectionMode == SelectionMode.multi) {
              items.add(PopupMenuItem(value: 'add_multi', enabled: _multiSelectedDays.isNotEmpty, child: ListTile(leading: Icon(Icons.add_task, color: _multiSelectedDays.isNotEmpty ? Theme.of(context).iconTheme.color : Colors.grey), title: Text('Adicionar aos ${(_multiSelectedDays.length)} dias'))));
              items.add(PopupMenuItem(value: 'folga_multi', enabled: _multiSelectedDays.isNotEmpty, child: ListTile(leading: Icon(Icons.free_breakfast_outlined, color: _multiSelectedDays.isNotEmpty ? Theme.of(context).iconTheme.color : Colors.grey), title: Text('Folga nos ${(_multiSelectedDays.length)} dias'))));
            } else {
              items.add(PopupMenuItem(value: 'adicionar_single', child: ListTile(leading: Icon(Icons.add_task, color: Theme.of(context).iconTheme.color), title: Text('Adicionar Compromisso'))));
              items.add(PopupMenuItem(value: 'folga_single', child: ListTile(leading: Icon(Icons.free_breakfast_outlined, color: Theme.of(context).iconTheme.color), title: Text('Marcar/Desmarcar Folga'))));
            }
            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(value: 'ver_contas', child: ListTile(leading: Icon(Icons.request_quote_outlined, color: Theme.of(context).iconTheme.color), title: Text('Ver Contas Mensais'))));

            // Itens do Google Drive REMOVIDOS daqui
            // if (_currentUser == null) { ... } else { ... }

            items.add(const PopupMenuDivider());
            items.add(PopupMenuItem(value: 'backup_local', child: ListTile(leading: Icon(Icons.save_alt, color: Theme.of(context).iconTheme.color), title: Text('Backup Local'))));
            items.add(PopupMenuItem(value: 'restore_local', child: ListTile(leading: Icon(Icons.restore_from_trash_outlined, color: Theme.of(context).iconTheme.color), title: Text('Restaurar Local'))));
            return items;
          },
          onSelected: (value) async {
            if (value == 'ver_contas') {
              _openBillsPage();
              // Cases do Google Drive REMOVIDOS
              // } else if (value == 'connect_google_drive') { ...
              // } else if (value == 'disconnect_google_drive') { ...
              // } else if (value == 'backup_google_drive') { ...
              // } else if (value == 'restore_google_drive') { ...
            } else if (value == 'backup_local') {
              _performBackupLocal();
            } else if (value == 'restore_local') {
              _performRestoreLocal();
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
            }
          },
        ),
      ),
    );
  }
}

// --- Template Selector Page ---
class TemplateSelectorPage extends StatefulWidget {
  final DateTime? selectedDate;
  TemplateSelectorPage({this.selectedDate});

  @override
  _TemplateSelectorPageState createState() => _TemplateSelectorPageState();
}

class _TemplateSelectorPageState extends State<TemplateSelectorPage> {
  late Box _templatesBox;
  late Box _commitmentsBox;
  List<Map<String, dynamic>> templates = [];

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
      dayCommitments.add(Map<String, dynamic>.from(template));
      await _commitmentsBox.put(dateKey, dayCommitments);
      if (mounted) Navigator.pop(context, true);
    } else {
      if (mounted) Navigator.pop(context, template);
    }
  }

  void _navigateToTemplateManager() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => TemplateManagerPage()));
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
            icon: Icon(Icons.settings_outlined),
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
                SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: Icon(Icons.add_circle_outline),
                  label: Text("Criar Novo Modelo"),
                  onPressed: _navigateToTemplateManager,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
          ))
          : ListView.builder(
        padding: EdgeInsets.all(8),
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
      ),
    );
  }
}

// --- Template Manager Page ---
class TemplateManagerPage extends StatefulWidget {
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar modelo.'), backgroundColor: Colors.red));
        return;
      }
    }
    Color selectedColor = isEditing ? Color(existingTemplate!['color'] as int? ?? Colors.blue.value) : Color(0xFF10A37F);
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
              TextField(controller: controllerTitle, decoration: InputDecoration(labelText: 'Título *', hintText: "Ex: Plantão"), maxLength: 50, textCapitalization: TextCapitalization.sentences),
              SizedBox(height: 8),
              TextField(controller: controllerHour, decoration: InputDecoration(labelText: 'Horário', hintText: "Ex: 08:00 - 18:00"), maxLength: 30),
              SizedBox(height: 8),
              TextField(controller: controllerNotes, decoration: InputDecoration(labelText: 'Notas', hintText: "Ex: Levar café"), maxLines: 3, maxLength: 100, textCapitalization: TextCapitalization.sentences),
              SizedBox(height: 15),
              Text("Cor:", style: Theme.of(context).textTheme.titleMedium), SizedBox(height: 10),
              BlockPicker(pickerColor: selectedColor, onColorChanged: (color) => selectedColor = color, availableColors: [
                Colors.red, Colors.pink, Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
                Colors.teal, Colors.green, Colors.lightGreen, Colors.lime, Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
                Colors.brown, Colors.grey, Colors.blueGrey, Color(0xFF10A37F)
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
            TextButton(onPressed: () async {
              if (controllerTitle.text.trim().isEmpty) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Título é obrigatório.'), backgroundColor: Colors.orange[800]));
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
            }, child: Text('Salvar')),
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
          title: Text('Excluir Modelo?'), content: Text('Excluir o modelo "$title"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: Colors.redAccent))),
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
        appBar: AppBar(title: Text('Gerenciar Modelos Comp.'), actions: [IconButton(onPressed: () => _addOrEditTemplate(), icon: Icon(Icons.add_circle_outline), tooltip: "Adicionar Modelo")]),
        body: _templateKeys.isEmpty
            ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Nenhum modelo criado.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)))
            : ListView.builder(
            padding: EdgeInsets.only(top: 8, bottom: 80, left: 8, right: 8),
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
                    IconButton(icon: Icon(Icons.edit_outlined, size: 22), color: Colors.white70, tooltip: 'Editar', onPressed: () => _addOrEditTemplate(editIndex: index), constraints: BoxConstraints(), padding: EdgeInsets.symmetric(horizontal: 8)),
                    IconButton(icon: Icon(Icons.delete_outline, size: 22), color: Colors.redAccent.withOpacity(0.8), tooltip: 'Excluir', onPressed: () => _deleteTemplate(index), constraints: BoxConstraints(), padding: EdgeInsets.symmetric(horizontal: 8)),
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
  @override
  _BillManagerPageState createState() => _BillManagerPageState();
}

class _BillManagerPageState extends State<BillManagerPage> {
  late Box _billsBox;
  List<Map<String, dynamic>> _billTemplates = [];
  final _uuid = Uuid();

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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar conta.'), backgroundColor: Colors.red));
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
          TextField(controller: controllerTitle, decoration: InputDecoration(labelText: 'Título *', hintText: "Ex: Aluguel"), maxLength: 50, textCapitalization: TextCapitalization.sentences),
          SizedBox(height: 8),
          TextField(controller: controllerDay, decoration: InputDecoration(labelText: 'Dia Venc./Ref. *', hintText: "Ex: 5"), keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], maxLength: 2),
          SizedBox(height: 8),
          TextField(controller: controllerNotes, decoration: InputDecoration(labelText: 'Notas'), maxLines: 2, maxLength: 100, textCapitalization: TextCapitalization.sentences),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
          TextButton(onPressed: () async {
            final title = controllerTitle.text.trim(); final dayString = controllerDay.text.trim(); final notes = controllerNotes.text.trim();
            if (title.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Título obrigatório.'), backgroundColor: Colors.orange[800]));
              return;
            }
            if (dayString.isEmpty) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dia obrigatório.'), backgroundColor: Colors.orange[800]));
              return;
            }
            final dayOfMonth = int.tryParse(dayString);
            if (dayOfMonth == null || dayOfMonth < 1 || dayOfMonth > 31) {
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dia inválido (1-31).'), backgroundColor: Colors.orange[800]));
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
          }, child: Text('Salvar')),
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
        title: Text('Excluir Modelo Conta?'), content: Text('Excluir o modelo "$title"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Excluir', style: TextStyle(color: Colors.redAccent))),
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
      appBar: AppBar(title: Text('Gerenciar Modelos de Conta'), actions: [IconButton(onPressed: () => _addOrEditBill(), icon: Icon(Icons.add_circle_outline), tooltip: "Adicionar Modelo Conta")]),
      body: _billTemplates.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Nenhum modelo de conta mensal.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)))
          : ListView.builder(
        padding: EdgeInsets.only(top: 8, bottom: 80, left: 8, right: 8),
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
              IconButton(icon: Icon(Icons.edit_outlined, size: 22), color: Colors.white70, tooltip: 'Editar', onPressed: () => _addOrEditBill(editId: billId), constraints: BoxConstraints(), padding: EdgeInsets.symmetric(horizontal: 8)),
              IconButton(icon: Icon(Icons.delete_outline, size: 22), color: Colors.redAccent.withOpacity(0.8), tooltip: 'Excluir', onPressed: () => _deleteBill(billId), constraints: BoxConstraints(), padding: EdgeInsets.symmetric(horizontal: 8)),
            ]),
          ));
        },
      ),
    );
  }
}

// ... (outras importações do seu main.dart)
// Não precisa de novas importações específicas para esta mudança na BillsPage,
// mas certifique-se de que 'package:flutter/material.dart' está lá.

// --- Bills Page ---
class BillsPage extends StatefulWidget {
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao atualizar status da conta.'), backgroundColor: Colors.red));
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
    // Supondo que BillManagerPage está definida em outro lugar ou no mesmo arquivo.
    // Se BillManagerPage foi removida ou precisa ser ajustada, isso precisaria ser tratado.
    // Por agora, manteremos a chamada como está.
    await Navigator.push(context, MaterialPageRoute(builder: (_) => BillManagerPage()));
    if (mounted) {
      _loadBillTemplates(); // Recarrega os modelos de conta
      _loadPaidStatusesForMonth(_focusedMonth); // Recarrega os status de pagamento para o mês atual
    }
  }

  @override
  Widget build(BuildContext context) {
    final MaterialLocalizations localizations = MaterialLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Contas Mensais'),
        actions: [
          IconButton(icon: Icon(Icons.settings_outlined), tooltip: 'Gerenciar Modelos de Conta', onPressed: _openBillManager),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: Icon(Icons.chevron_left), onPressed: _navigateToPreviousMonth, tooltip: 'Mês Anterior'),
            Text(localizations.formatMonthYear(_focusedMonth), style: Theme.of(context).textTheme.titleLarge),
            IconButton(icon: Icon(Icons.chevron_right), onPressed: _navigateToNextMonth, tooltip: 'Próximo Mês'),
          ]),
        ),
        const Divider(),
        Expanded(
          child: _billTemplates.isEmpty
              ? Center(child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text("Nenhum modelo de conta mensal cadastrado.", textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
              SizedBox(height: 10),
              ElevatedButton.icon(
                icon: Icon(Icons.settings_outlined), label: Text("Gerenciar Modelos"),
                onPressed: _openBillManager,
                style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Theme.of(context).colorScheme.onPrimary),
              )
            ]),
          ))
              : ListView.builder(
            padding: EdgeInsets.only(bottom: 20, left: 4, right: 4),
            itemCount: _billTemplates.length,
            itemBuilder: (context, index) {
              final bill = _billTemplates[index];
              final billId = bill['id'] as String;
              final title = bill['title'] as String? ?? 'Sem Título';
              final dayOfMonth = bill['dayOfMonth'] as int? ?? 0;
              final isPaid = _isBillPaid(billId, _focusedMonth);
              final notes = bill['notes'] as String? ?? '';

              // --- INÍCIO DA LÓGICA DE DATA VENCIDA ---
              bool isOverdue = false;
              Color titleColor = Colors.white; // Cor padrão para pendente não vencida
              Color dayLabelColor = Theme.of(context).colorScheme.primary;
              Color dayBackgroundColor = Theme.of(context).colorScheme.primary.withOpacity(0.2);


              if (!isPaid) {
                // Só verificamos se está vencido se não estiver pago
                final now = DateTime.now();
                // Normaliza 'hoje' para comparar apenas ano, mês e dia (sem horas/minutos)
                final todayNormalized = DateTime.utc(now.year, now.month, now.day);
                // Cria a data de vencimento da conta para o mês focado
                DateTime billDueDateInFocusedMonth;
                try {
                  // Tenta criar a data. Pode falhar se dayOfMonth for > dias no mês (ex: Dia 31 em Fev)
                  billDueDateInFocusedMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month, dayOfMonth);
                } catch (e) {
                  // Se o dia for inválido para o mês (ex: dia 30 de Fev), considera o último dia do mês
                  // ou uma lógica que faça sentido para o seu app.
                  // Para simplificar, se der erro, não consideraremos vencido aqui,
                  // ou podemos pegar o último dia do _focusedMonth.
                  // Exemplo: pegar último dia do mês
                  final lastDayOfMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
                  billDueDateInFocusedMonth = DateTime.utc(_focusedMonth.year, _focusedMonth.month, lastDayOfMonth);
                  print("Dia de vencimento ($dayOfMonth) inválido para o mês ${_focusedMonth.month}, usando o último dia: $lastDayOfMonth");
                }


                if (todayNormalized.isAfter(billDueDateInFocusedMonth)) {
                  isOverdue = true;
                  titleColor = Colors.redAccent; // Cor para vencido e não pago
                  dayLabelColor = Colors.redAccent;
                  dayBackgroundColor = Colors.redAccent.withOpacity(0.15);
                }
              } else { // Se estiver pago
                titleColor = Colors.grey[600]!;
                dayLabelColor = Colors.grey[600]!;
                dayBackgroundColor = Colors.grey.shade800;
              }
              // --- FIM DA LÓGICA DE DATA VENCIDA ---

              return Card(
                margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
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
                        // Muda a cor do checkbox se estiver vencido e não pago
                        activeColor: isOverdue ? Colors.redAccent : Theme.of(context).colorScheme.primary,
                        checkColor: isOverdue ? Colors.white : Colors.black, // Cor do "check"
                        side: isOverdue && !isPaid ? BorderSide(color: Colors.redAccent) : BorderSide(color: Colors.white54),

                      ),
                      SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(
                            decoration: isPaid ? TextDecoration.lineThrough : TextDecoration.none,
                            color: titleColor, // Aplicando a cor dinâmica
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
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: dayBackgroundColor, // Aplicando a cor de fundo dinâmica
                            borderRadius: BorderRadius.circular(6)),
                        child: Text("Dia $dayOfMonth", style: TextStyle(
                            color: dayLabelColor, // Aplicando a cor da label dinâmica
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
