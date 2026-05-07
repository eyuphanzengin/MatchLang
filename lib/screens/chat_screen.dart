import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/user_data_provider.dart';
import '../services/tts_manager.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  final TtsManager _ttsManager = TtsManager();
  bool _autoTTS = false;

  @override
  void initState() {
    super.initState();
    _initChatbot();
  }

  void _initChatbot() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _messages.add({
          'role': 'bot',
          'text':
              'Merhaba! Ben MatchLang, senin kisisel Ingilizce ogretmeninim. Aklina takilanlari sorabilir veya Ingilizce pratik yapmak istersen bana yazabilirsin!',
        });
      });
    });
  }

  List<String> _getWorstMistakesList(UserDataProvider userData) {
    // En çok yanlış yapılan kelimeleri çıkaralım
    final sortedStats = userData.wordStats.entries.toList()
      ..sort(
        (a, b) => (b.value['wrong'] ?? 0).compareTo(a.value['wrong'] ?? 0),
      );

    return sortedStats.take(5).map((e) => e.key).toList();
  }

  void _listenForSpeech() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => debugPrint('onStatus: $val'),
        onError: (val) => debugPrint('onError: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) {
            setState(() {
              _messageController.text = val.recognizedWords;
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final userData = context.read<UserDataProvider>();
      final String safeLevel = userData.currentLevel.toString();
      final List<String> safeKnownWords = userData.knownWords.cast<String>();
      final List<String> safeMistakes = _getWorstMistakesList(userData);

      // Android Emülatöründen bilgisayardaki localhost'a erişmek için 10.0.2.2 kullanılır.
      const serverUrl = 'http://127.0.0.1:8000/chat';
      // Son 6 mesajı geçmiş olarak gönderelim (Sistem mesajı hariç)
      final history = _messages
          .where((m) => m['role'] != 'system' && m['text'] != null)
          .skip(_messages.length > 6 ? _messages.length - 6 : 0)
          .toList();

      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'level': safeLevel,
          'known_words': safeKnownWords,
          'worst_mistakes': safeMistakes,
          'message': text,
          'history': history,
        }),
      );

      if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          final botResponse = data['response'] ?? '...';
          setState(() {
            _messages.add({'role': 'bot', 'text': botResponse});
            _isLoading = false;
          });
          
          if (_autoTTS) {
             _ttsManager.speak(botResponse);
          }
      } else {
          setState(() {
            _messages.add({'role': 'bot', 'text': '⚠️ Sunucu Hatası: (${response.statusCode})'});
            _isLoading = false;
          });
      }
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': 'Baglanti kurulamadi. Lutfen Python FastAPI sunucusunun arkada calistigindan emin ol.\n\n(Hata: $e)',
        });
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_rounded, color: Colors.amber, size: sw * 0.06),
            SizedBox(width: sw * 0.02),
            Flexible(
              child: Text(
                "Yapay Zeka Asistanı",
                style: GoogleFonts.rubik(
                  fontWeight: FontWeight.bold,
                  fontSize: sw * 0.045,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _autoTTS ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _autoTTS ? Colors.amber : Colors.grey,
              size: sw * 0.06,
            ),
            onPressed: () {
              setState(() {
                _autoTTS = !_autoTTS;
              });
            },
          )
        ],
        backgroundColor: const Color(0xFF121212),
        elevation: 2,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.all(sw * 0.035),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return _buildChatBubble(msg['text'], isUser, showTts: !isUser);
              },
            ),
          ),

          if (_isLoading)
            Padding(
              padding: EdgeInsets.all(sw * 0.02),
              child: CircularProgressIndicator(color: Colors.amber, strokeWidth: sw * 0.008),
            ),

          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser, {bool showTts = false}) {
    final sw = MediaQuery.of(context).size.width;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: sw * 0.012),
            padding: EdgeInsets.symmetric(horizontal: sw * 0.04, vertical: sw * 0.028),
            constraints: BoxConstraints(
              maxWidth: sw * 0.75,
            ),
            decoration: BoxDecoration(
              color: isUser ? Colors.orange.shade600 : Colors.blueGrey.shade800,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 0),
                bottomRight: Radius.circular(isUser ? 0 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: GoogleFonts.rubik(
                color: Colors.white,
                fontSize: sw * 0.037,
                height: 1.3,
              ),
            ),
          ),
          if (showTts)
            Padding(
              padding: EdgeInsets.only(left: sw * 0.02, bottom: sw * 0.01),
              child: GestureDetector(
                onTap: () => _ttsManager.speak(text),
                child: Icon(
                  Icons.volume_up_rounded,
                  color: Colors.white54,
                  size: sw * 0.05,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: sw * 0.035,
        vertical: sw * 0.025,
      ).copyWith(bottom: MediaQuery.of(context).padding.bottom + sw * 0.025),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: TextStyle(color: Colors.white, fontSize: sw * 0.037),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: _isListening ? "Dinleniyor..." : "Asistana bir şey yaz...",
                hintStyle: TextStyle(
                  color: _isListening ? Colors.amber : Colors.white54,
                  fontSize: sw * 0.035,
                ),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: sw * 0.045,
                  vertical: sw * 0.032,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          SizedBox(width: sw * 0.02),
          GestureDetector(
            onTap: _listenForSpeech,
            child: Container(
              padding: EdgeInsets.all(sw * 0.028),
              decoration: BoxDecoration(
                color: _isListening ? Colors.redAccent : const Color(0xFF2C2C2C),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
                size: sw * 0.055,
              ),
            ),
          ),
          SizedBox(width: sw * 0.012),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: EdgeInsets.all(sw * 0.032),
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.send_rounded, color: Colors.black87, size: sw * 0.055),
            ),
          ),
        ],
      ),
    );
  }
}
