from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama
from rag_service import rag_db
from fastapi.responses import Response
from gtts import gTTS
import io
import json
import random
import uvicorn

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
    weak_words_info = ""
    if request.worst_mistakes:
        mistakes_subset = ', '.join(request.worst_mistakes[:3])
        weak_words_info = f"\nThe user struggles with: {mistakes_subset}. Help them practice these naturally."

    # RAG Context
    context = rag_db.get_relevant_context(request.message)
    context_injection = f"\nKnowledge Base:\n{context}" if context else ""
    
    system_prompt = f"""You are MatchLang, a friendly English tutor chatbot for Turkish speakers learning English. User level: {request.level}/100.{weak_words_info}{context_injection}

Your behavior:
- When the user asks you to quiz them, immediately give them an English question. For example: translate a word, fill in the blank, or ask what a word means.
- If the user writes Turkish, answer in Turkish but include English words/sentences for learning.
- If the user writes English, answer in English and correct mistakes.
- Do NOT invent names for the user.
- Do NOT say "How can I help you" or "Size nasil yardimci olabilirim" or similar phrases.
- Do NOT repeat the same sentence twice.
- Keep answers 2-4 sentences."""
    
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
        },
        'A2': {
            "kitchen": "mutfak", "bedroom": "yatak odası", "garden": "bahçe",
            "bridge": "köprü", "rain": "yağmur", "snow": "kar", "cloud": "bulut",
            "wind": "rüzgar", "breakfast": "kahvaltı", "lunch": "öğle yemeği",
            "dinner": "akşam yemeği", "ticket": "bilet", "airport": "havalimanı",
            "hospital": "hastane", "library": "kütüphane", "neighbor": "komşu",
            "journey": "yolculuk", "hungry": "aç", "thirsty": "susuz",
            "tired": "yorgun", "beautiful": "güzel", "dangerous": "tehlikeli",
            "cheap": "ucuz", "expensive": "pahalı", "heavy": "ağır",
            "light": "hafif", "fast": "hızlı", "slow": "yavaş",
            "early": "erken", "late": "geç", "island": "ada", "village": "köy",
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
        },
        'B2': {
            "consequence": "sonuç", "circumstance": "durum", "perspective": "bakış açısı",
            "determination": "kararlılık", "enthusiasm": "heyecan",
            "emphasize": "vurgulamak", "investigate": "araştırmak",
            "reluctant": "isteksiz", "inevitable": "kaçınılmaz",
            "significant": "önemli", "controversial": "tartışmalı",
            "genuine": "gerçek", "revenue": "gelir", "phenomenon": "olgu",
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
                    print(f"[QuizFix] '{en}': '{tr}' -> '{correct_tr}'")
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
