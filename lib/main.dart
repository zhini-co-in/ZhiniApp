import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'models/home_model.dart';
import 'splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await availableCameras();

  await Hive.initFlutter();
  Hive.registerAdapter(HomeModelAdapter());
  await Hive.openBox<HomeModel>('homes');   // 👈 home/rooms/appliances cache
  await Hive.openBox('session');            // 👈 session data (mobile, homeId, etc.)

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}