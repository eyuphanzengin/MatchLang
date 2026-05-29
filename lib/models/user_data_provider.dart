import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class UserDataProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DocumentReference<Map<String, dynamic>> get _userRef {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User not logged in");
    }
    return _firestore.collection('users').doc(user.uid);
  }

  // --- TEMEL VERİLER ---
  String? userId;
  String userName = "Misafir";
  int currentLevel = 1;
  int hearts = 5;
  int stars = 0;
  int totalScore = 0;
  DateTime? lastHeartTime;
  String? avatarPath;
  int streakCount = 0;
  DateTime? lastLoginDate;

  // --- AYARLAR ---
  bool isSoundOn = true;
  bool isVibrationOn = true;

  // --- İSTATİSTİKLER ---
  Map<String, Map<String, int>> wordStats = {};
  List<String> knownWords = [];
  int todaysCorrectAnswers = 0;
  int todaysIncorrectAnswers = 0;
  int totalQuizzesPlayed = 0;

  // --- ANALITIK GETTER'LAR (Chatbot icin) ---
  double get quizAccuracy {
    final total = todaysCorrectAnswers + todaysIncorrectAnswers;
    if (total == 0) return 0.0;
    return todaysCorrectAnswers / total;
  }

  List<String> get weakestWords {
    final sorted = wordStats.entries.toList()
      ..sort((a, b) => (b.value['wrong'] ?? 0).compareTo(a.value['wrong'] ?? 0));
    return sorted.take(5).map((e) => e.key).toList();
  }

  UserDataProvider() {
    _initUser();
  }

  void _initUser() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        userId = user.uid;
        load();
      } else {
        userId = null;
        _resetLocalData();
        notifyListeners();
      }
    });
  }

  void _resetLocalData() {
    userName = "Misafir";
    currentLevel = 1;
    hearts = 5;
    stars = 0;
    totalScore = 0;
    lastHeartTime = null;
    avatarPath = 'assets/avatars/avatar1.png';
    wordStats = {};
    knownWords = [];
    isSoundOn = true;
    isVibrationOn = true;
    todaysCorrectAnswers = 0;
    todaysIncorrectAnswers = 0;
    totalQuizzesPlayed = 0;
    streakCount = 0;
    lastLoginDate = null;
  }

  Future<void> load() async {
    await _loadUserData();
  }

  // ============================================================
  // YEREL YEDEKLEME: SharedPreferences ile kritik verileri kaydet
  // Firebase baglantisi kesildiginde uygulama yerel yedekten
  // devam edebilsin diye bu sistem eklendi.
  // ============================================================
  Future<void> _saveToLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_userName', userName);
      await prefs.setInt('cached_currentLevel', currentLevel);
      await prefs.setInt('cached_hearts', hearts);
      await prefs.setInt('cached_stars', stars);
      await prefs.setInt('cached_totalScore', totalScore);
      await prefs.setString('cached_avatarPath', avatarPath ?? 'assets/avatars/avatar1.png');
      await prefs.setInt('cached_streakCount', streakCount);
      await prefs.setStringList('cached_knownWords', knownWords);
      await prefs.setInt('cached_todaysCorrect', todaysCorrectAnswers);
      await prefs.setInt('cached_todaysIncorrect', todaysIncorrectAnswers);
      await prefs.setInt('cached_totalQuizzesPlayed', totalQuizzesPlayed);
      await prefs.setBool('cached_isSoundOn', isSoundOn);
      await prefs.setBool('cached_isVibrationOn', isVibrationOn);
      if (lastHeartTime != null) {
        await prefs.setString('cached_lastHeartTime', lastHeartTime!.toIso8601String());
      }
      if (lastLoginDate != null) {
        await prefs.setString('cached_lastLoginDate', lastLoginDate!.toIso8601String());
      }
      await prefs.setString('cached_wordStats', jsonEncode(wordStats));
      if (kDebugMode) debugPrint("[LocalCache] Veriler yerele kaydedildi.");
    } catch (e) {
      if (kDebugMode) debugPrint("[LocalCache] Kaydetme hatasi: $e");
    }
  }

  Future<void> _loadFromLocalCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      userName = prefs.getString('cached_userName') ?? "Misafir";
      currentLevel = prefs.getInt('cached_currentLevel') ?? 1;
      hearts = prefs.getInt('cached_hearts') ?? 5;
      stars = prefs.getInt('cached_stars') ?? 0;
      totalScore = prefs.getInt('cached_totalScore') ?? 0;
      avatarPath = prefs.getString('cached_avatarPath') ?? 'assets/avatars/avatar1.png';
      streakCount = prefs.getInt('cached_streakCount') ?? 0;
      knownWords = prefs.getStringList('cached_knownWords') ?? [];
      todaysCorrectAnswers = prefs.getInt('cached_todaysCorrect') ?? 0;
      todaysIncorrectAnswers = prefs.getInt('cached_todaysIncorrect') ?? 0;
      totalQuizzesPlayed = prefs.getInt('cached_totalQuizzesPlayed') ?? 0;
      isSoundOn = prefs.getBool('cached_isSoundOn') ?? true;
      isVibrationOn = prefs.getBool('cached_isVibrationOn') ?? true;
      final heartStr = prefs.getString('cached_lastHeartTime');
      if (heartStr != null) lastHeartTime = DateTime.tryParse(heartStr);
      final loginStr = prefs.getString('cached_lastLoginDate');
      if (loginStr != null) lastLoginDate = DateTime.tryParse(loginStr);
      final statsStr = prefs.getString('cached_wordStats');
      if (statsStr != null) {
        final decoded = jsonDecode(statsStr) as Map<String, dynamic>;
        wordStats = decoded.map((key, value) => MapEntry(
          key,
          Map<String, int>.from(value as Map),
        ));
      }
      if (kDebugMode) debugPrint("[LocalCache] Veriler yerel yedekten yuklendi.");
    } catch (e) {
      if (kDebugMode) debugPrint("[LocalCache] Yukleme hatasi: $e");
    }
  }

  Future<void> _loadUserData() async {
    if (userId == null) return;
    try {
      final doc = await _userRef.get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        userName = data['userName'] ?? "Misafir";
        currentLevel = data['currentLevel'] ?? 1;
        hearts = data['hearts'] ?? 5;
        stars = data['stars'] ?? 0;
        totalScore = data['score'] ?? 0;
        avatarPath = data['avatarPath'] ?? 'assets/avatars/avatar1.png';
        isSoundOn = data['isSoundOn'] ?? true;
        isVibrationOn = data['isVibrationOn'] ?? true;
        todaysCorrectAnswers = data['todaysCorrectAnswers'] ?? 0;
        todaysIncorrectAnswers = data['todaysIncorrectAnswers'] ?? 0;
        totalQuizzesPlayed = data['totalQuizzesPlayed'] ?? 0;
        if (data['knownWords'] != null) {
          knownWords = List<String>.from(data['knownWords']);
        }
        if (data['lastHeartTime'] != null) {
          lastHeartTime = (data['lastHeartTime'] as Timestamp).toDate();
        }
        streakCount = data['streakCount'] ?? 0;
        if (data['lastLoginDate'] != null) {
          lastLoginDate = (data['lastLoginDate'] as Timestamp).toDate();
        }

        _checkAndUpdateStreak();
        
        // Firebase'den basariyla yuklendikten sonra yerel yedek al
        await _saveToLocalCache();
      } else {
        await _initNewUser();
      }
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint("Firebase yukleme hatasi, yerel yedek deneniyor: $e");
      // Firebase baglantisi yoksa yerel yedekten yukle
      await _loadFromLocalCache();
      notifyListeners();
    }
  }

  Future<void> _initNewUser() async {
    await _userRef.set({
      'userName': "Misafir",
      'currentLevel': 1,
      'hearts': 5,
      'stars': 0,
      'score': 0,
      'lastHeartTime': null,
      'avatarPath': 'assets/avatars/avatar1.png',
      'isSoundOn': true,
      'isVibrationOn': true,
      'todaysCorrectAnswers': 0,
      'todaysIncorrectAnswers': 0,
      'totalQuizzesPlayed': 0,
      'knownWords': [],
      'streakCount': 0,
      'lastLoginDate': null,
    });
    _resetLocalData();
  }

  Future<void> mergeGuestDataToNewUser(String newUserId) async {
    userId = newUserId;
    await load();
  }

  void _checkAndUpdateStreak() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lastLoginDate != null) {
      final lastLogin = DateTime(
        lastLoginDate!.year,
        lastLoginDate!.month,
        lastLoginDate!.day,
      );
      final difference = today.difference(lastLogin).inDays;

      if (difference > 1) {
        // Seri bozulmuş, sadece sıfırla ama arttırma. Arttırma oyun kazanınca olur.
        streakCount = 0;
        if (userId != null) {
          _userRef.update({'streakCount': streakCount});
        }
      }
    }
  }

  /// Günün ilk oyunu kazanıldığında çağrılır.
  /// Eğer o gün için seri henüz artmamışsa artırır ve true döner.
  bool increaseStreakIfNeeded() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (lastLoginDate != null) {
      final lastLogin = DateTime(
        lastLoginDate!.year,
        lastLoginDate!.month,
        lastLoginDate!.day,
      );
      final difference = today.difference(lastLogin).inDays;

      if (difference >= 1) {
        streakCount++;
        lastLoginDate = now;
        notifyListeners();
        if (userId != null) {
          _userRef.update({
            'streakCount': streakCount,
            'lastLoginDate': Timestamp.fromDate(now),
          });
        }
        return true;
      }
      return false; // Aynı gün zaten artmış
    } else {
      // Hiç oyunu yok
      streakCount = 1;
      lastLoginDate = now;
      notifyListeners();
      if (userId != null) {
        _userRef.update({
          'streakCount': streakCount,
          'lastLoginDate': Timestamp.fromDate(now),
        });
      }
      return true;
    }
  }

  Future<void> updateUserName(String newName) async {
    userName = newName;
    notifyListeners();
    if (userId != null) await _userRef.update({'userName': newName});
  }

  Future<void> updateAvatarPath(String path) async {
    // EKSİK OLAN METOD
    avatarPath = path;
    notifyListeners();
    if (userId != null) await _userRef.update({'avatarPath': path});
  }

  Future<void> updateHeartsAndLastTime(int newHearts, DateTime? newTime) async {
    hearts = newHearts;
    lastHeartTime = newTime;
    notifyListeners();
    if (userId != null) {
      await _userRef.update({
        'hearts': newHearts,
        'lastHeartTime': newTime != null ? Timestamp.fromDate(newTime) : null,
      });
    }
  }

  Future<void> updateHearts(int newHearts) async {
    await updateHeartsAndLastTime(newHearts, lastHeartTime);
  }

  Future<void> updateLastHeartTime(DateTime time) async {
    lastHeartTime = time;
    notifyListeners();
    if (userId != null) {
      await _userRef.update({'lastHeartTime': Timestamp.fromDate(time)});
    }
  }

  Future<void> addScore(int points) async {
    totalScore += points;
    notifyListeners();
    if (userId != null) await _userRef.update({'score': totalScore});
    await _saveToLocalCache();
  }

  Future<void> completeLevel(int levelPlayed) async {
    if (levelPlayed == currentLevel) {
      currentLevel++;
      if (userId != null) await _userRef.update({'currentLevel': currentLevel});
      if ((currentLevel - 1) % 10 == 0) {
        stars = (currentLevel - 1) ~/ 10;
        if (userId != null) await _userRef.update({'stars': stars});
      }
      notifyListeners();
      await _saveToLocalCache();
    }
  }

  Future<void> updateSoundSetting(bool value) async {
    isSoundOn = value;
    notifyListeners();
    if (userId != null) await _userRef.update({'isSoundOn': value});
  }

  Future<void> updateVibrationSetting(bool value) async {
    isVibrationOn = value;
    notifyListeners();
    if (userId != null) await _userRef.update({'isVibrationOn': value});
  }

  Future<void> updateWordStats(String word, bool isCorrect) async {
    // 1. Kelime istatistiklerini güncelle (Hafıza)
    if (!wordStats.containsKey(word)) {
      wordStats[word] = {'correct': 0, 'wrong': 0};
    }

    if (isCorrect) {
      wordStats[word]!['correct'] = (wordStats[word]!['correct'] ?? 0) + 1;
      // Eğer belirli bir eşiği geçerse "Known" olarak işaretle
      if ((wordStats[word]!['correct'] ?? 0) > 3) {
        if (!knownWords.contains(word)) knownWords.add(word);
      }
    } else {
      wordStats[word]!['wrong'] = (wordStats[word]!['wrong'] ?? 0) + 1;
    }

    notifyListeners(); // Arayüzü güncelle

    // 2. Firestore güncelle
    if (userId != null) {
      await _userRef.update({'wordStats': wordStats, 'knownWords': knownWords});
    }
  }

  Future<void> saveMistakesBatch(List<String> mistakes) async {
    if (mistakes.isEmpty) return;

    bool needsUpdate = false;
    for (String word in mistakes) {
      if (!wordStats.containsKey(word)) {
        wordStats[word] = {'correct': 0, 'wrong': 0};
      }
      wordStats[word]!['wrong'] = (wordStats[word]!['wrong'] ?? 0) + 1;
      needsUpdate = true;
    }

    if (needsUpdate) {
      notifyListeners();
      if (userId != null) {
        await _userRef.update({'wordStats': wordStats});
      }
    }
  }

  Future<void> moveMistakeToKnown(String word) async {
    // 1. Öğrenilenlere ekle (Eğer yoksa)
    if (!knownWords.contains(word)) {
      knownWords.add(word);
    }

    // 2. Hata listesinden tamamen çıkar
    if (wordStats.containsKey(word)) {
      wordStats.remove(word);
    }

    // 3. UI ve Veritabanı güncellemesi
    notifyListeners();
    if (userId != null) {
      await _userRef.update({'knownWords': knownWords, 'wordStats': wordStats});
    }
  }

  Future<void> moveKnownToMistake(String word) async {
    // 1. Öğrenilenlerden tamamen çıkar
    knownWords.remove(word);

    // 2. Hata listesine yeniden ekle (En az 1 hatası olsun)
    if (!wordStats.containsKey(word)) {
      wordStats[word] = {'correct': 0, 'wrong': 1};
    } else {
      // Zaten varsa (nadir durum) wrong sayısını artır veya en az 1 yap
      int currentWrong = wordStats[word]!['wrong'] ?? 0;
      if (currentWrong == 0) {
        wordStats[word]!['wrong'] = 1;
      }
    }

    // 3. UI ve Veritabanı güncellemesi
    notifyListeners();
    if (userId != null) {
      await _userRef.update({'knownWords': knownWords, 'wordStats': wordStats});
    }
  }

  Stream<List<Map<String, dynamic>>> leaderboardStream() {
    return _firestore
        .collection('users')
        .orderBy('score', descending: true)
        .limit(20)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Future<void> recordAnswer(bool isCorrect) async {
    if (isCorrect) {
      todaysCorrectAnswers++;
    } else {
      todaysIncorrectAnswers++;
    }
    notifyListeners();
    if (userId != null) {
      await _userRef.update({
        'todaysCorrectAnswers': todaysCorrectAnswers,
        'todaysIncorrectAnswers': todaysIncorrectAnswers,
      });
    }
    await _saveToLocalCache();
  }

  Future<void> incrementQuizzesPlayed() async {
    totalQuizzesPlayed++;
    notifyListeners();
    if (userId != null) {
      await _userRef.update({'totalQuizzesPlayed': totalQuizzesPlayed});
    }
    await _saveToLocalCache();
  }

  Future<void> markAsKnown(String word) async {
    if (!knownWords.contains(word)) {
      knownWords.add(word);
      notifyListeners();
      if (userId != null) await _userRef.update({'knownWords': knownWords});
    }
  }

  Future<List<Map<String, dynamic>>> fetchQuizQuestions(String level) async {
    return [];
  }

  Future<List<Map<String, String>>> fetchWordsForLevel(String level) async {
    return [];
  }

  Future<void> seedDatabaseWithSampleQuizzes() async {
    if (kDebugMode) debugPrint("Seed fonksiyonu çağrıldı (Pasif Mod)");
  }

  Future<void> resetProgress() async {
    if (userId == null) return;
    try {
      await _userRef.delete();
      _resetLocalData();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint("Reset hatası: $e");
    }
  }

  Future<void> signOutAndReload() async {
    await FirebaseAuth.instance.signOut();
    _resetLocalData();
    notifyListeners();
  }
}
