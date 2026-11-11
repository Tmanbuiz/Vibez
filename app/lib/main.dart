import 'package:flutter/material.dart';

import 'api.dart';
import 'pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.load();
  runApp(const VibezApp());
}

class VibezApp extends StatelessWidget {
  const VibezApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TmanVibez AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B5CF6), brightness: Brightness.dark),
        scaffoldBackgroundColor: const Color(0xFF0B0B12),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: const Color(0xFF16161F),
        ),
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
        title: const Text('TmanVibez AI', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(icon: Icon(Icons.image), label: 'Image'),
          NavigationDestination(icon: Icon(Icons.movie), label: 'Video'),
          NavigationDestination(icon: Icon(Icons.mic), label: 'Voice'),
          NavigationDestination(icon: Icon(Icons.library_music), label: 'Library'),
        ],
      ),
    );
  }
}
