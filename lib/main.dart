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
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const SplashScreen(), // 스플래시가 첫 화면
    );
  }
}

// ---------------------------------------------------------
// 1. 스플래시 화면 (사진 디자인 재현)
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
    Timer(const Duration(seconds: 3), () {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const WorkoutScreen()));
    });
  }
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("INDOOR", style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2)),
            Text("BIKE FIT", style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 2)),
            SizedBox(height: 15),
            Text("Indoor cycling studio", style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------
// 2. 메인 화면 (문자열 및 스캔 수정)
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
  BluetoothDevice? _connectedDevice;

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

  // ✅ 워치 스캔 로직 (권한 체크 및 팝업)
  void _startScan() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (context) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.onScanResults,
        builder: (context, snapshot) {
          final results = snapshot.data ?? [];
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text("주변 워치 검색 중...", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              Expanded(
                child: ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (c, i) => ListTile(
                    leading: const Icon(Icons.watch, color: Colors.blueAccent),
                    title: Text(results[i].device.platformName.isEmpty ? "알 수 없는 기기" : results[i].device.platformName),
                    onTap: () async {
                      await results[i].device.connect();
                      setState(() => _connectedDevice = results[i].device);
                      Navigator.pop(context);
                    },
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.7, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s) => Container(color: Colors.black)))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              const SizedBox(height: 40),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                IconButton(onPressed: _startScan, icon: Icon(Icons.watch, color: _connectedDevice != null ? Colors.greenAccent : Colors.white24))
              ]),
              const Spacer(),
              _statRow(),
              const SizedBox(height: 30),
              _btnRow(),
              const SizedBox(height: 40),
            ]),
          ),
        )
      ]),
    );
  }

  // ✅ 문자열 출력 오류 수정 완료
  Widget _statRow() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      _item("심박수", "$_heartRate", Colors.greenAccent),
      _item("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
      _item("시간", "${_duration.inMinutes.toString().padLeft(2, '0')}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
    ]),
  );

  Widget _item(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);

  Widget _btnRow() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _circleBtn(_isWorking ? Icons.pause : Icons.play_arrow, () {
      setState(() {
        _isWorking = !_isWorking;
        if(_isWorking) { _timer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); _calories += 0.01; })); }
        else { _timer?.cancel(); }
      });
    }),
    const SizedBox(width: 15),
    _circleBtn(Icons.refresh, () => setState(() { _duration = Duration.zero; _calories = 0.0; })),
    const SizedBox(width: 15),
    _circleBtn(Icons.save, () async {
      final r = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _heartRate, _calories, _duration);
      _records.insert(0, r);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((e)=>e.toJson()).toList()));
    }),
    const SizedBox(width: 15),
    _circleBtn(Icons.calendar_month, () => Navigator.push(context, MaterialPageRoute(builder: (c)=>HistoryScreen(records: _records, onSync: _loadData)))),
  ]);

  Widget _circleBtn(IconData i, VoidCallback t) => GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, shape: BoxShape.circle, border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white)));
}

// ---------------------------------------------------------
// 3. 기록 화면 (사용자 제공 사진 디자인 100% 복구)
// ---------------------------------------------------------
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focused = DateTime.now();
  DateTime? _selected;
  late List<WorkoutRecord> _cur;

  @override
  void initState() { super.initState(); _cur = List.from(widget.records); _selected = _focused; }

  @override
  Widget build(BuildContext context) {
    final daily = _cur.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selected!)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9), // 사진과 동일한 밝은 배경
      appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
      body: Column(children: [
        // 상단 체중 바 (사진 디자인)
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: const Color(0xFF5C7888), borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text("나의 현재 체중", style: TextStyle(color: Colors.white)),
            Text("70kg", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
        // 달력
        TableCalendar(
          locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focused,
          selectedDayPredicate: (d) => isSameDay(_selected, d),
          onDaySelected: (s, f) => setState(() { _selected = s; _focused = f; }),
          calendarStyle: const CalendarStyle(selectedDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle), todayDecoration: BoxDecoration(color: Colors.black12, shape: BoxShape.circle)),
        ),
        // 기록 리스트 (Expanded 추가하여 멈춤 해결)
        Expanded(
          child: ListView.builder(
            itemCount: daily.length,
            itemBuilder: (c, i) => Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
                title: Text("${daily[i].calories.toInt()} kcal 소모"),
                subtitle: Text("${daily[i].duration.inMinutes}분 운동 / ${daily[i].avgHR} bpm"),
              ),
            ),
          ),
        )
      ]),
    );
  }
}
