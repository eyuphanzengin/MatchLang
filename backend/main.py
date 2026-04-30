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

class UploadDocumentRequest(BaseModel):
    doc_id: str
    content: str
    
class MistakeExplainRequest(BaseModel):
    user_answer: str
    correct_answer: str
    context_type: str

@app.post("/upload_document")
async def upload_document(request: UploadDocumentRequest):
    rag_db.add_document(request.doc_id, request.content)
    return {"status": "success", "message": f"Document {request.doc_id} uploaded successfully."}

@app.post("/chat")
async def chat_with_tutor(request: ChatRequest):
    # Kullanıcının eksiklerine göre dinamikleşecek prompt
    worst_word = request.worst_mistakes[0] if request.worst_mistakes else "apple"
    
    # RAG Context'i al
    context = rag_db.get_relevant_context(request.message)
    context_injection = f"\n\n[DİKKAT! SİSTEM BELLEĞİNDEKİ BAZI BİLGİLER/DERS NOTLARI ŞUNLARDIR:\n{context}\nBu bilgileri göz önünde bulundurarak cevap ver.]" if context else ""
    
    system_prompt = f"""
Sen MatchLang adında bir dil öğrenme uygulamasının samimi, Türk ve İngilizce bilen yabancı dil asistanısın. 
Karşındakinin seviyesi: {request.level}.
Öğrendiği kelimeler: {', '.join(request.known_words) if request.known_words else 'Henüz belirtilmemiş'}.
Sık Hata Yaptığı kelimeler: {', '.join(request.worst_mistakes) if request.worst_mistakes else 'Henüz belirtilmemiş'}.

İKİ GÖREVİN VAR:
1. Kullanıcının attığı mesaja çok kısa, samimi ve motive edici bir destek ver. Eğer mesaj İngilizce ise hatasını düzelt. Değilse Türkçe konuşabilirsin.
2. Mesajın sonuna her zaman "İngilizce pratik yapalım mı?" minvalinde, onun hata yaptığı kelimeler üzerinden bir İngilizce cümle kurmasını iste (Örn: Bana '{worst_word}' kelimesini kullanarak bir cümle kurar mısın?).

Asla çok uzun şeyler yazma. Çok kısa ve enerjik konuş. Emoji kullan.{context_injection}
"""
    try:
        response = ollama.chat(model='llama3.2', messages=[
            {
                'role': 'system',
                'content': system_prompt
            },
            {
                'role': 'user',
                'content': request.message
            }
        ])
        return {"response": response['message']['content']}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/explain")
async def explain_mistake(request: MistakeExplainRequest):
    prompt = f"Explain simply in Turkish why '{request.user_answer}' is wrong for target '{request.correct_answer}'. Context: {request.context_type} (English learning). Keep it short."
    
    try:
        response = ollama.generate(model='llama3.2', prompt=prompt)
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

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
