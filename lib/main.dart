import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:table_calendar/table_calendar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  runApp(const BikeFitApp());
}

class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSeconds': duration.inSeconds
  };
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: Colors.black),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({Key? key}) : super(key: key);
  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  BluetoothDevice? _targetDevice;
  bool _isConnected = false;
  List<ScanResult> _scanResults = [];
  
  int _currentHR = 0;
  List<int> _hrHistory = [];
  Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  double _calories = 0.0;
  double _weight = 70.0;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  }

  // --- 워치 스캔 팝업 (강화된 스캔 로직) ---
  void _showDeviceScanPopup() async {
    setState(() { _scanResults = []; });

    // 1. 이미 시스템에 페어링된 기기(갤럭시 워치 등) 먼저 스캔 리스트에 추가 시도
    List<BluetoothDevice> connectedSystemDevices = await FlutterBluePlus.connectedSystemDevices;
    
    // 2. 스캔 시작 (가장 강력한 lowLatency 모드 적용)
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
      androidUsesFineLocation: true,
      androidScanMode: AndroidScanMode.lowLatency, 
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          var subscription = FlutterBluePlus.scanResults.listen((results) {
            if (mounted) {
              setDialogState(() { _scanResults = results; });
            }
          });

          return AlertDialog(
            title: const Text("워치 검색 (심박수 센서)"),
            content: SizedBox(
              width: double.maxFinite,
              height: 300,
              child: _scanResults.isEmpty 
                ? const Center(child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [CircularProgressIndicator(), SizedBox(height: 10), Text("워치를 찾는 중..."),],
                  ))
                : ListView.builder(
                    itemCount: _scanResults.length,
                    itemBuilder: (context, index) {
                      final r = _scanResults[index];
                      final name = r.device.platformName.isEmpty ? "알 수 없는 기기" : r.device.platformName;
                      return ListTile(
                        leading: const Icon(Icons.watch),
                        title: Text(name),
                        subtitle: Text(r.device.remoteId.toString()),
                        onTap: () {
                          subscription.cancel();
                          FlutterBluePlus.stopScan();
                          _connectToDevice(r.device);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
            ),
            actions: [
              TextButton(onPressed: () {
                subscription.cancel();
                FlutterBluePlus.stopScan();
                Navigator.pop(context);
              }, child: const Text("닫기"))
            ],
          );
        }
      ),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      setState(() { _targetDevice = device; _isConnected = true; });
      _discoverServices(device);
    } catch (e) {
      debugPrint("연결 오류: $e");
    }
  }

  void _discoverServices(BluetoothDevice device) async {
    List<BluetoothService> services = await device.discoverServices();
    for (var service in services) {
      for (var characteristic in service.characteristics) {
        if (characteristic.properties.notify) {
          await characteristic.setNotifyValue(true);
          characteristic.lastValueStream.listen((value) {
            if (value.isNotEmpty && value.length > 1) {
              setState(() {
                _currentHR = value[1]; 
                if (_stopwatch.isRunning) {
                  _hrHistory.add(_currentHR);
                  _calculateCalories();
                }
              });
            }
          });
        }
      }
    }
  }

  void _calculateCalories() {
    if (_currentHR > 0) {
      double met = _currentHR > 120 ? 8.0 : 4.0; 
      setState(() {
        _calories += (met * 3.5 * _weight / 200) / 60; 
      });
    }
  }

  void _toggleWorkout() {
    setState(() {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _timer?.cancel();
        _saveRecord();
      } else {
        _hrHistory.clear();
        _calories = 0.0;
        _stopwatch.reset();
        _stopwatch.start();
        _timer = Timer.periodic(const Duration(seconds: 1), (timer) => setState(() {}));
      }
    });
  }

  Future<void> _saveRecord() async {
    if (_hrHistory.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final avg = _hrHistory.reduce((a, b) => a + b) ~/ _hrHistory.length;
    final record = WorkoutRecord(
      DateTime.now().millisecondsSinceEpoch.toString(),
      DateFormat('yyyy-MM-dd').format(DateTime.now()),
      avg,
      _calories,
      _stopwatch.elapsed
    );
    
    List<String> records = prefs.getStringList('records') ?? [];
    records.add(jsonEncode(record.toJson()));
    await prefs.setStringList('records', records);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("INDOOR BIKE FIT"),
        actions: [
          IconButton(
            icon: Icon(_isConnected ? Icons.watch_connected : Icons.watch),
            onPressed: _showDeviceScanPopup,
            color: _isConnected ? Colors.blue : Colors.white,
          )
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_isConnected ? "워치 연결됨: ${_targetDevice?.platformName}" : "워치를 연결해주세요", 
                 style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 40),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 250, height: 250,
                  child: CircularProgressIndicator(
                    value: _stopwatch.isRunning ? null : 0,
                    strokeWidth: 8,
                    color: Colors.blueAccent,
                  ),
                ),
                Column(
                  children: [
                    Text("$_currentHR", style: const TextStyle(fontSize: 80, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    const Text("BPM", style: TextStyle(fontSize: 18, color: Colors.grey)),
                  ],
                )
              ],
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _infoColumn("운동시간", _formatDuration(_stopwatch.elapsed)),
                _infoColumn("소모 칼로리", "${_calories.toStringAsFixed(1)} kcal"),
              ],
            ),
            const SizedBox(height: 60),
            ElevatedButton(
              onPressed: _isConnected ? _toggleWorkout : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _stopwatch.isRunning ? Colors.redAccent : Colors.blueAccent,
                minimumSize: const Size(220, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))
              ),
              child: Text(_stopwatch.isRunning ? "운동 종료" : "운동 시작", style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const RecordReport())),
              child: const Text("기록 리포트 및 통계 보기", style: TextStyle(color: Colors.blue)),
            )
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(d.inMinutes)}:${twoDigits(d.inSeconds.remainder(60))}";
  }

  Widget _infoColumn(String title, String value) {
    return Column(
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 5),
        Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
      ],
    );
  }
}

class RecordReport extends StatefulWidget {
  const RecordReport({Key? key}) : super(key: key);
  @override
  State<RecordReport> createState() => _RecordReportState();
}

class _RecordReportState extends State<RecordReport> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  List<WorkoutRecord> _currentRecords = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('records') ?? [];
    setState(() {
      _currentRecords = raw.map((s) {
        final m = jsonDecode(s);
        return WorkoutRecord(m['id'], m['date'], m['avgHR'], m['calories'].toDouble(), Duration(seconds: m['durationSeconds']));
      }).toList();
    });
  }

  // 데이터 시각화 보완: 차트 위젯 개선
  Widget _buildChart(List<WorkoutRecord> filtered) {
    if (filtered.isEmpty) return const SizedBox.shrink();
    double maxCal = filtered.map((e) => e.calories).reduce((a, b) => a > b ? a : b);
    
    return Container(
      height: 250,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("오늘의 칼로리 소모 추이", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                maxY: maxCal * 1.2,
                barGroups: List.generate(filtered.length, (i) => BarChartGroupData(
                  x: i, 
                  barRods: [BarChartRodData(toY: filtered[i].calories, color: Colors.blueAccent, width: 18, borderRadius: BorderRadius.circular(4))]
                )),
                titlesData: const FlTitlesData(show: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.blueGrey.withOpacity(0.8),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dailyRecords = _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        appBar: AppBar(title: const Text("기록 리포트")),
        body: SingleChildScrollView(
          child: Column(
            children: [
              TableCalendar(
                locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
                calendarStyle: const CalendarStyle(todayDecoration: BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle)),
              ),
              const Divider(),
              if (dailyRecords.isEmpty) 
                const Padding(padding: EdgeInsets.all(40), child: Text("선택한 날짜의 운동 기록이 없습니다.", style: TextStyle(color: Colors.grey)))
              else ...[
                _buildChart(dailyRecords),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(alignment: Alignment.centerLeft, child: Text("상세 내역", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: dailyRecords.length,
                  itemBuilder: (context, index) {
                    final r = dailyRecords[index];
                    return ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.directions_bike, color: Colors.white)),
                      title: Text("${r.duration.inMinutes}분 ${r.duration.inSeconds % 60}초 운동"),
                      subtitle: Text("평균 ${r.avgHR} BPM | ${r.calories.toStringAsFixed(1)} kcal"),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  },
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
