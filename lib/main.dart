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
  // 데이터 변수
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  
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

  // 데이터 로드/저장 로직 (생략 - 기존과 동일)
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

  // 워치 연결 팝업 (사진의 '워치 연결' 버튼 대응)
  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    // ... (블루투스 연결 로직 동일)
    setState(() { _isWatchConnected = true; }); // 테스트용 강제 활성화
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (사진 9번의 붉은 배경)
          Positioned.fill(
            child: Image.asset(
              'assets/background.png', 
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black), // 파일 없을 때 대비
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),
                // 2. 상단 헤더 (타이틀 + 워치 연결 버튼)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Indoor bike fit', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                      ElevatedButton(
                        onPressed: _connectWatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black45,
                          side: const BorderSide(color: Colors.cyanAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))
                        ),
                        child: Text(_isWatchConnected ? "연결됨" : "워치 연결", style: const TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(flex: 2),

                // 3. 메인 데이터 박스 (심박수, 평균, 칼로리, 시간 - 사진 9번 중앙)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25),
                  padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 15),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatColumn("심박수", "$_heartRate", Colors.greenAccent),
                      _buildStatColumn("평균", "$_avgHeartRate", Colors.redAccent),
                      _buildStatColumn("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _buildStatColumn("시간", _formatDuration(_duration), Colors.blueAccent),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // 4. 하단 4단 버튼 (시작, 리셋, 저장, 기록 - 사진 9번 하단)
                Padding(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(Icons.play_arrow, "시작", () { 
                        setState(() { _isWorkingOut = !_isWorkingOut; });
                      }),
                      _buildActionButton(Icons.refresh, "리셋", () { /* 리셋 로직 */ }),
                      _buildActionButton(Icons.save, "저장", () { /* 저장 로직 */ }),
                      _buildActionButton(Icons.calendar_month, "기록", () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const HistoryScreen()));
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

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24)
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  String _formatDuration(Duration d) => "${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// 5. 기록 리포트 화면 (사진 10번 대응)
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // 일간/주간/월간 탭 UI 생략 (단순화)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildHistoryItem("6 kcal 소모", "2분 / 88 bpm"),
                _buildHistoryItem("90 kcal 소모", "10분 / 117 bpm"),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHistoryItem(String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Row(
        children: [
          const Icon(Icons.directions_bike, color: Colors.blue),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black)),
              Text(subtitle, style: const TextStyle(color: Colors.grey)),
            ],
          )
        ],
      ),
    );
  }
}
