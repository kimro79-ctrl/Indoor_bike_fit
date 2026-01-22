import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;

  // 워치 연결 시뮬레이션 및 데이터 수신
  void _connectWatch() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스마트워치 연결을 시도합니다...')));
    // 실제 기기 연결 로직은 기기 UUID에 따라 다르므로 여기서는 데이터 수신 시뮬레이션을 수행합니다.
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) t.cancel();
      setState(() {
        // 실제로는 워치에서 받은 데이터를 여기에 넣습니다.
        _heartRate = 60 + (DateTime.now().second % 60); 
        if (_isWorkingOut) {
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 20) _hrSpots.removeAt(0);
          
          // 심박수 90 이상일 때만 칼로리 소모 계산 (간이 공식)
          if (_heartRate >= 90) {
            _calories += 0.05; 
          }
        }
      });
    });
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            _timerCounter++;
          });
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
          Positioned.fill(child: Image.asset('assets/background.png', fit: BoxFit.cover, 
            errorBuilder: (_,__,___) => Container(color: Colors.black))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                const Text('BIKE FIT RECORD', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                
                // 그래프 섹션
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: LineChart(LineChartData(
                      lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, color: Colors.redAccent)],
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                    )),
                  ),
                ),

                // 데이터 섹션
                Expanded(
                  flex: 2,
                  child: GridView.count(
                    crossAxisCount: 2,
                    childAspectRatio: 1.5,
                    children: [
                      _dataTile('심박수', '$_heartRate BPM', Icons.favorite, Colors.red),
                      _dataTile('소모 칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orange),
                      _dataTile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blue),
                      _dataTile('상태', _heartRate >= 90 ? '고강도' : '저강도', Icons.speed, Colors.green),
                    ],
                  ),
                ),

                // 버튼 섹션
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _actionButton('워치 연결', Icons.watch, _connectWatch),
                      _actionButton(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _actionButton('저장', Icons.save, () => _showDialog('기록 저장', '현재까지의 기록이 저장되었습니다.')),
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

  Widget _dataTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.7)),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
  void _showDialog(String title, String content) => showDialog(context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(content), actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('확인'))]));
}
