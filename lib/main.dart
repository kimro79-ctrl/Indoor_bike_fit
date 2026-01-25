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

// --- 데이터 모델 ---
class WorkoutRecord {
  final String id;
  final String date;
  final int avgHR;
  final double calories;
  final Duration duration;
  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration);
}

class WeightRecord {
  final String date;
  final double weight;
  WeightRecord(this.date, this.weight);
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Indoor bike fit',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light, // ✅ 전체적으로 밝은 테마 적용
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA), // 화사한 연회색 배경
      ),
      home: const WorkoutScreen(),
    );
  }
}

// --- 메인 운동 화면 (이전과 동일하되 디자인 톤 유지) ---
class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0;
  int _avgHeartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];
  List<ScanResult> _filteredResults = [];
  StreamSubscription? _scanSubscription;

  @override
  void initState() { super.initState(); _loadRecords(); }

  void _showDeviceScanPopup() async {
    if (_isWatchConnected) return;
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    _filteredResults.clear();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 15), androidUsesFineLocation: true);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(builder: (context, setModalState) {
        _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
          if (mounted) setModalState(() { _filteredResults = results.where((r) => r.device.platformName.isNotEmpty).toList(); });
        });
        return Container(
          padding: const EdgeInsets.all(20),
          height: 300,
          child: Column(children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            const Text("워치 연결", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(child: ListView.builder(itemCount: _filteredResults.length, itemBuilder: (context, index) => ListTile(
              leading: const Icon(Icons.watch, color: Colors.blue),
              title: Text(_filteredResults[index].device.platformName),
              onTap: () { Navigator.pop(context); _connectToDevice(_filteredResults[index].device); }
            )))
          ]),
        );
      }),
    ).whenComplete(() { FlutterBluePlus.stopScan(); _scanSubscription?.cancel(); });
  }

  void _connectToDevice(BluetoothDevice device) async { try { await device.connect(); _setupDevice(device); } catch (e) { _showToast("연결 실패"); } }
  void _setupDevice(BluetoothDevice device) async { setState(() { _isWatchConnected = true; }); List<BluetoothService> services = await device.discoverServices(); for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } } }

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
    if (_isWorkingOut) { _showToast("운동을 먼저 정지해 주세요."); return; }
    if (_duration.inSeconds < 5) { _showToast("운동 시간이 너무 짧습니다."); return; }
    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() { _records.insert(0, WorkoutRecord(DateTime.now().millisecondsSinceEpoch.toString(), dateStr, _avgHeartRate, _calories, _duration)); });
    _saveToPrefs(); _showToast("기록 저장됨!");
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('workout_records');
    if (res != null) {
      final List<dynamic> decoded = jsonDecode(res);
      setState(() { _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList(); });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds}).toList()));
  }

  void _showToast(String msg) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating)); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 메인 운동화면은 집중을 위해 다크 유지
      body: SafeArea(child: Column(children: [
        const SizedBox(height: 30),
        const Text('Indoor Bike Fit', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
        _connectButton(),
        const Spacer(),
        _dataGrid(),
        const SizedBox(height: 40),
        _controlPanel(),
        const SizedBox(height: 50),
      ])),
    );
  }

  Widget _connectButton() => TextButton.icon(onPressed: _showDeviceScanPopup, icon: Icon(Icons.circle, size: 10, color: _isWatchConnected ? Colors.greenAccent : Colors.redAccent), label: Text(_isWatchConnected ? "워치 연결됨" : "워치 미연결", style: const TextStyle(color: Colors.white60)));
  Widget _dataGrid() => Container(padding: const EdgeInsets.all(20), child: GridView.count(shrinkWrap: true, crossAxisCount: 2, childAspectRatio: 1.5, children: [_statBox("심박수", "$_heartRate", Colors.greenAccent), _statBox("평균", "$_avgHeartRate", Colors.redAccent), _statBox("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _statBox("시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent)]));
  Widget _statBox(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(color: Colors.white30, fontSize: 12)), Text(v, style: TextStyle(color: c, fontSize: 32, fontWeight: FontWeight.bold))]);
  Widget _controlPanel() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _circleBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, () { setState(() { _isWorkingOut = !_isWorkingOut; if(_isWorkingOut) { _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() { _duration += const Duration(seconds: 1); if(_heartRate > 60) _calories += 0.12; })); } else { _workoutTimer?.cancel(); } }); }),
    _circleBtn(Icons.save, _handleSaveRecord),
    _circleBtn(Icons.history, () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs)))),
  ]);
  Widget _circleBtn(IconData i, VoidCallback t) => IconButton.filledTonal(onPressed: t, icon: Icon(i, size: 30), padding: const EdgeInsets.all(20));
}

// --- 화사한 히스토리 화면 ---
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records; final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now(); DateTime? _selectedDay;
  List<WeightRecord> _weightRecords = [];
  final TextEditingController _weightController = TextEditingController();

  @override
  void initState() { super.initState(); _loadWeights(); }

  Future<void> _loadWeights() async {
    final prefs = await SharedPreferences.getInstance();
    final String? res = prefs.getString('weight_records');
    if (res != null) {
      final List<dynamic> decoded = jsonDecode(res);
      setState(() { _weightRecords = decoded.map((item) => WeightRecord(item['date'], item['weight'])).toList(); });
    }
  }

  Future<void> _saveWeights() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('weight_records', jsonEncode(_weightRecords.map((r) => {'date': r.date, 'weight': r.weight}).toList()));
  }

  // ✅ 기록 길게 눌러 삭제 기능
  void _deleteRecord(WorkoutRecord record) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("기록 삭제"),
      content: const Text("이 운동 기록을 삭제할까요?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("취oc")),
        TextButton(onPressed: () {
          setState(() { widget.records.removeWhere((r) => r.id == record.id); });
          widget.onSync(); Navigator.pop(context);
        }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _showWeightSheet() {
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("오늘의 체중", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        TextField(controller: _weightController, autofocus: true, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: "kg")),
        const SizedBox(height: 20),
        ElevatedButton(onPressed: () {
          if(_weightController.text.isNotEmpty) {
            setState(() {
              String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              _weightRecords.removeWhere((r) => r.date == today);
              _weightRecords.insert(0, WeightRecord(today, double.parse(_weightController.text)));
            });
            _saveWeights(); _weightController.clear(); Navigator.pop(context);
          }
        }, child: const Text("저장")),
        const SizedBox(height: 20),
      ]),
    ));
  }

  @override
  Widget build(BuildContext context) {
    double totalCals = widget.records.where((r) => DateTime.parse(r.id).isAfter(DateTime.now().subtract(const Duration(days: 7)))).fold(0, (sum, r) => sum + r.calories);
    double weight = _weightRecords.isEmpty ? 0 : _weightRecords.first.weight;
    final filtered = widget.records.where((r) => _selectedDay == null || r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8), // ✅ 화사한 스카이 그레이 배경
      appBar: AppBar(title: const Text("운동 히스토리", style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0),
      floatingActionButton: FloatingActionButton(onPressed: _showWeightSheet, child: const Icon(Icons.add)),
      body: SingleChildScrollView( // ✅ Overflow 방지
        child: Column(children: [
          // 상단 화사한 요약 카드
          Container(
            margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF667EEA), Color(0xFF764BA2)]), // ✅ 화사한 그라데이션
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _summaryItem("주간 칼로리", "${totalCals.toStringAsFixed(0)}", "kcal"),
              Container(width: 1, height: 40, color: Colors.white24),
              _summaryItem("현재 체중", weight > 0 ? "$weight" : "-", "kg"),
            ]),
          ),
          // 화사한 달력 배너
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.blue.withOpacity(0.1))),
            child: TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1), lastDay: DateTime.utc(2030, 12, 31), focusedDay: _focusedDay, locale: 'ko_KR',
              rowHeight: 40, // ✅ 콤팩트한 사이즈
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
              eventLoader: (day) => widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
              calendarStyle: CalendarStyle(
                selectedDecoration: const BoxDecoration(color: Color(0xFF667EEA), shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), shape: BoxShape.circle),
                markerDecoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                defaultTextStyle: const TextStyle(fontWeight: FontWeight.bold),
              ),
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
          const SizedBox(height: 15),
          // 운동 리스트
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              itemBuilder: (c, i) => _workoutCard(filtered[i]),
            ),
          ),
          const SizedBox(height: 80),
        ]),
      ),
    );
  }

  Widget _summaryItem(String l, String v, String u) => Column(children: [Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)), Text(v, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)), Text(u, style: const TextStyle(color: Colors.white70, fontSize: 10))]);

  Widget _workoutCard(WorkoutRecord r) {
    return GestureDetector(
      onLongPress: () => _deleteRecord(r), // ✅ 삭제 기능 연결
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
        child: Row(children: [
          CircleAvatar(backgroundColor: Colors.blue[50], child: const Icon(Icons.directions_bike, color: Colors.blue, size: 20)),
          const SizedBox(width: 15),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.date, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            Text("${r.duration.inMinutes}분 운동 / ${r.avgHR}bpm", style: TextStyle(color: Colors.grey[600], fontSize: 12))
          ])),
          Text("${r.calories.toStringAsFixed(1)} kcal", style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
        ]),
      ),
    );
  }
}
