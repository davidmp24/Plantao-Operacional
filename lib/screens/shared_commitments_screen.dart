import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/auth_service.dart';
import '../services/sharing_service.dart';

class SharedCommitmentsScreen extends StatefulWidget {
  const SharedCommitmentsScreen({super.key});
  @override
  State<SharedCommitmentsScreen> createState() => _SharedCommitmentsScreenState();
}

class _SharedCommitmentsScreenState extends State<SharedCommitmentsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sharing = context.watch<SharingService>();

    if (!auth.isSignedIn) return _loginPrompt(context);
    if (sharing.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Tabs: "Minha Agenda" + um tab por usuário seguido
    final tabs = <Widget>[
      const Tab(
        icon: Icon(Icons.person, size: 18),
        text: 'Minha Agenda',
      ),
      ...sharing.followedProfiles.map((p) => Tab(
        icon: const Icon(Icons.people_alt_outlined, size: 18),
        text: p.displayName.split(' ').first, // primeiro nome
      )),
    ];

    final safeIndex = _selectedTabIndex.clamp(0, tabs.length - 1);

    // Quem estamos visualizando?
    String? currentUid;
    UserProfile? currentProfile;
    if (safeIndex == 0) {
      currentUid = sharing.myProfile?.uid;
      currentProfile = null;
    } else {
      final idx = safeIndex - 1;
      if (idx < sharing.followedProfiles.length) {
        currentProfile = sharing.followedProfiles[idx];
        currentUid = currentProfile.uid;
      }
    }

    return DefaultTabController(
      length: tabs.length,
      initialIndex: safeIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agenda Compartilhada'),
          actions: [
            // Botão de adicionar seguido
            IconButton(
              icon: const Icon(Icons.person_add_alt_1_outlined),
              tooltip: 'Seguir usuário',
              onPressed: () => _showFollowDialog(sharing),
            ),
            // Botão do meu código
            IconButton(
              icon: const Icon(Icons.qr_code_2_outlined),
              tooltip: 'Meu Código',
              onPressed: () => _showMyCodeDialog(context, sharing),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            onTap: (i) => setState(() => _selectedTabIndex = i),
            tabs: tabs,
            indicatorColor: const Color(0xFF10A37F),
            labelColor: const Color(0xFF10A37F),
            unselectedLabelColor: Colors.white54,
          ),
        ),
        body: _buildCalendarView(context, sharing, auth, currentUid, currentProfile),
        floatingActionButton: safeIndex == 0
            ? FloatingActionButton.extended(
                onPressed: () => _showPublishDialog(sharing),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Publicar'),
                backgroundColor: const Color(0xFF10A37F),
                foregroundColor: Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildCalendarView(
    BuildContext context,
    SharingService sharing,
    AuthService auth,
    String? uid,
    UserProfile? profile,
  ) {
    final stream = uid != null
        ? sharing.getCommitmentsStream(uid, _focusedDay)
        : const Stream<List<SharedCommitment>>.empty();

    return StreamBuilder<List<SharedCommitment>>(
      stream: stream,
      builder: (context, snapshot) {
        final shared = snapshot.data ?? [];
        final Map<DateTime, List<dynamic>> byDay = {};

        for (final c in shared) {
          final day = DateTime(c.date.year, c.date.month, c.date.day);
          byDay.putIfAbsent(day, () => []).add(c);
        }

        // Se for minha agenda, também injeta compromissos locais do Hive
        if (profile == null) {
          final box = Hive.box('commitments');
          for (final key in box.keys) {
            final parts = key.toString().split('-');
            if (parts.length == 3) {
              try {
                final day = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
                final localList = List<dynamic>.from(box.get(key, defaultValue: []));
                for (final e in localList) {
                  if (e is Map) byDay.putIfAbsent(day, () => []).add(e);
                }
              } catch (_) {}
            }
          }
        }

        final selNorm = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
        final selCommitments = byDay[selNorm] ?? [];

        return Column(children: [
          // Header de quem estamos vendo
          if (profile != null)
            Container(
              color: const Color(0xFF10A37F).withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF10A37F),
                  child: Text(
                    profile.displayName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(profile.email, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ])),
                TextButton(
                  onPressed: () => _confirmUnfollow(context, sharing, profile),
                  child: const Text('Deixar de seguir', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ]),
            ),

          // Calendário
          Container(
            color: Theme.of(context).colorScheme.surface,
            child: TableCalendar<dynamic>(
              locale: 'pt_BR',
              firstDay: DateTime.utc(2000),
              lastDay: DateTime.utc(2100),
              focusedDay: _focusedDay,
              selectedDayPredicate: (d) => isSameDay(d, _selectedDay),
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              eventLoader: (d) => byDay[DateTime(d.year, d.month, d.day)] ?? [],
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
              onPageChanged: (foc) => setState(() => _focusedDay = foc),
              headerStyle: const HeaderStyle(
                titleCentered: true, formatButtonVisible: false,
                titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                leftChevronIcon: Icon(Icons.chevron_left, color: Colors.white),
                rightChevronIcon: Icon(Icons.chevron_right, color: Colors.white),
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(color: const Color(0xFF10A37F).withValues(alpha: 0.4), shape: BoxShape.circle),
                selectedDecoration: const BoxDecoration(color: Color(0xFF10A37F), shape: BoxShape.circle),
                outsideDaysVisible: false,
                markerDecoration: const BoxDecoration(color: Color(0xFF10A37F), shape: BoxShape.circle),
              ),
            ),
          ),

          // Cabeçalho do dia selecionado
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(_selectedDay),
                  style: Theme.of(context).textTheme.titleMedium),
              Text('${selCommitments.length} item(s)', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            ]),
          ),
          const Divider(height: 1),

          // Lista dos eventos do dia
          Expanded(
            child: selCommitments.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.event_available_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
                    const SizedBox(height: 10),
                    Text(
                      profile != null ? 'Nenhum evento publicado neste dia' : 'Nenhum evento neste dia',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                    if (profile == null)
                      Text('Toque em "Publicar" para compartilhar', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                    itemCount: selCommitments.length,
                    itemBuilder: (_, i) {
                      final item = selCommitments[i];
                      if (item is SharedCommitment) {
                        final isOwner = item.ownerUid == auth.userId;
                        return Card(child: ListTile(
                          leading: CircleAvatar(backgroundColor: Color(item.colorValue)),
                          title: Text(
                            item.hour.isNotEmpty ? '[${item.hour}] ${item.title}' : item.title,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (item.notes.isNotEmpty) Text(item.notes, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            Row(children: [
                              const Icon(Icons.person_outline, size: 12, color: Colors.white38),
                              const SizedBox(width: 4),
                              Text(
                                isOwner ? 'Eu' : item.ownerName,
                                style: const TextStyle(fontSize: 11, color: Colors.white38),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(color: const Color(0xFF10A37F).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                child: const Text('publicado', style: TextStyle(fontSize: 9, color: Color(0xFF10A37F))),
                              ),
                            ]),
                          ]),
                          trailing: isOwner ? IconButton(
                            tooltip: 'Remover publicação',
                            icon: Icon(Icons.delete_outline, color: Colors.redAccent.withValues(alpha: 0.7), size: 20),
                            onPressed: () => _confirmDelete(context, sharing, item),
                          ) : null,
                        ));
                      } else if (item is Map) {
                        // Evento local (Hive) – só aparece na aba "Minha Agenda"
                        final colorValue = item['color'] ?? const Color(0xFF10A37F).toARGB32();
                        final hourStr = item['hour'] ?? '';
                        final notesStr = item['notes'] ?? '';
                        return Card(child: ListTile(
                          leading: CircleAvatar(backgroundColor: Color(colorValue)),
                          title: Text(
                            hourStr.isNotEmpty ? '[$hourStr] ${item['title']}' : '${item['title']}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (notesStr.isNotEmpty) Text(notesStr, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            const Row(children: [
                              Icon(Icons.phone_android, size: 12, color: Colors.white38),
                              SizedBox(width: 4),
                              Text('local', style: TextStyle(fontSize: 11, color: Colors.white38)),
                            ]),
                          ]),
                        ));
                      }
                      return const SizedBox();
                    },
                  ),
          ),
        ]);
      },
    );
  }

  // ─── Dialogs ──────────────────────────────────────────────────────────────

  Widget _loginPrompt(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Agenda Compartilhada')),
    body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.lock_person_outlined, size: 72, color: Colors.grey.withValues(alpha: 0.4)),
      const SizedBox(height: 20),
      Text('Recurso PRO', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      Text('Faça login com Google para compartilhar sua agenda.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 28),
      ElevatedButton.icon(
        icon: const Icon(Icons.login_rounded),
        label: const Text('Entrar com Google'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10A37F), foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: () => context.read<AuthService>().signIn(),
      ),
    ]))),
  );

  void _showMyCodeDialog(BuildContext context, SharingService sharing) {
    final code = sharing.myProfile?.shareCode ?? '...';
    final name = sharing.myProfile?.displayName ?? '';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Meu Código de Compartilhamento'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Compartilhe este código com quem deseja ver sua agenda:', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 28),
          decoration: BoxDecoration(
            color: const Color(0xFF10A37F).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF10A37F), width: 1.5),
          ),
          child: Text(code, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 6, color: Color(0xFF10A37F))),
        ),
        const SizedBox(height: 8),
        Text(name, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
      ]),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copiar'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Código copiado!'), backgroundColor: Colors.green),
            );
          },
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
      ],
    ));
  }

  void _showFollowDialog(SharingService sharing) async {
    final ctrl = TextEditingController();
    try {
      final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Seguir Usuário'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Insira o código de 8 caracteres do usuário:', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              labelText: 'Código do usuário',
              hintText: 'Ex: A1B2C3D4',
              prefixIcon: Icon(Icons.person_search_outlined),
            ),
            autofocus: true,
            maxLength: 8,
            textCapitalization: TextCapitalization.characters,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Seguir')),
        ],
      ));

      if (ok == true && ctrl.text.trim().isNotEmpty && mounted) {
        final result = await sharing.followByCode(ctrl.text.trim());
        if (!mounted) return;
        if (result.success) {
          setState(() {}); // rebuild das tabs
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Agora você segue ${result.profile?.displayName ?? ''}!'),
            backgroundColor: Colors.green,
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(result.errorMsg ?? 'Erro desconhecido.'),
            backgroundColor: Colors.red,
          ));
        }
      }
    } finally {
      ctrl.dispose();
    }
  }

  void _showPublishDialog(SharingService sharing) async {
    final titleCtrl = TextEditingController();
    final hourCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    Color selectedColor = const Color(0xFF10A37F);
    try {
      final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Publicar em ${DateFormat("dd/MM", 'pt_BR').format(_selectedDay)}'),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Será visível para quem te segue.', style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const SizedBox(height: 10),
            TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Título *'), textCapitalization: TextCapitalization.sentences, maxLength: 50, autofocus: true),
            const SizedBox(height: 8),
            TextField(controller: hourCtrl, decoration: const InputDecoration(labelText: 'Horário', hintText: 'Ex: 07:00 - 19:00'), maxLength: 30),
            const SizedBox(height: 8),
            TextField(controller: notesCtrl, decoration: const InputDecoration(labelText: 'Observações'), maxLines: 2, maxLength: 100, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 12),
            Text('Cor:', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            BlockPicker(
              pickerColor: selectedColor,
              onColorChanged: (c) => setS(() => selectedColor = c),
              availableColors: const [
                Color(0xFF10A37F), Colors.red, Colors.blue, Colors.orange,
                Colors.purple, Colors.teal, Colors.pink, Colors.indigo, Colors.amber,
              ],
            ),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publicar')),
          ],
        ),
      ));

      if (ok == true && mounted) {
        if (titleCtrl.text.trim().isEmpty) return;
        final added = await sharing.publishCommitment(
          date: _selectedDay,
          title: titleCtrl.text.trim(),
          hour: hourCtrl.text.trim(),
          notes: notesCtrl.text.trim(),
          colorValue: selectedColor.toARGB32(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added ? 'Publicado com sucesso!' : 'Erro ao publicar.'),
          backgroundColor: added ? Colors.green : Colors.red,
        ));
      }
    } finally {
      titleCtrl.dispose();
      hourCtrl.dispose();
      notesCtrl.dispose();
    }
  }

  void _confirmUnfollow(BuildContext context, SharingService sharing, UserProfile profile) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Deixar de seguir?'),
      content: Text('Você não verá mais a agenda de ${profile.displayName}.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
    if (confirm == true) {
      await sharing.unfollow(profile.uid);
      setState(() {});
    }
  }

  void _confirmDelete(BuildContext context, SharingService sharing, SharedCommitment c) async {
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Remover publicação?'),
      content: Text('Remover "${c.title}"?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover', style: TextStyle(color: Colors.redAccent))),
      ],
    ));
    if (confirm == true) await sharing.deleteMyCommitment(c.id);
  }
}
