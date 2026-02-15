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
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds
  };
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
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

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
          item['avgHR'], 
          (item['calories'] as num).toDouble(),
          Duration(seconds: item['durationSeconds'] ?? 0)
        )).toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    showModalBottomSheet(
      context: context, 
      backgroundColor: const Color(0xFF1E1E1E), 
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))), 
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) { 
          if (mounted) setModalState(() { _filteredResults = results; }); 
        });
        return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text("근처 워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) {
            final d = _filteredResults[index].device;
            final name = d.platformName.isEmpty ? "기기 (${d.remoteId})" : d.platformName;
            return ListTile(
              leading: const Icon(Icons.watch, color: Colors.blueAccent), 
              title: Text(name, style: const TextStyle(color: Colors.white)), 
              onTap: () { Navigator.pop(context); _connectToDevice(d); }
            );
          })) 
        ]));
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); } }
  
  void _setupDevice(BluetoothDevice device) async { 
    setState(() { _isWatchConnected = true; }); 
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { 
      if (s.uuid == Guid("180D")) { 
        for (var c in s.characteristics) { 
          if (c.uuid == Guid("2A37")) { 
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_decodeHR); 
          } 
        } 
      } 
    } 
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)); }

  // [수정됨] 파형 그래프 적용 구역
  Widget _chartArea() => SizedBox(
    height: 60,
    child: LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
            isCurved: true,             // 곡선 적용
            curveSmoothness: 0.35,      // 부드러움 정도
            color: Colors.blueAccent,   // 선 색상
            barWidth: 3,
            dotData: const FlDotData(show: false), // 점 숨기기
            belowBarData: BarAreaData(   // 그라데이션 채우기
              show: true,
              gradient: LinearGradient(
                colors: [Colors.blueAccent.withOpacity(0.3), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            const SizedBox(height: 40),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              _connectButton(),
            ]),
            const SizedBox(height: 30),
            _chartArea(),
            const SizedBox(height: 100),
            _goalProgress(progress),
            const SizedBox(height: 20),
            _dataBanner(),
            const SizedBox(height: 30),
            _controlButtons(),
          ]),
        ),
      ),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: _isWatchConnected ? Colors.blueAccent : Colors.white38)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: TextStyle(color: _isWatchConnected ? Colors.blueAccent : Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _goalProgress(double p) => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white70)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold))]),
    const SizedBox(height: 10),
    LinearProgressIndicator(value: p, backgroundColor: Colors.white12, color: Colors.blueAccent),
  ]));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.blueAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.white)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { 
      setState(() { 
        _isWorkingOut = !_isWorkingOut; 
        if (_isWorkingOut) { 
          _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
            setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) { _calories += 0.15; } }); 
          }); 
        } else { _workoutTimer?.cancel(); } 
      }); 
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState((){ _duration=Duration.zero; _calories=0.0; _hrSpots=[]; _timeCounter=0; }); }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async {
      if (_duration.inSeconds < 5) return;
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() { _records.insert(0, newRec); });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
      _showToast("저장 완료!");
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
  ]);
  
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// 기록 화면 (HistoryScreen 생략 - 기존 코드와 동일)
class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override Widget build(BuildContext context) { return Scaffold(appBar: AppBar(title: const Text("기록 리포트"))); }
}
