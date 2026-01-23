import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart'; 
import 'package:table_calendar/table_calendar.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override
  _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 95; // 기본값 95로 고정
  int _avgHeartRate = 95; // 평균값 95로 고정
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;
  bool _isWatchConnected = false;
  List<FlSpot> _hrSpots = [];
  double _timeCounter = 0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final String? recordsJson = prefs.getString('workout_records');
    if (recordsJson != null) {
      final List<dynamic> decodedList = jsonDecode(recordsJson);
      setState(() {
        _records = decodedList.map((item) => WorkoutRecord(
          item['id'] ?? DateTime.now().toString(),
          item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']),
        )).toList();
      });
    }
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('workout_records', jsonEncode(_records.map((r) => {
      'id': r.id, 'date': r.date, 'avgHR': r.avgHR, 'calories': r.calories, 'durationSeconds': r.duration.inSeconds
    }).toList()));
  }

  void _decodeHR(List<int> data) {
    // 워치 데이터가 들어오면 이 함수가 실행되지만, 95로 강제 적용합니다.
    if (mounted && _isWorkingOut) {
      setState(() {
        _heartRate = 95; 
        _timeCounter += 1;
        _hrSpots.add(FlSpot(_timeCounter, 95.0));
        if (_hrSpots.length > 100) _hrSpots.removeAt(0);
        
        _avgHeartRate = 95;
        // 💡 칼로리 계산: 심박수 95를 기준으로 매 초 계산
        _calories += (95 * 0.012 * (1/60)); 
      });
    }
  }

  void _saveRecord() async {
    if (_duration.inSeconds < 1) {
      _showSnack("저장할 데이터가 없습니다.");
      return;
    }
    if (_isWorkingOut) {
      _showSnack("먼저 정지 버튼을 눌러주세요.");
      return;
    }

    String dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    setState(() {
      // 💡 저장할 때도 심박수는 무조건 95로 저장
      _records.insert(0, WorkoutRecord(DateTime.now().toString(), dateStr, 95, _calories, _duration));
    });
    await _saveToPrefs();
    _showSnack("기록이 저장되었습니다!");
  }

  void _showSnack(String m) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 1)));
  }

  void _toggleWorkout() {
    setState(() {
      _isWorkingOut = !_isWorkingOut;
      if (_isWorkingOut) {
        _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          setState(() {
            _duration += const Duration(seconds: 1);
            // 워치 미연결 상태에서도 운동 중이면 칼로리가 95 기준으로 올라가도록 설정
            _calories += (95 * 0.012 * (1/60));
            _heartRate = 95;
            _avgHeartRate = 95;
          });
        });
      } else {
        _workoutTimer?.cancel();
      }
    });
  }

  void _resetWorkout() {
    if (_isWorkingOut) return;
    setState(() { 
      _duration = Duration.zero; 
      _calories = 0.0; 
      _avgHeartRate = 95; 
      _hrSpots = []; 
      _timeCounter = 0; 
      _heartRate = 95; 
    });
  }

  Future<void> _connectWatch() async {
    await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    showModalBottomSheet(
      context: context,
      builder: (c) => StreamBuilder<List<ScanResult>>(
        stream: FlutterBluePlus.scanResults,
        builder: (c, s) {
          final res = (s.data ?? []).where((r) => r.device.platformName.isNotEmpty).toList();
          return ListView.builder(itemCount: res.length, itemBuilder: (c, i) => ListTile(title: Text(res[i].device.platformName), onTap: () async {
            await res[i].device.connect(); _setupDevice(res[i].device); Navigator.pop(context);
          }));
        },
      ),
    );
  }

  void _setupDevice(BluetoothDevice device) async {
    setState(() { _isWatchConnected = true; });
    List<BluetoothService> services = await device.discoverServices();
    for (var s in services) { if (s.uuid == Guid("180D")) { for (var c in s.characteristics) { if (c.uuid == Guid("2A37")) { await c.setNotifyValue(true); c.lastValueStream.listen(_decodeHR); } } } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.grey[900])))),
          SafeArea(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 25),
                      const Text('OVER THE BIKE FIT', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
                      const SizedBox(height: 10),
                      _smallRoundedBtn(_isWatchConnected ? "워치 연결됨" : "워치 연결하기", _isWatchConnected ? Colors.cyanAccent : Colors.white, _connectWatch),
                      
                      Container(
                        height: 45, width: double.infinity, margin: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                        child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false),
                          lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0, 95)] : _hrSpots, isCurved: true, color: Colors.cyanAccent, barWidth: 2, dotData: const FlDotData(show: false))])),
                      ),

                      const Spacer(),
                      
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white24, width: 1.2)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _modestStat("심박수", "$_heartRate", Colors.cyanAccent),
                            _modestStat("평균심박", "$_avgHeartRate", Colors.redAccent),
                            _modestStat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                            _modestStat("운동시간", "${_duration.inMinutes}:${(_duration.inSeconds % 60).toString().padLeft(2, '0')}", Colors.blueAccent),
                          ],
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 40),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _rectBtn(_isWorkingOut ? Icons.pause : Icons.play_arrow, "시작/정지", _toggleWorkout),
                            const SizedBox(width: 15),
                            _rectBtn(Icons.refresh, "초기화", _resetWorkout),
                            const SizedBox(width: 15),
                            _rectBtn(Icons.save, "기록저장", _saveRecord),
                            const SizedBox(width: 15),
                            _rectBtn(Icons.bar_chart, "기록보기", () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onSync: _saveToPrefs)));
                              setState(() {});
                            }),
                          ],
                        ),
                      ),
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

  Widget _smallRoundedBtn(String t, Color c, VoidCallback tap) => GestureDetector(onTap: tap, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.5))), child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold))));
  Widget _modestStat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70)), const SizedBox(height: 4), Text(v, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: c))]);
  Widget _rectBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, behavior: HitTestBehavior.opaque, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white, size: 24))), const SizedBox(height: 8), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white))]);
}

// 히스토리 화면은 이전과 동일 (생략 가능하나 완전성을 위해 포함)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function onSync;
  const HistoryScreen({Key? key, required this.records, required this.onSync}) : super(key: key);
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  void _deleteRecord(WorkoutRecord record) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("기록 삭제"),
        content: const Text("이 운동 기록을 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("취소")),
          TextButton(onPressed: () {
            setState(() { widget.records.removeWhere((r) => r.id == record.id); });
            widget.onSync();
            Navigator.pop(c);
          }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRecords = _selectedDay == null 
        ? widget.records 
        : widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text("운동 히스토리", style: TextStyle(color: Colors.black)), backgroundColor: Colors.white, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2024, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            locale: 'ko_KR', 
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            eventLoader: (day) => widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
            calendarStyle: CalendarStyle(
              defaultTextStyle: const TextStyle(color: Colors.black),
              weekendTextStyle: const TextStyle(color: Colors.red),
              markerDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              todayDecoration: BoxDecoration(color: Colors.blue[100], shape: BoxShape.circle),
              selectedDecoration: const BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
            ),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true, titleTextStyle: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          Expanded(
            child: filteredRecords.isEmpty 
            ? const Center(child: Text("저장된 데이터가 없습니다.", style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: filteredRecords.length,
                itemBuilder: (c, i) {
                  final r = filteredRecords[i];
                  return ListTile(
                    onLongPress: () => _deleteRecord(r), 
                    leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.directions_bike, color: Colors.white, size: 20)),
                    title: Text("${r.date} 라이딩", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    subtitle: Text("${r.duration.inMinutes}분 | ${r.avgHR}BPM", style: const TextStyle(color: Colors.black54, fontSize: 11)),
                    trailing: Text("${r.calories.toStringAsFixed(1)}kcal", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                  );
                },
              ),
          ),
        ],
      ),
    );
  }
}
