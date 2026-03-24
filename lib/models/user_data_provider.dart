import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    streakCount = 0;
    lastLoginDate = null;
  }

  Future<void> load() async {
    await _loadUserData();
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
      } else {
        await _initNewUser();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading user data: $e");
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
    debugPrint("Seed fonksiyonu çağrıldı (Pasif Mod)");
  }

  Future<void> resetProgress() async {
    if (userId == null) return;
    try {
      await _userRef.delete();
      _resetLocalData();
      notifyListeners();
    } catch (e) {
      debugPrint("Reset hatası: $e");
    }
  }

  Future<void> signOutAndReload() async {
    await FirebaseAuth.instance.signOut();
    _resetLocalData();
    notifyListeners();
  }
}
