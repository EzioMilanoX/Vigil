import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/save.dart';
import 'ui/title_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Em pé, como uma lanterna, e em tela cheia.
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final save = Save();
  await save.load();
  runApp(VigilApp(save: save));
}

class VigilApp extends StatelessWidget {
  const VigilApp({super.key, required this.save});

  final Save save;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vigil',
      debugShowCheckedModeBanner: false,
      theme: vigilTheme,
      home: TitleScreen(save: save),
    );
  }
}

/// Preto e cor de osso: nada de roxo no meio do terror.
final vigilTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: Colors.black,
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFFE8DFC8),
    onPrimary: Colors.black,
    secondary: Color(0xFF8E877B),
    surface: Colors.black,
  ),
);
