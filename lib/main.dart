import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면을 길게 보여주기 위한 3초 지연
  await Future.delayed(const Duration(seconds: 3));
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
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = []; 
  double _timerCounter = 0;

  // 워치 연결 버튼: 권한 요청 후 설정 화면으로 이동
  Future<void> _handleWatchConnection() async {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location
    ].request();
    
    // 설정 화면으로 직접 이동 (사용자가 직접 권한을 켜도록 안내)
    await openAppSettings(); 
    
    setState(() {
      _isWatchConnected = true;
      _heartRate = 70; // 연결 후 초기값
    });
    _startWatchDataStream();
  }

  // 0.5초 단위의 디테일한 데이터 스트림
  void _startWatchDataStream() {
    Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted || !_isWatchConnected) {
        t.cancel();
        return;
      }
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 90 + Random().nextInt(50);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0); // 촘촘한 그래프 유지
          if (_heartRate >= 90) _calories += 0.04;
          _timerCounter += 0.5;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  void _toggleWorkout() {
    if (!_isWatchConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('워치를 먼저 연결해주세요!'))
      );
      return;
    }
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white54)),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 14, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                    label: Text(_isWatchConnected ? "워치 데이터 수신 중" : "권한 설정 및 워치 연결", style: const TextStyle(fontSize: 11)),
                    onPressed: _handleWatchConnection,
                    backgroundColor: Colors.black.withOpacity(0.6),
                  ),
                ),

                // 그래프: 50% 이상 축소 및 정교한 선 디자인
                Container(
                  height: MediaQuery.of(context).size.height * 0.12, 
                  margin: const EdgeInsets.symmetric(horizontal: 50),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(10)),
                  child: LineChart(LineChartData(
                    minY: 60, maxY: 160,
                    lineBarsData: [LineChartBarData(
                      spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots,
                      isCurved: true, curveSmoothness: 0.5,
                      color: Colors.cyanAccent.withOpacity(0.8),
                      barWidth: 1.5, // 얇은 선으로 디테일 강조
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, gradient: LinearGradient(
                        colors: [Colors.cyanAccent.withOpacity(0.2), Colors.transparent],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      ))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 하단 데이터 수치
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 50),
                  child: GridView.count(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2, childAspectRatio: 3.5,
                    children: [
                      _tile('심박수', '$_heartRate BPM', Icons.favorite, Colors.redAccent),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _heartRate >= 90 ? '고강도' : '안정', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 블랙 그라데이션 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, top: 15),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, () {}),
                      _btn('기록 보기', Icons.history, () {}),
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
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 10), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 9, color: Colors.white38))]),
    Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 85, height: 48,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(colors: [Color(0xFF333333), Color(0xFF000000)]), border: Border.all(color: Colors.white10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 14, color: Colors.white), Text(l, style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
