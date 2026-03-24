import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_data_provider.dart';
import '../services/tts_manager.dart';

class WordsScreen extends StatefulWidget {
  const WordsScreen({super.key});

  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TtsManager _ttsManager = TtsManager();
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    // _ttsManager initialized in constructor
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    // _ttsManager.stop(); // Optional
    super.dispose();
  }

  void _speak(String text) {
    _ttsManager.speak(text);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text(
            'Kelime Defterim',
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.tealAccent,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Sık Hata Yaptıklarım'),
              Tab(text: 'Öğrendiklerim'),
            ],
          ),
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade900, Colors.deepPurple.shade600],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Column(
            children: [
              // SEARCH BAR
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Kelime ara...',
                    hintStyle: const TextStyle(color: Colors.white60),
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    MistakesList(searchQuery: _searchQuery, onSpeak: _speak),
                    KnownList(searchQuery: _searchQuery, onSpeak: _speak),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MistakesList extends StatelessWidget {
  final String searchQuery;
  final Function(String) onSpeak;
  const MistakesList({
    super.key,
    required this.searchQuery,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    final wordStats = userData.wordStats;

    final mistakes =
        wordStats.entries
            .where((entry) => (entry.value['wrong'] ?? 0) > 0)
            .where((entry) => entry.key.toLowerCase().contains(searchQuery))
            .toList()
          ..sort(
            (a, b) => (b.value['wrong'] ?? 0).compareTo(a.value['wrong'] ?? 0),
          );

    if (mistakes.isEmpty) {
      return Center(
        child: Text(
          searchQuery.isEmpty
              ? 'Henüz hata kaydı yok.\nHarika gidiyorsun!'
              : 'Sonuç bulunamadı.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: mistakes.length,
      itemBuilder: (context, index) {
        final entry = mistakes[index];
        final word = entry.key;
        final wrongCount = entry.value['wrong'] ?? 0;
        final correctCount = entry.value['correct'] ?? 0;

        return Card(
          color: Colors.white.withValues(alpha: 0.1),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            leading: IconButton(
              icon: const Icon(Icons.volume_up, color: Colors.tealAccent),
              onPressed: () => onSpeak(word),
            ),
            title: Text(
              word,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              'Doğru: $correctCount  |  Yanlış: $wrongCount',
              style: GoogleFonts.poppins(color: Colors.white60),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                  child: Text(
                    wrongCount.toString(),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.greenAccent,
                  ),
                  tooltip: "Öğrendim",
                  onPressed: () async {
                    await context.read<UserDataProvider>().moveMistakeToKnown(
                      word,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            "Kelime öğrenilenlere taşındı! 🎉",
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class KnownList extends StatelessWidget {
  final String searchQuery;
  final Function(String) onSpeak;
  const KnownList({
    super.key,
    required this.searchQuery,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    final knownWords = userData.knownWords
        .where((w) => w.toLowerCase().contains(searchQuery))
        .toList();

    if (knownWords.isEmpty) {
      return Center(
        child: Text(
          searchQuery.isEmpty
              ? 'Henüz öğrenilen kelime yok.\nPratik yapmaya devam et!'
              : 'Sonuç bulunamadı.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 18),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: knownWords.length,
      itemBuilder: (context, index) {
        final word = knownWords[index];

        return Card(
          color: Colors.green.withValues(alpha: 0.1),
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: ListTile(
            leading: IconButton(
              icon: const Icon(Icons.volume_up, color: Colors.tealAccent),
              onPressed: () => onSpeak(word),
            ),
            title: Text(
              word,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            subtitle: Text(
              'Tamamen öğrenildi',
              style: GoogleFonts.poppins(color: Colors.white60),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.undo, color: Colors.orangeAccent),
              tooltip: "Hatalarıma geri taşı",
              onPressed: () async {
                await context.read<UserDataProvider>().moveKnownToMistake(word);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text("Kelime hatalara geri taşındı!"),
                      backgroundColor: Colors.orange,
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }
}
