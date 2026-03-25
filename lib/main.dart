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
import 'package:flutter_map/flutter_map.dart';
// ✅ 에러 로그 해결: latlong2 패키지를 직접 참조
import 'package:latlong2/latlong2.dart'; 
import 'package:geolocator/geolocator.dart';

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
  final String type;

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration, {this.type = 'indoor'});

  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories, 'durationSec': duration.inSeconds, 'type': type};
  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(json['id'], json['date'], json['avgHR'], (json['calories'] as num).toDouble(), Duration(seconds: json['durationSec']), type: json['type'] ?? 'indoor');
}

class BikeFitApp extends StatelessWidget {
  const BikeFitApp({Key? key}) : super(key: key);
  @override Widget build(BuildContext context) {
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
  Duration _duration = Duration.zero;
  List<WorkoutRecord> _records = [];

  @override void initState() { super.initState(); _loadData(); }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _goalCalories = prefs.getDouble('goal_calories') ?? 300.0;
      final String? res = prefs.getString('workout_records');
      if (res != null) {
        final List<dynamic> decoded = jsonDecode(res);
        _records = decoded.map((item) => WorkoutRecord.fromJson(item)).toList();
      }
    });
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            _badge("워치 연결", Colors.greenAccent),
          ]),
          const SizedBox(height: 180),
          _statGrid(),
          const SizedBox(height: 40),
          _actionButtons(),
        ])))),
      ]),
    );
  }

  Widget _statGrid() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_statItem("심박수", "$_heartRate", Colors.greenAccent), _statItem("평균", "$_avgHeartRate", Colors.redAccent), _statItem("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent)]));
  Widget _statItem(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: c))]);
  Widget _badge(String l, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(border: Border.all(color: c), borderRadius: BorderRadius.circular(5)), child: Text(l, style: TextStyle(color: c, fontSize: 10)));
  
  Widget _actionButtons() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
    _btn(Icons.play_arrow, "시작", () {}),
    const SizedBox(width: 15),
    _btn(Icons.directions_run, "실외주행", () => Navigator.push(context, MaterialPageRoute(builder: (c) => OutdoorMapScreen()))),
    const SizedBox(width: 15),
    _btn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryReportScreen(records: _records)))),
  ]);

  Widget _btn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15)), child: Icon(i, color: Colors.white))), const SizedBox(height: 5), Text(l, style: const TextStyle(fontSize: 10))]);
}

// ✅ 실외 주행 (LatLng 에러 해결)
class OutdoorMapScreen extends StatelessWidget {
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("실외 주행"), backgroundColor: Colors.black),
      body: FlutterMap(
        options: MapOptions(initialCenter: LatLng(37.56, 126.97), initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          PolylineLayer(polylines: [Polyline(points: [LatLng(37.56, 126.97), LatLng(37.57, 126.98)], color: Colors.blue, strokeWidth: 4)]),
        ],
      ),
    );
  }
}

// ✅ 기록 리포트 (이미지 1000014908.jpg 디자인 완벽 적용)
class HistoryReportScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryReportScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryReportScreenState createState() => _HistoryReportScreenState();
}

class _HistoryReportScreenState extends State<HistoryReportScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  @override Widget build(BuildContext context) {
    final daily = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.black), onPressed: () => Navigator.pop(context)),
          title: const Text("기록 리포트", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        ),
        body: SingleChildScrollView(child: Column(children: [
          // 나의 현재 체중 섹션 (이미지 상단 회색 바)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            decoration: BoxDecoration(color: const Color(0xFF5D7A88), borderRadius: BorderRadius.circular(15)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [
              Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 16)),
              Text("69.7kg", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20))
            ]),
          ),
          // 일간/주간/월간 컬러 버튼
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _filterBtn("일간", const Color(0xFFFF5A5A)), const SizedBox(width: 10),
            _filterBtn("주간", const Color(0xFFFFB347)), const SizedBox(width: 10),
            _filterBtn("월간", const Color(0xFF4A90E2)),
          ])),
          // 달력 카드 UI
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
            child: TableCalendar(
              locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay,
              headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
              calendarStyle: const CalendarStyle(
                selectedDecoration: BoxDecoration(color: Color(0xFF4A90E2), shape: BoxShape.circle),
                todayDecoration: BoxDecoration(color: Colors.black12, shape: BoxShape.circle),
              ),
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            ),
          ),
          // 운동 기록 리스트 (둥근 흰색 카드)
          ...daily.map((r) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: Row(children: [
              const Icon(Icons.directions_bike, color: Color(0xFF4A90E2), size: 30),
              const SizedBox(width: 15),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${r.calories.toInt()} kcal 소모", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("${r.duration.inMinutes}분 / ${r.avgHR} bpm", style: const TextStyle(color: Colors.grey, fontSize: 14)),
              ]),
            ]),
          )),
        ])),
      ),
    );
  }
  Widget _filterBtn(String l, Color c) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: (){}, child: Text(l, style: const TextStyle(fontWeight: FontWeight.bold))));
}
