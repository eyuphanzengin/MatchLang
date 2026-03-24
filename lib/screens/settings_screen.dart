import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_data_provider.dart';
import 'avatar_selection_screen.dart';
import 'welcome_screen.dart';
import 'login_screen.dart'; // Eklendi: Login sayfasına yönlendirme için

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _showEditNameDialog(BuildContext context, UserDataProvider userData) {
    final TextEditingController controller = TextEditingController(
      text: userData.userName,
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D2D2D), // Dark Dialog
        title: const Text(
          "Kullanıcı Adı Değiştir",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Yeni adınızı girin",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white38),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.tealAccent),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("İptal", style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                userData.updateUserName(controller.text.trim());
              }
              Navigator.pop(ctx);
            },
            child: const Text("Kaydet", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Çıkış Yap'),
        content: const Text(
          'Hesabınızdan çıkış yapmak istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Çıkış Yap', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();

    if (!context.mounted) return;
    await context.read<UserDataProvider>().signOutAndReload();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _resetProgress(BuildContext context) async {
    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("İlerlemeyi Sıfırla"),
        content: const Text(
          "Tüm ilerlemeniz (seviye, coin, can vb.) kalıcı olarak silinecek. Emin misiniz?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("İptal"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Sıfırla"),
          ),
        ],
      ),
    );

    if (shouldReset != true || !context.mounted) return;

    await context.read<UserDataProvider>().resetProgress();
    if (!context.mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final userData = context.watch<UserDataProvider>();
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Anonim kullanıcı kontrolü (Firebase üzerinden)
    final user = FirebaseAuth.instance.currentUser;
    final bool isGuest = user?.isAnonymous ?? false;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'Ayarlar',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1F1F1F),
              const Color(0xFF2D2D2D),
            ], // Dark Theme
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            screenWidth * 0.04,
            kToolbarHeight + screenHeight * 0.05,
            screenWidth * 0.04,
            screenWidth * 0.04,
          ),
          children: [
            _buildSectionHeader('Hesap', screenWidth),
            Card(
              elevation: 2,
              color: Colors.white.withValues(alpha: 0.05), // Dark Transparent
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
              child: Column(
                children: [
                  // KULLANICI ADI (YENİ)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    title: Text(
                      userData.userName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    subtitle: Text(
                      "Kullanıcı Adı",
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                    trailing: const Icon(Icons.edit, color: Colors.white70),
                    onTap: () => _showEditNameDialog(context, userData),
                  ),
                  const Divider(color: Colors.white24),
                  _buildAccountSection(
                    context,
                    userData,
                    screenWidth,
                    screenHeight,
                    isGuest,
                  ),
                ],
              ),
            ),

            // --- EKLENEN KISIM BAŞLANGICI ---
            if (isGuest) ...[
              SizedBox(height: screenHeight * 0.03),
              // Dikkat çekici Hesap Bağla Kartı
              Card(
                elevation: 3,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(screenWidth * 0.03),
                  side: BorderSide(color: Colors.grey.shade300, width: 1),
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: screenWidth * 0.04,
                    vertical: screenHeight * 0.01,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.link, color: Colors.grey.shade800),
                  ),
                  title: Text(
                    'Hesap Bağla',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.normal,
                      color: Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    'İlerlemeni kaybetmemek için giriş yap.',
                    style: GoogleFonts.poppins(
                      fontSize: screenWidth * 0.032,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    );
                  },
                ),
              ),
            ],

            // --- EKLENEN KISIM BİTİŞİ ---
            SizedBox(height: screenHeight * 0.03),
            _buildSectionHeader('Oyun Ayarları', screenWidth),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: userData.isSoundOn
                        ? Icons.volume_up
                        : Icons.volume_off,
                    title: 'Ses Efektleri',
                    trailing: Switch(
                      value: userData.isSoundOn,
                      onChanged: (value) => userData.updateSoundSetting(value),
                      activeTrackColor: Colors.tealAccent,
                      activeThumbColor: Colors.white,
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: screenWidth * 0.04,
                    endIndent: screenWidth * 0.04,
                  ),
                  _buildSettingsTile(
                    icon: Icons.vibration,
                    title: 'Titreşim',
                    trailing: Switch(
                      value: userData.isVibrationOn,
                      onChanged: (value) =>
                          userData.updateVibrationSetting(value),
                      activeTrackColor: Colors.tealAccent,
                      activeThumbColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: screenHeight * 0.03),

            // AI Section Removed
            SizedBox(height: screenHeight * 0.03),
            _buildSectionHeader('Diğer', screenWidth),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(screenWidth * 0.03),
              ),
              child: Column(
                children: [
                  _buildSettingsTile(
                    icon: Icons.restore,
                    title: 'İlerlemeyi Sıfırla',
                    onTap: () => _resetProgress(context),
                  ),
                  // Eğer kullanıcı misafir değilse Çıkış Yap butonunu göster
                  if (!isGuest) ...[
                    Divider(
                      height: 1,
                      indent: screenWidth * 0.04,
                      endIndent: screenWidth * 0.04,
                    ),
                    _buildSettingsTile(
                      icon: Icons.logout,
                      title: 'Çıkış Yap',
                      color: Colors.red.shade700,
                      onTap: () => _signOut(context),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountSection(
    BuildContext context,
    UserDataProvider userData,
    double screenWidth,
    double screenHeight,
    bool isGuest, // Parametre olarak alındı
  ) {
    final user = FirebaseAuth.instance.currentUser;

    return Padding(
      padding: EdgeInsets.all(screenWidth * 0.04),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: screenWidth * 0.075,
                backgroundImage: userData.avatarPath != null
                    ? AssetImage(userData.avatarPath!) as ImageProvider
                    : (!isGuest && user?.photoURL != null
                          ? NetworkImage(user!.photoURL!)
                          : null),
                backgroundColor: Colors.grey.shade400,
                child:
                    (userData.avatarPath == null &&
                        (isGuest || user?.photoURL == null))
                    ? Icon(
                        isGuest ? Icons.person_off : Icons.person,
                        size: screenWidth * 0.08,
                        color: Colors.white,
                      )
                    : null,
              ),
              SizedBox(width: screenWidth * 0.04),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isGuest
                          ? 'Misafir Kullanıcı'
                          : (user?.displayName ?? 'Kullanıcı'),
                      style: GoogleFonts.poppins(
                        fontSize: screenWidth * 0.045,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!isGuest && user?.email != null) ...[
                      SizedBox(height: screenHeight * 0.005),
                      Text(
                        user!.email!,
                        style: GoogleFonts.poppins(
                          fontSize: screenWidth * 0.035,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: screenHeight * 0.02),
          FilledButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AvatarSelectionScreen()),
            ),
            style: FilledButton.styleFrom(
              minimumSize: Size.fromHeight(screenHeight * 0.055),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Avatar Değiştir'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, double screenWidth) {
    return Padding(
      padding: EdgeInsets.only(
        left: screenWidth * 0.02,
        bottom: screenWidth * 0.02,
      ),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: screenWidth * 0.04,
          fontWeight: FontWeight.w600,
          color: Colors.white70,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white70),
      title: Text(
        title,
        style: GoogleFonts.poppins(color: color ?? Colors.white, fontSize: 16),
      ),
      trailing:
          trailing ??
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white30),
      onTap: onTap,
    );
  }
}
