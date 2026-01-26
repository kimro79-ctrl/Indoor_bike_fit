import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

// --- 모델 ---
class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
}

class WeightRecord {
  final String date;
  final double weight;
  WeightRecord(this.date, this.weight);
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

// --- 메인 화면 (기존 배경 복구) ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  double _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { 
    super.initState(); 
    _loadData(); 
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'], item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList();
      }
    });
  }

  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("목표 칼로리 설정"),
        content: TextField(controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center, style: const TextStyle(color: Colors.greenAccent, fontSize: 24)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("확인", style: TextStyle(color: Colors.greenAccent))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        // ✅ 원래 사용하던 뒷배경 복구
        Positioned.fill(child: Opacity(opacity: 0.6, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          // ✅ 슬림한 목표 바
          GestureDetector(
            onTap: _showGoalSettings,
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white54)),
                Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 10, color: Colors.greenAccent)),
              ]),
              const SizedBox(height: 5),
              LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.white10, color: Colors.greenAccent),
            ]),
          ),
          const SizedBox(height: 15),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); _calories += 0.15; })); } else { _workoutTimer?.cancel(); } }); }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async {
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadData)))),
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// --- 히스토리 화면 (체중 및 주간/월간 통계 통합) ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _currentWeight = 0.0;

  @override
  void initState() { super.initState(); _loadWeight(); }

  Future<void> _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _currentWeight = prefs.getDouble('last_weight') ?? 70.0; });
  }

  void _editWeight() {
    final controller = TextEditingController(text: _currentWeight.toString());
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("현재 체중 설정"),
      content: TextField(controller: controller, keyboardType: TextInputType.number, textAlign: TextAlign.center),
      actions: [
        TextButton(onPressed: () async {
          setState(() { _currentWeight = double.tryParse(controller.text) ?? 70.0; });
          (await SharedPreferences.getInstance()).setDouble('last_weight', _currentWeight);
          Navigator.pop(ctx);
        }, child: const Text("저장")),
      ],
    ));
  }

  double _getPeriodKcal(int days) {
    DateTime limit = DateTime.now().subtract(Duration(days: days));
    return widget.records.where((r) => DateTime.parse(r.date).isAfter(limit)).fold(0.0, (sum, r) => sum + r.calories);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          // ✅ 상단 체중 및 칼로리 요약 (주간/월간)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              GestureDetector(
                onTap: _editWeight,
                child: _infoBar("나의 현재 체중", "${_currentWeight}kg", Colors.blueGrey),
              ),
              const SizedBox(height: 10),
              Row(children: [
                _statCard("주간 칼로리", "${_getPeriodKcal(7).toInt()} kcal", Colors.blueAccent),
                const SizedBox(width: 10),
                _statCard("월간 칼로리", "${_getPeriodKcal(30).toInt()} kcal", Colors.indigo),
              ]),
            ]),
          ),
          // ✅ 달력 (이벤트 스팟 주황색 점 추가)
          _buildCalendarSection(),
          const SizedBox(height: 10),
          ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: filtered.length, itemBuilder: (c, i) => _buildRecordCard(filtered[i])),
        ])),
      ),
    );
  }

  Widget _infoBar(String t, String v, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(t, style: const TextStyle(color: Colors.white70)), Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))]));
  Widget _statCard(String t, String v, Color c) => Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(t, style: const TextStyle(color: Colors.white70, fontSize: 11)), Text(v, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))])));

  Widget _buildCalendarSection() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
    child: TableCalendar(
      locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
      rowHeight: 40, headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
      selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
      onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
      eventLoader: (day) => widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
      calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)), // ✅ 운동 스팟
    ),
  );

  Widget _buildRecordCard(WorkoutRecord r) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
    leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
    title: Text(r.date, style: const TextStyle(fontWeight: FontWeight.bold)),
    subtitle: Text("${r.duration.inMinutes}분 / ${r.avgHR}bpm"),
    trailing: Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
    onLongPress: () { /* 삭제 확인 팝업 로직 추가 가능 */ },
  );
}
