import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final DateTime dateTime;
  final int avgHR;
  final double calories;
  final Duration duration;

  WorkoutRecord(this.dateTime, this.avgHR, this.calories, this.duration);

  String get dateStr => DateFormat('MM/dd(E)', 'ko_KR').format(dateTime);
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0; 
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  
  BluetoothDevice? _targetDevice;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = []; 
  double _timeCounter = 0;
  List<WorkoutRecord> _records = []; 
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _loadRecords();
    _initTts();
  }

  void _initTts() async {
    await _tts.setLanguage("ko-KR");
    await _tts.setSpeechRate(0.5);
  }

  Future<void> _speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('workout_records');
    if (recordsJson != null) {
      final List<dynamic> decodedList = jsonDecode(recordsJson);
      setState(() {
        _records = decodedList.map((item) => WorkoutRecord(
          DateTime.parse(item['dateTime']),
          item['avgHR'],
          item['calories'],
          Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  Future<void> _saveRecordsToStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final List<Map<String, dynamic>> recordList = _records.map((r) => {
      'dateTime': r.dateTime.toIso8601String(),
      'avgHR': r.avgHR,
      'calories': r.calories,
      'durationSeconds': r.duration.inSeconds,
    }).toList();
    await prefs.setString('workout_records', jsonEncode(recordList));
  }

  void _resetWorkout() {
    if (_isWorkingOut) {
      _speak("운동을 먼저 중지해 주세요.");
      return;
    }
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0;
    });
    _speak("기록을 초기화했습니다.");
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        builder: (context, snapshot) {
          final results = (snapshot.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
          return Column(
            children: [
              const Padding(padding: EdgeInsets.all(15), child: Text("워치 선택")),
              Expanded(child: ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(title: Text(r.device.platformName), onTap: () async {
                  await r.device.connect(); _setupDevice(r.device); Navigator.pop(context);
                });
              })),
            ],
          );
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      if (service.uuid == Guid("180D")) {
        for (var char in service.characteristics) {
          if (char.uuid == Guid("2A37")) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((value) => _decodeHR(value));
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
          if (_hrSpots.length > 120) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          if (_heartRate >= 95) _calories += (_heartRate * 0.6309 * (1/60) * 0.2);
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _speak("운동을 시작합니다.");
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
          if (_duration.inSeconds > 0 && _duration.inSeconds % 600 == 0) {
            _speak("${_duration.inMinutes}분 경과, ${_calories.toInt()}칼로리 소모 중입니다.");
          }
        });
      } else {
        _workoutTimer?.cancel();
        _speak("운동을 중지합니다.");
      }
    });
  }

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now(), _avgHeartRate, _calories, _duration)); });
    await _saveRecordsToStorage();
    _speak("기록을 저장했습니다.");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                GestureDetector(onTap: _isWatchConnected ? null : _connectWatch, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.cyanAccent), color: Colors.black54), child: Text(_isWatchConnected ? "연결 완료" : "워치 연결"))),
                const Spacer(),
                Container(margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25), decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.6), border: Border.all(color: Colors.white24)), child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_dataItem(Icons.favorite, "심박수", "$_heartRate", Colors.cyanAccent), _dataItem(Icons.analytics, "평균", "$_avgHeartRate", Colors.redAccent)]),
                  const SizedBox(height: 30),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [_dataItem(Icons.local_fire_department, "칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _dataItem(Icons.timer, "시간", _formatDuration(_duration), Colors.blueAccent)]),
                ])),
                const SizedBox(height: 30),
                Padding(padding: const EdgeInsets.only(bottom: 40), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout),
                  _actionBtn(Icons.refresh, "리셋", _resetWorkout),
                  _actionBtn(Icons.file_upload_outlined, "저장", _saveRecord),
                  _actionBtn(Icons.calendar_month, "달력", () => Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryCalendarScreen(records: _records)))),
                ])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(IconData i, String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10)), Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold))]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white24)), child: Icon(i, size: 22))), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10))]);
  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

class HistoryCalendarScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryCalendarScreen({Key? key, required this.records}) : super(key: key);
  @override
  State<HistoryCalendarScreen> createState() => _HistoryCalendarScreenState();
}

class _HistoryCalendarScreenState extends State<HistoryCalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  @override
  Widget build(BuildContext context) {
    int totalMins = widget.records.take(7).fold(0, (sum, r) => sum + r.duration.inMinutes);
    int totalCals = widget.records.take(7).fold(0, (sum, r) => sum + r.calories.toInt());

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 히스토리"), backgroundColor: Colors.transparent),
      body: Column(
        children: [
          TableCalendar(
            locale: 'ko_KR', firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.now(), focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) => widget.records.where((r) => isSameDay(r.dateTime, day)).toList(),
            calendarStyle: const CalendarStyle(selectedDecoration: BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle), markerDecoration: BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)),
          ),
          Container(
            padding: const EdgeInsets.all(20), margin: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              Column(children: [const Text("최근 7회 시간", style: TextStyle(fontSize: 10)), Text("$totalMins분", style: const TextStyle(fontWeight: FontWeight.bold))]),
              Column(children: [const Text("최근 7회 칼로리", style: TextStyle(fontSize: 10)), Text("${totalCals}kcal", style: const TextStyle(fontWeight: FontWeight.bold))]),
            ]),
          ),
          Expanded(child: ListView(children: widget.records.where((r) => isSameDay(r.dateTime, _selectedDay)).map((r) => ListTile(
            leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
            title: Text("${r.duration.inMinutes}분 라이딩"),
            subtitle: Text("${r.calories.toInt()}kcal / ${r.avgHR}BPM"),
            onLongPress: () async {
              setState(() { widget.records.remove(r); });
              final prefs = await SharedPreferences.getInstance();
              prefs.setString('workout_records', jsonEncode(widget.records.map((e) => {'dateTime': e.dateTime.toIso8601String(), 'avgHR': e.avgHR, 'calories': e.calories, 'durationSeconds': e.duration.inSeconds}).toList()));
            },
          )).toList())),
        ],
      ),
    );
  }
}
