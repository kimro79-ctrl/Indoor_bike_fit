import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:table_calendar/table_calendar.dart';

void main() => runApp(const BikeFitApp());

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
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
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  Duration _duration = Duration.zero;
  Timer? _timer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  // 앱 실행 시 권한 요청
  Future<void> _initApp() async {
    await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.sensors,
      Permission.location,
    ].request();
  }

  // 시작/중지 버튼 로직
  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            // 심박수 85 이상일 때만 칼로리 계산 (시뮬레이션 포함)
            if (_isWatchConnected && _heartRate >= 85) {
              _calories += (_heartRate * 0.0005);
            }
          });
        });
      } else {
        _timer?.cancel();
      }
    });
  }

  // 리셋 로직
  void _reset() {
    _timer?.cancel();
    setState(() {
      _isWorkingOut = false;
      _duration = Duration.zero;
      _calories = 0.0;
      _heartRate = 0;
      _avgHeartRate = 0;
      _hrSpots = [const FlSpot(0, 0)];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/background.png'), // 배경 이미지
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeaderAndGraph(), // 타이틀 + 그래프 결합 섹션
              const Spacer(flex: 2),
              _buildDataPanel(),      // 심박수/평균/칼로리/시간
              const Spacer(flex: 1),
              _buildBottomButtons(),  // 하단 버튼부
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 1. 상단 타이틀 및 바로 아래 작은 그래프
  Widget _buildHeaderAndGraph() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Indoor bike fit", 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
              _buildConnectButton(),
            ],
          ),
          const SizedBox(height: 10),
          // 타이틀 바로 아래 위치한 작은 그래프
          Container(
            height: 80, // 크기를 작게 조절
            width: double.infinity,
            padding: const EdgeInsets.only(top: 10),
            child: _isWatchConnected 
              ? LineChart(_smallChartData()) 
              : const Center(child: Text("워치를 연결하면 그래프가 표시됩니다.", 
                  style: TextStyle(color: Colors.white24, fontSize: 12))),
          ),
        ],
      ),
    );
  }

  // 2. 데이터 판넬 (4개 항목 가로 정렬)
  Widget _buildDataPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _dataItem("심박수", "$_heartRate", Colors.greenAccent),
          _dataItem("평균", "$_avgHeartRate", Colors.redAccent),
          _dataItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
          _dataItem("운동시간", _formatDuration(_duration), Colors.blueAccent),
        ],
      ),
    );
  }

  // 3. 하단 버튼부
  Widget _buildBottomButtons() {
    return Row
