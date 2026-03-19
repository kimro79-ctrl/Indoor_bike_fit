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

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermissions());
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    }
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List decoded = jsonDecode(res);
        _records = decoded.map((i) => WorkoutRecord(i['id'], i['date'], i['avgHR'], (i['calories'] as num).toDouble(), Duration(seconds: i['durationSeconds']))).toList();
      }
    });
  }

  // ✅ 워치 스캔 로직 (스캔 시작 명령 포함)
  void _showDeviceScanPopup() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showToast("블루투스를 켜주세요");
      return;
    }

    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: true);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        var subscription = FlutterBluePlus.onScanResults.listen((results) {
          if (mounted) setModalState(() => _filteredResults = results);
        });

        return Container(
          padding: const EdgeInsets.all(20),
          height: 400,
          child: Column(children: [
            const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(child: ListView.builder(
              itemCount: _filteredResults.length,
              itemBuilder: (c, i) {
                final d = _filteredResults[i].device;
                return ListTile(
                  leading: const Icon(Icons.watch, color: Colors.blueAccent),
                  title: Text(d.platformName.isEmpty ? "알 수 없는 기기" : d.platformName),
                  onTap: () { 
                    subscription.cancel();
                    FlutterBluePlus.stopScan(); 
                    Navigator.pop(context); 
                    _connectToDevice(d); 
                  },
                );
              },
            )),
          ]),
        );
      }),
    ).then((_) => FlutterBluePlus.stopScan());
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
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
    } catch (e) { _showToast("연결 실패"); }
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, hr.toDouble()));
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
  }

  void _showToast(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(
          child: Column(children: [
            const SizedBox(height: 40),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              // ✅ 워치 연결: 아이콘이 아닌 텍스트 버튼으로 복구
              _connectTextButton(),
            ])),
            const SizedBox(height: 30),
            SizedBox(height: 80, child: _chartArea()),
            const Spacer(),
            _bottomControlPanel(),
            const SizedBox(height: 40),
          ]),
        ),
      ]),
    );
  }

  // ✅ 워치 연결 텍스트 버튼 UI (아이콘에서 텍스트로 복구)
  Widget _connectTextButton() => GestureDetector(
    onTap: _showDeviceScanPopup,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isWatchConnected ? Colors.greenAccent : Colors.white24),
      ),
      child: Text(
        _isWatchConnected ? "연결됨" : "워치 연결",
        style: TextStyle(color: _isWatchConnected ? Colors.greenAccent : Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    ),
  );

  Widget _bottomControlPanel() => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), 
    child: Column(children: [
      _goalProgress(),
      const SizedBox(height: 20),
      _dataBanner(),
      const SizedBox(height: 30),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _actionBtn(Icons.play_arrow, "시작", () { 
          setState(() { 
            _isWorkingOut = !_isWorkingOut; 
            if(_isWorkingOut) _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if(_heartRate>0) _calories += 0.15; })); 
            else _workoutTimer?.cancel(); 
          });
        }),
        const SizedBox(width: 15),
        _actionBtn(Icons.refresh, "리셋", () => setState(() { _duration = Duration.zero; _calories = 0.0; _heartRate = 0; _avgHeartRate = 0; _hrSpots = []; })),
        const SizedBox(width: 15),
        // ✅ 저장 버튼 (터치 영역 확보)
        _actionBtn(Icons.save, "저장", _saveRecord),
        const SizedBox(width: 15),
        _actionBtn(Icons.calendar_month, "기록", () {
          Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _loadInitialData)));
        }),
      ])
    ]));

  void _saveRecord() async {
    if (_duration.inSeconds < 5) {
      _showToast("운동 시간이 너무 짧아요");
      return;
    }
    final rec = WorkoutRecord(DateTime.now().toString(), DateFormat('yyyy-MM-dd').format(DateTime.now()), _avgHeartRate, _calories, _duration);
    _records.insert(0, rec);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => r.toJson()).toList()));
    _showToast("기록이 저장되었습니다");
  }

  Widget _chartArea() => LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, dotData: const FlDotData(show: false))]));
  Widget _goalProgress() => Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)), child: Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, color: Colors.white70)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(color: Colors.greenAccent))]),
    const SizedBox(height: 10),
    LinearProgressIndicator(value: (_calories/_goalCalories).clamp(0, 1), color: Colors.greenAccent, backgroundColor: Colors.white12),
  ]));
  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds%60).toString().padLeft(2,'0')}", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [
    GestureDetector(
      onTap: t, 
      child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))
    ), 
    const SizedBox(height: 6), 
    Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))
  ]);
}

// ✅ 기록 리포트 (길게 눌러 삭제)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final VoidCallback onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late List<WorkoutRecord> _currentList;
  @override
  void initState() { super.initState(); _currentList = List.from(widget.records); }

  void _deleteRecord(int index) async {
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("삭제"), content: const Text("기록을 삭제할까요?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
        TextButton(onPressed: () async {
          setState(() { _currentList.removeAt(index); });
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('workout_records', jsonEncode(_currentList.map((r) => r.toJson()).toList()));
          widget.onSync();
          Navigator.pop(c);
        }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("기록 리포트")),
      body: ListView.builder(
        itemCount: _currentList.length,
        itemBuilder: (c, i) => ListTile(
          onLongPress: () => _deleteRecord(i),
          leading: const Icon(Icons.directions_bike),
          title: Text("${_currentList[i].calories.toInt()} kcal"),
          subtitle: Text(_currentList[i].date),
        ),
      ),
    );
  }
}
