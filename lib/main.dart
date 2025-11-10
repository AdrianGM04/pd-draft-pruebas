import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/hub_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configuración de la ventana (solo si no es web)
  if (!kIsWeb) {
    try {
      await windowManager.ensureInitialized();

      const windowOptions = WindowOptions(
        size: Size(800, 600),
        center: true,
        backgroundColor: Colors.transparent,
        titleBarStyle: TitleBarStyle.normal,
      );

      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
        try {
          await windowManager.maximize();
        } catch (_) {}
      });
    } catch (e) {
      // Si window_manager falla, no rompemos la app
    }
  }

  // Correr la app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Factor de zoom lógico (80% = 0.8)
  static const double _scaleFactor = 0.8;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hub App',
      theme: ThemeData(
        primaryColor: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF58585a),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(fontSize: 20),
            padding: const EdgeInsets.symmetric(vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final modified = mq.copyWith(
          size: Size(mq.size.width / _scaleFactor, mq.size.height / _scaleFactor),
          textScaleFactor: mq.textScaleFactor * _scaleFactor,
        );
        return MediaQuery(
          data: modified,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const HubScreen(),
    );
  }
}
