import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  // 스플래시 화면 유지 시작
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  
  runApp(const BikeFitApp());

  // 3초간 대기 후 스플래시 화면 제거
  await Future.delayed(const Duration(seconds: 3));
  FlutterNativeSplash.remove();
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({super.key});
  @override
  State<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int bpm = 0;
  int elapsedSeconds = 0;
  int targetMinutes = 20;
  bool isRunning = false;
  String watchStatus = "기기 자동 검색 중...";
  List<FlSpot> heartRateSpots = [];
  List<Map<String, dynamic>> workoutLogs = [];

  BluetoothDevice? connectedDevice;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    // 앱 실행 시 자동 연결 프로세스 시작
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) {
      setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
    }
  }

  // 에러 해결 1: _saveLog 함수 위치를 클래스 내부에 정확히 정의
  Future<void> _saveLog(Map<String, dynamic> log) async {
    final prefs = await SharedPreferences.getInstance();
    workoutLogs.insert(0, log);
    await prefs.setString('workout_history', json.encode(workoutLogs));
    setState(() {});
  }

  Future<void> _autoConnect() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _startAutoScan();
  }

  void _startAutoScan() async {
    setState(() => watchStatus = "워치 자동 연결 시도 중...");
    
    // 에러 해결 2: 최신 패키지 문법에 맞춰 연결된 기기 확인 방식 수정
    try {
      List<BluetoothDevice> connectedDevices = FlutterBluePlus.connectedDevices;
      for (var device in connectedDevices) {
        String name = device.platformName.toLowerCase();
        if (name.contains("watch") || name.contains("amazfit") || name.contains("galaxy")) {
          _establishConnection(device);
          return;
        }
      }
    } catch (e) {
      debugPrint("기기 확인 중 오류 발생");
    }

    // 주변 기기 검색 시작
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("watch") || name.contains("amazfit") || name.contains("galaxy")) {
          FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      setState(() {
        connectedDevice = device;
        watchStatus = "연결 완료: ${device.platformName}";
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) { // 심박수 서비스
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) { // 측정값 캐릭터리스틱
              await c.setNotifyValue(true);
              c.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartRateSpots.add(FlSpot(heartRateSpots.length.toDouble(), bpm.toDouble()));
                    if (heartRateSpots.length > 50) heartRateSpots.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패 (탭하여 재시도)");
    }
  }

  // --- UI 도우미 함수들 ---
  Widget _infoBox(String label, String value, Color color) {
    return Column(children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: color))
    ]);
  }

  Widget _targetBox() {
    return Column(children: [
      const Text("목표설정", style: TextStyle(fontSize: 11, color: Colors.grey)),
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(onPressed: () => setState(() => targetMinutes
