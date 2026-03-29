import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';

import '../models/user_data_provider.dart';
import 'main_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  // --- GOOGLE GİRİŞİ ---
  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final GoogleSignInClientAuthorization clientAuth =
          await googleUser.authorizationClient.authorizeScopes(['email']);
      final credential = GoogleAuthProvider.credential(
        accessToken: clientAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _signIn(credential);
    } catch (e) {
      _showError('Google girişi başarısız: $e');
    }
  }

  // --- E-POSTA GİRİŞİ (BottomSheet) ---
  void _showEmailLoginDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const EmailAuthSheet(),
    );
  }

  // --- ORTAK GİRİŞ FONKSİYONU ---
  Future<void> _signIn(AuthCredential credential) async {
    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      if (!mounted) return;
      // Misafir verilerini yeni hesaba aktar
      await context
          .read<UserDataProvider>()
          .mergeGuestDataToNewUser(userCredential.user!.uid);

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Giriş hatası');
    } catch (e) {
      _showError('Bir hata oluştu: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final double screenHeight = screenSize.height;
    final double screenWidth = screenSize.width;

    final double horizontalPadding = screenWidth * 0.08;
    final double topSpacing = screenHeight * 0.12;
    final double titleToSubtitleSpacing = screenHeight * 0.02;
    final double subtitleToButtonSpacing = screenHeight * 0.1;
    final double buttonVerticalPadding = screenHeight * 0.022;
    final double buttonFontSize = screenWidth * 0.045;

    return Scaffold(
      backgroundColor: Colors.orange,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: Column(
            children: [
              SizedBox(height: topSpacing),
              Text(
                "İlerlemeni Kaydet",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: screenWidth * 0.09,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: titleToSubtitleSpacing),
              Text(
                "Hesap oluşturarak veya giriş yaparak puanlarını ve seviyeni koru.",
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: screenWidth * 0.045,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              SizedBox(height: subtitleToButtonSpacing),
              if (_isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else ...[
                _buildSocialButton(
                  text: "Google ile devam et",
                  iconData: Icons.g_mobiledata,
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.orange,
                  onTap: _signInWithGoogle,
                  isGoogle: true,
                  buttonVerticalPadding: buttonVerticalPadding,
                  buttonFontSize: buttonFontSize,
                ),
                SizedBox(height: screenHeight * 0.02),
                _buildSocialButton(
                  text: "E-posta ile devam et",
                  iconData: Icons.email_outlined,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  onTap: _showEmailLoginDialog,
                  hasBorder: true,
                  buttonVerticalPadding: buttonVerticalPadding,
                  buttonFontSize: buttonFontSize,
                ),
              ],
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialButton({
    required String text,
    required IconData iconData,
    required Color backgroundColor,
    required Color foregroundColor,
    required VoidCallback onTap,
    bool isGoogle = false,
    bool hasBorder = false,
    required double buttonVerticalPadding,
    required double buttonFontSize,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: hasBorder ? 0 : 2,
          side: hasBorder
              ? const BorderSide(color: Colors.white, width: 2)
              : BorderSide.none,
          padding: EdgeInsets.symmetric(vertical: buttonVerticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isGoogle)
              Image.asset('assets/images/google_logo.png', height: 24)
            else
              Icon(iconData, color: foregroundColor, size: 28),
            const SizedBox(width: 12),
            Text(
              text,
              style: GoogleFonts.poppins(
                fontSize: buttonFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- E-POSTA İLE GİRİŞ/KAYIT PENCERESİ ---
class EmailAuthSheet extends StatefulWidget {
  const EmailAuthSheet({super.key});

  @override
  State<EmailAuthSheet> createState() => _EmailAuthSheetState();
}

class _EmailAuthSheetState extends State<EmailAuthSheet> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _errorMessage;
  bool _isLogin = true;
  bool _loading = false;
  final _formKey = GlobalKey<FormState>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _errorMessage = null;
      _loading = true;
    });

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        if (!mounted) return;
        await context
            .read<UserDataProvider>()
            .mergeGuestDataToNewUser(user.uid);
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'user-not-found') {
          _errorMessage = 'Bu e-posta ile kayıtlı bir hesap bulunamadı.';
        } else if (e.code == 'wrong-password') {
          _errorMessage = 'Girdiğiniz şifre hatalı.';
        } else if (e.code == 'email-already-in-use') {
          _errorMessage = 'Bu e-posta adresi zaten kullanımda.';
        } else {
          _errorMessage = 'Hata: ${e.message}';
        }
      });
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Hata: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          30, 30, 30, MediaQuery.of(context).viewInsets.bottom + 30),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isLogin ? "Giriş Yap" : "Hesap Oluştur",
              style: GoogleFonts.poppins(
                  color: Colors.orange.shade800,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              validator: (val) => val != null && val.contains('@')
                  ? null
                  : 'Geçerli e-posta girin',
              decoration: InputDecoration(
                labelText: "E-posta",
                prefixIcon: const Icon(Icons.email, color: Colors.orange),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _passwordController,
              obscureText: true,
              validator: (val) =>
                  val != null && val.length >= 6 ? null : 'En az 6 karakter',
              decoration: InputDecoration(
                labelText: "Şifre",
                prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_errorMessage!,
                    style: const TextStyle(color: Colors.red)),
              ),
            if (_loading)
              const Center(
                  child: CircularProgressIndicator(color: Colors.orange))
            else
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: Text(_isLogin ? "Giriş Yap" : "Kaydol"),
              ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isLogin = !_isLogin;
                  _errorMessage = null;
                });
              },
              child: Text(
                _isLogin
                    ? "Hesabın yok mu? Kaydol"
                    : "Zaten hesabın var mı? Giriş Yap",
                style: const TextStyle(color: Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
