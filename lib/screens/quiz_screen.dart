import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:string_similarity/string_similarity.dart';

import '../services/ai_tutor_service.dart';
import '../services/sound_manager.dart';
import '../services/tts_manager.dart';
import '../models/user_data_provider.dart';

class QuizScreen extends StatefulWidget {
  final String level;
  final int levelIndex;

  const QuizScreen({super.key, required this.level, required this.levelIndex});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  int _correctAnswers = 0;
  int _mistakes = 0; // Track incorrect attempts for accuracy
  final Set<String> _sessionMistakes =
      {}; // Oyun içi hatalı kelimeleri burada biriktiriyoruz
  late DateTime _startTime;

  // YÖNETİCİLER
  late SoundManager _soundManager;
  final TtsManager _ttsManager = TtsManager(); // Ortak TTS örneği

  // CAN SİSTEMİ
  int _lives = 5; // 5 can

  // Geri Bildirim Durumu
  bool _showingFeedback = false;
  bool _lastAnswerCorrect = false;

  @override
  void initState() {
    super.initState();
    _soundManager = SoundManager(
      userDataProvider: context.read<UserDataProvider>(),
    );
    _startTime = DateTime.now();
    _loadQuiz();
  }

  @override
  void dispose() {
    _soundManager.dispose();
    super.dispose();
  }

  Future<void> _loadQuiz() async {
    final aiService = context.read<AITutorService>();
    final questions = await aiService.generateQuiz(
      level: widget.level,
      exactLevel: widget.levelIndex,
      topic: 'General',
    );

    if (mounted) {
      setState(() {
        _questions = questions;
        _isLoading = false;
        _startTime = DateTime.now();
      });
    }
  }

  void _handleAnswer(bool isCorrect, {String? mistakeWord}) {
    if (isCorrect) {
      // DOĞRU CEVAP
      _soundManager.playSuccessSound();
      context.read<UserDataProvider>().recordAnswer(true);

      setState(() {
        _lastAnswerCorrect = true;
        _showingFeedback = true;
      });
    } else {
      // YANLIŞ CEVAP
      _soundManager.playFailSound();
      _mistakes++;
      // Canı burada düşürmüyoruz, sadece yerel state
      setState(() {
        _lives--;
      });
      context.read<UserDataProvider>().recordAnswer(false);

      // Yanlış yapılan kelimeyi kaydetmeye çalış
      _recordMistake(mistakeWord);

      if (_lives <= 0) {
        final userData = context.read<UserDataProvider>();
        // Canları firebase/provider tarafında güncelle
        if (userData.hearts > 0) {
          userData.updateHearts(userData.hearts - 1);
        }

        setState(() {
          _lastAnswerCorrect = false;
          _showingFeedback = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Yanlış cevap! Tekrar dene. -1 Can"),
            backgroundColor: Colors.redAccent,
            duration: const Duration(milliseconds: 1500),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.only(
              bottom: MediaQuery.of(context).size.height - 150,
              left: 20,
              right: 20,
            ),
          ),
        );
      }
    }
  }

  void _recordMistake([String? specificWord]) {
    try {
      final q = _questions[_currentIndex];
      String? wordToTrack;

      if (specificWord != null) {
        wordToTrack = specificWord;
      } else if (q['type'] == 'choice' && q.containsKey('answer')) {
        wordToTrack = q['answer'];
      } else if (q.containsKey('target')) {
        wordToTrack = q['target']?.toString();
      }

      // Tüm metinleri (kelime veya cümle) kaydetmeye izin veriyoruz.
      // Gereksiz boşlukları ve temel noktalama işaretlerini temizleyelim.
      if (wordToTrack != null && wordToTrack.trim().isNotEmpty) {
        String cleanWord = wordToTrack.trim().replaceAll(
          RegExp(r'[^\w\sğüşıöçĞÜŞİÖÇ]'),
          '',
        );

        // Temizlendikten sonra hala geçerli bir içerik varsa kaydet
        if (cleanWord.isNotEmpty) {
          _sessionMistakes.add(cleanWord);
        }
      }
    } catch (e) {
      debugPrint("Mistake record error: $e");
    }
  }

  bool _canPop = false;

  void _onExit() {
    final userData = context.read<UserDataProvider>();
    if (userData.hearts > 0) {
      userData.updateHearts(userData.hearts - 1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Oyun terk edildi. -1 Can"),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 2),
        ),
      );
    }
    setState(() {
      _canPop = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  void _onContinuePressed() {
    if (_lives <= 0) {
      _failQuiz();
    } else {
      // Sadece doğru bilindiyse ilerle
      if (_lastAnswerCorrect) {
        _advanceQuestion(true);
      } else {
        // Bu blok erişilemez olmalı çünkü yanlış cevapta katman açmıyoruz (Can > 0 ise)
        // Ama kod güvenliği için: katmanı kapat.
        setState(() {
          _showingFeedback = false;
        });
      }
    }
  }

  void _advanceQuestion(bool isCorrect) {
    if (isCorrect) _correctAnswers++;

    setState(() {
      _showingFeedback = false;
    });

    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      _finishQuiz();
    }
  }

  void _failQuiz() {
    // Toplu şekilde hataları veritabanına kaydet
    context.read<UserDataProvider>().saveMistakesBatch(
      _sessionMistakes.toList(),
    );

    // Can güncellemesi zaten _handleAnswer içinde yapıldı

    final duration = DateTime.now().difference(_startTime);
    final totalQuestions = _questions.length;
    // Başarısızlık durumunda puan 0 veya düşük, ancak şu ana kadar kazanılanı hesaplayalım
    final score = (_correctAnswers * 10);

    // Canları zaten düşürdük. Şimdi Diyalog yerine "Sonuç Ekranı"nı göster.
    // isSuccess = false olarak gönder

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          score: score,
          totalQuestions: totalQuestions,
          correctAnswers: _correctAnswers,
          duration: duration,
          isSuccess: false,
          levelPlayed: widget.levelIndex,
          mistakes: _mistakes,
        ),
      ),
    );
  }

  void _finishQuiz() {
    // Toplu şekilde hataları veritabanına kaydet
    context.read<UserDataProvider>().saveMistakesBatch(
      _sessionMistakes.toList(),
    );

    final duration = DateTime.now().difference(_startTime);
    final totalQuestions = _questions.length;
    final score = (_correctAnswers * 10) + (totalQuestions * 2);

    final userData = context.read<UserDataProvider>();
    userData.addScore(score);

    final bool isSuccess =
        totalQuestions > 0 && (_correctAnswers / totalQuestions) >= 0.5;

    bool streakIncreased = false;
    int oldStreak = userData.streakCount;
    if (isSuccess) {
      // Bu metot true dönerse seri artışa geçmiş demektir
      streakIncreased = userData.increaseStreakIfNeeded();
    }

    if (streakIncreased) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => StreakCelebrationScreen(
            oldStreak: oldStreak,
            newStreak: userData.streakCount,
            score: score,
            totalQuestions: totalQuestions,
            correctAnswers: _correctAnswers,
            duration: duration,
            isSuccess: isSuccess,
            levelPlayed: widget.levelIndex,
            mistakes: _mistakes,
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            score: score,
            totalQuestions: totalQuestions,
            correctAnswers: _correctAnswers,
            duration: duration,
            isSuccess: isSuccess,
            levelPlayed: widget.levelIndex,
            mistakes: _mistakes,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onExit();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A237E), Color(0xFF0097A7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),

            SafeArea(
              child: _isLoading
                  ? _buildLoading()
                  : _questions.isEmpty
                  ? _buildErrorState()
                  : _buildQuizContent(),
            ),

            if (_showingFeedback) _buildFeedbackOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedbackOverlay() {
    final bool isGameOver = _lives <= 0;
    // Eğer oyun bitmediyse ve doğru bildiyse -> Harika
    // Eğer oyun bittiyse -> Hakkınız Bitti
    // Yanlış bildi ama oyun bitmediyse -> Zaten Overlay açılmıyor bu kodla.

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      width: double.infinity,
      height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isGameOver ? Icons.heart_broken : Icons.check_circle,
            size: 100,
            color: isGameOver ? Colors.red : Colors.greenAccent,
          ),
          const SizedBox(height: 20),
          Text(
            isGameOver ? "Hakkınız Bitti!" : "HARİKA!",
            textAlign: TextAlign.center,
            style: GoogleFonts.rubik(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (isGameOver)
            const Text(
              "Tekrar Denemek İçin Yeterli Canın Kalmadı.",
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          const SizedBox(height: 50),
          ElevatedButton(
            onPressed: _onContinuePressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            ),
            child: Text(
              isGameOver ? "SONUÇLARI GÖR" : "DEVAM ET",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 20),
          Text(
            "Yapay Zeka Quiz Hazırlıyor...",
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Text("Hata oluştu", style: TextStyle(color: Colors.white)),
    );
  }

  Widget _buildQuizContent() {
    final currentQ = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _onExit,
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white24,
                    color: Colors.amberAccent,
                    minHeight: 12,
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Row(
                children: [
                  const Icon(Icons.favorite, color: Colors.redAccent),
                  const SizedBox(width: 5),
                  Text(
                    "$_lives",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: KeyedSubtree(
              key: ValueKey(_currentIndex),
              child: _buildQuestionWidget(currentQ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionWidget(Map<String, dynamic> questionData) {
    switch (questionData['type']) {
      case 'translate_sentence':
        return TranslateQuestionWidget(
          data: questionData,
          ttsManager: _ttsManager,
          onResult: (success) => _handleAnswer(success),
        );
      case 'choice':
        return MultipleChoiceWidget(
          data: questionData,
          onCorrect: () => _handleAnswer(true),
          onWrong: () => _handleAnswer(false),
        );
      case 'match':
        return MatchingQuestionWidget(
          data: questionData,
          ttsManager: _ttsManager, // PASS
          onComplete: () => _handleAnswer(true),
          onMatch: () => _soundManager.playSuccessSound(), // Her eşleşmede ses
          onWrong: (word) => _handleAnswer(false, mistakeWord: word),
        );
      case 'speaking':
        return SpeakingQuestionWidget(
          data: questionData,
          onComplete: (success) => _handleAnswer(success),
        );
      case 'audio_assembly':
        return ListeningAssemblyWidget(
          data: questionData,
          ttsManager: _ttsManager, // PASS
          onResult: (success) => _handleAnswer(success),
        );
      default:
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _advanceQuestion(true),
        );
        return const SizedBox();
    }
  }
}

// ----------------------------------------------------------------
// ALT WIDGETLAR (GÜNCELLENMİŞ TASARIM VE FIXLER)
// ----------------------------------------------------------------

// 1. MATCHING
class MatchingQuestionWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onComplete;
  final VoidCallback onMatch; // TEKİL DOĞRU EŞLEŞME İÇİN
  final Function(String?) onWrong;
  final TtsManager ttsManager; // EKLENDİ

  const MatchingQuestionWidget({
    super.key,
    required this.data,
    required this.onComplete,
    required this.onMatch,
    required this.onWrong,
    required this.ttsManager,
  });
  @override
  State<MatchingQuestionWidget> createState() => _MatchingQuestionWidgetState();
}

class _MatchingQuestionWidgetState extends State<MatchingQuestionWidget> {
  late List<Map<String, dynamic>> pairs;
  late List<String> leftSide, rightSide;
  String? selLeft, selRight;
  final Set<String> matched = {};

  @override
  void initState() {
    super.initState();
    pairs = List<Map<String, dynamic>>.from(widget.data['pairs']);
    leftSide = pairs.map((e) => e['en'].toString()).toList()..shuffle();
    rightSide = pairs.map((e) => e['tr'].toString()).toList()..shuffle();
  }

  void _tap(String w, bool isL) {
    // EĞER İNGİLİZCE KELİMEYSE OKU (SOL TARAF)
    if (isL) {
      widget.ttsManager.speak(w); // USE MANAGER
    }

    setState(() {
      if (isL) {
        selLeft = w;
      } else {
        selRight = w;
      }
    });

    if (selLeft != null && selRight != null) {
      if (pairs.any((p) => p['en'] == selLeft && p['tr'] == selRight)) {
        widget.onMatch(); // Doğru eşleşme anında efekti patlat!
        setState(() {
          matched.add(selLeft!);
          matched.add(selRight!);
          selLeft = null;
          selRight = null;
        });
        if (matched.length == pairs.length * 2) {
          widget.onComplete();
        }
      } else {
        // YANLIŞ EŞLEŞTİRME
        // Use selLeft (English) as the word to track
        widget.onWrong(selLeft);

        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            setState(() {
              selLeft = null;
              selRight = null;
            });
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter out matched items so they disappear and others reflow
    final leftItems = leftSide.where((w) => !matched.contains(w)).toList();
    final rightItems = rightSide.where((w) => !matched.contains(w)).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start, // Align to top
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: leftItems.map((w) => _itemWrapper(w, true)).toList(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: rightItems.map((w) => _itemWrapper(w, false)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemWrapper(String w, bool isL) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _item(w, isL),
    );
  }

  Widget _item(String w, bool isL) {
    // Note: Items are filtered in build, so we don't need to check isMatched here for hiding.
    // The list passed to valid wrappers will only contain unmatched items.

    // However, keeping safe check just in case
    bool isMatched = matched.contains(w);
    bool isSelected = isL ? selLeft == w : selRight == w;

    if (isMatched) {
      return const SizedBox(); // Should not happen with new logic but safe fallback
    }

    return GestureDetector(
      onTap: () => _tap(w, isL),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 75, // Büyütüldü
        width: double.infinity,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amberAccent
              : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white24,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.5),
                blurRadius: 10,
                spreadRadius: 2,
              )
            else
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: const Offset(0, 4),
              ),
          ],
          gradient: isSelected
              ? LinearGradient(
                  colors: [Colors.amber.shade200, Colors.amber.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
        ),
        child: Text(
          w,
          style: TextStyle(
            color: isSelected ? Colors.black87 : Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            shadows: isSelected
                ? []
                : [
                    Shadow(
                      color: Colors.black26,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// 2. LISTENING ASSEMBLY
class ListeningAssemblyWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Function(bool) onResult;
  final TtsManager ttsManager;

  const ListeningAssemblyWidget({
    super.key,
    required this.data,
    required this.onResult,
    required this.ttsManager,
  });

  @override
  State<ListeningAssemblyWidget> createState() =>
      _ListeningAssemblyWidgetState();
}

class _WordOption {
  final String id;
  final String word;
  bool isSelected = false;

  _WordOption({required this.id, required this.word});
}

class _ListeningAssemblyWidgetState extends State<ListeningAssemblyWidget> {
  List<_WordOption> _allOptions = [];
  final List<_WordOption> _userSelection = []; // Stores references to options
  bool _isChecked = false;
  bool _isCorrect = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() async {
    String sentence = widget.data['target'] ?? "Hello world";
    List<String> words = sentence.replaceAll(RegExp(r'[^\w\s]'), '').split(' ');
    List<String> pool = List.from(words);
    if (widget.data['distractors'] != null) {
      pool.addAll(List<String>.from(widget.data['distractors']));
    }
    pool.shuffle();

    if (mounted) {
      setState(() {
        _allOptions = pool
            .asMap()
            .entries
            .map((e) => _WordOption(id: "${e.key}_${e.value}", word: e.value))
            .toList();
      });
    }
  }

  void _playAudio({double rate = 0.5}) async {
    widget.ttsManager.speak(widget.data['target'] ?? "");
  }

  void _checkAnswer() {
    if (_isChecked && !_isCorrect) {
      setState(() {
        // Reset selection (deselect all in pool)
        for (var opt in _userSelection) {
          opt.isSelected = false;
        }
        _userSelection.clear();
        _isChecked = false;
        _isCorrect = false;
      });
      return;
    }

    String userSentence = _userSelection
        .map((e) => e.word)
        .join(" ")
        .toLowerCase();
    String target = (widget.data['target'] ?? "")
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '');

    bool correct = userSentence == target;

    setState(() {
      _isChecked = true;
      _isCorrect = correct;
    });

    if (correct) {
      widget.onResult(true);
    } else {
      widget.onResult(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            "Cümleyi Oluştur",
            style: GoogleFonts.rubik(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          // NO_CONTENT
          const SizedBox(height: 10),
          const Text(
            "Duyduğunu sırala",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 30),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _playAudio(rate: 0.5),
                child: _audioBtn(Icons.volume_up_rounded),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () => _playAudio(rate: 0.1),
                child: _audioBtn(Icons.slow_motion_video_rounded, small: true),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // SELECTED AREA
          Container(
            height: 120,
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _userSelection.map((opt) {
                return ActionChip(
                  label: Text(
                    opt.word,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  backgroundColor: Colors.blueAccent,
                  onPressed: _isChecked
                      ? null
                      : () => setState(() {
                          // Remove from selection, unmark in pool
                          _userSelection.remove(opt);
                          opt.isSelected = false;
                        }),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          // POOL AREA (Ghosting)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _allOptions.map((opt) {
              return GestureDetector(
                onTap: (_isChecked || opt.isSelected)
                    ? null
                    : () => setState(() {
                        opt.isSelected = true;
                        _userSelection.add(opt);
                      }),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: opt.isSelected
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: opt.isSelected
                          ? Colors.transparent
                          : Colors.white30,
                    ),
                  ),
                  child: Text(
                    opt.word,
                    style: TextStyle(
                      color: opt.isSelected ? Colors.transparent : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
          if (!_isChecked || !_isCorrect)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _checkAnswer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isChecked
                      ? Colors.redAccent
                      : Colors.amber, // FIXED COLOR
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  _isChecked ? "YANLIŞ - TEKRAR DENE" : "KONTROL ET",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _audioBtn(IconData icon, {bool small = false}) {
    return Container(
      width: small ? 50 : 70,
      height: small ? 50 : 70,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: small ? 24 : 32),
    );
  }
}

// 3. MULTIPLE CHOICE
class MultipleChoiceWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final VoidCallback onCorrect, onWrong;
  const MultipleChoiceWidget({
    super.key,
    required this.data,
    required this.onCorrect,
    required this.onWrong,
  });
  @override
  State<MultipleChoiceWidget> createState() => _MCState();
}

class _MCState extends State<MultipleChoiceWidget> {
  String? sel;
  bool checked = false;
  int answerStatus = 0; // 0: None, 1: Correct, 2: Wrong (Try Again), 3: Failed

  void _tap(String option) {
    if (checked && answerStatus != 2) {
      return; // Allow selection only if fresh or Try Again mode
    }

    setState(() {
      sel = option;
      checked = false; // Don't show colors yet
      answerStatus = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    List<String> opts = List<String>.from(widget.data['options']);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.data['question'],
              style: GoogleFonts.rubik(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "Bu soruya cevap ver",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
          const Spacer(),
          ...opts.map((o) {
            Color btnColor = Colors.white.withValues(alpha: 0.1);
            if (checked) {
              if (answerStatus == 1 && o == widget.data['answer']) {
                btnColor = Colors.greenAccent;
              } else if (answerStatus == 3 && o == widget.data['answer']) {
                btnColor = Colors.greenAccent; // Show correct if failed
              } else if (checked && o == sel) {
                // Selected option
                if (answerStatus == 1) {
                  btnColor = Colors.greenAccent;
                } else if (answerStatus == 2) {
                  btnColor = Colors.redAccent; // Wrong, Try Again
                } else if (answerStatus == 3) {
                  btnColor = Colors.redAccent; // Wrong, Failed
                }
              }
            } else if (sel == o) {
              btnColor = Colors.white.withValues(
                alpha: 0.3,
              ); // Highlight selected but not checked
            }

            return GestureDetector(
              onTap: () => _tap(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 15),
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: btnColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: (sel == o) ? Colors.white : Colors.white30,
                    width: (sel == o) ? 2 : 1,
                  ),
                ),
                child: Text(
                  o,
                  style: TextStyle(
                    color: (checked && (o == widget.data['answer'] || o == sel))
                        ? Colors.black
                        : Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (checked && answerStatus != 2)
                  ? null
                  : () {
                      if (checked && answerStatus == 2) {
                        // Retry action
                        setState(() {
                          checked = false;
                          sel = null;
                          answerStatus =
                              4; // 4: Used second chance (internal state to forbid 3rd chance if we wanted, but logic below handles it)
                        });
                      } else if (!checked) {
                        // Check action
                        if (sel != null) {
                          // Check Logic
                          bool isCorrect = sel == widget.data['answer'];
                          setState(() {
                            checked = true;
                          });

                          if (isCorrect) {
                            setState(() => answerStatus = 1);
                            widget.onCorrect();
                          } else {
                            // If previously retried (we can track a separate bool for 'hasRetried')
                            if (answerStatus == 4) {
                              setState(() => answerStatus = 3); // Fail
                              widget.onWrong();
                            } else {
                              setState(() => answerStatus = 2); // Try Again
                            }
                          }
                        }
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: (checked && answerStatus == 2)
                    ? Colors.orangeAccent
                    : (checked && answerStatus == 3)
                    ? Colors.red
                    : Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(
                (!checked)
                    ? "KONTROL ET"
                    : (answerStatus == 2)
                    ? "TEKRAR DENE"
                    : (answerStatus == 3)
                    ? "MAALESEF YANLIŞ CEVAP VERDİNİZ"
                    : "DOĞRU",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 4. TRANSLATE SENTENCE
class TranslateQuestionWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Function(bool) onResult;
  final TtsManager ttsManager;

  const TranslateQuestionWidget({
    super.key,
    required this.data,
    required this.onResult,
    required this.ttsManager,
  });

  @override
  State<TranslateQuestionWidget> createState() => _TranslateState();
}

class _TranslateState extends State<TranslateQuestionWidget> {
  List<_WordOption> _allOptions = [];
  final List<_WordOption> _userSelection = [];
  bool _isChecked = false;
  bool _isCorrect = false;

  @override
  void initState() {
    super.initState();
    _initData();
    // Auto play audio once
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playAudio();
    });
  }

  void _initData() {
    List<String> opts = List<String>.from(widget.data['options'] ?? []);
    opts.shuffle();
    if (mounted) {
      setState(() {
        _allOptions = opts
            .asMap()
            .entries
            .map((e) => _WordOption(id: "${e.key}_${e.value}", word: e.value))
            .toList();
      });
    }
  }

  void _playAudio() {
    widget.ttsManager.speak(widget.data['source'] ?? "");
  }

  void _checkAnswer() {
    if (_isChecked && !_isCorrect) {
      setState(() {
        for (var opt in _userSelection) {
          opt.isSelected = false;
        }
        _userSelection.clear();
        _isChecked = false;
        _isCorrect = false;
      });
      return;
    }

    String userSentence = _userSelection
        .map((e) => e.word)
        .join(" ")
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize multiple spaces
        .trim();

    String target = (widget.data['target'] ?? "")
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize multiple spaces
        .trim();

    // Remove punctuation for comparison, but keep spaces
    userSentence = userSentence.replaceAll(RegExp(r'[^\w\sğüşıöçĞÜŞİÖÇ]'), '');
    target = target.replaceAll(RegExp(r'[^\w\sğüşıöçĞÜŞİÖÇ]'), '');

    bool correct = userSentence == target;

    setState(() {
      _isChecked = true;
      _isCorrect = correct;
    });

    if (correct) {
      widget.onResult(true);
    } else {
      widget.onResult(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            "Bu Cümleyi Çevir",
            style: GoogleFonts.rubik(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.transparent,
                backgroundImage: const AssetImage('assets/avatars/avatar1.png'),
                onBackgroundImageError: (_, __) {},
                child: const Icon(Icons.person, size: 40, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                      bottomLeft: Radius.zero,
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.volume_up,
                          color: Colors.blueAccent,
                        ),
                        onPressed: _playAudio,
                      ),
                      Expanded(
                        child: Text(
                          widget.data['source'] ?? "",
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
          // SELECTED AREA
          Container(
            height: 120,
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6, // Reduced spacing
              runSpacing: 6, // Reduced spacing
              children: _userSelection.map((opt) {
                return GestureDetector(
                  onTap: _isChecked
                      ? null
                      : () {
                          setState(() {
                            _userSelection.remove(opt);
                            opt.isSelected = false;
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent,
                      borderRadius: BorderRadius.circular(
                        8,
                      ), // Less rounded for straighter look
                    ),
                    child: Text(
                      opt.word,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          // POOL AREA (Ghosting)
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: _allOptions.map((opt) {
              return GestureDetector(
                onTap: (_isChecked || opt.isSelected)
                    ? null
                    : () {
                        setState(() {
                          opt.isSelected = true;
                          _userSelection.add(opt);
                        });
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: opt.isSelected
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: opt.isSelected
                          ? Colors.transparent
                          : Colors.white30,
                    ),
                  ),
                  child: Text(
                    opt.word,
                    style: TextStyle(
                      color: opt.isSelected ? Colors.transparent : Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 30),
          if (!_isChecked || !_isCorrect)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _checkAnswer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isChecked
                      ? Colors.redAccent
                      : Colors.amber, // FIXED: Colors.amber to match
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: Text(
                  _isChecked ? "YANLIŞ - TEKRAR DENE" : "KONTROL ET",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class FillInBlankWidget extends MultipleChoiceWidget {
  const FillInBlankWidget({
    super.key,
    required super.data,
    required super.onCorrect,
    required super.onWrong,
  });
}

// 4. SPEAKING
class SpeakingQuestionWidget extends StatefulWidget {
  final Map<String, dynamic> data;
  final Function(bool) onComplete;
  const SpeakingQuestionWidget({
    super.key,
    required this.data,
    required this.onComplete,
  });
  @override
  State<SpeakingQuestionWidget> createState() => _SpeakingState();
}

class _SpeakingState extends State<SpeakingQuestionWidget> {
  stt.SpeechToText speech = stt.SpeechToText();
  bool listening = false, res = false, success = false;
  String text = "Dokun ve Konuş...";

  void _listen() async {
    if (!listening) {
      bool available = await speech.initialize();
      if (available) {
        setState(() {
          listening = true;
          text = "Dinliyorum...";
          res = false;
        });
        speech.listen(
          onResult: (v) {
            setState(() {
              text = v.recognizedWords;
            });
          },
        );
      }
    } else {
      speech.stop();
      setState(() => listening = false);
      _check();
    }
  }

  void _check() {
    if (text == "Dinliyorum..." || text == "Dokun ve Konuş...") return;
    String t = widget.data['target'] ?? "Hello";
    double sim = StringSimilarity.compareTwoStrings(
      text.toLowerCase(),
      t.toLowerCase(),
    );

    // FIX: Eşik değeri artırıldı (0.4 -> 0.7)
    bool isOk = sim > 0.65;

    setState(() {
      res = true;
      success = isOk;
    });

    if (isOk) {
      widget.onComplete(true);
    } else {
      Future.delayed(
        const Duration(seconds: 1),
        () => widget.onComplete(false),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.data['target'] ?? "Hello",
              textAlign: TextAlign.center,
              style: GoogleFonts.rubik(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            text,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 18,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 60),
          GestureDetector(
            onTap: _listen,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 100,
              width: 100,
              decoration: BoxDecoration(
                color: listening ? Colors.redAccent : Colors.cyanAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (listening ? Colors.red : Colors.cyan).withValues(
                      alpha: 0.5,
                    ),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(
                listening ? Icons.mic_off : Icons.mic,
                size: 50,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 5. RESULT SCREEN
class ResultScreen extends StatelessWidget {
  final int score, totalQuestions, correctAnswers, levelPlayed, mistakes;
  final Duration duration;
  final bool isSuccess;
  const ResultScreen({
    super.key,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.duration,
    required this.isSuccess,
    required this.levelPlayed,
    required this.mistakes,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate stats
    final int totalAttempts = correctAnswers + mistakes;
    final int accuracy = totalAttempts > 0
        ? ((correctAnswers / totalAttempts) * 100).toInt()
        : 0;
    // Or simpler: We know isSuccess.

    // "Alıştırmayı tamamladın!" vs "Alıştırma Tamamlanamadı"
    final String title = isSuccess
        ? "Alıştırmayı tamamladın!"
        : "Alıştırma Başarısız";
    final Color mainColor = isSuccess
        ? const Color(0xFF58CC02)
        : const Color(0xFFFF4B4B);

    return Scaffold(
      backgroundColor: const Color(
        0xFF131F24,
      ), // Dark background like screenshot
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            // Avatar / Icon
            // Using a placeholder or simple text if image not available, but user wants image basically.
            // Assuming we use the user's avatar or a generic success/fail image.
            Image.asset(
              'assets/avatars/avatar1.png',
              height: 120,
              errorBuilder: (c, e, s) => Icon(
                isSuccess
                    ? Icons.emoji_events_rounded
                    : Icons.heart_broken_rounded,
                size: 100,
                color: mainColor,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.rubik(
                color: mainColor,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Stats Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard(
                  label: isSuccess ? "TOPLAM PUAN" : "PUAN",
                  value: "$score",
                  color: Colors.amber,
                ),
                _buildStatCard(
                  label: isSuccess
                      ? "İYİ"
                      : "DOĞRULUK", // "İYİ" from screenshot means accuracy/goodness
                  value: "$accuracy%",
                  color: Colors.green,
                ),
                _buildStatCard(
                  label: "SÜRE", // ACELECİ? Let's use SÜRE or HIZLI
                  value:
                      "${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}",
                  color: Colors.blue,
                ),
              ],
            ),

            const Spacer(),

            // Button
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    if (isSuccess) {
                      await context.read<UserDataProvider>().completeLevel(
                        levelPlayed,
                      );
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFF49C0F8,
                    ), // Light Blue like screenshot
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                    shadowColor: const Color(0xFF1CB0F6), // Darker blue shadow
                  ),
                  child: const Text(
                    "DEVAM ET", // or PUANI AL
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF131F24), // Background match
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 2),
        // Gradient or solid bg? Reference has solid dark with colored borders/headers maybe?
        // Actually reference has colored headers. Let's approximate.
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.rubik(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2), // Light BG
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              value,
              style: GoogleFonts.rubik(
                color: color, // Text color matches theme
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StreakCelebrationScreen extends StatefulWidget {
  final int oldStreak;
  final int newStreak;

  // Result parameters
  final int score;
  final int totalQuestions;
  final int correctAnswers;
  final Duration duration;
  final bool isSuccess;
  final int levelPlayed;
  final int mistakes;

  const StreakCelebrationScreen({
    super.key,
    required this.oldStreak,
    required this.newStreak,
    required this.score,
    required this.totalQuestions,
    required this.correctAnswers,
    required this.duration,
    required this.isSuccess,
    required this.levelPlayed,
    required this.mistakes,
  });

  @override
  State<StreakCelebrationScreen> createState() =>
      _StreakCelebrationScreenState();
}

class _StreakCelebrationScreenState extends State<StreakCelebrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _showNumbers = false;
  bool _readyToContinue = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _controller.forward().then((_) {
      setState(() {
        _showNumbers = true;
      });
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _readyToContinue = true;
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToResult() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ResultScreen(
          score: widget.score,
          totalQuestions: widget.totalQuestions,
          correctAnswers: widget.correctAnswers,
          duration: widget.duration,
          isSuccess: widget.isSuccess,
          levelPlayed: widget.levelPlayed,
          mistakes: widget.mistakes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF131F24), // Koyu arka plan
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scaleAnimation,
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.deepOrangeAccent,
                  size: 150,
                ),
              ),
              const SizedBox(height: 30),
              Text(
                "GÜNLÜK SERİ KORUNDU!",
                style: GoogleFonts.rubik(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.amberAccent,
                ),
              ),
              const SizedBox(height: 20),
              if (_showNumbers)
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 500),
                  opacity: 1.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "${widget.oldStreak}",
                        style: GoogleFonts.rubik(
                          fontSize: 40,
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 20),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 40,
                      ),
                      const SizedBox(width: 20),
                      Text(
                        "${widget.newStreak}",
                        style: GoogleFonts.rubik(
                          fontSize: 60,
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              if (_readyToContinue)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 30,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: _goToResult,
                      child: Text(
                        "DEVAM ET",
                        style: GoogleFonts.rubik(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 120), // Button yer tutucu
            ],
          ),
        ),
      ),
    );
  }
}
