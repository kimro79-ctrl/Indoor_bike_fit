import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 데이터 저장용
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const WorkoutScreen(),
    );
  }
}

// --- 메인 운동 화면 ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  List<FlSpot> _hrSpots = [];
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  // 운동 기록 저장 함수
  Future<void> _saveWorkout() async {
    if (_duration.inSeconds < 1) return; // 운동 시간이 없으면 저장 안 함

    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList('workout_history') ?? [];

    Map<String, dynamic> record = {
      'date': DateTime.now().toIso8601String(),
      'duration': _duration.inSeconds,
      'avgHr': _avgHeartRate,
      'kcal': _calories.toStringAsFixed(1),
    };

    history.add(jsonEncode(record));
    await prefs.setStringList('workout_history', history);
    
    _reset(); // 저장 후 초기화
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다!")));
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _heartRate = 0; _avgHeartRate = 0;
      _hrSpots.clear(); _isWorkingOut = false;
    });
  }

  void _toggleStart() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            // 심박수가 85 이상일 때만 칼로리 소모 계산 로직 (예시 공식)
            if (_heartRate >= 85) {
              _calories += (_heartRate * 0.0005); 
            }
          });
        });
      } else { _timer?.cancel(); }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/background.png'), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(
            children: [
              _buildTopBar(),
              Flexible(flex: 3, child: Center(child: Image.asset('assets/icon/bike_ui_dark.png', fit: BoxFit.contain))),
              Flexible(flex: 2, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 30), child: _isWatchConnected ? LineChart(_chartData()) : const Center(child: Text("워치 연결됨 시 그래프 노출")))),
              
              // 최적화된 데이터 바 (4개 항목)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _dataBox("심박수", "$_heartRate", Colors.greenAccent),
                    _dataBox("평균", "$_avgHeartRate", Colors.redAccent),
                    _dataBox("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                    _dataBox("시간", _formatDuration(_duration), Colors.blueAccent),
                  ],
                ),
              ),
              
              // 하단 버튼
              Padding(
                padding: const EdgeInsets.only(bottom: 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _circleBtn(Icons.play_arrow, "시작", _toggleStart),
                    _circleBtn(Icons.refresh, "리셋", _reset),
                    _circleBtn(Icons.save, "저장", _saveWorkout),
                    _circleBtn(Icons.calendar_month, "기록", () {
                      Navigator.push(context, MaterialPageRoute(builder: (c) => const HistoryScreen()));
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 나머지 위젯(_buildTopBar, _dataBox, _circleBtn, _chartData 등)은 이전과 동일하게 유지...
  Widget _dataBox(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: c))]);
  Widget _circleBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: CircleAvatar(radius: 28, backgroundColor: Colors.white10, child: Icon(i, color: Colors.white))), const SizedBox(height: 5), Text(l, style: const TextStyle(fontSize: 11))]);
  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  LineChartData _chartData() => LineChartData(gridData: FlGridData(show: false), titlesData: FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 3, dotData: FlDotData(show: false))]);
  Widget _buildTopBar() => Padding(padding: const EdgeInsets.all(15), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Indoor bike fit", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), TextButton(onPressed: ()=>setState(()=>_isWatchConnected=!_isWatchConnected), child: Text(_isWatchConnected?"연결됨":"워치 연결", style: TextStyle(color: _isWatchConnected?Colors.cyanAccent:Colors.white)))]));
}

// --- 기록 리포트 페이지 (달력 + 데이터 리스트) ---
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<Map<String, dynamic>> _allRecords = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> history = prefs.getStringList('workout_history') ?? [];
    setState(() {
      _allRecords = history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 선택한 날짜의 데이터만 필터링
    final dailyRecords = _allRecords.where((r) {
      final date = DateTime.parse(r['date']);
      return isSameDay(date, _selectedDay);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // 원래 앱 스타일 (밝은 배경)
      appBar: AppBar(title: const Text("기록 리포트", style: TextStyle(color: Colors.black)), backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1), lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
              defaultTextStyle: TextStyle(color: Colors.black),
              weekendTextStyle: TextStyle(color: Colors.red),
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.black, fontSize: 18)),
          ),
          const Divider(height: 1),
          Expanded(
            child: dailyRecords.isEmpty
                ? const Center(child: Text("저장된 운동 기록이 없습니다.", style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: dailyRecords.length,
                    itemBuilder: (context, i) {
                      final r = dailyRecords[i];
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_bike, color: Colors.white)),
                          title: Text("${r['kcal']} kcal 소모", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          subtitle: Text("시간: ${r['duration']}초 | 평균 심박수: ${r['avgHr']} bpm"),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
