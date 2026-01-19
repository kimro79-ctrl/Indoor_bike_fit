import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

void main() {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const BikeFitApp());
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
  List<double> heartPoints = List.generate(45, (index) => 0.0);
  
  // 운동 기록 저장용 리스트
  static List<Map<String, String>> workoutLogs = [];
  
  BluetoothDevice? connectedDevice;
  StreamSubscription? hrSubscription;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () => FlutterNativeSplash.remove());
  }

  // 워치 연동 로직 강화 (갤럭시워치, 어메이즈핏 대응)
  void _connectWatch() async {
    setState(() => watchStatus = "기기 검색 중...");
    
    // 블루투스 권한 및 상태 확인
    if (await FlutterBluePlus.isSupported == false) return;

    // 스캔 시작 (심박수 표준 서비스 UUID: 180d)
    await FlutterBluePlus.startScan(
      withServices: [Guid("180d")], 
      timeout: const Duration(seconds: 10),
      androidUsesFineLocation: true,
    );

    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        // 기기 이름이 있거나 심박수 서비스를 제공하는 기기 선택
        if (connectedDevice == null && r.device.platformName.isNotEmpty) {
          await FlutterBluePlus.stopScan();
          _establishConnection(r.device);
          break;
        }
      }
    });
  }

  void _establishConnection(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      setState(() { 
        connectedDevice = device; 
        watchStatus = "${device.platformName} 연결됨"; 
      });

      List<BluetoothService> services = await device.discoverServices();
      for (var service in services) {
        if (service.uuid == Guid("180d")) {
          for (var char in service.characteristics) {
            if (char.uuid == Guid("2a37")) {
              await char.setNotifyValue(true);
              hrSubscription = char.lastValueStream.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() {
                    bpm = value[1];
                    heartPoints.add(bpm.toDouble());
                    heartPoints.removeAt(0);
                  });
                }
              });
            }
          }
        }
      }
    } catch (e) {
      setState(() => watchStatus = "연결 실패: 다시 시도");
    }
  }

  void _toggleWorkout() {
    setState(() {
      isRunning = !isRunning;
      if (isRunning) {
        workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => elapsedSeconds++));
      } else {
        workoutTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    hrSubscription?.cancel();
    workoutTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        // 배경 이미지 (가운데 희미한 자전거 이미지가 없는 깔끔한 배경 권장)
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(colors: [Colors.white, Colors.redAccent]).createShader(bounds),
                child: const Text("OVER THE BIKE FIT", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 6, fontStyle: FontStyle.italic)),
              ),
              
              GestureDetector(
                onTap: _connectWatch,
                child: Container(
                  margin: const EdgeInsets.only(top: 15),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    border: Border.all(color: connectedDevice != null ? Colors.greenAccent : Colors.redAccent.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.watch, size: 14, color: connectedDevice != null ? Colors.greenAccent : Colors.grey),
                    const SizedBox(width: 8),
                    Text(watchStatus, style: TextStyle(fontSize: 11, color: connectedDevice != null ? Colors.greenAccent : Colors.white)),
                  ]),
                ),
              ),

              const Spacer(),
              
              // [중앙부] 희미한 이미지 제거 및 심박수 데이터 강조
              if (bpm > 0) ...[
                Text("$bpm", style: const TextStyle(fontSize: 100, fontWeight: FontWeight.bold, color: Colors.white)),
                const Text("BPM", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, letterSpacing: 5)),
                const SizedBox(height: 30),
                SizedBox(height: 60, width: 250, child: CustomPaint(painter: MiniNeonPainter(heartPoints))),
              ] else ...[
                const Text("READY", style: TextStyle(fontSize: 40, fontWeight: FontWeight.w100, color: Colors.white24, letterSpacing: 10)),
              ],

              const Spacer(),

              // 정보 섹션
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                    Column(
                      children: [
                        const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 10)),
                        Row(
                          children: [
                            IconButton(onPressed: () => setState(() { if (targetMinutes > 1) targetMinutes--; }), icon: const Icon(Icons.remove_circle_outline, color: Colors.white54)),
                            Text("$targetMinutes분", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            IconButton(onPressed: () => setState(() { targetMinutes++; }), icon: const Icon(Icons.add_circle_outline, color: Colors.white54)),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // 하단 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 50),
                child: Row(
                  children: [
                    actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, _toggleWorkout),
                    const SizedBox(width: 10),
                    actionBtn("저장", Colors.green.withOpacity(0.7), () {
                      if (elapsedSeconds > 0) {
                        workoutLogs.add({
                          "date": "${DateTime.now().month}/${DateTime.now().day} ${DateTime.now().hour}:${DateTime.now().minute}",
                          "time": "${elapsedSeconds ~/ 60}분 ${elapsedSeconds % 60}초",
                          "bpm": bpm > 0 ? "$bpm" : "--"
                        });
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 기록이 저장되었습니다.")));
                        setState(() { isRunning = false; workoutTimer?.cancel(); elapsedSeconds = 0; });
                      }
                    }),
                    const SizedBox(width: 10),
                    actionBtn("기록", Colors.blueGrey, () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(logs: workoutLogs)));
                    }),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String label, String val, Color col) => Column(children: [Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)), const SizedBox(height: 10), Text(val, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: col))]);
  Widget actionBtn(String label, Color col, VoidCallback fn) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: col, padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: fn, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))));
}

// [신규] 기록 저장 화면
class HistoryScreen extends StatelessWidget {
  final List<Map<String, String>> logs;
  const HistoryScreen({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("운동 기록"), backgroundColor: Colors.black),
      body: logs.isEmpty 
        ? const Center(child: Text("저장된 기록이 없습니다."))
        : ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              return ListTile(
                leading: const Icon(Icons.history, color: Colors.redAccent),
                title: Text("${log['date']} 운동"),
                subtitle: Text("시간: ${log['time']} | 평균심박수: ${log['bpm']}"),
                trailing: const Icon(Icons.chevron_right),
              );
            },
          ),
    );
  }
}

class MiniNeonPainter extends CustomPainter {
  final List<double> points;
  MiniNeonPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.redAccent..strokeWidth = 2.0..style = PaintingStyle.stroke;
    final path = Path();
    final xStep = size.width / (points.length - 1);
    path.moveTo(0, size.height);
    for (int i = 0; i < points.length; i++) {
      double y = size.height - (points[i] * size.height / 200); // 심박수에 따른 높이 조절
      path.lineTo(i * xStep, y);
    }
    canvas.drawPath(path, paint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
