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

ALL_WORDS = {}  # Flat lookup: en -> tr (from VERIFY_DICT)

@app.post("/chat")
async def chat_with_tutor(request: ChatRequest):
    # Lazy init ALL_WORDS from VERIFY_DICT (defined in generate_quiz)
    if not ALL_WORDS:
        for level_dict in _get_verify_dict().values():
            ALL_WORDS.update(level_dict)

    # Zayif kelimeleri belirt - DOGRULANMIS CEVIRILERLE
    if request.worst_mistakes:
        annotated = []
        for w in request.worst_mistakes[:5]:
            tr = ALL_WORDS.get(w.lower(), None)
            if tr:
                annotated.append(f"{w} (= {tr})")
            else:
                annotated.append(w)
        mistakes_str = ', '.join(annotated)
        weak_words_info = (
            f"\nCRITICAL DATA - The user's mistake words with VERIFIED translations: {mistakes_str}. "
            "RULES FOR THESE WORDS: "
            "1) If the user asks about their mistakes/errors/wrong words, you MUST IMMEDIATELY list ALL these words with the exact Turkish translations shown in parentheses. Do NOT ask follow-up questions, just list them directly. "
            "2) Use ONLY the translations shown in parentheses. Do NOT invent your own translations. "
            "3) After listing, offer to practice these words with example sentences. "
            "4) In normal conversation, weave these words naturally to help the user practice."
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

    def _safe_print(msg: str):
        """Print safely on Windows CP1252 terminals."""
        try:
            print(msg)
        except UnicodeEncodeError:
            print(msg.encode('ascii', 'replace').decode())

    _safe_print(f"[DEBUG CHAT] message: {request.message}")
    _safe_print(f"[DEBUG CHAT] worst_mistakes: {request.worst_mistakes}, weak_topics: {request.weak_topics}")
    _safe_print(f"[DEBUG CHAT] system_prompt (length={len(system_prompt)})")
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
        _safe_print(f"[DEBUG CHAT] LLM reply: {reply}")
        
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

def _get_verify_dict():
    """VERIFY_DICT: Tum seviyelerdeki dogrulanmis kelime cevirileri.
    Hem /chat hem /generate_quiz endpoint'leri tarafindan kullanilir."""
    return {
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

def _get_verified_sentences():
    """VERIFIED_SENTENCES: Tum seviyelerdeki dogrulanmis ve kaliteli cumle cevirileri."""
    return {
        'A1': [
            {"en": "I like reading books.", "tr": "Kitap okumayı severim."},
            {"en": "She lives in a big house.", "tr": "O, büyük bir evde yaşıyor."},
            {"en": "We eat breakfast at eight o'clock.", "tr": "Saat sekizde kahvaltı yaparız."},
            {"en": "He has a dog and a cat.", "tr": "Onun bir köpeği ve bir kedisi var."},
            {"en": "The weather is very nice today.", "tr": "Bugün hava çok güzel."},
            {"en": "I want to drink water.", "tr": "Su içmek istiyorum."},
            {"en": "They go to school by bus.", "tr": "Okula otobüsle gidiyorlar."},
            {"en": "My brother plays football.", "tr": "Erkek kardeşim futbol oynar."},
            {"en": "Where is the nearest supermarket?", "tr": "En yakın süpermarket nerede?"},
            {"en": "I can speak a little English.", "tr": "Biraz İngilizce konuşabiliyorum."}
        ],
        'A2': [
            {"en": "I visited my grandparents last weekend.", "tr": "Geçen hafta sonu büyükanne ve büyükbabamı ziyaret ettim."},
            {"en": "Could you please help me with this bag?", "tr": "Lütfen bu çanta için bana yardım edebilir misiniz?"},
            {"en": "He decided to buy a new car.", "tr": "Yeni bir araba almaya karar verdi."},
            {"en": "We are planning to go on holiday in July.", "tr": "Temmuz ayında tatile gitmeyi planlıyoruz."},
            {"en": "She works as a nurse at the local hospital.", "tr": "Yerel hastanede hemşire olarak çalışıyor."},
            {"en": "Learning a new language takes time and patience.", "tr": "Yeni bir dil öğrenmek zaman ve sabır gerektirir."},
            {"en": "I forgot my keys at home this morning.", "tr": "Bu sabah anahtarlarımı evde unuttum."},
            {"en": "They have been living in this city for five years.", "tr": "Beş yıldır bu şehirde yaşıyorlar."},
            {"en": "If it rains tomorrow, we will stay at home.", "tr": "Yarın yağmur yağarsa evde kalacağız."},
            {"en": "He runs faster than his classmates.", "tr": "Sınıf arkadaşlarından daha hızlı koşar."}
        ],
        'B1': [
            {"en": "Although it was raining, they went for a walk in the park.", "tr": "Yağmur yağmasına rağmen parkta yürüyüşe çıktılar."},
            {"en": "She has been looking for a job since she graduated from university.", "tr": "Üniversiteden mezun olduğundan beri iş arıyor."},
            {"en": "I would appreciate it if you could send me the details.", "tr": "Detayları bana gönderebilirseniz memnun olurum."},
            {"en": "The exhibition attracts thousands of visitors every month.", "tr": "Sergi her ay binlerce ziyaretçi çekiyor."},
            {"en": "We must reduce our carbon footprint to protect the environment.", "tr": "Çevreyi korumak için karbon ayak izimizi azaltmalıyız."},
            {"en": "The manager explained the new project guidelines clearly.", "tr": "Müdür, yeni proje yönergelerini net bir şekilde açıkladı."},
            {"en": "He is considered to be one of the most successful artists of his generation.", "tr": "Kendi neslinin en başarılı sanatçılarından biri olarak kabul ediliyor."},
            {"en": "I am looking forward to meeting you next week.", "tr": "Gelecek hafta sizinle görüşmeyi dört gözle bekliyorum."},
            {"en": "The research suggests that regular exercise improves mental health.", "tr": "Araştırma, düzenli egzersizin ruh sağlığını iyileştirdiğini gösteriyor."},
            {"en": "She was surprised by the unexpected gift from her colleagues.", "tr": "Meslektaşlarından gelen beklenmedik hediye karşısında şaşırdı."}
        ],
        'B2': [
            {"en": "The government has implemented new policies to tackle rising unemployment.", "tr": "Hükümet, artan işsizlikle mücadele etmek için yeni politikalar uyguladı."},
            {"en": "He made a significant contribution to the scientific community.", "tr": "Bilim camiasına önemli bir katkıda bulundu."},
            {"en": "We need to analyze the data thoroughly before drawing a conclusion.", "tr": "Bir sonuca varmadan önce verileri derinlemesine analiz etmeliyiz."},
            {"en": "She managed to overcome the obstacles despite facing many difficulties.", "tr": "Birçok zorlukla karşılaşmasına rağmen engelleri aşmayı başardı."},
            {"en": "The development of artificial intelligence has revolutionized many industries.", "tr": "Yapay zekanın gelişimi birçok endüstride devrim yarattı."},
            {"en": "He expressed concern about the potential consequences of the decision.", "tr": "Kararın potansiyel sonuçları hakkında endişesini dile getirdi."},
            {"en": "The company plans to expand its operations in foreign markets.", "tr": "Şirket, dış pazarlardaki operasyonlarını genişletmeyi planlıyor."},
            {"en": "She was praised for her exceptional leadership skills during the crisis.", "tr": "Kriz sırasındaki olağanüstü liderlik becerilerinden dolayı takdir edildi."},
            {"en": "He is studying the correlation between economic growth and education levels.", "tr": "Ekonomik büyüme ile eğitim seviyeleri arasındaki korelasyonu inceliyor."},
            {"en": "Environmental protection should be a priority for all nations.", "tr": "Çevrenin korunması tüm uluslar için bir öncelik olmalıdır."}
        ]
    }

@app.post("/generate_quiz")
async def generate_quiz(request: QuizRequest):
    cefr = 'A1'
    if request.level >= 76: cefr = 'B2'
    elif request.level >= 51: cefr = 'B1'
    elif request.level >= 26: cefr = 'A2'

    VERIFY_DICT = _get_verify_dict()
    dict_for_level = VERIFY_DICT.get(cefr, VERIFY_DICT['A1'])
    sentences_pool = _get_verified_sentences().get(cefr, _get_verified_sentences()['A1'])

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

    def generate_fallback_choice():
        """Yedek multiple choice sorusu."""
        en_word, tr_word = random.choice(list(dict_for_level.items()))
        other_words = [w for w in dict_for_level.keys() if w != en_word]
        distractors = random.sample(other_words, min(3, len(other_words)))
        
        # 50% ihtimalle Ingilizce->Turkce veya Turkce->Ingilizce sor
        if random.random() < 0.5:
            options = [en_word] + distractors
            random.shuffle(options)
            return {
                "type": "choice",
                "question": f"'{tr_word}' kelimesinin İngilizcesi nedir?",
                "options": options,
                "answer": en_word
            }
        else:
            tr_options = [dict_for_level[en_word]] + [dict_for_level[w] for w in distractors]
            random.shuffle(tr_options)
            return {
                "type": "choice",
                "question": f"'{en_word.capitalize()}' kelimesinin Türkçesi nedir?",
                "options": tr_options,
                "answer": dict_for_level[en_word]
            }

    def clean_and_verify_choice_question(q):
        """AI choice sorusunu dogrular, secenekleri ve soru metnini duzeltir."""
        question_text = q.get('question', '')
        options = q.get('options', [])
        answer = q.get('answer', '')
        
        if not options or not answer:
            return None
            
        answer_lower = answer.strip().lower()
        
        # ALL_WORDS'e bakalim (main.py global ALL_WORDS)
        global ALL_WORDS
        if not ALL_WORDS:
            for level_dict in VERIFY_DICT.values():
                ALL_WORDS.update(level_dict)
                
        # Cevap dogrulanmis sozlukte var mi?
        is_english_ans = answer_lower in ALL_WORDS
        is_turkish_ans = False
        for en, tr in ALL_WORDS.items():
            if tr.lower() == answer_lower:
                is_turkish_ans = True
                break
                
        if not is_english_ans and not is_turkish_ans:
            # Cevap sozlukte yoksa, guvenlik icin bu soruyu reddedelim (veya AI yabanci dilde kelimeler uretmisse)
            logger.warning(f"[QuizFix] Rejected choice question because answer '{answer}' is not in verified vocabulary.")
            return None
            
        # Seceneklerde dogru cevap olmali
        if answer not in options:
            if len(options) < 4:
                options.append(answer)
            else:
                options[0] = answer
                random.shuffle(options)
                
        # Cevap İngilizce mi?
        if is_english_ans:
            tr_word = ALL_WORDS[answer_lower]
            q['question'] = f"'{tr_word}' kelimesinin İngilizcesi nedir?"
            # Diger seceneklerin de İngilizce kelimeler oldugundan emin olalim, yoksa yerlerine rastgele koyalim
            for i, opt in enumerate(options):
                opt_lower = opt.strip().lower()
                if opt_lower != answer_lower and opt_lower not in ALL_WORDS:
                    fallback_en = random.choice([w for w in dict_for_level.keys() if w != answer_lower])
                    options[i] = fallback_en
            return q
            
        # Cevap Türkçe mi?
        if is_turkish_ans:
            english_word = ""
            for en, tr in ALL_WORDS.items():
                if tr.lower() == answer_lower:
                    english_word = en
                    break
            q['question'] = f"'{english_word.capitalize()}' kelimesinin Türkçesi nedir?"
            # Diger seceneklerin de Turkce kelimeler oldugundan emin olalim, yoksa yerlerine rastgele koyalim
            for i, opt in enumerate(options):
                opt_lower = opt.strip().lower()
                is_tr = False
                for en, tr in ALL_WORDS.items():
                    if tr.lower() == opt_lower:
                        is_tr = True
                        break
                if opt_lower != answer_lower and not is_tr:
                    fallback_en = random.choice([w for w in dict_for_level.keys() if w != english_word])
                    options[i] = dict_for_level[fallback_en]
            return q
            
        return q

    # 4 Cumle tabanli soruyu dogrulanmis havuzumuzdan secelim (2 translate_sentence, 2 audio_assembly)
    selected_sentences = random.sample(sentences_pool, 4)

    try:
        ts_questions = []
        for s in selected_sentences[:2]:
            ts_questions.append({
                "type": "translate_sentence",
                "question": "Bu cümleyi çevir",
                "sentence": s["en"],
                "answer": s["tr"]
            })
            
        aa_questions = []
        for s in selected_sentences[2:]:
            words_cleaned = s["en"].replace('.', '').replace(',', '').replace('?', '').replace('!', '').replace(';', '')
            words = [w.strip() for w in words_cleaned.split() if w.strip()]
            potential_distractors = [
                w.lower() for w in dict_for_level.keys() 
                if w.lower() not in [x.lower() for x in words]
            ]
            if len(potential_distractors) < 3:
                potential_distractors = ["running", "eating", "flying", "happy", "blue", "today"]
            distractors = random.sample(potential_distractors, min(3, len(potential_distractors)))
            aa_questions.append({
                "type": "audio_assembly",
                "question": "Duyduğun cümleyi oluştur",
                "target": s["en"],
                "distractors": distractors
            })

        # AI ile sadece kelime eslestirme ve secenekli sorulari uretmeye calisalim
        ai_questions = []
        try:
            prompt = f"""You are a language quiz generator. Create a vocabulary quiz for English learners at CEFR level {cefr} (level {request.level}/100).
Topic: {request.topic}.

You MUST return a valid JSON object with a "questions" key containing an array of exactly 10 questions.
Only generate these 2 types of questions:

Type 1 - "match": Word matching. EVERY pair must have CORRECT English-Turkish translation!
{{"type":"match","question":"Kelimeleri Eslestir","pairs":[{{"en":"cat","tr":"kedi"}},{{"en":"dog","tr":"kopek"}},{{"en":"bird","tr":"kus"}},{{"en":"fish","tr":"balik"}},{{"en":"tree","tr":"agac"}}]}}

Type 2 - "choice": Multiple choice
{{"type":"choice","question":"'Kitap' kelimesinin Ingilizcesi nedir?","options":["book","pen","table","chair"],"answer":"book"}}

CRITICAL RULES:
- Generate 4 match questions and 6 choice questions.
- For match: each pair MUST have correct English-Turkish translation from the CEFR {cefr} level.
- Return {{"questions": [...]}} with exactly 10 items. No null values."""

            response = ollama.chat(model='qwen2.5:3b', messages=[
                {'role': 'user', 'content': prompt}
            ], format='json')
            
            raw_content = response['message']['content']
            raw_content = raw_content.replace('```json', '').replace('```', '').strip()
            parsed = json.loads(raw_content)
            
            if isinstance(parsed, dict) and 'questions' in parsed:
                ai_questions = parsed['questions']
            elif isinstance(parsed, list):
                ai_questions = parsed
        except Exception as e:
            logger.error(f"Error calling/parsing LLM quiz: {e}")
            ai_questions = []

        match_questions = []
        choice_questions = []
        
        for q in ai_questions:
            q_type = q.get('type')
            if q_type == 'match' and isinstance(q.get('pairs'), list):
                validated_pairs = validate_match_pairs(q['pairs'])
                if len(validated_pairs) >= 3:
                    q['pairs'] = validated_pairs
                    match_questions.append(q)
            elif q_type == 'choice':
                cleaned_q = clean_and_verify_choice_question(q)
                if cleaned_q:
                    choice_questions.append(cleaned_q)

        # 10 soruluk final listesini olusturalim
        final_questions = []
        
        # 1. Match sorulari (tam olarak 2 tane)
        while len(match_questions) < 2:
            match_questions.append(generate_fallback_match())
        final_questions.extend(match_questions[:2])
        
        # 2. Choice sorulari (tam olarak 4 tane)
        while len(choice_questions) < 4:
            choice_questions.append(generate_fallback_choice())
        final_questions.extend(choice_questions[:4])
        
        # 3. Cumle sorulari (tam olarak 2 translate, 2 audio_assembly)
        final_questions.extend(ts_questions)
        final_questions.extend(aa_questions)
        
        # Sorulari karistiralim (Premium UX)
        random.shuffle(final_questions)
        
        return final_questions

    except Exception as e:
        logger.error(f"Generate quiz root exception: {e}")
        # root exception durumunda da 10 soru garantisi
        fallback_list = [
            generate_fallback_match(),
            generate_fallback_match(),
            generate_fallback_choice(),
            generate_fallback_choice(),
            generate_fallback_choice(),
            generate_fallback_choice(),
        ]
        # Cumleleri ekleyelim
        for s in selected_sentences[:2]:
            fallback_list.append({
                "type": "translate_sentence",
                "question": "Bu cümleyi çevir",
                "sentence": s["en"],
                "answer": s["tr"]
            })
        for s in selected_sentences[2:]:
            fallback_list.append({
                "type": "audio_assembly",
                "question": "Duyduğun cümleyi oluştur",
                "target": s["en"],
                "distractors": ["running", "eating", "flying"]
            })
        random.shuffle(fallback_list)
        return fallback_list

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
