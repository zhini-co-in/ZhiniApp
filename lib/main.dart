import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

    // TEMP DIAGNOSTIC
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );
    debugPrint('PUSH permission: ${settings.authorizationStatus}');

    String? apns;
    for (int i = 0; i < 10 && apns == null; i++) {
      apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns == null) await Future.delayed(const Duration(seconds: 1));
    }
    debugPrint('PUSH APNS token: $apns');

    final fcm = await FirebaseMessaging.instance.getToken();
    debugPrint('PUSH FCM token: $fcm');
  } catch (e) {
    debugPrint('PUSH check error: $e');
  }

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