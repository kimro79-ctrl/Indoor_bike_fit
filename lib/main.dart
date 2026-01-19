import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

void main() => runApp(const BikeFitApp());

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
  int bpm = 104;
  int targetMinutes = 21;
  int elapsedSeconds = 0;
  bool isRunning = false;
  List<double> heartPoints = List.generate(45, (index) => 25.0);
  Timer? dataTimer;
  Timer? workoutTimer;

  @override
  void initState() {
    super.initState();
    dataTimer = Timer.periodic(const Duration(milliseconds: 150), (t) {
      if (mounted) {
        setState(() {
          bpm = 102 + Random().nextInt(10);
          heartPoints.add(Random().nextDouble() * 45 + 5);
          heartPoints.removeAt(0);
        });
      }
    });
  }

  void toggleWorkout() {
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
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage("assets/background.png"), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Text("Over the Bike Fit", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 4)),
              
              // [개선] 배경과 녹아드는 그라데이션 배너
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
                padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.0), // 상단은 투명하게
                      Colors.red.withOpacity(0.15), // 중간에 붉은 안개 효과
                      Colors.black.withOpacity(0.8), // 하단은 다시 어둡게
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.favorite, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 15),
                      Text("$bpm bpm", style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                    ]),
                    const SizedBox(height: 25),
                    // [개선] 네온 스타일 곡선 그래프
                    SizedBox(
                      height: 90, 
                      width: double.infinity, 
                      child: CustomPaint(painter: NeonWavePainter(heartPoints))
                    ),
                  ],
                ),
              ),

              const Spacer(),
              
              // 하단 조작 패널
              Container(
                padding: const EdgeInsets.fromLTRB(30, 40, 30, 50),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.9),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(50)),
                ),
                child: Column(
                  children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      statUnit("운동시간", "${(elapsedSeconds ~/ 60).toString().padLeft(2, '0')}:${(elapsedSeconds % 60).toString().padLeft(2, '0')}", Colors.redAccent),
                      Container(width: 1, height: 35, color: Colors.white10),
                      targetUnit(),
                    ]),
                    const SizedBox(height: 40),
                    Row(children: [
                      actionBtn(isRunning ? "정지" : "시작", isRunning ? Colors.orange : Colors.redAccent, toggleWorkout),
                      const SizedBox(width: 15),
                      actionBtn("저장", Colors.green.withOpacity(0.8), () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("운동 데이터가 저장되었습니다.")));
                      }),
                    ]),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget statUnit(String t, String v, Color c) => Column(children: [Text(t, style: const TextStyle(color: Colors.grey, fontSize: 12)), Text(v, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c))]);
  Widget targetUnit() => Column(children: [
    const Text("목표시간", style: TextStyle(color: Colors.grey, fontSize: 12)),
    Row(children: [
      IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: () => setState(() => targetMinutes--)),
      Text("$targetMinutes분", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      IconButton(icon: const Icon(Icons.add, size: 20), onPressed: () => setState(() => targetMinutes++)),
    ])
  ]);
  Widget actionBtn(String t, Color c, VoidCallback f) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), onPressed: f, child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))));
}

// [개선] 네온 광택 효과를 가진 곡선 Painter
class NeonWavePainter extends CustomPainter {
  final List<double> points;
  NeonWavePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final glowPath = Path();
    final xStep = size.width / (points.length - 1);
    
    path.moveTo(0, size.height - points[0]);
    for (int i = 0; i < points.length - 1; i++) {
      var x1 = i * xStep;
      var y1 = size.height - points[i];
      var x2 = (i + 1) * xStep;
      var y2 = size.height - points[i + 1];
      path.cubicTo(x1 + (xStep / 2), y1, x1 + (xStep / 2), y2, x2, y2);
    }

    // 1. 하단 은은한 네온 광택 (Glow)
    final glowPaint = Paint()..color = Colors.redAccent.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 10.0..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawPath(path, glowPaint);

    // 2. 메인 샤프한 라인
    final linePaint = Paint()..color = Colors.redAccent..strokeWidth = 3.0..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
