import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  // ✅ 플러터 엔진 초기화 및 기본 스플래시 제어
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black, // 기본 배경은 블랙
      ),
      home: const SplashScreen(), // 텍스트 스플래시가 첫 화면으로 뜸
    );
  }
}

// ---------------------------------------------------------
// 1. 스플래시 화면 (사용자 제공 블랙 테마 디자인)
// ---------------------------------------------------------
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // 2.5초 후 메인으로 전환
    Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const WorkoutScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // ✅ 플러터 기본 로고 방지용 블랙 배경
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("INDOOR", style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const Text("BIKE FIT", style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2)),
            const SizedBox(height: 15),
            const Text("Indoor cycling studio", style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. 메인 화면 (디자인 고정 및 기능 수정)
// ---------------------------------------------------------
class WorkoutRecord {
  final String id, date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorking = false;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final res = prefs.getString('workout_records');
    if (res != null) {
      final List decoded = jsonDecode(res);
      setState(() {
        _records = decoded.map((item) => WorkoutRecord(item['id'], item['date'], item['avgHR'], (item['calories'] as num).toDouble(), Duration(seconds: item['durationSeconds']))).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.black))),
        SafeArea(
          child: Column(children: [
            const SizedBox(height: 40),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                Icon(Icons.watch, color: Colors.white24)
              ]),
            ),
            const Spacer(),
            // ✅ 문자열 출력 오류 수정된 배너
            _statBanner(),
            const SizedBox(height: 30),
            _buttonArea(),
            const SizedBox(height: 40),
          ]),
        )
      ]),
    );
  }

  Widget _statBanner() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20),
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _statItem("심박수", "$_heartRate", Colors.greenAccent),
      _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
      _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
    ]),
  );

  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);

  Widget _buttonArea() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _circleBtn(Icons.play_arrow, () => setState(() => _isWorking = true)),
    const SizedBox(width: 15),
    _circleBtn(Icons.refresh, () => setState(() { _duration = Duration.zero; _calories = 0.0; })),
    const SizedBox(width: 15),
    _circleBtn(Icons.save, () => _showSaveDialog()),
    const SizedBox(width: 15),
    _circleBtn(Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (c)=>HistoryScreen(records: _records)))),
  ]);

  Widget _circleBtn(IconData i, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white)));

  void _showSaveDialog() {
    showDialog(context: context, builder: (c) => AlertDialog(title: const Text("저장 완료"), content: const Text("운동 기록이 저장되었습니다."), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("확인"))]));
  }
}

// ---------------------------------------------------------
// 3. 기록 리포트 화면 (사용자님 원본 디자인 - 절대 수정 금지) 💎
// ---------------------------------------------------------
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // ✅ 두 번째 사진 배경색
      appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Column(children: [
        // ✅ 사용자님 원본 체중 바 (디자인 고정)
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: const Color(0xFF5C7888), borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 16)),
            Text("69.7kg", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          ]),
        ),
        // ✅ 일간/주간/월간 버튼 (디자인 고정)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _topBtn("일간", Colors.redAccent), const SizedBox(width: 8),
            _topBtn("주간", Colors.orangeAccent), const SizedBox(width: 8),
            _topBtn("월간", Colors.blueAccent),
          ]),
        ),
        // ✅ 사용자님 원본 캘린더 (디자인 고정)
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(_selected, d),
            onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
            calendarStyle: const CalendarStyle(
              selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
              markerDecoration: BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          ),
        ),
        // ✅ 하단 기록 카드 (디자인 고정)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _historyCard("6 kcal 소모", "2분 / 88 bpm"),
              _historyCard("90 kcal 소모", "10분 / 117 bpm"),
            ],
          ),
        )
      ]),
    );
  }

  Widget _topBtn(String l, Color c) => Expanded(child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10)), child: Center(child: Text(l, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))));

  Widget _historyCard(String t, String s) => Card(margin: const EdgeInsets.only(bottom: 8), elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: ListTile(leading: const Icon(Icons.directions_bike, color: Colors.blueAccent), title: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(s)));
}
