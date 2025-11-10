# RAGシステム更新トリガーフロー

## 概要

このドキュメントは、RAGシステムにおける各層（Atlas/Sparse/Dense）の更新タイミングとトリガーフローを詳細に示します。

## 全体フロー図

```
┌────────────────────────────────────────────────────────────────┐
│                  イベント: ドキュメントアップロード              │
└────────────────────────────────────────────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ documents INSERT         │
              │ status = 'uploaded'      │
              └──────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ Docling処理開始          │
              │ status = 'processing'    │
              └──────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              │ Docling処理               │
              │ - PDFパース               │
              │ - OCR実行                 │
              │ - 階層構造生成             │
              │ - チャンク分割             │
              └─────────────┬─────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ documents UPDATE         │
              │ status = 'processed'     │
              │ original_metadata = {...}│
              └──────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ Sparse層生成    │ │ Dense層生成     │ │ Centroid生成    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│document_fulltext│ │langchain_pg_    │ │documents.       │
│INSERT           │ │embedding INSERT │ │centroid_        │
│(PGroonga)       │ │(PGVector HNSW)  │ │embedding UPDATE │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │                  │                  │
         └──────────────────┴──────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ PostgreSQLトリガー実行    │
              │ trg_mark_kb_summary_     │
              │ for_regen                │
              └──────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ knowledge_bases_summary_ │
              │ embedding UPDATE         │
              │ is_active = false        │
              └──────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ バックグラウンドジョブ    │
              │ (5分ごと実行)             │
              └──────────────────────────┘
                            │
                            ▼
              ┌──────────────────────────┐
              │ KB要約再生成              │
              │ - LLMで要約生成           │
              │ - ベクトル化              │
              │ - 新バージョン挿入         │
              └──────────────────────────┘
```

## 詳細フロー

### 1. ドキュメントアップロード → Sparse層生成

```
┌────────────────────────────────────────────────────────────────┐
│                  Sparse層（全文検索）生成                       │
└────────────────────────────────────────────────────────────────┘

documents (status='processed')
    │
    ▼
SparseSearchService.index_document_chunks(document_id)
    │
    ├─ 1. ドキュメント情報取得
    │   SELECT * FROM documents WHERE id = :document_id
    │
    ├─ 2. チャンク取得
    │   SELECT uuid, document, cmetadata
    │   FROM langchain_pg_embedding
    │   WHERE document_id = :document_id
    │
    └─ 3. document_fulltext挿入
        │
        FOR EACH chunk:
            INSERT INTO document_fulltext
            (document_id, chunk_index, content, tenant_id,
             knowledge_base_id, collection_id)
            VALUES (...)
            ON CONFLICT (document_id, chunk_index) DO UPDATE
            SET content = EXCLUDED.content
        │
        ▼
    document_fulltext (PGroongaインデックス自動更新)
        ├─ idx_document_fulltext_gin (GINインデックス)
        ├─ idx_document_fulltext_pgroonga (PGroongaインデックス)
        └─ idx_document_fulltext_filters (複合インデックス)
```

### 2. ドキュメントアップロード → Dense層生成

```
┌────────────────────────────────────────────────────────────────┐
│                  Dense層（ベクトル検索）生成                     │
└────────────────────────────────────────────────────────────────┘

documents (status='processed')
    │
    ▼
VectorService.vectorize_document_chunks(document_id)
    │
    ├─ 1. ドキュメント情報取得
    │   SELECT * FROM documents WHERE id = :document_id
    │
    ├─ 2. 階層構造からチャンク抽出
    │   hierarchical_elements = doc.original_metadata['hierarchical_elements']
    │   chunks = extract_chunks_from_hierarchy(hierarchical_elements)
    │
    ├─ 3. Ollamaでベクトル化
    │   embeddings = OllamaEmbeddings(model="embeddinggemma:500m-768")
    │   vectors = await embeddings.aembed_documents(texts)
    │
    └─ 4. LangChain PGVectorに追加
        │
        vectorstore.aadd_texts(
            texts=[chunk['content'] for chunk in chunks],
            metadatas=[{
                'document_id': str(document_id),
                'chunk_index': i,
                'page_number': chunk['page_number'],
                ...
            } for i, chunk in enumerate(chunks)]
        )
        │
        ▼
    langchain_pg_embedding INSERT
        │
        ├─ cmetadata->>'document_id' 設定
        │
        ▼
    sync_embedding_document_id() トリガー実行
        │
        ├─ NEW.document_id := (NEW.cmetadata->>'document_id')::uuid
        │
        ▼
    langchain_pg_embedding (document_idカラム同期完了)
        ├─ idx_langchain_pg_embedding_hnsw (HNSWインデックス自動更新)
        ├─ idx_langchain_pg_embedding_ivfflat (IVFFlatインデックス自動更新)
        └─ idx_langchain_emb_tenant_kb (複合インデックス自動更新)
```

### 3. ドキュメントアップロード → Centroid生成

```
┌────────────────────────────────────────────────────────────────┐
│                 Document Centroid（重心）生成                   │
└────────────────────────────────────────────────────────────────┘

documents (status='processed')
    │
    ▼
AtlasService.calculate_document_centroid(document_id)
    │
    ├─ 1. ドキュメントの全チャンクembedding取得
    │   SELECT embedding
    │   FROM langchain_pg_embedding
    │   WHERE document_id = :document_id
    │
    ├─ 2. 平均ベクトル計算（重心）
    │   centroid = np.mean([emb for emb in embeddings], axis=0)
    │
    └─ 3. documentsテーブルに保存
        │
        UPDATE documents
        SET centroid_embedding = :centroid
        WHERE id = :document_id
        │
        ▼
    documents.centroid_embedding 設定完了
        ├─ idx_documents_centroid_hnsw (HNSWインデックス自動更新)
        └─ idx_documents_centroid_ivfflat (IVFFlatインデックス自動更新)
```

### 4. ドキュメント追加/削除 → KB要約非アクティブ化

```
┌────────────────────────────────────────────────────────────────┐
│          イベント: ドキュメント追加/削除（PostgreSQLトリガー）  │
└────────────────────────────────────────────────────────────────┘

documents INSERT/DELETE
    │
    ▼
trg_mark_kb_summary_for_regen トリガー実行
    │
    ├─ AFTER INSERT OR DELETE ON documents
    │  FOR EACH ROW
    │
    ▼
mark_kb_summary_for_regeneration() 関数実行
    │
    UPDATE knowledge_bases_summary_embedding
    SET is_active = false
    WHERE knowledge_base_id = COALESCE(NEW.knowledge_base_id, OLD.knowledge_base_id)
      AND is_active = true
    │
    ▼
knowledge_bases_summary_embedding
    ├─ is_active = false に更新
    │
    └─ バックグラウンドジョブで再生成待ち
```

### 5. バックグラウンドジョブ → KB要約再生成

```
┌────────────────────────────────────────────────────────────────┐
│           バックグラウンドジョブ（5分ごとcron実行）             │
└────────────────────────────────────────────────────────────────┘

cron: */5 * * * * (5分ごと)
    │
    ▼
AtlasService.regenerate_kb_summaries()
    │
    ├─ 1. 非アクティブなKBを取得
    │   SELECT DISTINCT kb.id, kb.name, kb.description
    │   FROM knowledge_bases kb
    │   LEFT JOIN knowledge_bases_summary_embedding kbse
    │       ON kb.id = kbse.knowledge_base_id AND kbse.is_active = true
    │   WHERE kbse.id IS NULL  -- is_active=trueの要約が存在しない
    │
    ├─ 2. KB内の全ドキュメント情報を取得
    │   SELECT filename, original_metadata->>'title', ...
    │   FROM documents
    │   WHERE knowledge_base_id = :kb_id
    │     AND status = 'processed'
    │   LIMIT 100
    │
    ├─ 3. LLMで要約テキスト生成（300-500文字）
    │   summary_text = await llm.generate_summary(
    │       kb_name=kb.name,
    │       kb_description=kb.description,
    │       documents=docs
    │   )
    │
    ├─ 4. 要約テキストをベクトル化
    │   summary_vector = await embedding_model.encode(summary_text)
    │
    ├─ 5. 統計情報計算
    │   SELECT COUNT(*) AS total_docs,
    │          SUM(chunk_count) AS total_chunks,
    │          AVG(LENGTH(original_metadata->>'text')) AS avg_length
    │   FROM documents
    │   WHERE knowledge_base_id = :kb_id
    │     AND status = 'processed'
    │
    └─ 6. 新しいバージョンとして挿入
        │
        INSERT INTO knowledge_bases_summary_embedding
        (knowledge_base_id, summary_text, summary_embedding,
         version, is_active, total_documents, total_chunks, avg_document_length)
        VALUES (:kb_id, :summary_text, :summary_vector,
                COALESCE((SELECT MAX(version) FROM knowledge_bases_summary_embedding
                          WHERE knowledge_base_id = :kb_id), 0) + 1,
                true, :total_docs, :total_chunks, :avg_length)
        │
        ▼
    knowledge_bases_summary_embedding
        ├─ 新バージョン（is_active=true）挿入
        ├─ idx_kb_summary_emb_hnsw 自動更新
        └─ Atlas層検索で新要約が使用される
```

### 6. Collection作成/更新 → Collection要約生成

```
┌────────────────────────────────────────────────────────────────┐
│             イベント: Collection作成/ドキュメント追加            │
└────────────────────────────────────────────────────────────────┘

collections INSERT/UPDATE
OR
documents INSERT/DELETE (collection_id変更)
    │
    ▼
AtlasService.regenerate_collection_summary(collection_id)
    │
    ├─ 1. Collection情報取得
    │   SELECT * FROM collections WHERE id = :collection_id
    │
    ├─ 2. Collection内のドキュメント取得
    │   SELECT filename, original_metadata
    │   FROM documents
    │   WHERE collection_id = :collection_id
    │     AND status = 'processed'
    │   LIMIT 100
    │
    ├─ 3. LLMで要約生成
    │   summary_text = await llm.generate_summary(
    │       collection_name=collection.name,
    │       collection_description=collection.description,
    │       documents=docs
    │   )
    │
    ├─ 4. ベクトル化
    │   summary_vector = await embedding_model.encode(summary_text)
    │
    ├─ 5. 統計情報
    │   SELECT COUNT(*) AS total_docs, ...
    │   FROM documents
    │   WHERE collection_id = :collection_id
    │     AND status = 'processed'
    │
    ├─ 6. 既存の要約を非アクティブ化
    │   UPDATE collections_summary_embedding
    │   SET is_active = false
    │   WHERE collection_id = :collection_id
    │     AND is_active = true
    │
    └─ 7. 新しいバージョン挿入
        │
        INSERT INTO collections_summary_embedding
        (collection_id, summary_text, summary_embedding,
         version, is_active, total_documents, total_chunks, avg_chunk_length)
        VALUES (...)
        │
        ▼
    collections_summary_embedding
        ├─ 新バージョン（is_active=true）挿入
        ├─ idx_coll_summary_emb_hnsw 自動更新
        └─ Atlas層検索で新要約が使用される
```

## トリガー一覧

### PostgreSQLトリガー

| トリガー名 | テーブル | イベント | 関数 | 用途 |
|-----------|---------|---------|------|------|
| trg_mark_kb_summary_for_regen | documents | INSERT, DELETE | mark_kb_summary_for_regeneration() | KB要約非アクティブ化 |
| trg_sync_embedding_document_id | langchain_pg_embedding | INSERT, UPDATE | sync_embedding_document_id() | document_idカラム同期 |
| trg_update_kb_doc_count | documents | INSERT, UPDATE, DELETE | update_kb_document_count() | KB document_count更新 |
| trg_update_collection_doc_count | documents | INSERT, UPDATE, DELETE | update_collection_document_count() | Collection document_count更新 |

### アプリケーションレベルトリガー

| イベント | トリガー | 処理 |
|---------|---------|------|
| documents.status = 'processed' | VectorService.vectorize_document_chunks() | Dense層生成 |
| documents.status = 'processed' | SparseSearchService.index_document_chunks() | Sparse層生成 |
| documents.status = 'processed' | AtlasService.calculate_document_centroid() | Centroid生成 |
| collections INSERT | AtlasService.regenerate_collection_summary() | Collection要約生成 |

### バックグラウンドジョブ

| ジョブ名 | 実行間隔 | 処理 |
|---------|---------|------|
| regenerate_kb_summaries | 5分 | 非アクティブなKB要約を再生成 |
| refresh_statistics | 1時間 | マテリアライズドビュー更新 |
| cleanup_old_embeddings | 1日 | 古いバージョンのembeddingクリーンアップ |

## バージョン管理フロー

### KB要約のバージョン管理

```
knowledge_bases_summary_embedding
    │
    ├─ version=1, is_active=true  (現在使用中)
    ├─ version=2, is_active=false (ドキュメント追加後、非アクティブ化)
    │
    ▼ バックグラウンドジョブで再生成
    │
    ├─ version=1, is_active=true  (まだ使用中)
    ├─ version=2, is_active=false (古いバージョン)
    └─ version=3, is_active=true  (新バージョン挿入)
           │
           ▼
    UNIQUE制約により version=1 が is_active=false に自動更新
    │
    ├─ version=1, is_active=false (自動非アクティブ化)
    ├─ version=2, is_active=false (古いバージョン)
    └─ version=3, is_active=true  (現在使用中)
```

### クリーンアップジョブ

```
cleanup_old_embeddings (1日1回実行)
    │
    ├─ 1. 古いバージョン削除
    │   DELETE FROM knowledge_bases_summary_embedding
    │   WHERE is_active = false
    │     AND created_at < NOW() - INTERVAL '30 days'
    │
    ├─ 2. 古いCollection要約削除
    │   DELETE FROM collections_summary_embedding
    │   WHERE is_active = false
    │     AND created_at < NOW() - INTERVAL '30 days'
    │
    └─ 3. VACUUM実行（ディスク領域回収）
        VACUUM ANALYZE knowledge_bases_summary_embedding;
        VACUUM ANALYZE collections_summary_embedding;
```

## パフォーマンス考慮

### 並列処理

```
documents.status = 'processed'
    │
    ├─────────────────┬─────────────────┬─────────────────┐
    │ (並列実行)      │ (並列実行)      │ (並列実行)      │
    ▼                 ▼                 ▼                 ▼
Sparse層生成      Dense層生成      Centroid生成     トリガー実行
    │                 │                 │                 │
    └─────────────────┴─────────────────┴─────────────────┘
                            │
                            ▼
                    全処理完了
```

### インデックス更新の遅延

- **HNSW/IVFFlat**: 非同期インデックス更新（バックグラウンド）
- **GIN**: 同期インデックス更新（挿入時）
- **PGroonga**: WAL書き込み後の非同期更新

### バックグラウンドジョブのスロットリング

```python
# 1度に処理するKB数を制限
MAX_KB_PER_BATCH = 10

# LLM API呼び出しのレート制限
await asyncio.sleep(1.0)  # 1秒待機
```

## 関連ドキュメント

- [../01-architecture.md](../01-architecture.md) - 7段階パイプライン全体像
- [../02-atlas-layer.md](../02-atlas-layer.md) - Atlas層詳細設計
- [../03-sparse-layer.md](../03-sparse-layer.md) - スパース層詳細設計
- [../04-dense-layer.md](../04-dense-layer.md) - Dense層詳細設計
- [database-schema.md](./database-schema.md) - 統合データベーススキーマ
