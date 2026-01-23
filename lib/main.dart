import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

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
      home: const WorkoutScreen(),
    );
  }
}

// --- 메인 운동 화면 ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0; 
  int _avgHeartRate = 0;
  int _totalHRSum = 0;
  int _hrCount = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  
  BluetoothDevice? _targetDevice;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false; 
  List<FlSpot> _hrSpots = [const FlSpot(0, 0)];
  double _timeCounter = 0;

  // 워치 연결 로직 (권한 요청 포함)
  Future<void> _connectWatch() async {
    HapticFeedback.mediumImpact();
    // 권한 요청
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    FlutterBluePlus.scanResults.listen((results) async {
      for (ScanResult r in results) {
        // 이름에 'fit' 또는 'watch'가 포함되거나 심박 서비스 보유 기기 스캔
        if (r.device.platformName.toLowerCase().contains("fit") || 
            r.device.platformName.toLowerCase().contains("amazfit") ||
            r.advertisementData.serviceUuids.contains(Guid("180D"))) {
          
          _targetDevice = r.device;
          await FlutterBluePlus.stopScan();
          try {
            await _targetDevice!.connect();
            setState(() => _isWatchConnected = true);
            
            List<BluetoothService> services = await _targetDevice!.discoverServices();
            for (var service in services) {
              if (service.uuid == Guid("180D")) {
                for (var char in service.characteristics) {
                  if (char.uuid == Guid("2A37")) {
                    await char.setNotifyValue(true);
                    char.lastValueStream.listen((value) => _decodeHR(value));
                  }
                }
              }
            }
          } catch (e) { debugPrint("연결 오류: $e"); }
        }
      }
    });
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _totalHRSum += _heartRate;
          _hrCount++;
          _avgHeartRate = _totalHRSum ~/ _hrCount;
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
        }
      });
    }
  }

  void _toggleWorkout() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _duration += const Duration(seconds: 1);
            if (_isWatchConnected && _heartRate >= 95) {
              _calories += (_heartRate * 0.0015);
            }
          });
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.85, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (_,__,___)=>Container(color: Colors.black)))),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                const Text('Over The Bike Fit', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                const SizedBox(height: 20),
                
                // 워치 연결 버튼
                GestureDetector(
                  onTap: _isWatchConnected ? null : _connectWatch,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20), 
                      border: Border.all(color: _isWatchConnected ? Colors.cyanAccent : Colors.white24), 
                      color: Colors.black.withOpacity(0.5)
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.watch, size: 16, color: _isWatchConnected ? Colors.cyanAccent : Colors.white),
                      const SizedBox(width: 8),
                      Text(_isWatchConnected ? "연결됨: ${_targetDevice?.platformName}" : "워치 찾기 및 연결", style: const TextStyle(fontSize: 13)),
                    ]),
                  ),
                ),

                const SizedBox(height: 15),
                // 그래프
                SizedBox(
                  height: 40, 
                  width: double.infinity,
                  child: _hrSpots.length > 1 
                    ? LineChart(LineChartData(
                        minY: 40, maxY: 200, gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                        lineBarsData: [LineChartBarData(spots: _hrSpots, isCurved: true, barWidth: 2, color: Colors.cyanAccent, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.cyanAccent.withOpacity(0.2)))]
                      ))
                    : const Center(child: Text("데이터 대기 중...", style: TextStyle(fontSize: 10, color: Colors.white24))),
                ),

                const Spacer(),
                
                // 데이터 보드
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 25), padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(30), color: Colors.black.withOpacity(0.7), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.favorite, "실시간 심박", _isWatchConnected ? "$_heartRate" : "--", Colors.cyanAccent),
                      _dataItem(Icons.analytics, "평균 심박수", _isWatchConnected ? "$_avgHeartRate" : "--", Colors.redAccent),
                    ]),
                    const SizedBox(height: 30),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _dataItem(Icons.local_fire_department, "소모 칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                      _dataItem(Icons.timer, "운동 시간", _formatDuration(_duration), Colors.blueAccent),
                    ]),
                  ]),
                ),
                
                const SizedBox(height: 40),

                // 하단 버튼
                Padding(
                  padding: const EdgeInsets.only(bottom: 40),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, _isWorkingOut ? "중지" : "시작", _toggleWorkout),
                    _actionBtn(Icons.file_upload_outlined, "저장", () {}),
                    _actionBtn(Icons.bar_chart, "기록", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => HistoryScreen(avgHR: _avgHeartRate, calories: _calories, duration: _duration, hrSpots: _hrSpots)));
                    }),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataItem(IconData icon, String label, String value, Color color) => Column(children: [
    Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 5), Text(label, style: const TextStyle(fontSize: 11, color: Colors.white60))]),
    const SizedBox(height: 8),
    Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  ]);

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) => Column(children: [
    GestureDetector(onTap: onTap, child: Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(18)), child: Icon(icon, size: 28))),
    const SizedBox(height: 10),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
  ]);

  String _formatDuration(Duration d) => "${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}";
}

// --- 운동 기록 상세 페이지 ---
class HistoryScreen extends StatelessWidget {
  final int avgHR;
  final double calories;
  final Duration duration;
  final List<FlSpot> hrSpots;

  const HistoryScreen({Key? key, required this.avgHR, required this.calories, required this.duration, required this.hrSpots}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text("운동 결과 리포트"), backgroundColor: Colors.transparent, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              height: 250, width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
              child: LineChart(LineChartData(
                minY: 40, maxY: 200,
                lineBarsData: [LineChartBarData(spots: hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 3, dotData: const FlDotData(show: false))],
                titlesData: const FlTitlesData(show: false), gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
              )),
            ),
            const SizedBox(height: 30),
            _resultTile("총 소모 칼로리", "${calories.toStringAsFixed(1)} kcal", Icons.local_fire_department, Colors.orangeAccent),
            _resultTile("평균 심박수", "$avgHR BPM", Icons.analytics, Colors.redAccent),
            _resultTile("총 운동 시간", "${duration.inMinutes}분 ${duration.inSeconds % 60}초", Icons.timer, Colors.blueAccent),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(String t, String v, IconData i, Color c) => Container(
    margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(15)),
    child: Row(children: [
      Icon(i, color: c, size: 30), const SizedBox(width: 20),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t, style: const TextStyle(color: Colors.white60, fontSize: 14)),
        Text(v, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    ]),
  );
}
