import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/user_data_provider.dart';

class AvatarSelectionScreen extends StatefulWidget {
  const AvatarSelectionScreen({super.key});

  @override
  State<AvatarSelectionScreen> createState() => _AvatarSelectionScreenState();
}

class _AvatarSelectionScreenState extends State<AvatarSelectionScreen> {
  final List<String> avatarPaths = List.generate(
    18,
    (index) => 'assets/avatars/avatar${index + 1}.png',
  );
  late PageController _pageController;
  int _currentPage = 0;
  String? _selectedAvatarPath;

  @override
  void initState() {
    super.initState();
    // Başlangıçta seçili olan avatarı bul ve ona odaklan
    final currentAvatar = context.read<UserDataProvider>().avatarPath;
    int initialIndex = 0;
    if (currentAvatar != null) {
      initialIndex = avatarPaths.indexOf(currentAvatar);
      if (initialIndex == -1) initialIndex = 0;
    }

    _currentPage = initialIndex;
    _selectedAvatarPath = currentAvatar;

    _pageController = PageController(
      initialPage: initialIndex,
      viewportFraction: 0.5, // Kartların genişliği
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // 1. ARKA PLAN
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1F1C2C), Color(0xFF0F2027)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: CustomPaint(painter: GridPainter()),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 2. ÜST BAR
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Text(
                    "KİMLİĞİNİ SEÇ",
                    style: GoogleFonts.orbitron(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                      shadows: [
                        const Shadow(color: Colors.cyanAccent, blurRadius: 10),
                      ],
                    ),
                  ),
                ),

                const Spacer(),

                // 3. 3D KARUSEL (Dönen Kartlar)
                SizedBox(
                  height: 400,
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() {
                        _currentPage = index;
                        _selectedAvatarPath = avatarPaths[index];
                      });
                    },
                    itemCount: avatarPaths.length,
                    itemBuilder: (context, index) {
                      return AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          double value = 1.0;
                          if (_pageController.position.haveDimensions) {
                            value = _pageController.page! - index;
                            value = (1 - (value.abs() * 0.4)).clamp(0.0, 1.0);
                          } else {
                            // İlk açılışta
                            value = (index == _currentPage) ? 1.0 : 0.6;
                          }

                          final isSelected = index == _currentPage;

                          return Center(
                            child: Transform.scale(
                              scale: Curves.easeOut.transform(value),
                              child: Opacity(
                                opacity: max(0.4, value),
                                child: _buildAvatarCard(
                                  avatarPaths[index],
                                  isSelected,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                const Spacer(),

                // 4. ALT SEÇİM BUTONLARI
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white30),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            "VAZGEÇ",
                            style: GoogleFonts.exo2(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            if (_selectedAvatarPath != null) {
                              context.read<UserDataProvider>().updateAvatarPath(
                                _selectedAvatarPath!,
                              );
                              Navigator.pop(context);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            elevation: 10,
                            shadowColor: Colors.cyanAccent.withValues(
                              alpha: 0.5,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          child: Text(
                            "SEÇ VE BAŞLA",
                            style: GoogleFonts.exo2(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarCard(String path, bool isSelected) {
    return Container(
      width: 280,
      height: 360,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C3E),
        borderRadius: BorderRadius.circular(30),
        border: isSelected
            ? Border.all(color: Colors.cyanAccent, width: 3)
            : Border.all(color: Colors.white10),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.cyanAccent.withValues(alpha: 0.4),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 10),
                ),
              ]
            : [const BoxShadow(color: Colors.black54, blurRadius: 10)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Holografik Arka Plan Efekti
          if (isSelected)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(27),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent.withValues(alpha: 0.1),
                        Colors.deepPurpleAccent.withValues(alpha: 0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),

          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Hero(
                tag: isSelected ? 'avatar_hero' : 'avatar_$path',
                child: Image.asset(path, height: 180, fit: BoxFit.contain),
              ),
              const SizedBox(height: 30),
              Text(
                "AVATAR ${path.replaceAll(RegExp(r'[^0-9]'), '')}", // Sadece numarayı al
                style: GoogleFonts.rubikGlitch(
                  fontSize: 22,
                  color: isSelected ? Colors.white : Colors.white38,
                ),
              ),
              const SizedBox(height: 10),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    "SEÇİLDİ",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
