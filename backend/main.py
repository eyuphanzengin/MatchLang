from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import ollama
from rag_service import rag_db
from fastapi.responses import Response
from gtts import gTTS
import io

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
    # Eğer özel bir zayıflığı varsa bunu belirt, yoksa zorlama.
    weak_words_info = ""
    if request.worst_mistakes:
        mistakes_subset = ', '.join(request.worst_mistakes[:3])
        weak_words_info = f"The user often makes mistakes with these English words: {mistakes_subset}. If appropriate, naturally encourage them to practice these words."

    # RAG Context'i al
    context = rag_db.get_relevant_context(request.message)
    context_injection = f"\n\nSystem Knowledge Base (Use this if relevant to answer the user):\n{context}" if context else ""
    
    system_prompt = f"""You are MatchLang, an expert and charismatic English language tutor. 
The user is at English level: {request.level}/100.
{weak_words_info}

CRITICAL RULES:
1. NEVER repeat yourself. NEVER ask "How can I help you?" repeatedly.
2. If the user asks to practice English, IMMEDIATELY start a casual English conversation. Ask them a simple question to get started.
3. If the user speaks Turkish, reply in perfect, natural Turkish. If they speak English, reply in English.
4. Keep your answers brief, engaging, and highly intelligent. Do not act like a robot. Act like a cool, friendly human tutor.
{context_injection}
"""
    
    # Sohbet geçmişini (history) oluştur ve yapay zekaya besle
    messages = [{'role': 'system', 'content': system_prompt}]
    
    # Gelen history listesindeki roller 'bot' ise ollama için 'assistant' yapmalıyız
    for msg in request.history:
        role = 'assistant' if msg.get('role') == 'bot' else 'user'
        content = msg.get('text', '')
        if content:
            messages.append({'role': role, 'content': content})
            
    # Son atılan mesajı (eğer history'e eklenmemişse) ekle
    # Flutter tarafında yeni mesaj 'history' listesine eklenmeden yollanıyor olabilir, 
    # Ama Flutter'da _messages.add zaten çağrılıyor, history'nin son elemanı muhtemelen yeni mesaj.
    # Güvenlik için kontrol edelim: Eğer history'nin son elemanı şu anki mesaj değilse ekle
    if not messages or messages[-1]['content'] != request.message:
        messages.append({'role': 'user', 'content': request.message})

    try:
        response = ollama.chat(
            model='qwen2.5:1.5b', 
            messages=messages,
            options={
                "temperature": 0.6
            }
        )
        return {"response": response['message']['content']}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/explain")
async def explain_mistake(request: MistakeExplainRequest):
    prompt = f"Explain simply in Turkish why '{request.user_answer}' is wrong for target '{request.correct_answer}'. Context: {request.context_type} (English learning). Keep it short."
    
    try:
        response = ollama.generate(model='qwen2.5:1.5b', prompt=prompt)
        return {"response": response['response']}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/tts")
async def generate_tts(text: str):
    try:
        tts = gTTS(text=text, lang='en', tld='com')
        fp = io.BytesIO()
        tts.write_to_fp(fp)
        fp.seek(0)
        return Response(content=fp.read(), media_type="audio/mpeg")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/generate_quiz")
async def generate_quiz(request: QuizRequest):
    import json
    
    cefr = 'A1'
    if request.level >= 76: cefr = 'B2'
    elif request.level >= 51: cefr = 'B1'
    elif request.level >= 26: cefr = 'A2'

    prompt = f"""
Generate a language learning quiz for level {request.level} / 100 (CEFR Level: {cefr}).
Topic: {request.topic}.

Return EXACTLY a JSON array containing 10 diverse questions. Mix all types.
Format:
[
  {{
    "type": "match",
    "question": "Eşleştirme",
    "pairs": [{{"en": "Word", "tr": "Kelime"}}]
  }},
  {{
    "type": "audio_assembly",
    "question": "Duyduğunu Kur",
    "target": "English sentence",
    "distractors": ["wrong", "words"]
  }},
  {{
    "type": "translate_sentence",
    "question": "Bu cümleyi çevir",
    "source": "English sentence to translate",
    "target": "Beklenen Türkçe Cümle",
    "options": ["doğru", "kelime", "yanlış", "kelimeler"]
  }},
  {{
    "type": "choice",
    "question": "Soru metni",
    "options": ["A", "B", "C", "D"],
    "answer": "Correct Option"
  }}
]
"""
    try:
        response = ollama.chat(model='qwen2.5:1.5b', messages=[
            {{
                'role': 'user',
                'content': prompt
            }}
        ], format='json')
        
        raw_content = response['message']['content']
        # Remove any potential markdown ticks if Llama hallucinates them
        raw_content = raw_content.replace('```json', '').replace('```', '').strip()
        parsed_json = json.loads(raw_content)
        return parsed_json
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
