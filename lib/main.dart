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

class WorkoutRecord {
  final String id;
  final String date; // yyyy-MM-dd
  final String time; // HH:mm
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.time, this.avgHR, this.calories, this.duration);
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
  List<ScanResult> _filteredResults = [];

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(
          item['id'] ?? DateTime.now().toString(),
          item['date'],
          item['time'] ?? "00:00",
          item['avgHR'],
          item['calories'],
          Duration(seconds: item['durationSeconds'])
        )).toList();
      }
    });
  }

  // ✅ 작고 심플해진 설정 팝업
  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          height: 180, // 높이를 대폭 줄임
          child: Column(
            children: [
              Container(width: 30, height: 4, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 15),
              Row(
                children: [
                  const Text("목표 설정", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                      decoration: const InputDecoration(suffixText: " kcal", border: InputBorder.none),
                    ),
                  ),
                ],
              ),
              const Divider(color: Colors.white10),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    setState(() { _goalCalories = double.tryParse(controller.text) ?? 300.0; });
                    (await SharedPreferences.getInstance()).setDouble('goal_calories', _goalCalories);
                    Navigator.pop(context);
                  },
                  child: const Text("확인", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // (중략: 기존 WorkoutScreen 위젯 로직 동일 - 심박수 및 저장기능)
  // 저장 시 'time' 추가: DateFormat('HH:mm').format(DateTime.now())
  
  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Container(color: Colors.black)),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            _connectButton(),
          ]),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          GestureDetector(
            onTap: _showGoalSettings,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)), child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(borderRadius: BorderRadius.circular(5), child: SizedBox(height: 10, child: LinearProgressIndicator(value: progress, backgroundColor: Colors.white12, color: Colors.greenAccent))),
            ])),
          ),
          const SizedBox(height: 20),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _connectButton() => Container(); // 이전 코드와 동일
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(Icons.play_arrow, "시작", () { setState(() { _isWorkingOut = true; _startTimer(); }); }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async {
      if (_duration.inSeconds < 5) return;
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), DateFormat('HH:mm').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'time': r.time, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
  ]);

  void _startTimer() { /* 타이머 로직 */ }
  void _showDeviceScanPopup() { /* 블루투스 스캔 로직 */ }
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// --- 히스토리 리포트 화면 (일간 추가 버전) ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _mode = 0; // 0: 일간, 1: 주간, 2: 월간
  bool _showChart = false;

  List<BarChartGroupData> _buildChartGroups() {
    List<WorkoutRecord> targetRecords = [];
    DateTime now = DateTime.now();

    if (_mode == 0) { // 일간: 오늘 기록만 시간순으로
      targetRecords = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(now)).toList().reversed.toList();
    } else if (_mode == 1) { // 주간: 최근 7일
      targetRecords = widget.records.where((r) => DateTime.parse(r.date).isAfter(now.subtract(const Duration(days: 7)))).toList().reversed.toList();
    } else { // 월간: 최근 30일
      targetRecords = widget.records.where((r) => DateTime.parse(r.date).isAfter(now.subtract(const Duration(days: 30)))).toList().reversed.toList();
    }

    return List.generate(targetRecords.length, (index) => BarChartGroupData(x: index, barRods: [BarChartRodData(toY: targetRecords[index].calories, color: _mode == 0 ? Colors.orangeAccent : Colors.blueAccent, width: 12, borderRadius: BorderRadius.circular(4))]));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Row(children: [
            _statCard("일간", _mode == 0, Colors.orangeAccent, () => setState(() { _mode = 0; _showChart = true; })),
            const SizedBox(width: 8),
            _statCard("주간", _mode == 1, Colors.blueAccent, () => setState(() { _mode = 1; _showChart = true; })),
            const SizedBox(width: 8),
            _statCard("월간", _mode == 2, Colors.indigo, () => setState(() { _mode = 2; _showChart = true; })),
          ])),
          if (_showChart) AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 180, margin: const EdgeInsets.symmetric(horizontal: 16), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: BarChart(BarChartData(barGroups: _buildChartGroups(), borderData: FlBorderData(show: false), titlesData: const FlTitlesData(show: false))),
          ),
          const SizedBox(height: 10),
          TableCalendar(locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: DateTime.now(), calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
          // 기록 리스트 생략 (기존과 동일)
        ])),
      ),
    );
  }

  Widget _statCard(String t, bool isSel, Color c, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(color: isSel ? c : Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSel ? Colors.transparent : Colors.black12)),
        child: Center(child: Text(t, style: TextStyle(color: isSel ? Colors.white : Colors.black54, fontWeight: FontWeight.bold, fontSize: 13))),
      ),
    ),
  );
}
