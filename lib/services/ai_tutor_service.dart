import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/content_bank.dart';

class AITutorService with ChangeNotifier {
  
  // Artık yerel Llama 3.2 kullanıldığı için her zaman aktif varsayıyoruz.
  bool get isAiActive => true; 

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

    // 1. LLAMA 3.2 SUNUCUSUNDAN ÇEK
    try {
      return await _generateWithLocalLlama(lvl, topic);
    } catch (e) {
      debugPrint("Llama hatası, yedek (Procedural) banka kullanılıyor: $e");
    }

    // 2. AKSİ HALDE ZENGİN LOKAL VERİYİ KULLAN (Çevrimdışı/Yedek)
    await Future.delayed(
      const Duration(milliseconds: 600),
    ); // Simüle edilmiş yükleme
    return _generateProceduralQuiz(lvl);
  }

  // --- LLAMA (LOCAL AI) MANTIĞI ---
  Future<List<Map<String, dynamic>>> _generateWithLocalLlama(
    int level,
    String topic,
  ) async {
    const serverUrl = 'http://10.0.2.2:8000/generate_quiz';
    
    final response = await http.post(
      Uri.parse(serverUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'level': level,
        'topic': topic,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      // Gelen veri doğrudan JSON dizisidir (List<Map<String,dynamic>>)
      return List<Map<String, dynamic>>.from(decoded);
    } else {
      throw Exception("Llama Sunucu Hatası: ${response.statusCode}");
    }
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
    // AI aktif, Llama'ya sor
    try {
      const serverUrl = 'http://10.0.2.2:8000/explain';
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_answer': userAnswer ?? '',
          'correct_answer': correctAnswer ?? '',
          'context_type': contextType ?? '',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['response'] ?? "Cevap anlaşılamadı.";
      }
    } catch (e) {
      debugPrint("Llama explain hatası: $e");
    }

    // Yedek
    await Future.delayed(const Duration(milliseconds: 500));
    return "Cevabınız yanlıştı. Doğru cevap '$correctAnswer'. İngilizcede cümle yapısı Özne + Yüklem + Nesne şeklindedir.";
  }
}
