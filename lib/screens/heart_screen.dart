import 'dart:async';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_data_provider.dart';

class HeartScreen extends StatefulWidget {
  const HeartScreen({super.key});

  @override
  State<HeartScreen> createState() => _HeartScreenState();
}

class _HeartScreenState extends State<HeartScreen> {
  Timer? _timer;
  Duration _remainingTime = Duration.zero;
  final int heartIntervalMinutes = 10;

  @override
  void initState() {
    super.initState();
    _setupTimerForUI();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setupTimerForUI() {
    _updateRemainingTimeForUI();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateRemainingTimeForUI();
      }
    });
  }

  void _updateRemainingTimeForUI() {
    final userData = context.read<UserDataProvider>();
    if (userData.lastHeartTime == null || userData.hearts >= 5) {
      if (_remainingTime != Duration.zero) {
        if (mounted) setState(() => _remainingTime = Duration.zero);
      }
      return;
    }

    final now = DateTime.now();
    final nextHeartTime = userData.lastHeartTime!.add(
      Duration(minutes: heartIntervalMinutes),
    );
    final newRemainingTime = nextHeartTime.difference(now);

    if (mounted) {
      setState(() {
        _remainingTime = newRemainingTime.isNegative
            ? Duration.zero
            : newRemainingTime;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Canlarım',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepOrange.shade400, Colors.red.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(screenWidth * 0.07),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeartDisplay(userData.hearts, screenWidth),
                SizedBox(height: screenHeight * 0.04),
                _buildActionCard(userData, screenWidth, screenHeight),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeartDisplay(int hearts, double screenWidth) {
    final circleSize = screenWidth * 0.45;
    return Container(
      width: circleSize,
      height: circleSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withAlpha(50),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(51),
            blurRadius: 15,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          '$hearts/5',
          style: GoogleFonts.poppins(
            fontSize: screenWidth * 0.15,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: [
              const Shadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(2, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(
    UserDataProvider userData,
    double screenWidth,
    double screenHeight,
  ) {
    bool areHeartsFull = userData.hearts >= 5;

    return Card(
      elevation: 8,
      color: Colors.white.withAlpha(40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(screenWidth * 0.09),
      ),
      child: Padding(
        padding: EdgeInsets.all(screenWidth * 0.04),
        child: Column(
          children: [
            if (!areHeartsFull) ...[
              Text(
                'Sonraki Can',
                style: GoogleFonts.poppins(
                  fontSize: screenWidth * 0.05,
                  color: Colors.white70,
                ),
              ),
              SizedBox(height: screenHeight * 0.005),
              Text(
                _formatDuration(_remainingTime),
                style: GoogleFonts.poppins(
                  fontSize: screenWidth * 0.11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: screenHeight * 0.01),
                child: const Divider(color: Colors.white30),
              ),
            ],
            Text(
              areHeartsFull ? 'Hazırsın!' : 'Dinlenme Zamanı',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: screenWidth * 0.05,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: screenHeight * 0.01),
            Text(
              areHeartsFull 
                  ? 'Enerjin tam, öğrenmeye devam et!' 
                  : 'Canların her 10 dakikada bir yenilenir.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: screenWidth * 0.035,
                color: Colors.white.withAlpha(200),
              ),
            ),
            // Satın al butonu kaldırıldı.
          ],
        ),
      ),
    );
  }
}
