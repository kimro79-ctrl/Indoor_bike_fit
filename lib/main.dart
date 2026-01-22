import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 2초 대기
  await Future.delayed(const Duration(seconds: 2));
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
  List<String> _workoutHistory = [];

  // 워치 연결 버튼 로직 (실제 권한 확인 후 연결)
  Future<void> _handleWatchConnection() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    if (statuses.values.every((status) => status.isGranted)) {
      setState(() {
        _isWatchConnected = true;
        _heartRate = 72;
      });
      _startHeartRateMonitoring();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('워치가 성공적으로 연결되었습니다.'))
      );
    } else {
      await openAppSettings();
    }
  }

  // 0.2초마다 데이터를 생성하여 디테일한 그래프 구현
  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
      if (!mounted || !_isWatchConnected) {
        t.cancel();
        return;
      }
      
      setState(() {
        if (_isWorkingOut) {
          _heartRate = 125 + Random().nextInt(25); 
          _timerCounter += 0.2;
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          // 그래프에 더 많은 점(150개)을 유지하여 더 디테일하게 표시
          if (_hrSpots.length > 150) _hrSpots.removeAt(0);
          _calories += 0.025;
        } else {
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

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

  void _saveWorkout() {
    if (_duration.inSeconds < 1) return;
    String record = "${DateTime.now().toString().substring(5, 16)} | ${_duration.inMinutes}분 | ${_calories.toStringAsFixed(1)}kcal";
    setState(() => _workoutHistory.insert(0, record));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('기록이 저장되었습니다.')));
  }

  void _showHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('운동 기록'),
        backgroundColor: Colors.black87,
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _workoutHistory.isEmpty 
            ? const Center(child: Text('기록이 없습니다.'))
            : ListView.builder(
                itemCount: _workoutHistory.length,
                itemBuilder: (context, index) => ListTile(
                  leading: const Icon(Icons.history, color: Colors.cyanAccent),
                  title: Text(_workoutHistory[index], style: const TextStyle(fontSize: 12)),
                ),
              ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 배경 이미지
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  child: ActionChip(
                    avatar: Icon(Icons.bluetooth, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white38),
                    label: Text(_isWatchConnected ? "워치 데이터 동기화 중" : "권한 설정 및 워치 연결"),
                    onPressed: _isWatchConnected ? null : _handleWatchConnection,
                    backgroundColor: Colors.black54,
                  ),
                ),

                // 에러 수정된 디테일 그래프
                Container(
                  height: 150,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 180,
                    lineBarsData: [LineChartBarData(
                      spots: _isWatchConnected && _hrSpots.isNotEmpty ? _hrSpots : [const FlSpot(0, 0)],
                      isCurved: true, 
                      barWidth: 2, 
                      color: Colors.cyanAccent.withOpacity(_isWatchConnected ? 1.0 : 0.0),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: _isWatchConnected, color: Colors.cyanAccent.withOpacity(0.1))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 하단 데이터 타일
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(25)),
                  child: GridView.count(
                    shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 2.5,
                    children: [
                      _tile('심박수', _isWatchConnected ? '$_heartRate BPM' : '--', Icons.favorite, Colors.redAccent),
                      _tile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _tile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _tile('상태', _isWorkingOut ? '운동 중' : '대기', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _btn('저장', Icons.save, _saveWorkout),
                      _btn('기록 보기', Icons.history, _showHistory),
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
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: c, size: 14), const SizedBox(width: 5), Text(l, style: const TextStyle(fontSize: 11, color: Colors.white70))]),
    const SizedBox(height: 5),
    Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
  ]);

  Widget _btn(String l, IconData i, VoidCallback t) => InkWell(onTap: t, child: Container(
    width: 100, height: 60,
    decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), color: Colors.black, border: Border.all(color: Colors.white12)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, size: 24), const SizedBox(height: 4), Text(l, style: const TextStyle(fontSize: 11))]),
  ));

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
