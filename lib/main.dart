import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.date, this.avgHR, this.calories, this.duration);
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
        fontFamily: 'Pretendard', // 폰트가 있다면 적용, 없다면 기본폰트 사용
      ),
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

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('workout_records');
    if (recordsJson != null) {
      final List<dynamic> decodedList = jsonDecode(recordsJson);
      setState(() {
        _records = decodedList.map((item) => WorkoutRecord(
          item['date'],
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
      'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds,
    }).toList();
    await prefs.setString('workout_records', jsonEncode(recordList));
  }

  void _resetWorkout() {
    if (_isWorkingOut) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동을 먼저 중지해주세요.")));
      return;
    }
    setState(() {
      _duration = Duration.zero; _calories = 0.0; _avgHeartRate = 0; _hrSpots = []; _timeCounter = 0;
    });
    HapticFeedback.mediumImpact();
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
              const Padding(padding: EdgeInsets.all(15), child: Text("연결할 워치 선택", style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(child: results.isEmpty ? const Center(child: Text("주변에 감지된 워치가 없습니다.")) : ListView.builder(itemCount: results.length, itemBuilder: (context, index) {
                final r = results[index];
                return ListTile(leading: const Icon(Icons.watch, color: Colors.cyanAccent), title: Text(r.device.platformName), onTap: () async {
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
    setState(() { _targetDevice = device; _isWatchConnected = true; });
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
          if (_hrSpots.length > 60) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
          if (_heartRate >= 90) _calories += (_heartRate * 0.005);
        }
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _duration += const Duration(seconds: 1)));
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    String formattedDate = "${DateTime.now().month}/${DateTime.now().day}";
    setState(() { _records.insert(0, WorkoutRecord(formattedDate, _avgHeartRate, _calories, _duration)); });
    await _saveRecordsToStorage();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("기록 저장 완료!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (assets/background.png가 있어야 함)
          Positioned.fill(child: Opacity(opacity: 0.5, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // 2. 상단 타이틀 및 워치 연결 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Over The Bike Fit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      GestureDetector(
                        onTap: _isWatchConnected ? null : _connectWatch,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24),
                            color: Colors.black45
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.watch, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                              const SizedBox(width: 5),
                              Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(),

                // 3. 메인 데이터 패널 (사진처럼 둥근 박스)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(40),
                    border: Border.all(color: Colors.white10)
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _dataBox(Icons.favorite, "현재 심박수", "${_heartRate > 0 ? _heartRate : '--'}", Colors.cyanAccent),
                          _dataBox(Icons.analytics, "평균 심박수", "$_avgHeartRate", Colors.redAccent),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _dataBox(Icons.local_fire_department, "소모 칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                          _dataBox(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // 4. 하단 4개 액션 버튼 (사진 9번 참조)
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", _toggleWorkout, _isWorkingOut ? Colors.orange : Colors.cyanAccent),
                      _circleBtn(Icons.refresh, "리셋", _resetWorkout, Colors.white54),
                      _circleBtn(Icons.save, "저장", _saveRecord, Colors.white54),
                      _circleBtn(Icons.history, "기록", () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(records: _records, hrSpots: _hrSpots)));
                      }, Colors.white54),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataBox(IconData i, String t, String v, Color c) => Column(
    children: [
      Row(children: [Icon(i, size: 16, color: c), const SizedBox(width: 5), Text(t, style: const TextStyle(color: Colors.white60, fontSize: 12))]),
      const SizedBox(height: 5),
      Text(v, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
    ],
  );

  Widget _circleBtn(IconData i, String l, VoidCallback o, Color c) => Column(
    children: [
      GestureDetector(
        onTap: o,
        child: Container(
          width: 65, height: 65,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.1), border: Border.all(color: Colors.white10)),
          child: Icon(i, color: c, size: 28),
        ),
      ),
      const SizedBox(height: 8),
      Text(l, style: const TextStyle(fontSize: 11, color: Colors.white70)),
    ],
  );

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// 5. 히스토리 화면 (사진 10번 참조)
class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  final List<FlSpot> hrSpots;
  const HistoryScreen({Key? key, required this.records, required this.hrSpots}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    int totalCals = records.take(7).fold(0, (sum, r) => sum + r.calories.toInt());
    int totalMins = records.take(7).fold(0, (sum, r) => sum + r.duration.inMinutes);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 히스토리"), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 통계 카드
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.cyanAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _statText("최근 7회 칼로리", "${totalCals}kcal"),
                _statText("최근 7회 시간", "${totalMins}분"),
              ],
            ),
          ),
          const SizedBox(height: 30),
          const Text("최근 심박수 그래프", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          SizedBox(
            height: 120,
            child: LineChart(LineChartData(
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(spots: hrSpots.isNotEmpty ? hrSpots : [const FlSpot(0,0)], isCurved: true, color: Colors.cyanAccent, dotData: const FlDotData(show: false))]
            )),
          ),
          const SizedBox(height: 30),
          const Text("전체 기록", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...records.map((r) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.directions_bike, color: Colors.cyanAccent),
            title: Text("${r.duration.inMinutes}분 운동 완료"),
            subtitle: Text(r.date),
            trailing: Text("${r.avgHR} BPM", style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          )).toList(),
        ],
      ),
    );
  }

  Widget _statText(String l, String v) => Column(children: [Text(l, style: const TextStyle(fontSize: 11, color: Colors.white60)), Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.cyanAccent))]);
}
