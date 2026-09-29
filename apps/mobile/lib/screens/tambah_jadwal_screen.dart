import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/commitment.dart';
import '../models/enums.dart';
import '../models/recurrence_rule.dart';
import '../theme/app_theme.dart';
import '../viewmodels/jadwal_view_model.dart';

enum _PolaJadwal { rutin, sekali }

class TambahJadwalScreen extends StatefulWidget {
  const TambahJadwalScreen({super.key, this.onBack, this.onSave, this.commitment, this.recurrenceRule});
  final VoidCallback? onBack;
  final VoidCallback? onSave;
  final Commitment? commitment;
  final RecurrenceRule? recurrenceRule;
  bool get isEditing => commitment != null;
  @override
  State<TambahJadwalScreen> createState() => _TambahJadwalScreenState();
}

class _TambahJadwalScreenState extends State<TambahJadwalScreen> {
  final _titleCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  _PolaJadwal _pola = _PolaJadwal.rutin;
  CommitmentType _type = CommitmentType.fixed;
  final Set<int> _hari = {};
  DateTime _tanggal = DateTime.now();
  TimeOfDay _mulai = const TimeOfDay(hour: 13, minute: 0);
  TimeOfDay _selesai = const TimeOfDay(hour: 15, minute: 0);
  static const _monthShort = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Agu','Sep','Okt','Nov','Des'];
  static const _namaHari = ['Sen','Sel','Rab','Kam','Jum','Sab','Min'];

  @override
  void initState() {
    super.initState();
    final commitment = widget.commitment;
    if (commitment == null) return;
    _titleCtrl.text = commitment.title;
    _categoryCtrl.text = commitment.category ?? '';
    _type = commitment.type;
    _tanggal = commitment.startAt;
    _mulai = TimeOfDay.fromDateTime(commitment.startAt);
    _selesai = TimeOfDay.fromDateTime(commitment.endAt);
    final rule = widget.recurrenceRule;
    if (rule == null) {
      _pola = _PolaJadwal.sekali;
    } else {
      _pola = _PolaJadwal.rutin;
      final parts = <String,String>{};
      for (final part in rule.rrule.split(';')) {
        final split = part.split('=');
        if (split.length == 2) parts[split[0]] = split[1];
      }
      for (final token in (parts['BYDAY'] ?? '').split(',')) {
        final weekday = switch (token) {
          'MO' => DateTime.monday, 'TU' => DateTime.tuesday, 'WE' => DateTime.wednesday,
          'TH' => DateTime.thursday, 'FR' => DateTime.friday, 'SA' => DateTime.saturday,
          'SU' => DateTime.sunday, _ => null,
        };
        if (weekday != null) _hari.add(weekday);
      }
    }
  }

  @override
  void dispose() { _titleCtrl.dispose(); _categoryCtrl.dispose(); super.dispose(); }
  String get _tanggalLabel => '${_tanggal.day} ${_monthShort[_tanggal.month - 1]} ${_tanggal.year}';
  String _hhmm(TimeOfDay time) => '${time.hour.toString().padLeft(2,'0')}.${time.minute.toString().padLeft(2,'0')}';

  Future<void> _pilihTanggal() async {
    final picked = await showDatePicker(context: context, initialDate: _tanggal, firstDate: DateTime(2024), lastDate: DateTime(2035));
    if (picked != null) setState(() => _tanggal = picked);
  }
  Future<void> _pilihWaktu({required bool mulai}) async {
    final picked = await showTimePicker(context: context, initialTime: mulai ? _mulai : _selesai);
    if (picked == null) return;
    setState(() {
      if (mulai) {
        _mulai = picked;
      } else {
        _selesai = picked;
      }
    });
  }
  bool _waktuValid() => (_selesai.hour * 60 + _selesai.minute) > (_mulai.hour * 60 + _mulai.minute);

  Future<void> _simpan() async {
    final title = _titleCtrl.text.trim();
    final category = _categoryCtrl.text.trim();
    final vm = context.read<JadwalViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    if (title.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('Schedule title is required'))); return; }
    if (!_waktuValid()) { messenger.showSnackBar(const SnackBar(content: Text('End time must be after start time'))); return; }
    if (_pola == _PolaJadwal.rutin && _hari.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('Select at least one day'))); return; }
    final start = DateTime(_tanggal.year,_tanggal.month,_tanggal.day,_mulai.hour,_mulai.minute);
    final end = DateTime(_tanggal.year,_tanggal.month,_tanggal.day,_selesai.hour,_selesai.minute);
    bool ok;
    if (widget.commitment case final existing?) {
      ok = await vm.ubah(existing: existing, title: title, category: category.isEmpty ? null : category, type: _type, recurring: _pola == _PolaJadwal.rutin, weekdays: _hari, start: start, end: end);
    } else if (_pola == _PolaJadwal.rutin) {
      ok = await vm.tambahRutin(title: title, category: category.isEmpty ? null : category, weekdays: _hari, jamMulai: _mulai.hour, menitMulai: _mulai.minute, jamSelesai: _selesai.hour, menitSelesai: _selesai.minute, type: _type, mulaiDari: _tanggal);
    } else {
      ok = await vm.tambah(title: title, category: category.isEmpty ? null : category, start: start, end: end, type: _type);
    }
    if (!mounted) return;
    if (ok) { widget.onSave?.call(); return; }
    messenger.showSnackBar(SnackBar(content: Text(vm.errorMessage ?? 'Failed to save schedule'), action: SnackBarAction(label: 'Try again', onPressed: _simpan)));
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<JadwalViewModel>();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20,16,20,24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: GestureDetector(onTap: vm.isSaving ? null : widget.onBack, child: Container(width:40,height:40,decoration:BoxDecoration(color:C.card,shape:BoxShape.circle,border:Border.all(color:C.accent.withValues(alpha:0.6))),alignment:Alignment.center,child:const Icon(Icons.chevron_left,color:C.accent,size:22)))),
        const SizedBox(height:14),
        Text(widget.isEditing ? 'Edit Schedule' : 'Add Schedule', style: const TextStyle(color:C.white,fontSize:24)),
        const SizedBox(height:24),
        _FieldCard(label:'Judul Jadwal', child:_input(_titleCtrl,'Kelas Metode Riset')),
        const SizedBox(height:16),
        _FieldCard(label:'Category', child:_input(_categoryCtrl,'Kuliah, kerja, tim, lomba')),
        const SizedBox(height:16),
        _FieldCard(label:'Schedule Pattern', child:Row(children:[_Chip(label:'Recurring',active:_pola==_PolaJadwal.rutin,onTap:()=>setState(()=>_pola=_PolaJadwal.rutin)),const SizedBox(width:10),_Chip(label:'One-time',active:_pola==_PolaJadwal.sekali,onTap:()=>setState(()=>_pola=_PolaJadwal.sekali))])),
        const SizedBox(height:16),
        _FieldCard(label:'Time Type', child:Row(children:[_Chip(label:'FIXED',active:_type==CommitmentType.fixed,onTap:()=>setState(()=>_type=CommitmentType.fixed)),const SizedBox(width:10),_Chip(label:'FLEXIBLE',active:_type==CommitmentType.flexible,onTap:()=>setState(()=>_type=CommitmentType.flexible))])),
        const SizedBox(height:16),
        if (_pola == _PolaJadwal.rutin)
          _FieldCard(label:'Setiap hari',child:Wrap(spacing:8,runSpacing:8,children:List.generate(7,(index){final weekday=index+1;final active=_hari.contains(weekday);return _Chip(label:_namaHari[index],active:active,onTap:()=>setState((){if(active){_hari.remove(weekday);}else{_hari.add(weekday);}}));})))
        else _FieldCard(label:'Date', child:_TapValue(value:_tanggalLabel,onTap:_pilihTanggal)),
        const SizedBox(height:16),
        Row(children:[Expanded(child:_FieldCard(label:'Dari jam',child:_TapValue(value:_hhmm(_mulai),onTap:()=>_pilihWaktu(mulai:true)))),const SizedBox(width:16),Expanded(child:_FieldCard(label:'Sampai jam',child:_TapValue(value:_hhmm(_selesai),onTap:()=>_pilihWaktu(mulai:false))))]),
        const SizedBox(height:24),
        GestureDetector(onTap:vm.isSaving?null:_simpan,child:Container(padding:const EdgeInsets.symmetric(vertical:18),decoration:BoxDecoration(color:C.accent,borderRadius:BorderRadius.circular(14)),alignment:Alignment.center,child:vm.isSaving?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2,color:C.bg)):Text(widget.isEditing?'Save Changes':'Add Schedule',style:const TextStyle(color:C.bg,fontSize:16,fontWeight:FontWeight.w700)))),
        const SizedBox(height:12),
        GestureDetector(onTap:vm.isSaving?null:widget.onBack,child:Container(padding:const EdgeInsets.symmetric(vertical:16),decoration:BoxDecoration(color:C.card,borderRadius:BorderRadius.circular(14)),alignment:Alignment.center,child:const Text('Cancel',style:TextStyle(color:C.white,fontSize:15)))),
      ]),
    );
  }
  Widget _input(TextEditingController controller,String hint,{int maxLines=1}) => TextField(controller:controller,maxLines:maxLines,style:const TextStyle(color:C.white,fontSize:16),cursorColor:C.accent,decoration:InputDecoration(isDense:true,contentPadding:EdgeInsets.zero,border:InputBorder.none,hintText:hint,hintStyle:const TextStyle(color:C.detailMuted,fontSize:16)));
}

class _TapValue extends StatelessWidget { const _TapValue({required this.value,required this.onTap}); final String value; final VoidCallback onTap; @override Widget build(BuildContext context)=>GestureDetector(onTap:onTap,behavior:HitTestBehavior.opaque,child:Text(value,style:const TextStyle(color:C.white,fontSize:16))); }
class _Chip extends StatelessWidget { const _Chip({required this.label,required this.active,required this.onTap}); final String label; final bool active; final VoidCallback onTap; @override Widget build(BuildContext context)=>GestureDetector(onTap:onTap,child:Container(padding:const EdgeInsets.symmetric(horizontal:16,vertical:10),decoration:BoxDecoration(color:active?C.accent:C.bg,borderRadius:BorderRadius.circular(999)),child:Text(label,style:TextStyle(color:active?C.bg:C.white,fontSize:13,fontWeight:FontWeight.w700)))); }
class _FieldCard extends StatelessWidget { const _FieldCard({required this.label,required this.child}); final String label; final Widget child; @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:C.card,borderRadius:BorderRadius.circular(14),border:Border.all(color:C.accentSub.withValues(alpha:0.5))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:const TextStyle(color:C.accent,fontSize:13,fontWeight:FontWeight.w700)),const SizedBox(height:8),child])); }