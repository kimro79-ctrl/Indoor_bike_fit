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
        'id': id,
        'date': date,
        'avgHR': avgHR,
        'calories': calories,
        'durationSeconds': duration.inSeconds
      };
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
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
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false, _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestBluetoothPermissions();
    });
  }

  Future<void> _requestBluetoothPermissions() async {
    final statuses = await [
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool anyPermanentlyDenied = statuses.values.any((s) => s.isPermanentlyDenied);
    bool anyDenied = statuses.values.any((s) => s.isDenied);

    if (anyPermanentlyDenied && mounted) {
      _showToast("근처 기기 권한을 설정에서 허용해주세요.");
      await openAppSettings();
    } else if (anyDenied && mounted) {
      _showToast("블루투스 및 위치 권한이 필요합니다.");
    }

    try {
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        await FlutterBluePlus.turnOn();
      }
    } catch (e) {
      if (mounted) _showToast("블루투스를 수동으로 켜주세요");
    }
  }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded
            .map((item) => WorkoutRecord(
                  item['id'] ?? DateTime.now().toString(),
                  item['date'],
                  item['avgHR'],
                  (item['calories'] as num).toDouble(),
                  Duration(seconds: item['durationSeconds'] ?? 0),
                ))
            .toList();
      }
    });
  }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;

    await _requestBluetoothPermissions();

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      _showToast("블루투스를 켜주세요");
      return;
    }

    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
            if (mounted) {
              setModalState(() {
                _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList();
              });
            }
          });

          return Container(
            padding: const EdgeInsets.all(20),
            height: MediaQuery.of(context).size.height * 0.4,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 20),
                const Text("워치 검색", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Expanded(
                  child: _filteredResults.isEmpty
                      ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                      : ListView.builder(
                          itemCount: _filteredResults.length,
                          itemBuilder: (context, index) => ListTile(
                            leading: const Icon(Icons.watch, color: Colors.blueAccent),
                            title: Text(_filteredResults[index].device.platformName),
                            onTap: () {
                              Navigator.pop(context);
                              _connectToDevice(_filteredResults[index].device);
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
    });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try {
      await device.connect();
      _setupDevice(device);
    } catch (e) {
      _showToast("연결 실패");
    }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() => _isWatchConnected = true);
    final services = await device.discoverServices();
    for (var s in services) {
      if (s.uuid == Guid("180D")) {
        for (var c in s.characteristics) {
          if (c.uuid == Guid("2A37")) {
            await c.setNotifyValue(true);
            c.lastValueStream.listen(_decodeHR);
          }
        }
      }
    }
  }

  void _decodeHR(List<int> data) {
    if (data.isEmpty) return;
    final hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, hr.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).round();
        }
      });
    }
  }

  void _showGoalSettings() {
    final controller = TextEditingController(text: _goalCalories.toInt().toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(25),
          height: 260,
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 25),
              const Text("목표 칼로리 설정",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 36, fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  suffixText: "kcal",
                  suffixStyle: TextStyle(color: Colors.white38, fontSize: 16),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () async {
                    final value = double.tryParse(controller.text);
                    if (value != null && value > 0) {
                      setState(() => _goalCalories = value);
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setDouble('goal_calories', _goalCalories);
                    }
                    if (mounted) Navigator.pop(context);
                  },
                  child: const Text("설정 완료", style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_calories / _goalCalories).clamp(0.0, 1.0);

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.8,
              child: Image.asset(
                'assets/background.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom,
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Indoor bike fit',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          _connectButton(),
                        ],
                      ),
                      const SizedBox(height: 25),
                      _chartArea(),
                      const Spacer(),
                      GestureDetector(
                        onTap: _showGoalSettings,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    "CALORIE GOAL",
                                    style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    "${_calories.toInt()} / ${_goalCalories.toInt()} kcal",
                                    style: const TextStyle(fontSize: 12, color: Colors.greenAccent, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(5),
                                child: SizedBox(
                                  height: 10,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.white12,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _dataBanner(),
                      const SizedBox(height: 30),
                      _controlButtons(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectButton() => GestureDetector(
        onTap: _showDeviceScanPopup,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent),
          ),
          child: Text(
            _isWatchConnected ? "연결됨" : "워치 연결",
            style: const TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ),
      );

  Widget _chartArea() => SizedBox(
        height: 60,
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: const FlTitlesData(show: false),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: _timeCounter > 0 ? _timeCounter + 5 : 1,  // 0이면 최소 범위 유지
            minY: 0,
            maxY: 200,
            lineBarsData: [
              LineChartBarData(
                spots: _hrSpots.isEmpty ? [] : _hrSpots,  // 더미 데이터 완전 제거
                isCurved: true,
                color: Colors.greenAccent,
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
            ],
          ),
        ),
      );

  Widget _dataBanner() => Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _statItem("심박수", "$_heartRate", Colors.greenAccent),
            _statItem("평균", "$_avgHeartRate", Colors.redAccent),
            _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
            _statItem(
              "시간",
              "\( {_duration.inMinutes}: \){(_duration.inSeconds % 60).toString().padLeft(2, '0')}",
              Colors.blueAccent,
            ),
          ],
        ),
      );

  Widget _statItem(String label, String value, Color color) => Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      );

  Widget _controlButtons() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _actionBtn(
            _
