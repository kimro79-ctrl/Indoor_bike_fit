import 'package:flutter/material.dart';
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
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({Key? key}) : super(key: key);

  // 버튼 클릭 시 작동할 메시지 함수
  void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.png', fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.black)),
          ),
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 50),
                  child: Text('OVER THE BIKE FIT', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                Container(
                  padding: const EdgeInsets.only(bottom: 50),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _menuButton(context, Icons.bluetooth, '연결', () => _showNotice(context, '블루투스 기기 검색 중...')),
                      _menuButton(context, Icons.play_circle_fill, '시작', () => _showNotice(context, '운동 측정을 시작합니다.')),
                      _menuButton(context, Icons.history, '기록', () => _showNotice(context, '이전 기록을 불러옵니다.')),
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

  Widget _menuButton(BuildContext context, IconData icon, String label, VoidCallback action) {
    return Column(
      children: [
        IconButton(icon: Icon(icon, size: 40, color: Colors.blue), onPressed: action),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}
