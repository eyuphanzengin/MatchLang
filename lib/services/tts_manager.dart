import 'package:audioplayers/audioplayers.dart';

class TtsManager {
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  TtsManager();

  Future<void> speak(String text) async {
    if (text.isEmpty) return;

    try {
      // Tüm cihazlar (Emülatör ve Telefon) için Bulut (FastAPI) TTS kullan.
      // Cihazın yerel TTS motoru çökme yaptığı için tamamen kaldırıldı.
      await _audioPlayer.stop();
      String url = 'http://10.0.2.2:8000/tts?text=${Uri.encodeComponent(text)}';
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      print("TTS Speak Error: $e");
    }
  }
}