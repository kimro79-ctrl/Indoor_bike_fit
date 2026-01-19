import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(OverTheBikeFitApp());

class OverTheBikeFitApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Over the Bike Fit",
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1A1A1A), // 딥그레이 배경
        colorScheme: const ColorScheme.dark(primary: Color(0xFFB30000)), // 딥레드 포인트
      ),
      home: const SplashScreen(),
    );
  }
}

// --- Splash 화면 ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset("assets/background.png", fit: BoxFit.cover),
          Container(color: Colors.black.withOpacity(0.6)),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  "Over the Bike Fit",
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB30000),
                    shadows: [
                      Shadow(blurRadius: 20, color: Colors.redAccent),
                    ],
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Indoor Cycling Tracker",
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- 홈 화면 ---
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int seconds = 0;
  int targetTime = 20 * 60;
  int heartRate = 75;
  bool running = false;
  Timer? timer;
  List<int> heartData = [];

  void startWorkout() {
    setState(() => running = true);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        seconds++;
        heartRate = 65 + Random().nextInt(40);
        heartData.add(heartRate);
        if (heartData.length > 40) heartData.removeAt(0);
      });
    });
  }

  void stopWorkout() {
    timer?.cancel();
    setState(() => running = false);
  }

  void resetWorkout() {
    timer?.cancel();
    setState(() {
      seconds = 0;
      heartData.clear();
      running = false;
    });
  }

  void addGoal() => setState(() => targetTime += 5 * 60);
  void subtractGoal() => setState(() {
        if (targetTime > 5 * 60) targetTime -= 5 * 60;
      });

  @override
  Widget build(BuildContext context) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, "0");
    final sec = (seconds % 60).toString().padLeft(2, "0");

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Image.asset("assets/icons/bike_ui_dark.png", width: 150),
              const SizedBox(height: 20),
              Text("$minutes:$sec",
                  style: const TextStyle(fontSize: 50, color: Colors.white)),
              const SizedBox(height: 10),
              Text("❤️ $heartRate bpm",
                  style: const TextStyle(
                      fontSize: 28, color: Color(0xFFB30000))),
              const SizedBox(height: 30),
              Expanded(child: _heartGraph()),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                      onPressed: subtractGoal,
                      icon: const Icon(Icons.remove_circle,
                          color: Colors.redAccent, size: 36)),
                  Text("${targetTime ~/ 60}분 목표",
                      style:
                          const TextStyle(fontSize: 20, color: Colors.white)),
                  IconButton(
                      onPressed: addGoal,
                      icon: const Icon(Icons.add_circle,
                          color: Colors.redAccent, size: 36)),
                ],
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildButton("Start", running ? null : startWorkout),
                  _buildButton("Stop", running ? stopWorkout : null),
                  _buildButton("Reset", resetWorkout),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _heartGraph() {
    return CustomPaint(
      painter: HeartGraphPainter(heartData),
      child: Container(),
    );
  }

  Widget _buildButton(String label, VoidCallback? onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            onPressed != null ? const Color(0xFFB30000) : Colors.grey[700],
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        shadowColor: Colors.redAccent.withOpacity(0.5),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}

class HeartGraphPainter extends CustomPainter {
  final List<int> data;
  HeartGraphPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = const Color(0xFFB30000)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    final path = Path();
    final dx = size.width / (data.length - 1);
    for (int i = 0; i < data.length; i++) {
      final x = i * dx;
      final y = size.height - ((data[i] - 50) / 100 * size.height);
      if (i == 0) path.moveTo(x, y);
      else path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
