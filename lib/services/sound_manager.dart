import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../models/user_data_provider.dart';

class SoundManager {
  final UserDataProvider _userDataProvider;

  SoundManager({required UserDataProvider userDataProvider})
    : _userDataProvider = userDataProvider;

  Future<void> playSuccessSound() async {
    if (_userDataProvider.isSoundOn) {
      try {
        final player = AudioPlayer();
        await player.play(AssetSource('audio/success.wav'));
      } catch (e) {
        debugPrint("Başarı sesi çalınırken hata oluştu: $e");
      }
    }
  }

  Future<void> playFailSound() async {
    if (_userDataProvider.isSoundOn) {
      try {
        final player = AudioPlayer();
        await player.play(AssetSource('audio/fail.mp3'));
      } catch (e) {
        debugPrint("Hata sesi çalınırken hata oluştu: $e");
      }
    }
  }

  void dispose() {}
}
