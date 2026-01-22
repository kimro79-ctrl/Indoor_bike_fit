import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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
      theme: ThemeData(brightness: Brightness.dark),
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
  String _watchStatus = "워치 검색 중...";
  bool _isWorkingOut = false;

  @override
  void initState() {
    super.initState();
    _startWatchScan(); // 시작 버튼과 분리하여 즉시 실행
  }

  // 실제 워치 스캔 로직 (워치 공유 모드 필요)
  void _startWatchScan() async {
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          if (r.device.platformName.contains("Watch") || r.device.platformName.contains("Galaxy")) {
            setState(() => _watchStatus = "연결됨: ${r.device.platformName}");
          }
        }
      });
    } catch (e) {
      setState(() => _watchStatus = "블루투스를 확인하세요");
    }
  }

  @override
  Widget build(BuildContext context) {
    // 버튼과 배너의 동일한 배경색 (진한 반투명 블랙)
    final Color commonColor = Colors.black.withOpacity(0.4);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover),
          ),
          // 2. 배경과 조화되는 그라데이션 (하단 가독성)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.1), Colors.black.withOpacity(0.8)],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 10),
                const Text('Over The Bike Fit', 
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                
                const SizedBox(height: 15),

                // 3. 워치 검색창 (작고 상단 배치)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.watch, size: 14, color: Colors.cyanAccent),
                        const SizedBox(width: 8),
                        Text(_watchStatus, style: const TextStyle(fontSize: 10, color: Colors.white)),
                      ],
                    ),
                  ),
                ),

                const Spacer(), // 데이터를 하단으로 밀어냄

                // 4. 데이터 배너 (하단부, 더 흐리게, 크기 줄임)
                Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                  decoration: BoxDecoration(
                    color: commonColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _dataTile(Icons.favorite, "심박수", "$_heartRate", Colors.cyanAccent),
                      _dataTile(Icons.local_fire_department, "칼로리", "0.0", Colors.orangeAccent),
                      _dataTile(Icons.timer, "시간", "00:00", Colors.blueAccent),
                    ],
                  ),
                ),

                const SizedBox(height: 25),

                // 5. 조작 버튼 (사각형, 작게, 배너와 색상 동일)
                Padding(
                  padding: const EdgeInsets.only(bottom: 35),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _squareBtn(Icons.play_arrow, "시작", commonColor, () {
                        HapticFeedback.lightImpact();
                        setState(() => _isWorkingOut = !_isWorkingOut);
                      }),
                      const SizedBox(width: 15),
                      _squareBtn(Icons.save, "저장", commonColor, () {}),
                      const SizedBox(width: 15),
                      _squareBtn(Icons.bar_chart, "기록", commonColor, () {}),
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

  Widget _dataTile(IconData i, String l, String v, Color c) => Column(
    children: [
      Row(children: [Icon(i, size: 12, color: c), const SizedBox(width: 4), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white38))]),
      const SizedBox(height: 5),
      Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
    ],
  );

  Widget _squareBtn(IconData i, String l, Color bg, VoidCallback t) => Column(
    children: [
      InkWell(
        onTap: t,
        child: Container(
          width: 58, height: 58,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(i, size: 24, color: Colors.white70),
        ),
      ),
      const SizedBox(height: 6),
      Text(l, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4))),
    ],
  );
}
