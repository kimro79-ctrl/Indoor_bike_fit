import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 스플래시 화면을 조금 더 길게 유지하기 위한 지연 (3초)
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
  List<FlSpot> _hrSpots = [const FlSpot(0, 70)];
  double _timerCounter = 0;

  @override
  void initState() {
    super.initState();
    _startBackgroundDataStream(); // 앱 시작 시 기본 데이터 흐름 시작
  }

  // 1. 권한 설정 버튼 기능 (직접 설정창으로 이동 및 권한 요청)
  Future<void> _requestAndOpenSettings() async {
    // 블루투스 및 위치 권한 요청 팝업
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();

    // 사용자가 설정을 직접 바꿀 수 있도록 시스템 설정창 열기
    if (statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied)) {
      await openAppSettings(); 
    } else {
      setState(() => _isWatchConnected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('워치 연결 권한이 허용되었습니다.'))
      );
    }
  }

  // 워치 연결 없이도 심박수가 시뮬레이션되도록 설정
  void _startBackgroundDataStream() {
    Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) t.cancel();
      setState(() {
        if (_isWorkingOut) {
          // 운동 중에는 더 역동적으로 변화
          _heartRate = 85 + Random().nextInt(40);
          _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 20) _hrSpots.removeAt(0);
          if (_heartRate >= 90) _calories += 0.08;
        } else {
          // 평상시
          _heartRate = 65 + Random().nextInt(10);
        }
      });
    });
  }

  // 워치 연결 없이도 시작/저장 가능
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() { _duration += const Duration(seconds: 1); _timerCounter++; });
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
                const SizedBox(height: 15),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white70)),
                
                // 권한 설정 및 워치 연결 버튼
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: ActionChip(
                    avatar: Icon(Icons.settings_bluetooth, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                    label: Text(_isWatchConnected ? "워치 연동 중" : "권한 설정 및 워치 연결"),
                    onPressed: _requestAndOpenSettings,
                    backgroundColor: Colors.black.withOpacity(0.5),
                  ),
                ),

                // 2. 그래프 크기 1/2로 대폭 축소
                Container(
                  height: MediaQuery.of(context).size.height * 0.15, // 기존 0.22 -> 0.15로 축소
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LineChart(LineChartData(
                    minY: 50, maxY: 150,
                    lineBarsData: [LineChartBarData(
                      spots: _hrSpots, isCurved: true, 
                      color: Colors.cyanAccent, barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.1))
                    )],
                    titlesData: const FlTitlesData(show: false),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                  )),
                ),

                const Spacer(),

                // 3. 데이터 타일 (버튼 바로 위)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 3.0,
                    children: [
                      _compactTile('심박수', '$_heartRate BPM', Icons.favorite, Colors.redAccent),
                      _compactTile('칼로리', '${_calories.toStringAsFixed(1)} kcal', Icons.local_fire_department, Colors.orangeAccent),
                      _compactTile('운동 시간', _formatDuration(_duration), Icons.timer, Colors.blueAccent),
                      _compactTile('상태', _heartRate >= 90 ? '고강도' : '안정', Icons.bolt, Colors.amberAccent),
                    ],
                  ),
                ),

                // 4. 하단 버튼 세트 (블랙 그라데이션)
                Padding(
                  padding: const EdgeInsets.only(bottom: 30, top: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _miniGradButton(_isWorkingOut ? '정지' : '시작', _isWorkingOut ? Icons.stop : Icons.play_arrow, _toggleWorkout),
                      _miniGradButton('저장', Icons.save, () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('데이터가 성공적으로 저장되었습니다.')));
                      }),
                      _miniGradButton('기록 보기', Icons.history, () {}),
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

  Widget _compactTile(String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 12),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _miniGradButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 90, height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: [Color(0xFF3A3A3A), Color(0xFF000000)]),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
