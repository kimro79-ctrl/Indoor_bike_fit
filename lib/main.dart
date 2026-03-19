import 'dart:async';
import 'dart:convert';
import 'dart:io'; 
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
  final String id, date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds};
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(), // 원본대로 메인으로 바로 진입
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
  void initState() {
    super.initState();
    _loadInitialData();
    // ✅ 사용자님 코드: UI 렌더링 후 권한 팝업 호출 (안드로이드 14 대응)
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    if (!Platform.isAndroid) return;
    // ✅ 근처 기기 검색을 위해 SCAN, CONNECT 권한 반드시 포함
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List decoded = jsonDecode(res);
        _records = decoded.map((i) => WorkoutRecord(i['id'] ?? DateTime.now().toString(), i['date'], i['avgHR'], (i['calories'] as num).toDouble(), Duration(seconds: i['durationSeconds'] ?? 0))).toList();
      }
    });
  }

  // ✅ 워치 스캔 (사용자님 원본 로직 그대로 복구)
  void _showDeviceScanPopup() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showToast("블루투스를 켜주세요");
      return;
    }
    _filteredResults.clear();
    await FlutterBluePlus.stopScan();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: true);

    showModalBottomSheet(
      context: context, backgroundColor: const Color(0xFF1E1E1E), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          List<ScanResult> devices = [];
          for (var r in results) {
            if (!devices.any((e) => e.device.remoteId == r.device.remoteId)) devices.add(r);
          }
          if (mounted) setModalState(() => _filteredResults = devices);
        });
        return Container(padding: const EdgeInsets.all(20), height: MediaQuery.of(context).size.height * 0.4, child: Column(children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(child: _filteredResults.isEmpty ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent)) : 
            ListView.builder(itemCount: _filteredResults.length, itemBuilder: (c, i) {
              final d = _filteredResults[i].device;
              return ListTile(
                leading: const Icon(Icons.watch, color: Colors.blueAccent),
                title: Text(d.platformName.isEmpty ? "BLE Device" : d.platformName),
                subtitle: Text(d.remoteId.toString()),
                onTap: () { Navigator.pop(context); _connectToDevice(d); },
              );
            }))
        ]));
      })).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _setupDevice(device);
    } catch (e) { _showToast("연결 실패"); }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() => _isWatchConnected = true);
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid.toString().toUpperCase().contains("180D")) {
        for (var c in s.characteristics) {
          if (c.uuid.toString().toUpperCase().contains("2A37")) {
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

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: SizedBox(height: MediaQuery.of(context).size.height - 100, child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.5)),
            _connectButton(),
          ]),
          const SizedBox(height: 25),
          _chartArea(),
          const Spacer(),
          _calorieGoalWidget(progress),
          const SizedBox(height: 20),
          _dataBanner(),
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))))),
      ]),
    );
  }

  Widget _connectButton() => GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.greenAccent)), child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _chartArea() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _calorieGoalWidget(double p) => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white10)), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold))]),
    const SizedBox(height: 10),
    ClipRRect(borderRadius: BorderRadius.circular(5), child: LinearProgressIndicator(value: p, minHeight: 10, backgroundColor: Colors.white12, color: Colors.greenAccent)),
  ]));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () { 
      setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if(_heartRate >= 95) _calories += 0.15; })); } else { _workoutTimer?.cancel(); } }); 
    }), const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState(() { _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _heartRate = 0; _hrSpots = []; _timeCounter = 0; }); }), const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", () async { 
      if(_duration.inSeconds < 5) { _showToast("기록이 너무 짧습니다."); return; }
      final newRec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
      setState(() => _records.insert(0, newRec));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
      _showToast("저장 완료!");
    }), const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)))),
  ]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

// ---------------------------------------------------------
// ✅ 기록 리포트 화면 (길게 눌러 삭제 팝업 원본 로직 복구)
// ---------------------------------------------------------
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late List<WorkoutRecord> _currentRecords;
  @override
  void initState() { super.initState(); _currentRecords = List.from(widget.records); }

  void _confirmDelete(String id) {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제 확인"), content: const Text("이 기록을 삭제하시겠습니까?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
        TextButton(onPressed: () async {
          setState(() => _currentRecords.removeWhere((r) => r.id == id));
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('workout_records', jsonEncode(_currentRecords.map((r) => r.toJson()).toList()));
          widget.onSync();
          Navigator.pop(c);
        }, child: const Text("삭제", style: TextStyle(color: Colors.redAccent))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: ListView.builder(itemCount: _currentRecords.length, itemBuilder: (c, i) {
          final r = _currentRecords[i];
          return Card(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4), color: Colors.white, child: ListTile(
            onLongPress: () => _confirmDelete(r.id), // ✅ 길게 눌러 삭제
            leading: const Icon(Icons.directions_bike, color: Colors.blueAccent),
            title: Text("${r.calories.toInt()} kcal 소모", style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${r.date} / ${r.duration.inMinutes}분"),
          ));
        }),
      ),
    );
  }
}
