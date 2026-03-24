const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { GoogleGenAI } = require("@google/genai");

// Define the API Key context parameter (Will be loaded from Firebase set secret)
const { defineSecret } = require('firebase-functions/params');
const geminiApiKey = defineSecret('GEMINI_API_KEY');

exports.chatWithBot = onCall({
    secrets: [geminiApiKey],
},
    async (request) => {
        try {
            // Input details
            const userMessage = request.data.message;
            const userLevel = request.data.level || 1;
            const knownWords = request.data.knownWords || [];
            const mistakes = request.data.mistakes || [];

            if (!userMessage) {
                throw new HttpsError("invalid-argument", "Mesaj boş olamaz.");
            }

            // Initialize Gemini API
            const ai = new GoogleGenAI({ apiKey: geminiApiKey.value() });

            // Construct powerful Prompt
            const systemPrompt = `Sen MatchLang adında bir dil öğrenme uygulamasının samimi, Türk ve İngilizce bilen yabancı dil asistanısın. 
Karşındaki kişinin seviyesi: ${userLevel} / 100. (Eğer 1-10 arasıysa tamamen acemi, 50 üstüyse orta seviyedir.)
Kullanıcının daha önceden öğrendiği ve pekiştirdiği kelimeler (Known Words): [${knownWords.join(", ")}].
Kullanıcının sınavlarda çok sık hata yaptığı ve zorlandığı kelimeler: [${mistakes.join(", ")}].

GÖREVLERİN:
1. Kullanıcının attığı mesaja kısa, samimi ve teşvik edici bir Türkçe veya İngilizce yanıt ver.
2. Karşındaki kişi İngilizce pratik yapmak istiyor. Eğer "bana pratik yaptır" tarzı bir şey diyorsa, ona Hata yaptığı kelimeler (mistakes) üzerinden minik bir İngilizce soru veya cümle kurdurma görevi ver.
3. Asla çok uzun paragraflar yazma. Mobil uygulama ekranında okunacak kadar (max 3-4 cümle) kısa ve öz ol.
4. Çıktıda markdown kalınlaştırma (**) veya emoji kullanabilirsin.`;

            const response = await ai.models.generateContent({
                model: 'gemini-1.5-flash',
                contents: [
                    { role: "user", parts: [{ text: systemPrompt }] },
                    { role: "model", parts: [{ text: "Anladım. Karşımdaki kullanıcının seviyesine uygun role-play yeteneklerim devrede. İlk mesajını bekliyorum." }] },
                    { role: "user", parts: [{ text: userMessage }] }
                ],
            });

            return {
                reply: response.text,
            };
        } catch (error) {
            logger.error("ChatBot error", error);
            throw new HttpsError("internal", "Chatbot cevap veremedi: " + error.message);
        }
    });
