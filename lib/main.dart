import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'models/home_model.dart';
import 'splash_screen.dart';
import 'services/log_service.dart'; // Phase 2
//import 'services/push_service.dart';   // Phase 3
import 'firebase_options.dart';
import 'theme/theme_controller.dart';
import 'update_service.dart';
import 'theme/app_theme.dart';
import 'package:flutter/rendering.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // TEMP DIAGNOSTIC
  try {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
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

  LogService.instance.init(); // Phase 2
  //await PushService.instance.init();   // Phase 3
  await availableCameras();

  await Hive.initFlutter();
  Hive.registerAdapter(HomeModelAdapter());
  await Hive.openBox<HomeModel>('homes');
  await Hive.openBox('session');

  await ThemeController.load(); // saved Light / Dark mode
  ThemeController.notifier.addListener(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.reassembleApplication();
    });
  });

  runApp(const MyApp());

  runApp(const MyApp());
  UpdateService.checkForUpdate();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Step 1: ella widget ayum rebuild pannu
  static void _rebuildAll() {
    void rebuild(Element el) {
      el.markNeedsBuild();
      el.visitChildren(rebuild);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(rebuild);
  }

  // Step 2: cached decoration paint ah reset pannu
  static void _resetPaintCaches() {
    final root = WidgetsBinding.instance.rootElement?.renderObject;
    if (root == null) return;
    void visit(RenderObject ro) {
      if (ro is RenderDecoratedBox) {
        final d = ro.decoration;
        ro.decoration = const BoxDecoration(); // cache drop aagum
        ro.decoration = d; // thirumba original, puthu colour oda
      }
      ro.markNeedsPaint();
      ro.visitChildren(visit);
    }

    visit(root);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.notifier,
      builder: (context, isDark, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _rebuildAll();
          WidgetsBinding.instance.addPostFrameCallback((_) => _resetPaintCaches());
        });
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: AppColors.scaffoldBg,
          ),
          home: SplashScreen(),
        );
      },
    );
  }
}