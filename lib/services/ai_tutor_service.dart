import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/content_bank.dart';

class AITutorService with ChangeNotifier {
  GenerativeModel? _model;
  // USER API KEY entegre edildi
  String? _apiKey = "AIzaSyBvVD6LHiMBp5RMBBCjRHnBQ3_pzrCjyfA";

  AITutorService() {
    _initModel();
  }

  void _initModel() {
    if (_apiKey != null && _apiKey!.isNotEmpty) {
      try {
        _model = GenerativeModel(model: 'gemini-2.0-flash', apiKey: _apiKey!);
        debugPrint("Gemini AI Modeli Başlatıldı (gemini-2.0-flash).");
      } catch (e) {
        debugPrint("AI Model başlatma hatası: $e");
      }
    }
  }

  // --- API ANAHTARI AYARLAYICI ---
  void setApiKey(String key) {
    if (key.isNotEmpty) {
      _apiKey = key;
      _initModel();
      notifyListeners();
    }
  }

  bool get isAiActive => _apiKey != null && _model != null;

  // --- QUIZ OLUŞTURMA ---
  Future<List<Map<String, dynamic>>> generateQuiz({
    required String level,
    required String topic,
    int? exactLevel, // 1-100 arası
  }) async {
    int lvl = exactLevel ?? 1;
    if (exactLevel == null) {
      // Yedek: dizeden ayrıştır
      String levelKey = level.replaceAll(RegExp(r'[^0-9]'), '');
      if (levelKey.isEmpty) levelKey = "1";
      lvl = int.tryParse(levelKey) ?? 1;
    }

    // 1. EĞER GEMINI AKTİFSE ORADAN ÇEK
    if (isAiActive) {
      try {
        return await _generateWithGemini(lvl, topic);
      } catch (e) {
        debugPrint("Gemini hatası, yedek kullanılıyor: $e");
      }
    }

    // 2. AKSİ HALDE ZENGİN LOKAL VERİYİ KULLAN
    await Future.delayed(
      const Duration(milliseconds: 600),
    ); // Simüle edilmiş yükleme
    return _generateProceduralQuiz(lvl);
  }

  // --- GEMINI MANTIĞI ---
  Future<List<Map<String, dynamic>>> _generateWithGemini(
    int level,
    String topic,
  ) async {
    if (_model == null) throw Exception("AI Model not initialized");

    // Zorluk (CEFR) hesapla
    String cefr = 'A1';
    if (level >= 76) {
      cefr = 'B2';
    } else if (level >= 51) {
      cefr = 'B1';
    } else if (level >= 26) {
      cefr = 'A2';
    }
    final prompt =
        """
      Generate a language learning quiz for level $level / 100 (CEFR Level: $cefr).
      Topic: $topic.
      
      Return ONLY valid JSON.
      Format:
      [
        {
          "type": "match",
          "question": "Eşleştirme",
          "pairs": [{"en": "Word", "tr": "Kelime"}] (5 pairs)
        },
        {
          "type": "audio_assembly",
          "question": "Duyduğunu Kur",
          "target": "English sentence",
          "distractors": ["wrong", "words"]
        },
        {
          "type": "translate_sentence",
          "question": "Bu cümleyi çevir",
          "source": "English sentence to translate",
          "target": "Beklenen Türkçe Cümle",
          "options": ["doğru", "kelime", "yanlış", "kelimeler"] (Mixed options for user to build turkish sentence)
        },
        {
          "type": "choice",
          "question": "Soru metni",
          "options": ["A", "B", "C", "D"],
          "answer": "Correct Option"
        }
      ]
      Provide exactly 10 diverse questions (mix all types) appropriate for CEFR $cefr.
    """;

    final content = [Content.text(prompt)];
    final response = await _model!.generateContent(content);

    String? jsonStr = response.text;
    if (jsonStr == null) throw Exception("Empty AI response");

    // Markdown temizliği
    jsonStr = jsonStr.replaceAll('```json', '').replaceAll('```', '').trim();

    final List<dynamic> decoded = jsonDecode(jsonStr);
    return List<Map<String, dynamic>>.from(decoded);
  }

  // --- YEREL YEDEK MANTIĞI ---
  List<Map<String, dynamic>> _generateProceduralQuiz(int level) {
    // Zorluk belirle: 1-25 A1, 26-50 A2, 51-75 B1, 76-100 B2
    String difficultyKey = 'A1';
    if (level >= 76) {
      difficultyKey = 'B2';
    } else if (level >= 51) {
      difficultyKey = 'B1';
    } else if (level >= 26) {
      difficultyKey = 'A2';
    }
    // Bankadan veri çek
    final wordPool = List<Map<String, String>>.from(
      ContentBank.words[difficultyKey] ?? [],
    );
    final sentencePool = List<Map<String, String>>.from(
      ContentBank.sentences[difficultyKey] ?? [],
    );

    final random = Random();
    List<Map<String, dynamic>> quiz = [];

    // 1. EŞLEŞTİRME
    if (wordPool.isNotEmpty) {
      wordPool.shuffle(random);
      List<Map<String, String>> pairs = [];
      for (int i = 0; i < 5 && i < wordPool.length; i++) {
        pairs.add(wordPool[i]);
      }
      quiz.add({
        "type": "match",
        "question": "Kelimeleri Eşleştir",
        "pairs": pairs,
      });
    }

    // 2. DUYDUĞUNU OLUŞTUR (Cümle)
    if (sentencePool.isNotEmpty) {
      final targetMap = sentencePool[random.nextInt(sentencePool.length)];
      final target = targetMap['en']!;

      // Yanıltıcılar
      List<String> distractors = [];
      for (int i = 0; i < 3; i++) {
        if (wordPool.isNotEmpty) {
          distractors.add(wordPool[random.nextInt(wordPool.length)]['en']!);
        }
      }

      quiz.add({
        "type": "audio_assembly",
        "question": "Duyduğunu Oluştur",
        "target": target,
        "distractors": distractors,
      });
    }

    // 3. ÇOKTAN SEÇMELİ
    if (wordPool.isNotEmpty) {
      final qWord = wordPool[random.nextInt(wordPool.length)];
      final correct = qWord['en']!;
      final options = <String>[correct];

      int attempts = 0;
      while (options.length < 4 && attempts < 20) {
        final w = wordPool[random.nextInt(wordPool.length)]['en']!;
        if (!options.contains(w)) options.add(w);
        attempts++;
      }
      options.shuffle(random);

      quiz.add({
        "type": "choice",
        "question": "'${qWord['tr']}' kelimesinin İngilizcesi nedir?",
        "options": options,
        "answer": correct,
      });
    }

    // 4. SESLİ OKUMA
    if (sentencePool.isNotEmpty) {
      final s = sentencePool[random.nextInt(sentencePool.length)]['en']!;
      quiz.add({"type": "speaking", "question": "Sesli Oku", "target": s});
    }

    return quiz;
  }

  // --- HATA AÇIKLAYICI ---
  Future<String> explainMistake({
    String? original,
    String? userAnswer,
    String? correctAnswer,
    String? contextType,
  }) async {
    // Eğer AI aktifse ona sorabiliriz
    if (isAiActive && _model != null) {
      try {
        final prompt =
            "Explain simply in Turkish why '$userAnswer' is wrong for target '$correctAnswer'. Context: $contextType (English learning). Keep it short.";
        final response = await _model!.generateContent([Content.text(prompt)]);
        if (response.text != null) return response.text!;
      } catch (e) {
        // Hata olursa lokale düş
      }
    }

    // Yedek
    await Future.delayed(const Duration(milliseconds: 500));
    return "Cevabınız yanlıştı. Doğru cevap '$correctAnswer'. İngilizcede cümle yapısı Özne + Yüklem + Nesne şeklindedir.";
  }
}
