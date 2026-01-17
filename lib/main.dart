import 'package:flutter/material.dart';
import 'dart:async';

void main() {
  runApp(const OverTheBikeFit());
}

class OverTheBikeFit extends StatelessWidget {
  const OverTheBikeFit({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.red,
      ),
      home: const SplashScreen(),
    );
  }
}

// 1. 스플래시 화면 (네온 디자인 반영)
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            colors: [Color(0xFF4A0000), Colors.black],
            center: Alignment.center,
            radius: 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 네온 자전거 이미지 (기존 이미지 활용)
            Image.asset('assets/icon/bike_ui_dark.png', width: 200),
            const SizedBox(height: 40),
            const Text(
              'Over the Bike Fit',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.2,
                shadows: [
                  Shadow(color: Colors.red, blurRadius: 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 2. 홈 화면 (이미지 UI 재현)
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const Icon(Icons.arrow_back_ios_new, size: 20),
        title: const Text('홈 화면', style: TextStyle(fontSize: 18)),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // 심박수 섹션 (네온 테두리)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.red.withOpacity(0.5), width: 2),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(color: Colors.red.withOpacity(0.1), blurRadius: 10),
                ],
              ),
              child: Row(
                children: [
                  Image.asset('assets/icon/heart.png', width: 40),
                  const SizedBox(width: 15),
                  const Text('신박수', style: TextStyle(fontSize: 18, color: Colors.white70)),
                  const Spacer(),
                  const Text(
                    '98 bpm',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.redAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            // 중앙 자전거 아이콘
            Expanded(
              child: Center(
                child: Opacity(
                  opacity: 0.8,
                  child: Image.asset('assets/icon/bike_ui_dark.png', width: 250),
                ),
              ),
            ),
            // 기록 섹션 (운동시간, 목표)
            Row(
              children: [
                _buildInfoCard('운동시간', '00:15', Icons.access_time, Colors.orangeAccent),
                const SizedBox(width: 15),
                _buildInfoCard('목표', '20분', Icons.flag, Colors.white),
              ],
            ),
            const SizedBox(height: 30),
            // 하단 컨트롤 버튼
            Row(
              children: [
                _buildActionButton('정지', Colors.red.shade900),
                const SizedBox(width: 10),
                _buildActionButton('리셋', Colors.grey.shade800),
                const SizedBox(width: 10),
                _buildActionButton('저장', const Color(0xFF0F3D0F)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // 정보 카드 위젯
  Widget _buildInfoCard(String title, String value, IconData icon, Color valColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: Colors.white54),
                const SizedBox(width: 5),
                Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: valColor),
            ),
          ],
        ),
      ),
    );
  }

  // 하단 버튼 위젯
  Widget _buildActionButton(String label, Color color) {
    return Expanded(
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
