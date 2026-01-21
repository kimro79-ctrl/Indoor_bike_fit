import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  // 스플래시 3.5초로 약간 연장 (확실한 인지)
  await Future.delayed(const Duration(milliseconds: 3500));
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
  String watchStatus = "탭하여 워치 연결";
  Timer? workoutTimer;
  List<Map<String, dynamic>> workoutLogs = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('workout_history');
    if (data != null) setState(() => workoutLogs = List<Map<String, dynamic>>.from(json.decode(data)));
  }

  Future<void> _saveLog() async {
    if (elapsedSeconds < 5) return;
    final prefs = await SharedPreferences.getInstance();
    final log = {
      "date": "${DateTime.now().year}.${DateTime.now().month}.${DateTime.now().day}",
      "time": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초",
      "bpm": bpm > 0 ? "$bpm" : "-"
    };
    workoutLogs.insert(0, log);
    await prefs.setString('workout_history', json.encode(workoutLogs));
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다.")));
  }

  // 연결 시 설정 확인 및 권한 요청
  Future<void> _handleWatchConnection() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    await FlutterBluePlus.turnOn();
    setState(() => watchStatus = "기기 연결 확인 중...");
    
    // 이미 시스템에 연결된 워치가 있는지 먼저 체크
    List<BluetoothDevice> systemDevices = await FlutterBluePlus.connectedDevices;
    if (systemDevices.isNotEmpty) {
      _establishConnection(systemDevices.first);
    } else {
      // 없을 경우 스캔 시작
      FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.toLowerCase().contains("watch") || r.device.platformName.toLowerCase().contains("fit")) {
            FlutterBluePlus.stopScan();
            _establishConnection(r.device);
            break;
          }
        }
      });
    }
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() => watchStatus = "연결됨: ${device.platformName}");
    } catch (e) {
      setState(() => watchStatus = "연결 실패 (설정 확인)");
    }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text("운동 기록", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView.builder(
                itemCount: workoutLogs.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(workoutLogs[i]['date']),
                  subtitle: Text("시간: ${workoutLogs[i]['time']} | 심박수: ${workoutLogs[i]['bpm']}"),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover)),
        child: SafeArea(
          child: Column(children: [
            // 상단 바 정렬 및 기록 버튼 복구
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const SizedBox(width: 40),
                const Text("BIKE FIT", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, letterSpacing: 2)),
                IconButton(icon: const Icon(Icons.history, color: Colors.white, size: 30), onPressed: _showHistory),
              ]),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _handleWatchConnection,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(25)),
                child: Text(watchStatus, style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
            const Spacer(),
            // 가시성을 대폭 개선한 하단 패널
            Container(
              padding: const EdgeInsets.fromLTRB(30, 40, 30, 40),
              decoration: const BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.vertical(top: Radius.circular(40))),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  // 운동 시간 (비율 확대)
                  Expanded(child: Column(children: [
                    const Text("운동시간", style: TextStyle(fontSize: 14, color: Colors.white54)),
                    const SizedBox(height: 10),
                    Text("${elapsedSeconds ~/ 60}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", 
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                  ])),
                  Container(height: 50, width: 1, color: Colors.white10),
                  // 목표 설정 (비율 확대)
                  Expanded(child: Column(children: [
                    const Text("목표설정", style: TextStyle(fontSize: 14, color: Colors.white54)),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(icon: const Icon(Icons.remove_circle_outline, size: 24), onPressed: () => setState(() => targetMinutes--)),
                      Text("$targetMinutes분", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.add_circle_outline, size: 24), onPressed: () => setState(() => targetMinutes++)),
                    ]),
                  ])),
                ]),
                const SizedBox(height: 40),
                Row(children: [
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: isRunning ? Colors.grey[700] : Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                        else workoutTimer?.cancel();
                      });
                    }, child: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)))),
                  const SizedBox(width: 15),
                  Expanded(child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                    onPressed: _saveLog, child: const Text("저장", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)))),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
