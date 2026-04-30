import os
import chromadb
from langchain_text_splitters import RecursiveCharacterTextSplitter

class ChromaRagService:
    def __init__(self):
        # Koleksiyonu kalıcı bir klasörde tut: "backend/chroma_data"
        db_path = os.path.join(os.path.dirname(__file__), "chroma_data")
        self.client = chromadb.PersistentClient(path=db_path)
        
        # Koleksiyonu oluştur/getir (Varsayılan all-MiniLM-L6-v2 modeli otomatik indirilip kullanılacak)
        self.collection = self.client.get_or_create_collection(name="matchlang_docs")
        
        # Belgeleri çok uzun olmaması için anlamsal parçalara ayırma aracı
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=500,
            chunk_overlap=50,
            length_function=len,
        )

    def add_document(self, doc_id: str, content: str):
        """Metni bloklara ayırıp vektörlere (embedding) döker ve veritabanına kaydeder."""
        chunks = self.text_splitter.split_text(content)
        
        # Her bir blok (chunk) için özel ID oluştur
        ids = [f"{doc_id}_chunk_{i}" for i in range(len(chunks))]
        metadatas = [{"doc_id": doc_id, "chunk_index": i} for i in range(len(chunks))]
        
        if chunks:
            # Upsert komutu ile ekle/güncelle (Oto Embedding işlemi burada yapılır)
            self.collection.upsert(
                documents=chunks,
                metadatas=metadatas,
                ids=ids
            )
            print(f"[RAG] Belge '{doc_id}' vektörize edildi ve veritabanına {len(chunks)} parça eklendi.")

    def get_relevant_context(self, query: str, n_results: int = 3) -> str:
        """Sorguya yapısal ve anlamsal (semantic) olarak en benzer parçaları bulur."""
        if self.collection.count() == 0:
            return ""
            
        # Eğer veritabanında istenen n_results'tan daha az parça varsa dinamik ayarla
        safe_n = min(n_results, self.collection.count())
        
        # Cosine similarity ile en alakalı parçaları listele
        results = self.collection.query(
            query_texts=[query],
            n_results=safe_n
        )
        
        # Bulunan bağlamı (sadece text olarak) birleştir
        if results and results['documents'] and len(results['documents'][0]) > 0:
            relevant_chunks = results['documents'][0]
            built_context = "\n---\n".join(relevant_chunks)
            print(f"[RAG SEARCH] '{query}' için veri çekildi! (Bulunan parça: {len(relevant_chunks)})")
            return built_context
            
        return ""

# Global Servis Örneği. Artık bellek üzerindeki sahte yapı (InMemory) değil!
rag_db = ChromaRagService()
