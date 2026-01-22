import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.delayed(const Duration(seconds: 4));
  runApp(const BikeFitApp());
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
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  List<String> _records = [];

  // 워치 연결 버튼 로직
  Future<void> _handleWatchConnection() async {
    await [Permission.bluetoothConnect, Permission.bluetoothScan, Permission.location].request();
    await openAppSettings(); 
    setState(() => _isWatchConnected = true);

    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) return;
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 105 + Random().nextInt(35);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _timerCounter += 0.5;
          _calories += 0.06;
        } else {
          _heartRate = 60 + Random().nextInt(10);
        }
      });
    });
  }

  // 시작/정지 버튼 (워치와 무관하게 작동)
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  // 저장 버튼
  void _saveData() {
    if (_duration.inSeconds < 1) return;
    String r = "${DateTime.now().toString().substring(5,16)} | ${_duration.inMinutes}분 | ${_calories.toStringAsFixed(1)}kcal";
    setState(() => _records.insert(0, r));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('기록이 저장되었습니다.')));
  }

  // 기록 보기 팝업
  void _showRecords() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('운동 기록'),
        backgroundColor: Colors.grey[900],
        content: SizedBox(
          width: double.maxFinite,
          height: 200,
          child: _records.isEmpty ? const Center(child: Text('기록이 없습니다.')) : ListView.builder(
            itemCount: _records.length,
            itemBuilder: (c, i) => ListTile(title: Text(_records[i], style: const TextStyle(fontSize: 12))),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: Colors.black))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 16, color: _isWatchConnected ? Colors.cyan : Colors.white),
                    label: Text(_isWatchConnected ? "워치 연동됨" : "권한 설정 및 워치 연결"),
                    onPressed: _handleWatchConnection,
                  ),
                ),
                Container(
                  height: 100,
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 160,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, barWidth: 2, color: Colors.cyanAccent.withOpacity(_isWatchConnected ? 1 : 0),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: _isWatchConnected, color: Colors.cyanAccent.withOpacity(0.1))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 3,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, Colors.red),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orange),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blue),
                      _tile('상태', _isWorkingOut ? '운동중' : '대기', Icons.bolt, Colors.amber),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, top: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, _saveData),
                      _btn('기록 보기', Icons.history, _showRecords),
                    ],
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _tile(String l, String v, IconData i, Color c) => Column(children: [
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 12), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white54))]),
    Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 90, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.black54, border: Border.all(color: Colors.white10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 18), Text(l, style: const TextStyle(fontSize: 10))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
