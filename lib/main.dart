import 'package:flutter/material.dart';

void main() {
  // 최신 엔진 연결을 위한 필수 코드
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BikeFitApp());
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key}); // 최신 super 파라미터 문법 사용

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bike Fit App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 배경색을 지정하여 이미지 로딩 전에도 에러가 보이지 않게 처리
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 배경 이미지 (이미지가 없어도 빌드는 되도록 에러 처리 포함)
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => 
                Container(color: Colors.black), // 이미지 없을 때 검정 배경
            ),
          ),
          // 2. 콘텐츠 레이어
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Text(
                    'OVER THE BIKE FIT',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                // 3. 하단 메뉴 버튼 (Row로 배치하여 겹침 방지)
                Container(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _menuButton(context, Icons.bluetooth, '연결'),
                      _menuButton(context, Icons.play_circle_fill, '시작'),
                      _menuButton(context, Icons.settings, '설정'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuButton(BuildContext context, IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(icon, size: 40, color: Colors.blue),
          onPressed: () {}, // 버튼 동작은 빌드 성공 후 추가
        ),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
