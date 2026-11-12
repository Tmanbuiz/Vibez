import 'package:flutter/material.dart';

import 'api.dart';
import 'pages.dart';

const _ink = Color(0xFF090A11);
const _surface = Color(0xFF12131D);
const _violet = Color(0xFFAE68FF);
const _cyan = Color(0xFF61D9F2);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const VibezApp());
}

class VibezApp extends StatelessWidget {
  const VibezApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.fromSeed(
      seedColor: _violet,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _violet,
      secondary: _cyan,
      surface: _surface,
      onSurface: const Color(0xFFF5F2FA),
    );

    return MaterialApp(
      title: 'Vibez AI Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: _ink,
        appBarTheme: const AppBarTheme(
          backgroundColor: _ink,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF14151F),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          labelStyle: const TextStyle(color: Color(0xFFAAA8B8)),
          hintStyle: const TextStyle(color: Color(0xFF686879)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF272737)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF272737)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: _violet, width: 1.6),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: ButtonStyle(
            minimumSize: const WidgetStatePropertyAll(Size.fromHeight(50)),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
            side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFF39364A))),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF10111A),
          indicatorColor: const Color(0xFF302343),
          elevation: 0,
          height: 72,
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
                color: states.contains(WidgetState.selected) ? const Color(0xFFE9D5FF) : const Color(0xFF9291A0),
              )),
        ),
        dividerColor: const Color(0xFF242432),
      ),
      home: const Shell(),
    );
  }
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  @override
  void initState() {
    super.initState();
    if (!Api.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset('assets/vibez-icon.jpg', width: 38, height: 38, fit: BoxFit.cover),
            ),
            const SizedBox(width: 11),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Vibez', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                Text('AI STUDIO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.8, color: Color(0xFFAAA8B8))),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filledTonal(
              tooltip: 'Settings',
              style: IconButton.styleFrom(backgroundColor: const Color(0xFF1B1B27)),
              icon: const Icon(Icons.tune_rounded, size: 20),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: IndexedStack(
              index: index,
              children: const [MusicPage(), ImagePage(), VideoPage(), VoicePage(), LibraryPage()],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.graphic_eq_rounded), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_mosaic_rounded), label: 'Images'),
          NavigationDestination(icon: Icon(Icons.movie_creation_outlined), label: 'Video'),
          NavigationDestination(icon: Icon(Icons.mic_none_rounded), label: 'Voice'),
          NavigationDestination(icon: Icon(Icons.library_music_rounded), label: 'Library'),
        ],
      ),
    );
  }
}
