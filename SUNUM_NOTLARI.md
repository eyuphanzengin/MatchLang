# MatchLang Proje Sunum Notları

Bu belge, MatchLang projesini teknik ve işleyiş açısından anlatan, özellikle Yapay Zeka entegrasyonuna odaklanan bir rehberdir. Sunumunuzda kullanabileceğiniz kritik bilgileri içerir.

## 1. Proje Özeti
**MatchLang**, kullanıcıların İngilizce kelime ve cümle yapılarını oyunlaştırılmış bir deneyimle öğrenmelerini sağlayan, Flutter ile geliştirilmiş mobil tabanlı bir dil öğrenme uygulamasıdır. Klasik ezber yöntemleri yerine, görsel eşleştirme, dinleme, konuşma ve cümle kurma gibi interaktif yöntemler kullanır.

## 2. Teknoloji Yığını (Tech Stack)
*   **Framework:** Flutter (Dart) - Cross-platform (Android/iOS) uygulama geliştirme.
*   **Backend & Veritabanı:** Firebase (Firestore, Auth) - Kullanıcı yönetimi ve veri saklama.
*   **Yapay Zeka (AI):** Google Gemini API (`google_generative_ai`) - Dinamik içerik oluşturma.
*   **Ses Teknolojileri:**
    *   **TTS (Text-to-Speech):** `flutter_tts` - Metinleri seslendirme.
    *   **STT (Speech-to-Text):** `speech_to_text` - Kullanıcının konuşmasını metne dökme.
*   **Durum Yönetimi (State Management):** Provider paketi.

---

## 3. Yapay Zeka Entegrasyonu (En Önemli Kısım)
Projenin kalbi `AITutorService` sınıfıdır. Burada Google'ın **Gemini** modeli kullanılarak sonsuz ve kişiselleştirilmiş bir içerik akışı sağlanır.

### A. Dinamik Quiz Oluşturma (`generateQuiz`)
Uygulama, statik bir veritabanından soru çekmek yerine, soruları anlık olarak üretir veya prosedürel (yerel algoritma) ile hibrit bir yapı kullanır.
*   **Nasıl Çalışır?**
    *   Kullanıcının seviyesi (A1, A2, B1 vb.) ve konu (örn: "General", "Travel") parametre olarak alınır.
    *   Gemini'ye özel bir "Prompt" (Komut) gönderilir.
    *   **Prompt Örneği:** *"Bana A1 seviyesinde, json formatında; 5 kelime eşleştirmesi, 1 cümle çevirisi, 1 çoktan seçmeli, 1 dinleme sorusu üret."*
    *   Gelen yanıt JSON formatındadır ve doğrudan uygulama içinde Dart objelerine dönüştürülür.
*   **Avantajı:** Kullanıcı asla aynı sorularla karşılaşmaz. İçerik sonsuzdur ve kullanıcının seviyesine göre zorluk anlık ayarlanabilir.

### B. Hata Analizi ve Açıklama (`explainMistake`)
Kullanıcı yanlış yaptığında, sadece "Yanlış" demek yerine neden yanlış yaptığını açıklayabiliriz.
*   Gemini'ye kullanıcının cevabı ve doğru cevap gönderilir.
*   AI, dil bilgisi kurallarına dayanarak kısa bir açıklama üretir (Örn: *"Burada 'go' yerine 'went' kullanmalısın çünkü cümle geçmiş zaman."*).

### C. Kelime Önerileri
Kullanıcının zayıf olduğu kelimeleri analiz edip, buna benzer yeni kelimeler önermek için de AI kullanılır.

---

## 4. Oyun ve Uygulama Mekanikleri

### A. Quiz Türleri
1.  **Eşleştirme (Matching):** İngilizce ve Türkçe kelimeleri birbirine sürükleyip eşleştirme.
2.  **Cümle Kurma (Listening/Translation):** Karışık verilen kelimeleri doğru sıraya dizerek anlamlı cümle oluşturma.
3.  **Çoktan Seçmeli:** Kelimenin anlamını şıklar arasından bulma.
4.  **Konuşma (Speaking):** Ekranda görülen cümleyi mikrofonla okuma. `speech_to_text` kütüphanesi ile kullanıcının sesi metne çevrilir ve benzerlik analizi (`string_similarity`) yapılır. %80 üzeri benzerlik "Doğru" kabul edilir.

### B. Seviye Sistemi ve İlerleme (`HomeScreen`)
*   Seviyeler bir **Yol Haritası (Roadmap)** şeklinde tasarlanmıştır (Hexagon/Altıgen tasarım).
*   Kullanıcı bir seviyeyi geçmeden diğerine geçemez (Kilit sistemi).
*   Her seviye tamamlandığında XP (Puan) kazanılır ve veritabanına (Firebase) kaydedilir.

### C. Can ve Enerji Sistemi
*   Kullanıcının toplam 5 canı (kalbi) vardır.
*   Her yanlış cevapta veya oyunu yarıda bıraktığında **1 Can** düşer.
*   Canlar bittiğinde oyun oynanamaz (Gamification/Oyunlaştırma öğesi).

### D. İstatistikler ve Liderlik Tablosu
*   Kullanıcının bildiği kelimeler (`knownWords`) ve hata yaptığı kelimeler (`wordStats`) kaydedilir.
*   **Liderlik Tablosu:** Firebase'den en yüksek puanlı kullanıcılar çekilerek sıralanır.

---

## 5. Kritik Kod Dosyaları (Hocaya Gösterilebilir)
*   **`lib/services/ai_tutor_service.dart`**: Tüm yapay zeka iletişiminin yapıldığı yer.
*   **`lib/screens/quiz_screen.dart`**: Quiz mantığının, soru tiplerinin ve oyun akışının yönetildiği ana ekran.
*   **`lib/models/user_data_provider.dart`**: Kullanıcı verilerinin (puan, can, seviye) yönetildiği ve Firebase ile senkronize edildiği yer.

## 6. Gelecek Planları (Sunumda Bahsedilebilir)
*   **Offline Mod:** Daha önce üretilen soruların önbelleğe alınarak internetsiz oynanabilmesi.
*   **Daha Gelişmiş AI:** Kullanıcının hata geçmişine göre özel ders programı çıkaran bir "AI Koç" modülü.
*   **Multiplayer:** Arkadaşlarla eş zamanlı kelime yarışması.
