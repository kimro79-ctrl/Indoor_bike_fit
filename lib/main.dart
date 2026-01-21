import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
  await Future.delayed(const Duration(milliseconds: 2500));
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
  int targetMinutes = 20;
  int elapsedSeconds = 0;
  bool isRunning = false;
  String watchStatus = "탭하여 워치 연결";
  List<FlSpot> heartRateSpots = [];
  List<Map<String, dynamic>> workoutLogs = [];
  double totalCalories = 0.0;

  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  StreamSubscription? scanSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('workoutLogs');
    if (data != null) {
      setState(() => workoutLogs = List<Map<String, dynamic>>.from(jsonDecode(data)));
    }
  }

  // 칼로리 로직: 심박수 90 이상일 때만 소모량 계산
  double _calculateCalories(int currentBpm) {
    if (currentBpm < 90) return 0.0;
    return (currentBpm - 80) * 0.0018; 
  }

  void _startScan() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    setState(() => watchStatus = "워치 탐색 중...");
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    } catch (e) {
      setState(() => watchStatus = "블루투스 확인 필요");
      return;
    }
    scanSubscription?.cancel();
    scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String name = r.device.platformName.toLowerCase();
        if (name.contains("watch") || name.contains("fit") || name.contains("amazfit") || 
            r.advertisementData.serviceUuids.contains(Guid("180d"))) {
          FlutterBluePlus.stopScan();
          _connectToDevice(r.device);
          break;
        }
      }
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() { connectedDevice = device; watchStatus = "연결됨: ${device.platformName}"; });
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid == Guid("180d")) {
          for (var c in s.characteristics) {
            if (c.uuid == Guid("2a37")) {
              await c.setNotifyValue(true);
              hrSubscription?.cancel();
              hrSubscription = c.lastValueStream.listen((value) {
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
    } catch (e) { setState(() => watchStatus = "연결 실패"); }
  }

  @override
  Widget build(BuildContext context) {
    const Color neonColor = Color(0xFF00E5FF);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic)),
              
              GestureDetector(
                onTap: _startScan,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(border: Border.all(color: neonColor.withOpacity(0.4)), borderRadius: BorderRadius.circular(12)),
                  child: Text(watchStatus, style: const TextStyle(fontSize: 9, color: neonColor)),
                ),
              ),

              // 심박수 영역 (콤팩트 레이아웃)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 5),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15)),
                child: Row(
                  children: [
                    Column(children: [
                      const Text("BPM", style: TextStyle(fontSize: 8, color: Colors.white54)),
                      Text("${bpm > 0 ? bpm : '--'}", style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: neonColor)),
                    ]),
                    const SizedBox(width: 15),
                    Expanded(
                      child: SizedBox(height: 35, child: LineChart(LineChartData(
                        gridData: const FlGridData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(
                          spots: heartRateSpots.isEmpty ? [const FlSpot(0, 0)] : heartRateSpots,
                          isCurved: true, color: neonColor, barWidth: 1.5, dotData: const FlDotData(show: false),
                        )]
                      ))),
                    )
                  ],
                ),
              ),

              const Spacer(),

              // 하단 레이아웃 일렬 배치 (칼로리 | 운동시간 | 목표설정)
              Container(
                padding: const EdgeInsets.fromLTRB(15, 20, 15, 30),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black.withOpacity(0.95)])
                ),
                child: Column(children: [
                  Row(
                    children: [
                      _infoCell("칼로리", "${totalCalories.toStringAsFixed(1)} kcal", neonColor),
                      _vDivider(),
                      _infoCell("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.white),
                      _vDivider(),
                      _targetCell(),
                    ],
                  ),
                  const SizedBox(height: 25),
                  Row(children: [
                    _btn(isRunning ? "정지" : "시작", isRunning ? Colors.grey : Colors.redAccent, () {
                      setState(() {
                        isRunning = !isRunning;
                        if (isRunning) {
                          workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
                            setState(() {
                              elapsedSeconds++;
                              if (bpm >= 90) totalCalories += _calculateCalories(bpm);
                            });
                          });
                        } else { workoutTimer?.cancel(); }
                      });
                    }),
                    const SizedBox(width: 8),
                    _btn("저장", Colors.green, () async {
                      if (elapsedSeconds > 0) {
                        workoutLogs.insert(0, {
                          "date": "${DateTime.now().month}/${DateTime.now().day}",
                          "time": "${elapsedSeconds ~/ 60}분",
                          "avgBpm": "$bpm",
                          "kcal": totalCalories.toStringAsFixed(1)
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('workoutLogs', jsonEncode(workoutLogs));
                        setState(() { elapsedSeconds = 0; totalCalories = 0.0; heartRateSpots.clear(); isRunning = false; });
                        workoutTimer?.cancel();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록 저장됨")));
                      }
                    }),
                    const SizedBox(width: 8),
                    _btn("기록", Colors.blueGrey, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryPage(logs: workoutLogs)));
                    }),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCell(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(label, style: const TextStyle(fontSize: 8, color: Colors.white54)),
      const SizedBox(height: 3),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color), textAlign: TextAlign.center),
    ]),
  );

  Widget _targetCell() => Expanded(
    child: Column(children: [
      const Text("목표설정", style: TextStyle(fontSize: 8, color: Colors.white54)),
      const SizedBox(height: 2),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(onTap: () => setState(() => targetMinutes--), child: const Icon(Icons.remove, size: 14)),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text("$targetMinutes분", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
        GestureDetector(onTap: () => setState(() => targetMinutes++), child: const Icon(Icons.add, size: 14)),
      ]),
    ]),
  );

  Widget _vDivider() => Container(width: 1, height: 18, color: Colors.white10);

  Widget _btn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: f, child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))));
}

class HistoryPage extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  const HistoryPage({super.key, required this.logs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty ? const Center(child: Text("기록이 없습니다.")) : ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.directions_bike, color: Color(0xFF00E5FF)),
          title: Text("${logs[i]['date']} 운동 - ${logs[i]['kcal']} kcal"),
          subtitle: Text("시간: ${logs[i]['time']} | 심박: ${logs[i]['avgBpm']} BPM"),
        ),
      ),
    );
  }
}
