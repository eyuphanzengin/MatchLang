import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'service_manager.dart';

class TtsManager {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isSpeaking = false;
  
  TtsManager() {
    // Dinleyiciyi bir kez kur
    _audioPlayer.onPlayerComplete.listen((_) {
      _isSpeaking = false;
    });
  }

  bool get isSpeaking => _isSpeaking;

  /// Metindeki Turkce karakterlere bakarak dili otomatik algila.
  String _detectLanguage(String text) {
    // Turkce ozel karakterler
    final turkishChars = RegExp(r'[ğüşıöçĞÜŞİÖÇ]');
    // Turkce yaygin kelimeler (kisa kontrol)
    final turkishWords = ['bir', 've', 'bu', 'için', 'ile', 'olan', 'var', 
      'ben', 'sen', 'biz', 'ne', 'nasıl', 'neden', 'ama', 'çok', 'gibi',
      'daha', 'ya', 'da', 'de', 'mi', 'mı', 'değil', 'kadar', 'sonra'];
    
    // Turkce karakter varsa kesinlikle Turkce
    if (turkishChars.hasMatch(text)) return 'tr';
    
    // Kelime bazli kontrol
    final words = text.toLowerCase().split(RegExp(r'\s+'));
    int turkishCount = 0;
    for (final w in words) {
      if (turkishWords.contains(w)) turkishCount++;
    }
    // Kelimelerin %30'u Turkce ise Turkce say
    if (words.isNotEmpty && turkishCount / words.length > 0.3) return 'tr';
    
    return 'en';
  }

  /// Verilen metni seslendirir. Dil otomatik algilanir veya elle verilebilir.
  Future<void> speak(String text, {String? lang, bool slow = false}) async {
    if (text.isEmpty) return;

    // Dil belirtilmemisse otomatik algila
    lang ??= _detectLanguage(text);

    try {
      // Eger zaten caliyorsa durmasini bekle, boylece cakisma onlenir
      if (_isSpeaking) {
        await stop();
      }
      _isSpeaking = true;
      final String baseUrl = ServiceManager().backendBaseUrl;
      String url = '$baseUrl/tts?text=${Uri.encodeComponent(text)}&lang=$lang&slow=$slow';
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      _isSpeaking = false;
      debugPrint("TTS Speak Error: $e");
    }
  }

  /// Seslendirmeyi durdurur.
  Future<void> stop() async {
    try {
      _isSpeaking = false;
      await _audioPlayer.stop();
    } catch (e) {
      debugPrint("TTS Stop Error: $e");
    }
  }

  /// Kaynaklari serbest birakir.
  void dispose() {
    _audioPlayer.dispose();
  }
}