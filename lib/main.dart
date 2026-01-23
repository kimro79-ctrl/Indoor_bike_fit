import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

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
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
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
          item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']),
        )).toList();
      });
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
          if (_heartRate >= 100) _calories += (_heartRate * 0.012 * (1/60));
        }
      });
    }
  }

  // --- UI 구성 요소 ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.4, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container()))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('OVER THE BIKE FIT', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.cyanAccent, letterSpacing: 2)),
                const SizedBox(height: 15),
                
                // 워치 연결 버튼 (작게 변경)
                _smallRoundedBtn(_isWatchConnected ? "CONNECTED" : "CONNECT WATCH", _isWatchConnected ? Colors.cyanAccent : Colors.white, _connectWatch),
                
                // 📈 실시간 그래프 (워치 연결 아래, 작고 길게)
                Container(
                  height: 60,
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(10)),
                  child: LineChart(
                    LineChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: const FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _hrSpots,
                          isCurved: true,
                          color: Colors.cyanAccent,
                          barWidth: 2,
                          isStrokeCapRound: true,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1)),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(),
                
                // 📊 데이터 배너 (크기 1/2로 축소)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _compactStat("HR", "$_heartRate", Colors.cyanAccent),
                      _verticalDivider(),
                      _compactStat("AVG", "$_avgHeartRate", Colors.redAccent),
                      _verticalDivider(),
                      _compactStat("KCAL", _calories.toStringAsFixed(0), Colors.orangeAccent),
                      _verticalDivider(),
                      _compactStat("TIME", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                    ],
                  ),
                ),

                const Spacer(),

                // 🔘 하단 버튼들 (모서리 둥근 사각형으로 작게)
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _rectBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "START", _toggleWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.refresh, "RESET", _resetWorkout),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.save, "SAVE", _saveRecord),
                      const SizedBox(width: 15),
                      _rectBtn(Icons.bar_chart, "REPORT", () {
                        Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)));
                      }),
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

  Widget _smallRoundedBtn(String txt, Color color, VoidCallback tap) => GestureDetector(
    onTap: tap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(txt, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    ),
  );

  Widget _compactStat(String label, String val, Color color) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54)),
      Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
    ],
  );

  Widget _verticalDivider() => Container(height: 20, width: 1, color: Colors.white10);

  Widget _rectBtn(IconData icon, String label, VoidCallback tap) => GestureDetector(
    onTap: tap,
    child: Column(
      children: [
        Container(
          width: 50, height: 50,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54, fontWeight: FontWeight.bold)),
      ],
    ),
  );

  // --- 기존 연결 로직 유지 ---
  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(context: context, builder: (c) => StreamBuilder<List<ScanResult>>(
      stream: FlutterBluePlus.scanResults,
      builder: (c, s) {
        final res = (s.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
        return ListView.builder(itemCount: res.length, itemBuilder: (c, i) => ListTile(title: Text(res[i].device.platformName), onTap: () async {
          await res[i].device.connect(); _setupDevice(res[i].device); Navigator.pop(context);
        }));
      },
    ));
  }
  
  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } }
  }

  void _toggleWorkout() {
    setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _duration += const Duration(seconds: 1))); } else { _workoutTimer?.cancel(); } });
  }

  void _resetWorkout() { if (!_isWorkingOut) setState(() { _duration = Duration.zero; _calories = 0.0; _hrSpots = [const FlSpot(0, 0)]; _timeCounter = 0; }); }

  void _saveRecord() async {
    if (_duration == Duration.zero) return;
    String date = DateFormat('MM/dd(E)', 'ko_KR').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(date, _avgHeartRate, _calories, _duration)); });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("SAVED!")));
  }
}

// --- 운동 보기 (History) 화면 ---
class HistoryScreen extends StatelessWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("WORKOUT REPORT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5)), backgroundColor: Colors.transparent),
      body: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: records.length,
        itemBuilder: (c, i) {
          final r = records[i];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
            child: Row(
              children: [
                const Icon(Icons.directions_bike, color: Colors.cyanAccent),
                const SizedBox(width: 15),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.date, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                  Text("${r.duration.inMinutes}min Workout", style: const TextStyle(fontWeight: FontWeight.bold)),
                ])),
                Text("${r.calories.toInt()} kcal", style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
              ],
            ),
          );
        },
      ),
    );
  }
}
