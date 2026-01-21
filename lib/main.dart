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

  // 워치 연결 로직 (이벤트 수정)
  Future<void> _handleConnect() async {
    setState(() => watchStatus = "권한 확인 중...");
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    
    setState(() => watchStatus = "워치를 찾는 중...");
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    FlutterBluePlus.scanResults.listen((results) {
      if (results.isNotEmpty) {
        FlutterBluePlus.stopScan();
        results.first.device.connect().then((_) {
          setState(() => watchStatus = "연결됨: ${results.first.device.platformName}");
        });
      }
    });
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
      builder: (context) => ListView.builder(
        itemCount: workoutLogs.length,
        itemBuilder: (context, i) => ListTile(
          title: Text(workoutLogs[i]['date'] ?? ""),
          subtitle: Text("시간: ${workoutLogs[i]['time']}"),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 40),
                    const Text("BIKE FIT", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                    IconButton(icon: const Icon(Icons.history, size: 30), onPressed: _showHistory),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              // 워치 연결 버튼
              GestureDetector(
                onTap: _handleConnect,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(border: Border.all(color: Colors.cyanAccent), borderRadius: BorderRadius.circular(20)),
                  child: Text(watchStatus, style: const TextStyle(color: Colors.cyanAccent)),
                ),
              ),
              const Spacer(),
              // 하단 UI: 검은 박스 제거하고 그라데이션 오버레이 느낌으로 수정
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(children: [
                          const Text("운동시간", style: TextStyle(color: Colors.white70)),
                          Text("${elapsedSeconds ~/ 60}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", 
                              style: const TextStyle(fontSize: 35, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                        ]),
                        Column(children: [
                          const Text("목표설정", style: TextStyle(color: Colors.white70)),
                          Row(children: [
                            IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => setState(() => targetMinutes--)),
                            Text("$targetMinutes분", style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => setState(() => targetMinutes++)),
                          ]),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 30),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            onPressed: () {
                              setState(() {
                                isRunning = !isRunning;
                                if (isRunning) workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
                                else workoutTimer?.cancel();
                              });
                            },
                            child: Text(isRunning ? "정지" : "시작", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            onPressed: () {}, // 저장 로직
                            child: const Text("저장", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
