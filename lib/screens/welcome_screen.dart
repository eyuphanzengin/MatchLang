import 'package:flutter/material.dart';
// NO_CONTENT

import 'login_screen.dart';
import 'home_screen.dart';
// NO_CONTENT

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // UserDataProvider zaten main.dart içinde init oluyor,
    // burada manuel load çağırmaya gerek yok.
  }

  void _navigateToLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  void _navigateToLevel(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double screenHeight = screenSize.height;
    final double screenWidth = screenSize.width;

    final double horizontalPadding = screenWidth * 0.06;
    final double topSpacing = screenHeight * 0.1;
    final double titleToSubtitleSpacing = screenHeight * 0.05;
    final double subtitleToButtonSpacing = screenHeight * 0.15;
    final double buttonVerticalPadding = screenHeight * 0.022;

    final double titleFontSize = screenWidth * 0.11;
    final double subtitleFontSize = screenWidth * 0.05;
    final double buttonFontSize = screenWidth * 0.045;

    return Scaffold(
      backgroundColor: Colors.orange,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: screenHeight - MediaQuery.of(context).padding.top,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: topSpacing),
                  Center(
                    child: Text(
                      "MatchLang",
                      style: TextStyle(
                        fontSize: titleFontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: titleToSubtitleSpacing),
                  Center(
                    child: Text(
                      "Yeni kelimeler öğrenmeye hazır mısın?",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: subtitleFontSize,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(height: subtitleToButtonSpacing),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _navigateToLevel(context),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.white),
                        padding: EdgeInsets.symmetric(
                          vertical: buttonVerticalPadding,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Öğrenmeye Başla",
                        style: TextStyle(fontSize: buttonFontSize),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _navigateToLogin(context),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.orange,
                        side: const BorderSide(color: Colors.white),
                        padding: EdgeInsets.symmetric(
                          vertical: buttonVerticalPadding,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        "Zaten bir hesabım var",
                        style: TextStyle(fontSize: buttonFontSize),
                      ),
                    ),
                  ),
                  SizedBox(height: topSpacing / 2),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
