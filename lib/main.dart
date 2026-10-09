import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'models/home_model.dart';
import 'splash_screen.dart';
import 'services/log_service.dart';      // Phase 2
//import 'services/push_service.dart';   // Phase 3
import 'firebase_options.dart';
import 'update_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  LogService.instance.init();            // Phase 2
  //await PushService.instance.init();   // Phase 3
  await availableCameras();

  await Hive.initFlutter();
  Hive.registerAdapter(HomeModelAdapter());
  await Hive.openBox<HomeModel>('homes');
  await Hive.openBox('session');

  runApp(const MyApp());
  UpdateService.checkForUpdate();
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