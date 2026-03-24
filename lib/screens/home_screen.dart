import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

// game_screen.dart removed
import 'quiz_screen.dart';
import 'heart_screen.dart';
import 'star_screen.dart';

import '../models/user_data_provider.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  Timer? _heartTimer;
  final int heartIntervalMinutes = 10;
  // FLAG REMOVED
  late AnimationController _floatingController;
  int _lastAutoScrolledLevel = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupHeartTimer();
    });

    _floatingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _heartTimer?.cancel();
    _scrollController.dispose();
    _floatingController.dispose();
    super.dispose();
  }

  void _setupHeartTimer() {
    if (!mounted) return;
    final userData = context.read<UserDataProvider>();
    if (userData.lastHeartTime == null) {
      userData.updateLastHeartTime(DateTime.now());
    }
    _heartTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateHeartStatus();
    });
  }

  void _updateHeartStatus() {
    if (!mounted) return;
    final userData = context.read<UserDataProvider>();
    if (userData.lastHeartTime == null || userData.hearts >= 5) {
      return;
    }
    final now = DateTime.now();
    final diff = now.difference(userData.lastHeartTime!);
    int minutesPassed = diff.inMinutes;
    int heartsToAdd = minutesPassed ~/ heartIntervalMinutes;
    if (heartsToAdd > 0) {
      final newHearts = (userData.hearts + heartsToAdd).clamp(0, 5);
      final newTime = userData.lastHeartTime!.add(
        Duration(minutes: heartsToAdd * heartIntervalMinutes),
      );
      userData.updateHeartsAndLastTime(newHearts, newTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final double topSectionHeight = 100.0;
    final double itemSpacing = 160.0;

    return Consumer<UserDataProvider>(
      builder: (context, userData, child) {
        if (userData.userId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollController.hasClients) {
              if (userData.currentLevel != _lastAutoScrolledLevel) {
                double offset = (userData.currentLevel - 2.5) * itemSpacing;
                if (offset < 0) offset = 0;
                if (offset > _scrollController.position.maxScrollExtent) {
                  offset = _scrollController.position.maxScrollExtent;
                }
                _scrollController.jumpTo(offset);
                _lastAutoScrolledLevel = userData.currentLevel;
              }
            }
          });
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: const Color(0xFF121212),
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF1F1C2C), Color(0xFF928DAB)],
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                    ),
                  ),
                  child: CustomPaint(painter: CyberGridPainter()),
                ),
              ),

              Positioned.fill(
                top: 0,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 200, top: 150),
                  itemCount: 100,
                  itemBuilder: (context, index) {
                    final level = index + 1;
                    final isPlayable = level <= userData.currentLevel;
                    final isBossLevel = level % 10 == 0;
                    final isCompleted = level < userData.currentLevel;
                    final isActive = level == userData.currentLevel;

                    final double xOffset =
                        sin(index / 1.8) * (screenWidth * 0.22);
                    double? prevXOffset;
                    if (index < 99) {
                      prevXOffset =
                          sin((index + 1) / 1.8) * (screenWidth * 0.22);
                    }

                    return SizedBox(
                      height: itemSpacing,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          if (prevXOffset != null)
                            CustomPaint(
                              size: Size(screenWidth, itemSpacing),
                              painter: NeonPathPainter(
                                startX: xOffset,
                                endX: prevXOffset,
                                isPassed: isCompleted,
                                color: isCompleted
                                    ? Colors.cyanAccent
                                    : Colors.grey.withValues(alpha: 0.3),
                              ),
                            ),
                          Transform.translate(
                            offset: Offset(xOffset, 0),
                            child: GestureDetector(
                              onTap: isPlayable
                                  ? () {
                                      if (userData.hearts <= 0) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Enerjiniz bitti. Dinlenme vakti!',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => QuizScreen(
                                            level: "A${(level / 10).ceil()}",
                                            levelIndex: level,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                              child: Stack(
                                alignment: Alignment.center,
                                clipBehavior: Clip.none,
                                children: [
                                  HexagonLevelNode(
                                    level: level,
                                    isActive: isActive,
                                    isLocked: !isPlayable,
                                    isBoss: isBossLevel,
                                    isCompleted: isCompleted,
                                  ),
                                  if (isActive)
                                    AnimatedBuilder(
                                      animation: _floatingController,
                                      builder: (context, child) {
                                        return Positioned(
                                          top:
                                              -85 +
                                              (sin(
                                                    _floatingController.value *
                                                        2 *
                                                        pi,
                                                  ) *
                                                  6),
                                          child: child!,
                                        );
                                      },
                                      child: _buildAvatar(userData),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      height: topSectionHeight,
                      color: Colors.black.withValues(alpha: 0.2),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(
                        bottom: 20,
                        left: 20,
                        right: 20,
                      ),
                      child: Center(
                        child: buildTopButtonsRow(user, context, userData),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatar(UserDataProvider userData) {
    String assetPath = 'assets/avatars/avatar1.png';
    if (userData.avatarPath != null && userData.avatarPath!.isNotEmpty) {
      assetPath = userData.avatarPath!;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: Text(
            "Hazır mısın?",
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 60,
          width: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
            image: DecorationImage(
              image: AssetImage(assetPath),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ],
    );
  }

  Widget buildTopButtonsRow(
    User? user,
    BuildContext context,
    UserDataProvider userData,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStatusChip(
            context,
            icon: Icons.local_fire_department_rounded,
            color: Colors.deepOrangeAccent,
            value: "${userData.streakCount}",
            label: "Seri",
            onTap: () {},
          ),
          const SizedBox(width: 15),
          _buildStatusChip(
            context,
            icon: Icons.favorite_rounded,
            color: const Color(0xFFFF5252),
            value: "${userData.hearts}",
            label: "Can",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HeartScreen()),
            ),
          ),
          const SizedBox(width: 20), // Artırılmış boşluk
          _buildStatusChip(
            context,
            icon: Icons.bolt_rounded,
            color: Colors.amber,
            value: "${userData.totalScore}",
            label: "Puan",
            onTap: () {},
          ),
          const SizedBox(width: 20), // Artırılmış boşluk
          _buildStatusChip(
            context,
            icon: Icons.stars_rounded,
            color: const Color(0xFFFFD740),
            value: "${userData.stars}",
            label: "Rütbe",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StarScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A35),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Text(
              value,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HexagonLevelNode extends StatelessWidget {
  final int level;
  final bool isActive;
  final bool isLocked;
  final bool isBoss;
  final bool isCompleted;

  const HexagonLevelNode({
    super.key,
    required this.level,
    required this.isActive,
    required this.isLocked,
    required this.isBoss,
    required this.isCompleted,
  });

  @override
  Widget build(BuildContext context) {
    final Color baseColor = isLocked
        ? const Color(0xFF424242)
        : (isBoss
              ? const Color(0xFFFF9100)
              : (isCompleted
                    ? const Color(0xFF00E676)
                    : const Color(0xFF2979FF)));

    final double size = isBoss ? 80.0 : 70.0;
    // elevation removed

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: baseColor,
            shape: BoxShape.circle,
            boxShadow: [
              if (!isLocked)
                BoxShadow(
                  color: baseColor.withValues(alpha: isActive ? 0.6 : 0.3),
                  blurRadius: isActive ? 20 : 10,
                  spreadRadius: isActive ? 2 : 0,
                ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 0,
                offset: Offset(0, 6),
              ),
            ],
            border: isActive
                ? Border.all(color: Colors.white, width: 4)
                : Border.all(color: Colors.white24, width: 2),
          ),
          child: Center(
            child: isLocked
                ? Icon(
                    Icons.lock_rounded,
                    color: Colors.white38,
                    size: size * 0.4,
                  )
                : (isBoss
                      ? const Icon(
                          Icons.emoji_events_rounded,
                          color: Colors.white,
                          size: 36,
                        )
                      : Text(
                          "$level",
                          style: GoogleFonts.rubik(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        )),
          ),
        ),
        if (isActive)
          Padding(
            padding: const EdgeInsets.only(top: 15.0),
            child: Container(
              width: 40,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: const BorderRadius.all(Radius.elliptical(40, 10)),
                boxShadow: [
                  BoxShadow(
                    color: baseColor.withValues(alpha: 0.5),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class NeonPathPainter extends CustomPainter {
  final double startX;
  final double endX;
  final bool isPassed;
  final Color color;

  NeonPathPainter({
    required this.startX,
    required this.endX,
    required this.isPassed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = isPassed ? 6 : 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final p1 = Offset((size.width / 2) + startX, size.height / 2);
    final p2 = Offset((size.width / 2) + endX, size.height * 1.5);

    path.moveTo(p1.dx, p1.dy);
    final controlPoint = Offset((p1.dx + p2.dx) / 2, size.height);
    path.quadraticBezierTo(controlPoint.dx, controlPoint.dy, p2.dx, p2.dy);

    if (isPassed) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 12
        ..style = PaintingStyle.stroke
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawPath(path, glowPaint);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
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
