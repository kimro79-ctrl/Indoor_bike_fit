import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
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
      home: const WorkoutScreen(),
    );
  }
}

class WorkoutScreen extends StatefulWidget {
  const WorkoutScreen({Key? key}) : super(key: key);
  @override _WorkoutScreenState createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends State<WorkoutScreen> {
  int _heartRate = 0, _avgHeartRate = 0;
  double _calories = 0.0, _goalCalories = 300.0;
  List<WorkoutRecord> _records = [];

  @override
  void initState() { super.initState(); _loadInitialData(); }

  Future<void> _loadInitialData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord(item['id'] ?? DateTime.now().toString(), item['date'], item['avgHR'], item['calories'], Duration(seconds: item['durationSeconds']))).toList();
      }
    });
  }

  Future<void> _updateRecords(List<WorkoutRecord> newRecords) async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(newRecords.map((r) => r.toJson()).toList());
    await prefs.setString('workout_records', encoded);
    setState(() { _records = newRecords; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
          const Spacer(),
          _dataBanner(),
          const SizedBox(height: 30),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _actionBtn(Icons.calendar_month, "기록", () async {
              await Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records, onUpdate: _updateRecords)));
              _loadInitialData();
            }),
          ]),
          const SizedBox(height: 40),
        ]))),
      ]),
    );
  }

  Widget _dataBanner() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "0", Colors.greenAccent), _statItem("칼로리", "0", Colors.orangeAccent), _statItem("시간", "00:00", Colors.blueAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), const SizedBox(height: 6), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  Widget _actionBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))), const SizedBox(height: 6), Text(l, style: const TextStyle(fontSize: 10, color: Colors.white70))]);
}

class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  final Function(List<WorkoutRecord>) onUpdate;
  const HistoryScreen({Key? key, required this.records, required this.onUpdate}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  double _weight = 70.0;
  late List<WorkoutRecord> _currentRecords;

  @override
  void initState() { super.initState(); _currentRecords = List.from(widget.records); _selectedDay = _focusedDay; _loadWeight(); }

  Future<void> _loadWeight() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() { _weight = prefs.getDouble('last_weight') ?? 70.0; });
  }

  // ✅ 삭제 확인 다이얼로그
  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("기록 삭제", style: TextStyle(fontSize: 16)),
        content: const Text("이 운동 기록을 삭제하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          TextButton(onPressed: () {
            setState(() { _currentRecords.removeWhere((r) => r.id == id); widget.onUpdate(_currentRecords); });
            Navigator.pop(context);
          }, child: const Text("삭제", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  // ✅ 체중 설정
  void _showWeightSetting() {
    final controller = TextEditingController(text: _weight.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("체중 설정"),
        content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(suffixText: "kg")),
        actions: [TextButton(onPressed: () async {
          final newWeight = double.tryParse(controller.text) ?? 70.0;
          (await SharedPreferences.getInstance()).setDouble('last_weight', newWeight);
          setState(() { _weight = newWeight; });
          Navigator.pop(context);
        }, child: const Text("저장"))],
      ),
    );
  }

  // ✅ 그래프 팝업
  void _showGraphPopup(String title, int days, Color color) {
    final limit = DateTime.now().subtract(Duration(days: days));
    var filtered = _currentRecords.where((r) => DateTime.parse(r.date).isAfter(limit)).toList().reversed.toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        height: 350, padding: const EdgeInsets.all(25),
        child: Column(children: [
          Text("$title 칼로리 통계", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 30),
          Expanded(child: BarChart(BarChartData(
            barGroups: List.generate(filtered.length, (i) => BarChartGroupData(x: i, barRods: [BarChartRodData(toY: filtered[i].calories, color: color, width: 16, borderRadius: BorderRadius.circular(4))])),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
          ))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDateStr = DateFormat('yyyy-MM-dd').format(_selectedDay!);
    final dailyRecords = _currentRecords.where((r) => r.date == selectedDateStr).toList();

    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          GestureDetector(
            onTap: _showWeightSetting,
            child: Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), decoration: BoxDecoration(color: const Color(0xFF678392), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 16)), Text("${_weight}kg", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))])),
          ),
          
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _colorBtn("일간", Colors.redAccent, () => _showGraphPopup("일간", 1, Colors.redAccent)),
            const SizedBox(width: 8),
            _colorBtn("주간", Colors.orangeAccent, () => _showGraphPopup("주간", 7, Colors.orangeAccent)),
            const SizedBox(width: 8),
            _colorBtn("월간", Colors.blueAccent, () => _showGraphPopup("월간", 30, Colors.blueAccent)),
          ])),

          Container(
            margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: TableCalendar(
              locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
              // ✅ 달력 스팟 표시 (이벤트 로더)
              eventLoader: (day) => _currentRecords.where((r) => r.date == DateFormat('yyyy-MM-dd').format(day)).toList(),
              calendarStyle: const CalendarStyle(markerDecoration: BoxDecoration(color: Color(0xFF9FA8DA), shape: BoxShape.circle), selectedDecoration: BoxDecoration(color: Color(0xFF4285F4), shape: BoxShape.circle)),
            ),
          ),

          const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Align(alignment: Alignment.centerLeft, child: Text("상세 기록 (길게 눌러 삭제)", style: TextStyle(fontSize: 12, color: Colors.grey)))),
          
          ListView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            itemCount: dailyRecords.length,
            itemBuilder: (context, index) {
              final r = dailyRecords[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  onLongPress: () => _confirmDelete(r.id), // ✅ 길게 누르면 삭제
                  leading: const Icon(Icons.directions_bike, color: Color(0xFF4285F4)),
                  title: Text("${r.calories.toInt()} kcal"),
                  subtitle: Text("${r.avgHR} bpm"),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _confirmDelete(r.id)),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
        ])),
      ),
    );
  }

  Widget _colorBtn(String label, Color color, VoidCallback onTap) => Expanded(child: ElevatedButton(
    style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    onPressed: onTap, child: Text(label),
  ));
}
