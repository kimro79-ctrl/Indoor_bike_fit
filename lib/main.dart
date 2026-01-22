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
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  String _watchName = "Amazfit GTS2 mini";

  void _vibrate() => HapticFeedback.lightImpact();

  Future<void> _handleWatchConnection() async {
    _vibrate();
    if (await Permission.bluetoothConnect.request().isGranted) {
      setState(() => _isWatchConnected = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (바이크 네온 이미지)
          Positioned.fill(
            child: Opacity(
              opacity: 0.4, 
              child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container())
            )
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 20),
                
                // 상단 워치 상태 바 (사진 디자인)
                GestureDetector(
                  onTap: _handleWatchConnection,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 50),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                      color: Colors.black.withOpacity(0.3),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.search, size: 18, color: Colors.cyanAccent),
                        const SizedBox(width: 8),
                        Text(
                          _isWatchConnected ? "발견됨: $_watchName" : "워치 검색 중...",
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),

                // 중앙은 이미지가 보이도록 비워둠 (Spacer)
                const Spacer(),

                // 실시간 데이터 배너 (사진 디자인)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.symmetric(vertical: 25),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                    color: Colors.white.withOpacity(0.1),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataColumn("실시간", "$_heartRate", Colors.cyanAccent),
                      _dataColumn("평균", "$_avgHeartRate", Colors.redAccent),
                      _dataColumn("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataColumn("시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),

                // 하단 사각형 버튼 세트 (사진 디자인)
                Padding(
                  padding: const EdgeInsets.only(bottom: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _squareBtn(Icons.play_arrow, "시작", () => setState(() => _isWorkingOut = true)),
                      _squareBtn(Icons.save, "저장", () {}),
                      _squareBtn(Icons.bar_chart, "기록", () {}),
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

  // 데이터 컬럼 위젯
  Widget _dataColumn(String label, String value, Color color) => Column(
    children: [
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
    ],
  );

  // 사각형 조작 버튼 위젯
  Widget _squareBtn(IconData icon, String label, VoidCallback onTap) => Column(
    children: [
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 75,
          height: 75,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, size: 30, color: Colors.white),
        ),
      ),
      const SizedBox(height: 8),
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
    ],
  );

  String _formatDuration(Duration d) => 
    "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}
