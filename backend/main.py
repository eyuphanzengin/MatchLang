from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama
from rag_service import rag_db
from fastapi.responses import Response
from gtts import gTTS
import io
import json
import logging
import random
import uvicorn

logger = logging.getLogger(__name__)

app = FastAPI(title="MatchLang AI Tutor Backend")

# Allow Flutter app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], # Since it's local development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class ChatRequest(BaseModel):
    level: str
    known_words: list[str]
    worst_mistakes: list[str]
    message: str
    history: list[dict] = []
    quiz_accuracy: int = 0
    weak_topics: list[str] = []
    total_quizzes_played: int = 0
    current_streak: int = 0

class UploadDocumentRequest(BaseModel):
    doc_id: str
    content: str
    
class MistakeExplainRequest(BaseModel):
    user_answer: str
    correct_answer: str
    context_type: str

class QuizRequest(BaseModel):
    level: int
    topic: str

@app.post("/upload_document")
async def upload_document(request: UploadDocumentRequest):
    rag_db.add_document(request.doc_id, request.content)
    return {"status": "success", "message": f"Document {request.doc_id} uploaded successfully."}

@app.post("/chat")
async def chat_with_tutor(request: ChatRequest):
    # Zayif kelimeleri belirt
    if request.worst_mistakes:
        mistakes_subset = ', '.join(request.worst_mistakes[:5])
        weak_words_info = (
            f"\nThe user struggles with these specific words: {mistakes_subset}. "
            "If the user asks about their mistakes, errors, or what words they got wrong, list these words clearly (in Turkish translation if asked) and offer help with them. "
            "Otherwise, weave these words naturally into your conversation to help them practice."
        )
    else:
        weak_words_info = (
            "\nThe user has not made any mistakes yet. "
            "If the user asks about their mistakes, errors, or wrong words, tell them that they haven't made any mistakes yet and congratulate them!"
        )

    # Quiz performans bilgisi
    quiz_info = ""
    if request.total_quizzes_played > 0:
        quiz_info = (
            f"\nQuiz stats: accuracy={request.quiz_accuracy}%, "
            f"quizzes_played={request.total_quizzes_played}, "
            f"streak={request.current_streak} days."
        )
        if request.quiz_accuracy < 50:
            quiz_info += " The user is struggling. Use simpler words, be encouraging."
        elif request.quiz_accuracy >= 80:
            quiz_info += " The user is doing great! Challenge them with harder vocabulary."

    if request.current_streak >= 3:
        quiz_info += f" Congratulate them on their {request.current_streak}-day streak if relevant!"

    # Zayif konular
    weak_topics_info = ""
    if request.weak_topics:
        weak_topics_info = (
            f"\nWeak topics: {', '.join(request.weak_topics[:5])}. "
            "If the user asks about their weak topics or mistakes, list them. "
            "Otherwise, try to incorporate these topics naturally."
        )

    # RAG Context
    context = rag_db.get_relevant_context(request.message)
    context_injection = f"\nKnowledge Base:\n{context}" if context else ""
    
    system_prompt = f"""You are MatchLang, a friendly and charismatic English tutor for Turkish speakers. User level: {request.level}/100.{weak_words_info}{quiz_info}{weak_topics_info}{context_injection}

STRICT RULES:
1. When the user writes Turkish, reply in Turkish but include English examples for learning.
2. When the user writes English, reply in English and gently correct mistakes.
3. If the user asks for a quiz/test, give them a quick exercise (translate, fill blank, etc.).
4. Keep answers 2-4 sentences. Be concise and engaging.
5. NEVER say "How can I help you" or "Size nasıl yardımcı olabilirim" or similar greetings.
6. NEVER repeat the same sentence twice.
7. NEVER invent a name for the user.
8. When writing Turkish, use correct grammar: ğ, ü, ş, ı, ö, ç characters properly.

EXAMPLE CONVERSATIONS:
User: "Merhaba, bugün ne yapacağız?"
You: "Bugün İngilizce pratik yapalım! 🎯 Mesela 'environment' kelimesini bilir misin? Türkçesi 'çevre' demek. Bir cümlede kullanalım: 'We should protect the environment.' Sen de bir cümle kur!"

User: "I want to learn new words"
You: "Great! Let's try 'challenge' - it means 'zorluk' in Turkish. Example: 'Learning a new language is a big challenge.' Can you make your own sentence with this word?"

User: "book ne demek?"
You: "'Book' Türkçede 'kitap' demek! 📚 Örnek cümle: 'I read a book every week.' Sen de 'book' ile bir cümle kurabilir misin?" """
    
    messages = [{'role': 'system', 'content': system_prompt}]
    
    # Gelen sohbet gecmisini ekle
    for msg in request.history:
        role = 'assistant' if msg.get('role') == 'bot' else 'user'
        content = msg.get('text', '')
        if content:
            messages.append({'role': role, 'content': content})
            
    # Son mesaji ekle (eger gecmiste yoksa)
    if not messages or messages[-1]['content'] != request.message:
        messages.append({'role': 'user', 'content': request.message})

    print(f"[DEBUG CHAT] message: {request.message}")
    print(f"[DEBUG CHAT] worst_mistakes: {request.worst_mistakes}, weak_topics: {request.weak_topics}")
    print(f"[DEBUG CHAT] system_prompt:\n{system_prompt}\n")
    try:
        response = ollama.chat(
            model='qwen2.5:3b', 
            messages=messages,
            options={
                "temperature": 0.5,
                "top_p": 0.9
            }
        )
        reply = response['message']['content']
        print(f"[DEBUG CHAT] LLM reply: {reply}")
        
        # Son savunma: Yasakli kaliplari temizle
        banned = [
            "Size nasıl yardımcı olabilirim",
            "Size nasil yardimci olabilirim",
            "How can I help you",
            "How can I assist you",
        ]
        for phrase in banned:
            reply = reply.replace(phrase + "?", "").replace(phrase + ".", "").replace(phrase, "")
        reply = reply.strip()
        if not reply:
            reply = "Devam edelim! Bana bir soru sorabilir veya Ingilizce pratik yapabiliriz."
        
        return {"response": reply}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/explain")
async def explain_mistake(request: MistakeExplainRequest):
    prompt = f"Explain simply in Turkish why '{request.user_answer}' is wrong for target '{request.correct_answer}'. Context: {request.context_type} (English learning). Keep it short."
    
    try:
        response = ollama.generate(model='qwen2.5:3b', prompt=prompt)
        return {"response": response['response']}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

tts_cache = {}

@app.get("/tts")
async def generate_tts(text: str, lang: str = "en", slow: bool = False):
    """Text-to-Speech endpoint. Supports caching for instant playback."""
    cache_key = f"{text}_{lang}_{slow}"
    try:
        if cache_key in tts_cache:
            return Response(content=tts_cache[cache_key], media_type="audio/mpeg")
            
        tts = gTTS(text=text, lang=lang, slow=slow, tld='com')
        fp = io.BytesIO()
        tts.write_to_fp(fp)
        audio_data = fp.getvalue()
        
        # Bellek sismemesi icin basit LRU (500 limit)
        if len(tts_cache) > 500:
            tts_cache.clear()
            
        tts_cache[cache_key] = audio_data
        return Response(content=audio_data, media_type="audio/mpeg")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate_quiz")
async def generate_quiz(request: QuizRequest):

    cefr = 'A1'
    if request.level >= 76: cefr = 'B2'
    elif request.level >= 51: cefr = 'B1'
    elif request.level >= 26: cefr = 'A2'

    # ============================================================
    # DOGRULAMA SOZLUGU: AI match ciftleri uretir, sozluk ile
    # dogrulanir. Yanlis ceviri varsa duzeltilir.
    # AI bilinmeyen kelime uretirse guvenilir.
    # ============================================================
    VERIFY_DICT = {
        'A1': {
            "cat": "kedi", "dog": "köpek", "bird": "kuş", "fish": "balık",
            "tree": "ağaç", "apple": "elma", "water": "su", "book": "kitap",
            "house": "ev", "car": "araba", "sun": "güneş", "moon": "ay",
            "milk": "süt", "bread": "ekmek", "mother": "anne", "father": "baba",
            "school": "okul", "hand": "el", "eye": "göz", "door": "kapı",
            "table": "masa", "chair": "sandalye", "pen": "kalem", "flower": "çiçek",
            "red": "kırmızı", "blue": "mavi", "green": "yeşil", "white": "beyaz",
            "black": "siyah", "one": "bir", "two": "iki", "three": "üç",
            "sister": "kız kardeş", "brother": "erkek kardeş", "baby": "bebek",
            "ball": "top", "hat": "şapka", "shoe": "ayakkabı", "bag": "çanta",
            "star": "yıldız", "rain": "yağmur", "snow": "kar", "egg": "yumurta",
            "nose": "burun", "ear": "kulak", "mouth": "ağız", "foot": "ayak",
            "head": "kafa", "hair": "saç", "leg": "bacak", "arm": "kol",
            "boy": "erkek çocuk", "girl": "kız çocuk", "man": "adam", "woman": "kadın",
            "teacher": "öğretmen", "student": "öğrenci", "friend": "arkadaş",
            "coffee": "kahve", "tea": "çay", "sugar": "şeker", "salt": "tuz",
            "rice": "pirinç", "meat": "et", "chicken": "tavuk", "cheese": "peynir",
            "orange": "portakal", "banana": "muz", "grape": "üzüm", "lemon": "limon",
            "tomato": "domates", "potato": "patates", "onion": "soğan",
            "four": "dört", "five": "beş", "six": "altı", "seven": "yedi",
            "eight": "sekiz", "nine": "dokuz", "ten": "on",
            "big": "büyük", "small": "küçük", "hot": "sıcak", "cold": "soğuk",
            "new": "yeni", "old": "eski", "good": "iyi", "bad": "kötü",
            "happy": "mutlu", "sad": "üzgün", "hungry": "aç",
            "window": "pencere", "room": "oda", "bed": "yatak", "phone": "telefon",
            "bus": "otobüs", "train": "tren", "plane": "uçak", "boat": "tekne",
        },
        'A2': {
            "kitchen": "mutfak", "bedroom": "yatak odası", "garden": "bahçe",
            "bridge": "köprü", "cloud": "bulut", "wind": "rüzgar",
            "breakfast": "kahvaltı", "lunch": "öğle yemeği", "dinner": "akşam yemeği",
            "ticket": "bilet", "airport": "havalimanı", "hospital": "hastane",
            "library": "kütüphane", "neighbor": "komşu", "journey": "yolculuk",
            "thirsty": "susuz", "tired": "yorgun", "beautiful": "güzel",
            "dangerous": "tehlikeli", "cheap": "ucuz", "expensive": "pahalı",
            "heavy": "ağır", "light": "hafif", "fast": "hızlı", "slow": "yavaş",
            "early": "erken", "late": "geç", "island": "ada", "village": "köy",
            "city": "şehir", "country": "ülke", "mountain": "dağ", "river": "nehir",
            "lake": "göl", "sea": "deniz", "forest": "orman", "desert": "çöl",
            "passport": "pasaport", "hotel": "otel", "map": "harita",
            "road": "yol", "street": "cadde", "corner": "köşe",
            "market": "market", "money": "para", "price": "fiyat",
            "clothes": "kıyafet", "shirt": "gömlek", "doctor": "doktor",
            "medicine": "ilaç", "weather": "hava durumu", "summer": "yaz",
            "winter": "kış", "spring": "ilkbahar", "autumn": "sonbahar",
            "holiday": "tatil", "job": "iş", "office": "ofis",
            "meeting": "toplantı", "manager": "müdür", "worker": "çalışan",
            "email": "e-posta", "address": "adres", "language": "dil",
            "question": "soru", "answer": "cevap", "problem": "sorun",
            "idea": "fikir", "dream": "rüya", "story": "hikaye",
            "newspaper": "gazete", "magazine": "dergi", "page": "sayfa",
            "letter": "mektup", "gift": "hediye", "birthday": "doğum günü",
            "wedding": "düğün", "game": "oyun", "team": "takım",
            "match": "maç", "player": "oyuncu", "winner": "kazanan",
            "angry": "kızgın", "afraid": "korkmuş", "surprised": "şaşırmış",
            "honest": "dürüst", "lazy": "tembel", "brave": "cesur",
        },
        'B1': {
            "knowledge": "bilgi", "experience": "deneyim", "environment": "çevre",
            "opportunity": "fırsat", "decision": "karar", "advantage": "avantaj",
            "challenge": "zorluk", "solution": "çözüm", "purpose": "amaç",
            "memory": "hafıza", "habit": "alışkanlık", "century": "yüzyıl",
            "audience": "izleyici", "customer": "müşteri", "improve": "geliştirmek",
            "discover": "keşfetmek", "suggest": "önermek", "achieve": "başarmak",
            "polite": "kibar", "enormous": "devasa", "curious": "meraklı",
            "ancient": "antik", "seldom": "nadiren", "perhaps": "belki",
            "accident": "kaza", "emergency": "acil durum", "insurance": "sigorta",
            "complaint": "şikayet", "satisfaction": "memnuniyet",
            "advertisement": "reklam", "connection": "bağlantı",
            "communication": "iletişim", "population": "nüfus",
            "tradition": "gelenek", "culture": "kültür", "religion": "din",
            "government": "hükümet", "election": "seçim", "law": "hukuk",
            "economy": "ekonomi", "industry": "sanayi", "agriculture": "tarım",
            "technology": "teknoloji", "software": "yazılım", "data": "veri",
            "research": "araştırma", "experiment": "deney", "theory": "teori",
            "education": "eğitim", "degree": "derece", "certificate": "sertifika",
            "skill": "beceri", "talent": "yetenek", "ability": "yeterlilik",
            "confidence": "güven", "patience": "sabır", "courage": "cesaret",
            "freedom": "özgürlük", "justice": "adalet", "equality": "eşitlik",
            "responsibility": "sorumluluk", "behavior": "davranış",
            "attitude": "tutum", "opinion": "görüş", "argument": "tartışma",
            "discussion": "tartışma", "conclusion": "sonuç", "evidence": "kanıt",
            "influence": "etki", "effect": "etki", "cause": "sebep",
            "process": "süreç", "method": "yöntem", "strategy": "strateji",
            "progress": "ilerleme", "development": "gelişme", "growth": "büyüme",
            "decline": "düşüş", "increase": "artış", "decrease": "azalış",
            "success": "başarı", "failure": "başarısızlık", "effort": "çaba",
        },
        'B2': {
            "consequence": "sonuç", "circumstance": "durum",
            "perspective": "bakış açısı", "determination": "kararlılık",
            "enthusiasm": "heyecan", "emphasize": "vurgulamak",
            "investigate": "araştırmak", "reluctant": "isteksiz",
            "inevitable": "kaçınılmaz", "significant": "önemli",
            "controversial": "tartışmalı", "genuine": "gerçek",
            "revenue": "gelir", "phenomenon": "olgu",
            "ambiguous": "belirsiz", "comprehensive": "kapsamlı",
            "contemporary": "çağdaş", "sophisticated": "sofistike",
            "sustainable": "sürdürülebilir", "transparent": "şeffaf",
            "abstract": "soyut", "concrete": "somut",
            "autonomous": "özerk", "bureaucracy": "bürokrasi",
            "catastrophe": "felaket", "coincidence": "tesadüf",
            "contradiction": "çelişki", "controversy": "tartışma",
            "dilemma": "ikilem", "discrimination": "ayrımcılık",
            "epidemic": "salgın", "exploitation": "sömürü",
            "hypothesis": "hipotez", "ideology": "ideoloji",
            "implementation": "uygulama", "infrastructure": "altyapı",
            "innovation": "yenilik", "intervention": "müdahale",
            "legislation": "mevzuat", "manipulation": "manipülasyon",
            "negotiation": "müzakere", "obligation": "yükümlülük",
            "perception": "algı", "privilege": "ayrıcalık",
            "propaganda": "propaganda", "prosperity": "refah",
            "rehabilitation": "rehabilitasyon", "revolution": "devrim",
            "sacrifice": "fedakarlık", "solidarity": "dayanışma",
            "speculation": "spekülasyon", "stereotype": "kalıp yargı",
            "surveillance": "gözetim", "tolerance": "hoşgörü",
            "transformation": "dönüşüm", "transition": "geçiş",
            "vulnerability": "savunmasızlık", "welfare": "refah",
            "acquisition": "edinim", "allegation": "iddia",
            "assessment": "değerlendirme", "assumption": "varsayım",
            "collaboration": "işbirliği", "compensation": "tazminat",
            "configuration": "yapılandırma", "consolidation": "birleştirme",
            "consultation": "danışma", "deterioration": "bozulma",
            "distinction": "ayrım", "domination": "hakimiyet",
            "elimination": "eleme", "emergence": "ortaya çıkış",
            "fluctuation": "dalgalanma", "foundation": "temel",
            "globalization": "küreselleşme", "implication": "ima",
            "inclination": "eğilim", "integration": "entegrasyon",
            "justification": "gerekçe", "maintenance": "bakım",
        },
    }

    dict_for_level = VERIFY_DICT.get(cefr, VERIFY_DICT['A1'])

    def validate_match_pairs(pairs):
        """AI'nin urettigi match ciftlerini dogrula ve duzelt."""
        validated = []
        seen_en = set()
        seen_tr = set()
        for pair in pairs:
            en = pair.get('en', '').strip().lower()
            tr = pair.get('tr', '').strip()
            if not en or not tr:
                continue
            if en in dict_for_level:
                correct_tr = dict_for_level[en]
                if tr.lower() != correct_tr.lower():
                    logger.info(f"[QuizFix] '{en}': '{tr}' -> '{correct_tr}'")
                    tr = correct_tr
            
            # Ayni kelimeden 2 tane varsa (UI'da bug yapar) atla
            if en in seen_en or tr.lower() in seen_tr:
                continue
                
            seen_en.add(en)
            seen_tr.add(tr.lower())
            validated.append({"en": en, "tr": tr})
        return validated
    def generate_fallback_match():
        """AI basarisiz olursa yedek match sorusu."""
        items = [{"en": k, "tr": v} for k, v in dict_for_level.items()]
        selected = random.sample(items, min(5, len(items)))
        return {"type": "match", "question": "Kelimeleri Eşleştir", "pairs": selected}

    prompt = f"""You are a language quiz generator. Create a quiz for English learners at CEFR level {cefr} (level {request.level}/100).
Topic: {request.topic}.

You MUST return a valid JSON object with a "questions" key containing an array of exactly 10 questions.
Use these 4 question types:

Type 1 - "match": Word matching. EVERY pair must have CORRECT English-Turkish translation!
{{"type":"match","question":"Kelimeleri Eslestir","pairs":[{{"en":"cat","tr":"kedi"}},{{"en":"dog","tr":"kopek"}},{{"en":"bird","tr":"kus"}},{{"en":"fish","tr":"balik"}},{{"en":"tree","tr":"agac"}}]}}

Type 2 - "choice": Multiple choice
{{"type":"choice","question":"'Kitap' kelimesinin Ingilizcesi nedir?","options":["book","pen","table","chair"],"answer":"book"}}

Type 3 - "translate_sentence": Sentence translation
{{"type":"translate_sentence","question":"Bu cumleyi cevir","sentence":"I like reading books","answer":"Kitap okumayi severim"}}

Type 4 - "audio_assembly": Build the sentence
{{"type":"audio_assembly","question":"Duydugun cumleyi olustur","target":"The cat is sleeping","distractors":["running","eating","flying"]}}

CRITICAL RULES:
- Include 2 match, 4 choice, 2 translate_sentence, 2 audio_assembly.
- For match: each pair MUST have correct English-Turkish translation. Double check!
- Return {{"questions": [...]}} with exactly 10 items. No null values."""

    try:
        response = ollama.chat(model='qwen2.5:3b', messages=[
            {'role': 'user', 'content': prompt}
        ], format='json')
        
        raw_content = response['message']['content']
        raw_content = raw_content.replace('```json', '').replace('```', '').strip()
        parsed = json.loads(raw_content)
        
        ai_questions = []
        if isinstance(parsed, dict) and 'questions' in parsed:
            ai_questions = parsed['questions']
        elif isinstance(parsed, list):
            ai_questions = parsed

        # Match sorularini dogrula ve duzelt
        has_valid_match = False
        for q in ai_questions:
            if q.get('type') == 'match' and isinstance(q.get('pairs'), list):
                q['pairs'] = validate_match_pairs(q['pairs'])
                if len(q['pairs']) >= 3:
                    has_valid_match = True
                else:
                    q['pairs'] = generate_fallback_match()['pairs']
                    has_valid_match = True

        if not has_valid_match:
            ai_questions.append(generate_fallback_match())

        return ai_questions
    except Exception as e:
        return [generate_fallback_match(), generate_fallback_match()]

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
