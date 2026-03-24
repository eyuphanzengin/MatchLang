import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_data_provider.dart';

class StarScreen extends StatefulWidget {
  const StarScreen({super.key});

  @override
  State<StarScreen> createState() => _StarScreenState();
}

class _StarScreenState extends State<StarScreen> {
  final ScrollController _scrollController = ScrollController();

  Map<String, dynamic> getRankInfo(int stars) {
    if (stars >= 10) {
      return {
        'name': 'Efsane',
        'icon': Icons.workspace_premium,
        'color': const Color(0xFFFFD700), // Gold
        'desc': 'Zirvenin sahibi sensin!',
      };
    }
    switch (stars) {
      case 0:
        return {
          'name': 'Acemi',
          'icon': Icons.child_care,
          'color': Colors.grey.shade600,
          'desc': 'Yolculuğun daha yeni başlıyor.',
        };
      case 1:
        return {
          'name': 'Çırak',
          'icon': Icons.construction,
          'color': Colors.brown.shade500,
          'desc': 'Temelleri öğreniyorsun.',
        };
      case 2:
        return {
          'name': 'Kalfa',
          'icon': Icons.engineering,
          'color': Colors.blueGrey.shade500,
          'desc': 'Yetilerin gelişiyor.',
        };
      case 3:
        return {
          'name': 'Usta',
          'icon': Icons.school,
          'color': Colors.blue.shade800,
          'desc': 'Artık ne yaptığını biliyorsun.',
        };
      case 4:
        return {
          'name': 'Bilge',
          'icon': Icons.auto_stories,
          'color': Colors.deepPurple.shade600,
          'desc': 'Bilgin herkese ışık tutuyor.',
        };
      case 5:
        return {
          'name': 'Kaşif',
          'icon': Icons.explore,
          'color': Colors.teal.shade700,
          'desc': 'Yeni ufuklara yelken açtın.',
        };
      case 6:
        return {
          'name': 'Fatih',
          'icon': Icons.flag,
          'color': Colors.red.shade800,
          'desc': 'Zorlukların üstesinden geliyorsun.',
        };
      case 7:
        return {
          'name': 'Şampiyon',
          'icon': Icons.emoji_events,
          'color': Colors.amber.shade700,
          'desc': 'Kazanan sensin.',
        };
      case 8:
        return {
          'name': 'Üstat',
          'icon': Icons.star_half,
          'color': const Color(0xFFC0C0C0), // Silver
          'desc': 'Mükemmelliğe çok yakınsın.',
        };
      case 9:
        return {
          'name': 'Lord',
          'icon': Icons.security,
          'color': Colors.indigo.shade800,
          'desc': 'Sözün kanun hükmünde.',
        };
      default:
        return {
          'name': 'Efsane',
          'icon': Icons.workspace_premium,
          'color': const Color(0xFFFFD700),
          'desc': 'Zirvenin sahibi sensin!',
        };
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentRank();
    });
  }

  void _scrollToCurrentRank() {
    final userData = context.read<UserDataProvider>();
    // Her item yaklaşık 100px + padding. Ortalama bir değerle kaydır.
    // 5. rank ise 5 * 120 = 600 gibi.
    if (_scrollController.hasClients) {
      double offset = (userData.stars * 120.0) - 200;
      if (offset < 0) offset = 0;
      _scrollController.animateTo(
        offset,
        duration: const Duration(seconds: 1),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    final currentStars = userData.stars;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Rütbe Yolu',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF232526), Color(0xFF414345)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 120, bottom: 50),
          itemCount: 11, // 0'dan 10'a kadar (11 rank)
          itemBuilder: (context, index) {
            final info = getRankInfo(index);
            final bool isUnlocked = index <= currentStars;
            final bool isCurrent = index == currentStars;

            return _buildRankItem(index, info, isUnlocked, isCurrent);
          },
        ),
      ),
    );
  }

  Widget _buildRankItem(
    int level,
    Map<String, dynamic> info,
    bool isUnlocked,
    bool isCurrent,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Bağlantı Çizgisi (İlk item hariç)
          if (level > 0)
            Positioned(
              top: -30,
              bottom: 50,
              left: 30,
              child: Container(
                width: 4,
                color: isUnlocked
                    ? info['color'].withValues(alpha: 0.5)
                    : Colors.white10,
              ),
            ),

          Opacity(
            opacity: isUnlocked ? 1.0 : 0.5,
            child: Container(
              decoration: BoxDecoration(
                color: isCurrent
                    ? info['color'].withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: isCurrent
                    ? Border.all(color: info['color'], width: 2)
                    : Border.all(color: Colors.white12),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: info['color'].withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  // Rank ICON
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: isUnlocked
                          ? info['color']
                          : Colors.grey.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isUnlocked ? info['icon'] : Icons.lock,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 20),
                  // TEXT INFO
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          info['name'],
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          info['desc'],
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // STARS REQUIRED
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "$level",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (!isUnlocked && !isCurrent)
            Positioned.fill(
              child: Container(color: Colors.transparent),
            ), // Tıklamayı engellemek için (opsiyonel)
        ],
      ),
    );
  }
}
