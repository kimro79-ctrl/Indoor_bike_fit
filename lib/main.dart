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
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Indoor_fit_app',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0; int _avgHeartRate = 0; double _calories = 0.0;
  Duration _duration = Duration.zero; Timer? _workoutTimer;
  bool _isWorkingOut = false; bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = []; double _timeCounter = 0;
  List<WorkoutRecord> _records = []; List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  // ✅ [내부 로직] 현재 심박수 강도에 따른 색상 결정
  Color _getCurrentStatusColor() {
    if (_heartRate == 0) return Colors.greenAccent;
    if (_heartRate < 110) return Colors.lightBlueAccent;
    if (_heartRate < 136) return Colors.greenAccent;
    if (_heartRate < 156) return Colors.yellowAccent;
    if (_heartRate < 176) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  // ✅ [내부 로직] 아주 작은 구간 이름 (상단 연결버튼 옆 등에 활용 가능, 현재는 미배치)
  String _getHRZoneMiniText() {
    if (_heartRate == 0) return "";
    if (_heartRate < 110) return "Z1";
    if (_heartRate < 136) return "Z2";
    if (_heartRate < 156) return "Z3";
    if (_heartRate < 176) return "Z4";
    return "Z5";
  }

  @override
  void initState() { super.initState(); _loadRecords(); }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
            if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); });
          });
          return Container(
            padding: const EdgeInsets.all(20), height: 400,
            child: Column(children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              const Text("주변 워치 검색", style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: ListView.builder(
                itemCount: _filteredResults.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(_filteredResults[i].device.platformName),
                  onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[i].device); },
                ),
              )),
            ]),
          );
        }
      ),
    ).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async {
    try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); }
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
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
    int hr = (data[0] & 0x01) == 0 ? data[1] : (data[2] << 8) | data[1];
    if (mounted && hr > 0) {
      setState(() {
        _heartRate = hr;
        if (_isWorkingOut) {
          _timeCounter += 1;
          _hrSpots.add(FlSpot(_timeCounter, _heartRate.toDouble()));
          if (_hrSpots.length > 50) _hrSpots.removeAt(0);
          _avgHeartRate = (_hrSpots.map((e) => e.y).reduce((a, b) => a + b) / _hrSpots.length).toInt();
        }
      });
    }
  }

  void _handleSaveRecord() {
    if (_isWorkingOut || _duration.inSeconds < 5) return;
    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now().toString(), dateStr, _avgHeartRate, _calories, _duration)); });
    _saveToPrefs(); _showToast("저장 완료");
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('workout_records');
    if (res != null) {
      final List<dynamic> list = jsonDecode(res);
      setState(() { _records = list.map((item) => WorkoutRecord(item['id'], item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList(); });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
  }

  void _showToast(String m) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1))); }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getCurrentStatusColor();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.9, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          const Text('Indoor_fit_app', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
          const SizedBox(height: 15),
          GestureDetector(onTap: _showDeviceScanPopup, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(15), border: Border.all(color: statusColor)), child: Text("${_isWatchConnected ? "연결됨" : "워치 연결"} ${_getHRZoneMiniText()}", style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)))),
          const SizedBox(height: 25),
          
          // ✅ 그래프 선 색상만 유동적으로 변경
          SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 0)] : _hrSpots, isCurved: true, color: statusColor, barWidth: 2, dotData: const FlDotData(show: false))]))),
          
          const Spacer(),
          
          // ✅ 기존 UI 그대로! 하단 스탯 바의 심박수 색상만 변경
          Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _statItem("심박수", "$_heartRate", statusColor), 
            _statItem("평균", "$_avgHeartRate", Colors.redAccent), 
            _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), 
            _statItem("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)
          ])),
          
          const SizedBox(height: 30),
          _controlButtons(),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 11, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);

  Widget _controlButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _actionBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작", () {
      setState(() { _isWorkingOut = !_isWorkingOut; if (_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if (_heartRate >= 95) _calories += 0.003; })); } else { _workoutTimer?.cancel(); } });
    }),
    const SizedBox(width: 15),
    _actionBtn(Icons.refresh, "리셋", () { if(!_isWorkingOut) setState((){_duration=Duration.zero;_calories=0.0;_avgHeartRate=0;_heartRate=0;_hrSpots=[];}); }),
    const SizedBox(width: 15),
    _actionBtn(Icons.save, "저장", _handleSaveRecord),
    const SizedBox(width: 15),
    _actionBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs)))),
  ]);

  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records; final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now(); DateTime? _selectedDay;
  @override
  Widget build(BuildContext context) {
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(title: const Text("히스토리"), backgroundColor: Colors.black),
      body: Column(children: [
        TableCalendar(firstDay: DateTime.utc(2024,1,1), lastDay: DateTime.utc(2030,12,31), focusedDay: _focusedDay, selectedDayPredicate: (d) => isSameDay(_selectedDay, d), onDaySelected: (s, f) => setState(() { _selectedDay = s; _focusedDay = f; }), calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle))),
        Expanded(child: ListView.builder(itemCount: filtered.length, itemBuilder: (c, i) => ListTile(title: Text(filtered[i].date), subtitle: Text("${filtered[i].duration.inMinutes}분 / ${filtered[i].avgHR}bpm"), trailing: Text("${filtered[i].calories.toStringAsFixed(1)} kcal")))),
      ]),
    );
  }
}
