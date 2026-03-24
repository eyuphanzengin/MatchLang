import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'models/user_data_provider.dart';

// NO_CONTENT
import 'screens/welcome_screen.dart';
import 'services/sound_manager.dart';
import 'services/tts_manager.dart';
import 'services/ai_tutor_service.dart';

import 'screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  await Firebase.initializeApp();

  // Tam ekran modu
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 1. User Data Provider'ı başlat
        ChangeNotifierProvider<UserDataProvider>(
          create: (_) => UserDataProvider(),
        ),
        // 2. AI Servisi
        ChangeNotifierProvider<AITutorService>(create: (_) => AITutorService()),
        // 3. TTS Yöneticisi
        Provider<TtsManager>(create: (_) => TtsManager()),
        // 4. Ses Yöneticisi (UserDataProvider'a bağımlı)
        ProxyProvider<UserDataProvider, SoundManager>(
          update: (_, userData, __) => SoundManager(userDataProvider: userData),
          dispose: (_, soundManager) => soundManager.dispose(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MatchLang',
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.cyan,
          scaffoldBackgroundColor: const Color(0xFF121212),
          useMaterial3: true,
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return const MainScreen(); // Giriş yapılmışsa Ana Ekrana
        }
        return const WelcomeScreen(); // Değilse Karşılama Ekranına
      },
    );
  }
}
