import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await initializeDateFormatting('ko_KR', null);
  
  await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.location].request();
  
  FlutterNativeSplash.remove();
  runApp(const BikeFitApp());
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
  int _heartRate = 0;
  double _calories = 0.0;
  Duration _duration = Duration.zero;
  Timer? _workoutTimer;
  bool _isWorkingOut = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(image: AssetImage('assets/background.png'), fit: BoxFit.cover),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              const Text('Indoor bike fit', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              const Spacer(),
              // ✅ 수정된 에셋 경로 적용
              Image.asset('assets/icon/bike_ui_dark.png', height: 220, errorBuilder: (c, e, s) => const Icon(Icons.directions_bike, size: 100, color: Colors.greenAccent)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.7), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  _stat("심박수", "$_heartRate", Colors.greenAccent),
                  _stat("칼로리", _calories.toStringAsFixed(1), Colors.orangeAccent),
                ]),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  setState(() { 
                    _isWorkingOut = !_isWorkingOut; 
                    if (_isWorkingOut) {
                      _workoutTimer = Timer.periodic(const Duration(seconds: 1), (t) => setState(() => _duration += const Duration(seconds: 1)));
                    } else {
                      _workoutTimer?.cancel();
                    }
                  });
                },
                child: Text(_isWorkingOut ? "PAUSE" : "START"),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _stat(String l, String v, Color c) => Column(children: [Text(l), Text(v, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c))]);
}
