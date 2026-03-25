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
// ✅ 빌드 에러 원인 해결: latlong2 임포트 경로 확인
import 'package:latlong2/latlong2.dart' as ll; 
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
  final double distanceKm;
  final String type;

  WorkoutRecord(this.id, this.date, this.avgHR, this.calories, this.duration, {this.distanceKm = 0.0, this.type = 'indoor'});

  Map<String, dynamic> toJson() => {
    'id': id, 'date': date, 'avgHR': avgHR, 'calories': calories,
    'durationSeconds': duration.inSeconds, 'distanceKm': distanceKm, 'type': type
  };

  factory WorkoutRecord.fromJson(Map<String, dynamic> json) => WorkoutRecord(
    json['id'], json['date'], json['avgHR'], (json['calories'] as num).toDouble(),
    Duration(seconds: json['durationSeconds']),
    distanceKm: (json['distanceKm'] as num?)?.toDouble() ?? 0.0,
    type: json['type'] ?? 'indoor'
  );
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
  List<FlSpot> _hrSpots = [];

  @override void initState() { super.initState(); _loadRecords(); }

  Future<void> _loadRecords() async {
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
    double progress = (_calories / _goalCalories).clamp(0.0, 1.0);
    return Scaffold(
      body: Stack(children: [
        Positioned.fill(child: Opacity(opacity: 0.8, child: Image.asset('assets/background.png', fit: BoxFit.cover, errorBuilder: (c,e,s)=>Container(color: Colors.black)))),
        SafeArea(child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Column(children: [
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Indoor bike fit', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
            _iconBadge("워치 연결", Colors.greenAccent),
          ]),
          const SizedBox(height: 100),
          _simpleChart(),
          const SizedBox(height: 50),
          _goalBar(progress),
          const SizedBox(height: 20),
          _mainDataGrid(),
          const SizedBox(height: 40),
          _actionRow(),
        ])))),
      ]),
    );
  }

  Widget _simpleChart() => SizedBox(height: 60, child: LineChart(LineChartData(gridData: const FlGridData(show: false), titlesData: const FlTitlesData(show: false), borderData: FlBorderData(show: false), lineBarsData: [LineChartBarData(spots: _hrSpots.isEmpty ? [const FlSpot(0,0)] : _hrSpots, isCurved: true, color: Colors.greenAccent, barWidth: 2, dotData: const FlDotData(show: false))])));
  Widget _goalBar(double p) => Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("CALORIE GOAL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)), Text("${_calories.toInt()} / ${_goalCalories.toInt()} kcal", style: const TextStyle(color: Colors.greenAccent, fontSize: 10))]), const SizedBox(height: 8), LinearProgressIndicator(value: p, color: Colors.greenAccent, backgroundColor: Colors.white12)]);
  Widget _mainDataGrid() => Container(padding: const EdgeInsets.symmetric(vertical: 20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_stat("심박수", "$_heartRate", Colors.greenAccent), _stat("평균", "$_avgHeartRate", Colors.redAccent), _stat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent), _stat("시간", "${_duration.inMinutes}:${(_duration.inSeconds%60).toString().padLeft(2,'0')}", Colors.blueAccent)]));
  Widget _stat(String l, String v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 10, color: Colors.white60)), Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: c))]);
  Widget _iconBadge(String l, Color c) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(border: Border.all(color: c), borderRadius: BorderRadius.circular(8)), child: Text(l, style: TextStyle(color: c, fontSize: 10)));
  
  Widget _actionRow() => Wrap(spacing: 15, children: [
    _roundBtn(Icons.play_arrow, "시작", () {}),
    _roundBtn(Icons.directions_run, "실외주행", () => Navigator.push(context, MaterialPageRoute(builder: (c) => OutdoorMapScreen(records: _records)))),
    _roundBtn(Icons.save, "저장", () {}),
    _roundBtn(Icons.calendar_month, "기록", () => Navigator.push(context, MaterialPageRoute(builder: (c) => HistoryScreen(records: _records)))),
  ]);

  Widget _roundBtn(IconData i, String l, VoidCallback t) => Column(children: [GestureDetector(onTap: t, child: Container(width: 55, height: 55, decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.white24)), child: Icon(i, color: Colors.white))), const SizedBox(height: 5), Text(l, style: const TextStyle(fontSize: 10))]);
}

// ✅ 실외 주행 (빌드 에러 수정 완료)
class OutdoorMapScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const OutdoorMapScreen({Key? key, required this.records}) : super(key: key);
  @override _OutdoorMapScreenState createState() => _OutdoorMapScreenState();
}
class _OutdoorMapScreenState extends State<OutdoorMapScreen> {
  final MapController _mapController = MapController();
  List<ll.LatLng> _points = []; // ll 별칭 사용

  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("실외 주행"), backgroundColor: Colors.black),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(initialCenter: ll.LatLng(37.56, 126.97), initialZoom: 15),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
          PolylineLayer(polylines: [Polyline(points: _points, color: Colors.blueAccent, strokeWidth: 4)]),
        ],
      ),
    );
  }
}

// ✅ 기록 리포트 (이미지 디자인 반영)
class HistoryScreen extends StatefulWidget {
  final List<WorkoutRecord> records;
  const HistoryScreen({Key? key, required this.records}) : super(key: key);
  @override _HistoryScreenState createState() => _HistoryScreenState();
}
class _HistoryScreenState extends State<HistoryScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay = DateTime.now();

  @override Widget build(BuildContext context) {
    final daily = widget.records.where((r) => r.date == DateFormat('yyyy-MM-dd').format(_selectedDay!)).toList();
    return Theme(
      data: ThemeData(brightness: Brightness.light),
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(title: const Text("기록 리포트"), backgroundColor: Colors.white, foregroundColor: Colors.black, elevation: 0),
        body: SingleChildScrollView(child: Column(children: [
          // 1000014908.jpg의 체중 바 디자인
          Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), decoration: BoxDecoration(color: const Color(0xFF627D8B), borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text("나의 현재 체중", style: TextStyle(color: Colors.white, fontSize: 15)), Text("69.7kg", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18))])),
          // 필터 버튼 (일간/주간/월간)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
            _filterBtn("일간", const Color(0xFFFF5252)), const SizedBox(width: 8),
            _filterBtn("주간", const Color(0xFFFFB74D)), const SizedBox(width: 8),
            _filterBtn("월간", const Color(0xFF448AFF)),
          ])),
          // 캘린더 카드
          Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]), child: TableCalendar(
            locale: 'ko_KR', firstDay: DateTime(2024), lastDay: DateTime(2030), focusedDay: _focusedDay, rowHeight: 45,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (sel, foc) => setState(() { _selectedDay = sel; _focusedDay = foc; }),
            calendarStyle: const CalendarStyle(selectedDecoration: BoxDecoration(color: Color(0xFF448AFF), shape: BoxShape.circle), todayDecoration: BoxDecoration(color: Colors.black12, shape: BoxShape.circle), todayTextStyle: TextStyle(color: Colors.black)),
            headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
          )),
          // 하단 운동 리스트
          ...daily.map((r) => Container(margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Row(children: [
            const Icon(Icons.directions_bike, color: Color(0xFF448AFF), size: 30),
            const SizedBox(width: 15),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${r.calories.toInt()} kcal 소모", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text("${r.duration.inMinutes}분 / ${r.avgHR} bpm", style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ]),
          ]))),
          if (daily.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Text("운동 기록이 없습니다.", style: TextStyle(color: Colors.grey))),
        ])),
      ),
    );
  }
  Widget _filterBtn(String l, Color c) => Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: (){}, child: Text(l, style: const TextStyle(fontWeight: FontWeight.bold))));
}
