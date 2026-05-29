import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class ServiceManager {
  static final ServiceManager _instance = ServiceManager._internal();
  factory ServiceManager() => _instance;
  ServiceManager._internal();

  bool _isEmulator = false;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    
    try {
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        // Check standard emulator indicators
        _isEmulator = !androidInfo.isPhysicalDevice ||
            androidInfo.model.contains('Emulator') ||
            androidInfo.model.contains('Android SDK built for x86') ||
            androidInfo.model.toLowerCase().contains('gphone') || // Yeni nesil emülatörler
            androidInfo.model.toLowerCase().contains('sdk') ||
            androidInfo.hardware.contains('goldfish') ||
            androidInfo.hardware.contains('ranchu') ||
            androidInfo.fingerprint.startsWith('generic') ||
            androidInfo.fingerprint.startsWith('unknown');
            
        debugPrint("[ServiceManager] Android Cihaz Tespiti. Emülatör mü?: $_isEmulator");
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _isEmulator = !iosInfo.isPhysicalDevice;
        debugPrint("[ServiceManager] iOS Cihaz Tespiti. Simülatör mü?: $_isEmulator");
      }
    } catch (e) {
      debugPrint("[ServiceManager] Cihaz tespiti yapılırken hata oluştu: $e");
      // Hata durumunda güvenli liman olarak emülatör varsay, çünkü çökme riski taşıyor
      _isEmulator = true; 
    }

    _isInitialized = true;
  }

  bool get isEmulator => _isEmulator;
  
  // TTS için karar mekanizması
  bool get shouldUseCloudTts => _isEmulator; // Eğer emülatörse bulut(gTTS) kullan

  // Backend adresi (Emülatörler ve gerçek cihazlar için localhost yönlendirmesi)
  String get backendBaseUrl {
    if (kIsWeb) {
      return 'http://127.0.0.1:8000';
    }
    try {
      if (Platform.isAndroid) {
        if (_isEmulator) {
          return 'http://10.0.2.2:8000';
        } else {
          // Gerçek Android cihazlarda 'adb reverse tcp:8000 tcp:8000' ile localhost yönlendirilir.
          return 'http://127.0.0.1:8000';
        }
      }
    } catch (_) {}
    return 'http://127.0.0.1:8000';
  }
}
