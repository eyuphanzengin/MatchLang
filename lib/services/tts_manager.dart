import 'package:audioplayers/audioplayers.dart';

class TtsManager {
  final AudioPlayer _audioPlayer = AudioPlayer();

  TtsManager();

  Future<void> speak(String text) async {
    try {
      await _audioPlayer.stop();
      if (text.isNotEmpty) {
        String url = 'http://10.0.2.2:8000/tts?text=${Uri.encodeComponent(text)}';
        await _audioPlayer.play(UrlSource(url));
      }
    } catch (e) {
      print("Cloud TTS Speak Error: $e");
    }
  }
}