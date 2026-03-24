import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import '../models/user_data_provider.dart';

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
  late final GenerativeModel _model;
  late final ChatSession _chat;

  @override
  void initState() {
    super.initState();
    _initChatbot();
  }

  void _initChatbot() {
    // API anahtarını alıyoruz
    final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';

    if (apiKey.isEmpty || apiKey == 'your_api_key_here') {
      setState(() {
        _messages.add({
          'role': 'bot',
          'text':
              '⚠️ Sistem Hatası: Lütfen projeye ait .env dosyasındaki GEMINI_API_KEY değişkenini doldurun.',
        });
      });
      return;
    }

    // Başlangıç promptu için verileri çekip modeli ona göre kuruyoruz
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userData = context.read<UserDataProvider>();

      final systemPrompt =
          """
Sen MatchLang adında bir dil öğrenme uygulamasının samimi, Türk ve İngilizce bilen yabancı dil asistanısın. 
Karşındakinin seviyesi: ${userData.currentLevel}.
Öğrendiği kelimeler: [${userData.knownWords.join(", ")}].
Sık Hata Yaptığı kelimeler: [${_getWorstMistakes(userData)}].

İKİ GÖREVİN VAR:
1. Kullanıcının attığı mesaja kısa, samimi ve motive edici bir destek ver. 
2. Mesajın sonuna "İngilizce pratik yapalım mı?" minvalinde, onun hata yaptığı kelimeler üzerinden bir İngilizce cümle kurmasını iste (Örn: Bana 'accident' kullanarak bir cümle kurar mısın?).

Asla uzun şeyler yazma. Çok kısa ve heyecanlı konuş. Emoji kullan.
""";

      // Modeli gerçek formatı ve sistem komutu (systemInstruction) ile başlatıyoruz
      _model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
        systemInstruction: Content.system(systemPrompt),
      );

      // Sohbeti (Geçmişsiz) ana sistem komutu üzerine başlatıyoruz
      _chat = _model.startChat();

      setState(() {
        _messages.add({
          'role': 'bot',
          'text':
              'Merhaba! Ben MatchLang asistanın. 🎉\nAklına takılanları sorabilir veya İngilizce pratik yapmak istersen bana yazabilirsin!',
        });
      });
    });
  }

  String _getWorstMistakes(UserDataProvider userData) {
    // En çok yanlış yapılan kelimeleri çıkaralım
    final sortedStats = userData.wordStats.entries.toList()
      ..sort(
        (a, b) => (b.value['wrong'] ?? 0).compareTo(a.value['wrong'] ?? 0),
      );

    final topMistakes = sortedStats.take(5).map((e) => e.key).toList();
    return topMistakes.join(', ');
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
      final response = await _chat.sendMessage(Content.text(text));
      setState(() {
        _messages.add({'role': 'bot', 'text': response.text ?? '...'});
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'bot',
          'text': 'Bir bağlantı hatası oluştu: $e',
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
    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_rounded, color: Colors.amber),
            const SizedBox(width: 10),
            Text(
              "Yapay Zeka Asistanı",
              style: GoogleFonts.rubik(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF121212),
        elevation: 2,
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(15),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return _buildChatBubble(msg['text'], isUser);
              },
            ),
          ),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.amber),
            ),

          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
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
            fontSize: 15,
            height: 1.3,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 10,
      ).copyWith(bottom: MediaQuery.of(context).padding.bottom + 10),
      decoration: const BoxDecoration(color: Color(0xFF121212)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "Asistana bir şey yaz...",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2C2C2C),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Colors.amber,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
