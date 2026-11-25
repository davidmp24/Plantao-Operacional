import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import '../services/schedule_service.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ScheduleGeneratorScreen extends StatefulWidget {
  const ScheduleGeneratorScreen({super.key});
  @override
  State<ScheduleGeneratorScreen> createState() => _ScheduleGeneratorScreenState();
}

class _ScheduleGeneratorScreenState extends State<ScheduleGeneratorScreen> {
  ScheduleModel _selectedModel = ScheduleModel.misto_dia_noite_folga;
  DateTime _startDate = DateTime.now();
  int _months = 3;
  bool _isGenerating = false;
  double _progress = 0;
  List<MapEntry<DateTime, TurnSlot>>? _preview;

  static const _modelLabels = {
    ScheduleModel.misto_dia_noite_folga: 'Misto Dia/Noite — D, N, F, F (12h36h)',
    ScheduleModel.cinco_por_dois_fixo: '5x2 Fixo — Seg-Sex + 2 folgas',
    ScheduleModel.cinco_por_dois_rotativo: '5x2 Rotativo — Turnos Manhã/Tarde/Noite',
  };

  static const _modelDescriptions = {
    ScheduleModel.misto_dia_noite_folga: 'Ciclo de 4: Dia (07-19) → Noite (19-07) → Folga → Folga → repete',
    ScheduleModel.cinco_por_dois_fixo: 'Seg a Sex trabalha, Sab e Dom folga. Turno fixo.',
    ScheduleModel.cinco_por_dois_rotativo: 'Seg-Ter / Qua-Qui / Sex-Sab nos turnos Manhã→Tarde→Noite rotativos. Dom folga.',
  };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    if (!auth.isSignedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Gerador de Escala')),
        body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.lock_person_outlined, size: 72, color: Colors.grey.withOpacity(0.4)),
          const SizedBox(height: 20),
          Text('Recurso PRO', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text('Faça login para gerar escalas automáticas e publicar no Google Calendar.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 28),
          ElevatedButton.icon(icon: const Icon(Icons.login_rounded), label: const Text('Entrar com Google'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10A37F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () => context.read<AuthService>().signIn()),
        ]))),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Gerador de Escala')),
      body: _isGenerating
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(value: _progress, color: const Color(0xFF10A37F)),
              const SizedBox(height: 20),
              Text('Publicando... ${(_progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text('${(_progress * (_preview?.length ?? 0)).toInt()} de ${_preview?.length ?? 0} eventos', style: TextStyle(color: Colors.grey[500])),
            ]))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionTitle(icon: Icons.view_agenda_outlined, title: 'Modelo de Escala'),
                const SizedBox(height: 8),
                ...ScheduleModel.values.map((model) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: RadioListTile<ScheduleModel>(
                    value: model, groupValue: _selectedModel,
                    onChanged: (v) => setState(() { _selectedModel = v!; _preview = null; }),
                    title: Text(_modelLabels[model]!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(_modelDescriptions[model]!, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                    activeColor: const Color(0xFF10A37F),
                  ),
                )),
                const SizedBox(height: 16),
                _SectionTitle(icon: Icons.settings_outlined, title: 'Configuração'),
                const SizedBox(height: 8),
                Card(child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Data de Início'),
                    subtitle: Text(DateFormat("dd 'de' MMMM 'de' yyyy (EEEE)", 'pt_BR').format(_startDate), style: const TextStyle(fontWeight: FontWeight.w500)),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: _pickStartDate,
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(children: [
                      const Icon(Icons.date_range_outlined, size: 24, color: Colors.white70),
                      const SizedBox(width: 16),
                      const Text('Período:'),
                      const SizedBox(width: 8),
                      Expanded(child: Slider(
                        value: _months.toDouble(), min: 1, max: 12, divisions: 11,
                        label: '$_months ${_months == 1 ? "mês" : "meses"}',
                        activeColor: const Color(0xFF10A37F),
                        onChanged: (v) => setState(() { _months = v.toInt(); _preview = null; }),
                      )),
                      Text('$_months ${_months == 1 ? "mês" : "meses"}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ]),
                  ),
                ])),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Visualizar Preview'),
                  onPressed: _generatePreview,
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF10A37F), side: const BorderSide(color: Color(0xFF10A37F)), padding: const EdgeInsets.symmetric(vertical: 14)),
                )),
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  _SectionTitle(icon: Icons.list_alt_rounded, title: 'Preview (${_preview!.length} dias)'),
                  const SizedBox(height: 8),
                  _buildPreviewList(),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: Text('Salvar ${_preview!.length} Eventos na Agenda'),
                    onPressed: _publishToCalendar,
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10A37F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  )),
                ],
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(context: context, initialDate: _startDate, firstDate: DateTime(2024), lastDate: DateTime(2030), locale: const Locale('pt', 'BR'));
    if (picked != null) setState(() => _startDate = picked);
  }

  void _generatePreview() {
    final auth = context.read<AuthService>();
    final service = ScheduleService(auth);
    final preview = service.generateSchedule(startDate: _startDate, model: _selectedModel, months: _months);
    setState(() => _preview = preview);
  }

  Future<void> _publishToCalendar() async {
    if (_preview == null) return;
    final confirm = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Salvar Escala?'),
      content: Text('Serão criados ${_preview!.length} eventos na sua agenda local.\n\nVocê poderá sincronizar com o Google Agenda posteriormente.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar'))],
    ));
    if (confirm != true) return;
    setState(() { _isGenerating = true; _progress = 0; });
    final box = Hive.box('commitments');
    
    int success = 0;
    int errors = 0;
    
    for (int i = 0; i < _preview!.length; i++) {
      final entry = _preview![i];
      setState(() => _progress = i / _preview!.length);
      try {
        final slot = entry.value;
        final date = entry.key;
        
        final dateKey = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        List<dynamic> existing = List<dynamic>.from(box.get(dateKey, defaultValue: []));
        
        final colorValue = _slotColor(slot).value;
        final hourStr = slot.type == TurnType.folga 
          ? '' 
          : '${slot.start.hour.toString().padLeft(2, '0')}:${slot.start.minute.toString().padLeft(2, '0')} → ${slot.end.hour.toString().padLeft(2, '0')}:${slot.end.minute.toString().padLeft(2, '0')}';
          
        existing.add({
          'title': slot.label,
          'color': colorValue,
          'hour': hourStr,
          'notes': 'Gerado automaticamente pelo Plantão Operacional PRO',
        });
        
        await box.put(dateKey, existing);
        success++;
      } catch(e) {
        errors++;
      }
    }
    
    if (mounted) {
      setState(() => _isGenerating = false);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Escala Salva!'),
        content: Text('✅ $success eventos criados localmente.${errors > 0 ? "\n⚠️ $errors com erro." : ""}'),
        actions: [TextButton(onPressed: () { Navigator.pop(ctx); }, child: const Text('Fechar'))],
      ));
    }
  }

  Widget _buildPreviewList() {
    final items = _preview!.take(30).toList();
    final hasMore = _preview!.length > 30;
    return Card(child: Column(children: [
      ...items.map((entry) {
        final date = entry.key; final slot = entry.value;
        final color = _slotColor(slot);
        final isWork = slot.type == TurnType.trabalho;
        return ListTile(dense: true,
          leading: Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          title: Text(DateFormat('EEE, dd/MM', 'pt_BR').format(date), style: const TextStyle(fontSize: 13)),
          subtitle: Text(slot.label, style: TextStyle(fontSize: 11, color: isWork ? color : Colors.grey[500])),
          trailing: isWork ? Text('${slot.start.hour.toString().padLeft(2, '0')}:00 → ${slot.end.hour.toString().padLeft(2, '0')}:00${slot.overnight ? '+1' : ''}', style: TextStyle(fontSize: 11, color: color)) : null,
        );
      }),
      if (hasMore) Padding(padding: const EdgeInsets.all(8), child: Text('... e mais ${_preview!.length - 30} dias', style: TextStyle(color: Colors.grey[500], fontSize: 12))),
    ]));
  }

  Color _slotColor(TurnSlot slot) {
    if (slot.type == TurnType.folga) return Colors.green;
    switch (slot.colorId) {
      case '11': return const Color(0xFFE53935);
      case '9':  return const Color(0xFF3949AB);
      case '5':  return const Color(0xFFF57F17);
      default:   return const Color(0xFF10A37F);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 18, color: const Color(0xFF10A37F)),
    const SizedBox(width: 8),
    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF10A37F))),
  ]);
}
