import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  int _maxHeartRate = 0;
  int _avgHeartRate = 0;
  int _totalHRSum = 0;
  int _hrCount = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  Timer? _watchTimer;
  
  // 상태 변수
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  
  List<FlSpot> _hrSpots = [];
  double _timerCounter = 0;
  String _watchStatus = "워치 연결";

  @override
  void dispose() {
    _workoutTimer?.cancel();
    _watchTimer?.cancel();
    super.dispose();
  }

  void _vibrate() => HapticFeedback.lightImpact();

  String _getHRStatus() {
    if (!_isWatchConnected) return "워치 연결 필요";
    if (!_isWorkingOut) return "대기 중...";
    if (_heartRate >= 160) return "최대 강도 🔥";
    if (_heartRate >= 140) return "무산소 구간 ⚡";
    if (_heartRate >= 120) return "지방 연소 ✨";
    return "웜업 중 🚲";
  }

  Color _getHeartRateColor() {
    if (!_isWatchConnected) return Colors.grey;
    if (_heartRate >= 160) return Colors.redAccent;
    if (_heartRate >= 140) return Colors.orangeAccent;
    if (_heartRate >= 120) return Colors.greenAccent;
    return Colors.cyanAccent;
  }

  // 워치 연결 시뮬레이션
  Future<void> _handleWatchConnection() async {
    _vibrate();
    // 권한 요청 (실제 앱에서는 필요)
    if (await Permission.bluetoothConnect.request().isGranted) {
      setState(() {
        _isWatchConnected = true;
        _watchStatus = "워치 연결됨";
        _heartRate = 70; // 연결 직후 초기값
      });
      _startHeartRateMonitoring();
    }
  }

  // 데이터 모니터링 로직
  void _startHeartRateMonitoring() {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      
      // [수정] 워치가 연결되어 있지 않으면 아무것도 하지 않음 (그래프 멈춤)
      if (!_isWatchConnected) return;

      setState(() {
        if (_isWorkingOut) {
          // 운동 중일 때 랜덤 심박수 생성
          _heartRate = 110 + Random().nextInt(60);
          
          if (_heartRate > _maxHeartRate) _maxHeartRate = _heartRate;
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;
          _calories += 0.08;
        } else {
          // 운동 중은 아니지만 연결은 되어 있을 때 (평온 심박수)
          _heartRate = 65 + Random().nextInt(10);
        }

        // 그래프용 데이터 추가 (연결 상태면 항상 그림)
        _timerCounter += 0.5;
        _hrSpots.add(FlSpot(_timerCounter, _heartRate.toDouble()));
        // 데이터가 너무 많아지면 앞부분 삭제 (부드러운 이동)
        if (_hrSpots.length > 60) _hrSpots.removeAt(0);
      });
    });
  }

  void _toggleWorkout() {
    _vibrate();
    // 워치 연결 안 되어 있으면 운동 시작 불가 알림
    if (!_isWatchConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("워치를 먼저 연결해주세요!"), duration: Duration(seconds: 1)));
      return;
    }

    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        // 운동 시작 시 초기화
        _totalHRSum = 0; _hrCount = 0; _avgHeartRate = 0;
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() => _duration += const Duration(seconds: 1));
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _saveWorkout() {
    _vibrate();
    if (_duration.inSeconds < 5) return;
    setState(() { _duration = Duration.zero; _calories = 0.0; _hrSpots.clear(); _timerCounter = 0; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다."), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    // 하단 버튼이 키보드나 오버플로우에 가려지지 않도록 SafeArea 사용 안 함 (Stack으로 직접 배치)
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경
          Positioned.fill(child: Opacity(opacity: 0.2, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container()))),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withOpacity(0.95)],
                ),
              ),
            ),
          ),

          // 2. 메인 콘텐츠 (스크롤 가능하게 변경하여 화면 작아도 OK)
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Text('Over The Bike Fit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Colors.white.withOpacity(0.9))),
                
                const SizedBox(height: 20),
                
                // [워치 연결 버튼]
                if (!_isWatchConnected)
                  GestureDetector(
                    onTap: _handleWatchConnection,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                        color: Colors.cyanAccent.withOpacity(0.1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.watch, color: Colors.cyanAccent, size: 18),
                          SizedBox(width: 8),
                          Text("워치 연결 터치", style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else
                  // 연결되었을 때 상태 표시
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth_connected, color: _getHeartRateColor(), size: 16),
                        const SizedBox(width: 5),
                        Text("$_watchStatus (${_heartRate} bpm)", style: TextStyle(color: _getHeartRateColor(), fontSize: 13)),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // [그래프] 위치 이동 & 사이즈 축소
                Text(_getHRStatus(), style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120, // 높이를 60 -> 120 정도로 (너무 작으면 안 보여서 적당히)
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LineChart(
                      LineChartData(
                        minY: 40, maxY: 200,
                        gridData: FlGridData(show: false),
                        titlesData: FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineTouchData: LineTouchData(enabled: false), // 터치 효과 끔
                        lineBarsData: [
                          LineChartBarData(
                            spots: _hrSpots.isEmpty ? [const FlSpot(0, 70)] : _hrSpots,
                            isCurved: true,
                            curveSmoothness: 0.35,
                            barWidth: 1.5, // 선 두께 얇게
                            color: _getHeartRateColor(),
                            dotData: FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [_getHeartRateColor().withOpacity(0.1), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                          )
                        ],
                      ),
                    ),
                  ),
                ),

                const Spacer(), // 남은 공간 밀어내기

                // [데이터 정보 창]
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataBox("평균 BPM", "$_avgHeartRate"),
                      _dataBox("최대 BPM", "$_maxHeartRate"),
                      _dataBox("칼로리", _calories.toStringAsFixed(0)),
                      _dataBox("시간", _formatDuration(_duration)),
                    ],
                  ),
                ),
                
                const SizedBox(height: 120), // 버튼 들어갈 자리 확보
              ],
            ),
          ),

          // 3. [수정] 하단 버튼 바 (Overflow 해결)
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Row(
              children: [
                // Expanded를 사용하여 화면 너비에 맞게 버튼 크기 자동 조절
                Expanded(
                  child: _actionBtn(
                    _isWorkingOut ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    _isWorkingOut ? "중지" : "시작",
                    _toggleWorkout,
                    _isWorkingOut ? Colors.redAccent : Colors.greenAccent
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionBtn(Icons.save_rounded, "저장", _saveWorkout, Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionBtn(Icons.history_rounded, "기록", (){}, Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataBox(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
    ],
  );

  // 버튼 위젯 (크기 유동적)
  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 55, // 버튼 높이
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.2),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
