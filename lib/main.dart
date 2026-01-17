import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const OverTheBikeFit());
}

class OverTheBikeFit extends StatelessWidget {
  const OverTheBikeFit({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      home: const CyclingHomeScreen(),
    );
  }
}

class CyclingHomeScreen extends StatefulWidget {
  const CyclingHomeScreen({super.key});

  @override
  State<CyclingHomeScreen> createState() => _CyclingHomeScreenState();
}

class _CyclingHomeScreenState extends State<CyclingHomeScreen> {
  bool isRunning = false;
  int seconds = 0;
  double heartRate = 98;
  List<FlSpot> hrPoints = [];
  int timerCount = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 10; i++) {
      hrPoints.add(FlSpot(i.toDouble(), 90 + Random().nextDouble() * 10));
    }
  }

  void toggleTimer() {
    setState(() {
      if (isRunning) {
        timer?.cancel();
        isRunning = false;
      } else {
        isRunning = true;
        timer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            seconds++;
            timerCount++;
            heartRate = 95 + Random().nextDouble() * 15;
            hrPoints.add(FlSpot(timerCount.toDouble() + 10, heartRate));
            if (hrPoints.length > 20) hrPoints.removeAt(0);
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/background.png'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildHeartRateCard(),
              const Expanded(child: SizedBox()),
              _buildInfoRow(),
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Text('CYCLE FIT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.redAccent)),
    );
  }

  Widget _buildHeartRateCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      height: 220,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("심박수 실시간 그래프", style: TextStyle(color: Colors.white70)),
              Text("${heartRate.toInt()} bpm", style: const TextStyle(fontSize: 24, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: hrPoints,
                    isCurved: true,
                    color: Colors.redAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(show: true, color: Colors.redAccent.withOpacity(0.2)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _infoBox('운동시간', _formatTime(seconds), Colors.redAccent),
          const SizedBox(width: 15),
          _infoBox('목표', '20분', Colors.white),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _btn(isRunning ? '정지' : '시작', isRunning ? Colors.red[900]! : Colors.red, toggleTimer),
          const SizedBox(width: 10),
          _btn('리셋', Colors.grey[800]!, () {
            timer?.cancel();
            setState(() { isRunning = false; seconds = 0; timerCount = 0; hrPoints.clear(); });
          }),
        ],
      ),
    );
  }

  Widget _infoBox(String t, String v, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(15)),
      child: Column(children: [Text(t, style: const TextStyle(color: Colors.white54)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]),
    ),
  );

  Widget _btn(String l, Color c, VoidCallback o) => Expanded(
    child: ElevatedButton(onPressed: o, style: ElevatedButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(vertical: 15)), child: Text(l)),
  );

  String _formatTime(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
}
