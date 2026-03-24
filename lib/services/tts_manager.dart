import 'package:flutter_tts/flutter_tts.dart';

class TtsManager {
  final FlutterTts _flutterTts = FlutterTts();

  TtsManager() {
    _initTts();
  }

  Future<void> _initTts() async {
    // Dil ayarını İngilizce yapıyoruz (Amerikan aksanı)
    await _flutterTts.setLanguage("en-US");

    // Konuşma hızı (0.0 ile 1.0 arası). 0.5 eğitim için idealdir, net anlaşılır.
    await _flutterTts.setSpeechRate(0.5);

    // Ses tonu (1.0 normal insan sesi)
    await _flutterTts.setPitch(1.0);

    // iOS için sesin sessiz modda bile çıkmasını sağlar
    await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers
        ],
        IosTextToSpeechAudioMode.voicePrompt
    );
  }

  Future<void> speak(String text) async {
    // Eğer önceki bir konuşma varsa durdur (üst üste binmesin)
    await _flutterTts.stop();

    if (text.isNotEmpty) {
      await _flutterTts.speak(text);
    }
  }
}