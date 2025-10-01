# Admin API の Redis 使用法

**バージョン**: 1.0.0
**最終更新**: 2025-09-30

## 目次
- [概要](#概要)
- [ジョブステータス管理](#ジョブステータス管理)
- [ドキュメント処理キュー](#ドキュメント処理キュー)
- [管理APIレート制限](#管理apiレート制限)
- [OCR処理の進捗管理](#ocr処理の進捗管理)
- [実装詳細](#実装詳細)

---

## 概要

### Admin API Service における Redis の役割

Admin API Service (`ai-micro-api-admin`) は、管理機能、ドキュメント処理、OCR、RAG システムを担当するマイクロサービスです。Redis は以下の主要機能で利用されます：

1. **ジョブステータス管理**: 長時間実行ジョブの進捗追跡
2. **ドキュメント処理キュー**: 非同期ドキュメント処理の管理
3. **管理APIレート制限**: 管理操作の過剰実行防止
4. **OCR処理の進捗管理**: ドキュメントOCRの進捗とステータス

### 接続情報

**サービス**: ai-micro-api-admin (Port 8003)
**Redis URL**: `redis://:<password>@host.docker.internal:6379`
**クライアント**: redis-py
**主要データ**: ジョブステータス、処理キュー、進捗情報

---

## ジョブステータス管理

### ジョブステータスの目的

ドキュメント処理やOCRなどの長時間実行タスクの進捗をリアルタイムで追跡します。

### キーパターン

```
job:status:<job_id>
```

**例**:
```
job:status:doc-ocr-550e8400-e29b-41d4-a716-446655440000
```

### データ構造

**データ型**: String (JSON)

**JSON スキーマ**:
```json
{
  "job_id": "doc-ocr-550e8400-e29b-41d4-a716-446655440000",
  "job_type": "document_ocr",
  "status": "processing",
  "progress": 45,
  "total_pages": 10,
  "processed_pages": 4,
  "current_page": 5,
  "started_at": "2025-09-30T10:00:00Z",
  "updated_at": "2025-09-30T10:02:30Z",
  "estimated_completion": "2025-09-30T10:05:00Z",
  "document_id": "550e8400-e29b-41d4-a716-446655440000",
  "user_id": "user-123",
  "error": null
}
```

**ステータス値**:
- `pending`: 待機中
- `processing`: 処理中
- `completed`: 完了
- `failed`: 失敗
- `cancelled`: キャンセル

**TTL**: 86400秒（24時間）- 完了後も履歴として保持

### 実装例: ジョブの作成

```python
# app/services/job_manager.py

from datetime import datetime, timedelta
import uuid
import json

class JobManager:
    def __init__(self, redis_client: Redis):
        self.redis = redis_client

    def create_job(
        self,
        job_type: str,
        document_id: str,
        user_id: str,
        total_pages: int = 0
    ) -> str:
        """
        ジョブを作成して Redis に保存

        Returns:
            str: ジョブID
        """

        job_id = f"{job_type}-{uuid.uuid4()}"

        job_data = {
            "job_id": job_id,
            "job_type": job_type,
            "status": "pending",
            "progress": 0,
            "total_pages": total_pages,
            "processed_pages": 0,
            "current_page": 0,
            "started_at": datetime.utcnow().isoformat(),
            "updated_at": datetime.utcnow().isoformat(),
            "estimated_completion": None,
            "document_id": document_id,
            "user_id": user_id,
            "error": None
        }

        # Redis に保存（TTL: 24時間）
        job_key = f"job:status:{job_id}"
        self.redis.setex(
            job_key,
            86400,
            json.dumps(job_data, ensure_ascii=False)
        )

        return job_id

    def update_job_status(
        self,
        job_id: str,
        status: str,
        progress: int = None,
        processed_pages: int = None,
        current_page: int = None,
        error: str = None
    ):
        """ジョブステータスを更新"""

        job_key = f"job:status:{job_id}"

        # 既存データ取得
        existing_data = self.redis.get(job_key)
        if not existing_data:
            raise ValueError(f"Job not found: {job_id}")

        job_data = json.loads(existing_data)

        # 更新
        job_data["status"] = status
        job_data["updated_at"] = datetime.utcnow().isoformat()

        if progress is not None:
            job_data["progress"] = progress

        if processed_pages is not None:
            job_data["processed_pages"] = processed_pages

        if current_page is not None:
            job_data["current_page"] = current_page

        if error is not None:
            job_data["error"] = error

        # 完了時刻の推定
        if job_data["total_pages"] > 0 and processed_pages:
            elapsed = (datetime.utcnow() - datetime.fromisoformat(job_data["started_at"])).total_seconds()
            avg_time_per_page = elapsed / processed_pages
            remaining_pages = job_data["total_pages"] - processed_pages
            estimated_seconds = remaining_pages * avg_time_per_page
            job_data["estimated_completion"] = (
                datetime.utcnow() + timedelta(seconds=estimated_seconds)
            ).isoformat()

        # 保存
        self.redis.setex(
            job_key,
            86400,
            json.dumps(job_data, ensure_ascii=False)
        )

    def get_job_status(self, job_id: str) -> dict:
        """ジョブステータスを取得"""

        job_key = f"job:status:{job_id}"
        job_data = self.redis.get(job_key)

        if not job_data:
            return None

        return json.loads(job_data)
```

### エンドポイントでの使用

```python
# app/routers/documents.py

from fastapi import APIRouter, UploadFile, BackgroundTasks

router = APIRouter()

@router.post("/documents/upload")
async def upload_document(
    file: UploadFile,
    background_tasks: BackgroundTasks,
    job_manager: JobManager = Depends(get_job_manager),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    ドキュメントアップロードとOCR処理開始
    """

    # 1. ドキュメントをデータベースに保存
    document = Document(
        id=uuid.uuid4(),
        title=file.filename,
        user_id=current_user.id,
        status="uploaded"
    )
    db.add(document)
    db.commit()

    # 2. ファイルを保存
    file_path = save_uploaded_file(file, str(document.id))

    # 3. ページ数を取得
    total_pages = get_pdf_page_count(file_path)

    # 4. ジョブ作成
    job_id = job_manager.create_job(
        job_type="document_ocr",
        document_id=str(document.id),
        user_id=str(current_user.id),
        total_pages=total_pages
    )

    # 5. バックグラウンドでOCR処理を開始
    background_tasks.add_task(
        process_document_ocr,
        document.id,
        job_id,
        file_path
    )

    return {
        "message": "Document uploaded successfully",
        "document_id": str(document.id),
        "job_id": job_id,
        "status": "pending"
    }

@router.get("/documents/jobs/{job_id}")
async def get_job_status(
    job_id: str,
    job_manager: JobManager = Depends(get_job_manager),
    current_user: User = Depends(get_current_user)
):
    """ジョブステータス取得"""

    job_status = job_manager.get_job_status(job_id)

    if not job_status:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Job not found"
        )

    # 権限チェック
    if job_status["user_id"] != str(current_user.id) and current_user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized"
        )

    return job_status
```

---

## ドキュメント処理キュー

### キューの目的

複数のドキュメント処理リクエストを順次処理するためのキューを管理します。

### キーパターン

```
queue:document:processing
```

**データ型**: List

**要素**: ジョブIDの文字列

### 実装例

```python
# app/services/document_queue.py

class DocumentQueue:
    def __init__(self, redis_client: Redis):
        self.redis = redis_client
        self.queue_key = "queue:document:processing"

    def enqueue(self, job_id: str):
        """ジョブをキューに追加"""
        self.redis.rpush(self.queue_key, job_id)

    def dequeue(self) -> str:
        """ジョブをキューから取得（ブロッキング）"""
        # BLPOP: ブロッキングPOP（タイムアウト5秒）
        result = self.redis.blpop(self.queue_key, timeout=5)
        if result:
            return result[1]  # (key, value) のタプル
        return None

    def get_queue_length(self) -> int:
        """キュー内のジョブ数を取得"""
        return self.redis.llen(self.queue_key)

    def get_queue_items(self) -> list:
        """キュー内のすべてのジョブIDを取得"""
        return self.redis.lrange(self.queue_key, 0, -1)

# ワーカープロセス
async def document_processing_worker(
    queue: DocumentQueue,
    job_manager: JobManager
):
    """
    ドキュメント処理ワーカー
    """

    logger.info("Document processing worker started")

    while True:
        try:
            # キューからジョブを取得（ブロッキング）
            job_id = queue.dequeue()

            if job_id:
                logger.info(f"Processing job: {job_id}")

                # ジョブステータスを取得
                job_status = job_manager.get_job_status(job_id)

                if not job_status:
                    logger.warning(f"Job not found: {job_id}")
                    continue

                # ステータスを "processing" に更新
                job_manager.update_job_status(job_id, status="processing")

                # ドキュメント処理を実行
                try:
                    await process_document(job_status)

                    # 完了
                    job_manager.update_job_status(
                        job_id,
                        status="completed",
                        progress=100
                    )

                except Exception as e:
                    logger.error(f"Job failed: {job_id}, error: {e}")

                    # 失敗
                    job_manager.update_job_status(
                        job_id,
                        status="failed",
                        error=str(e)
                    )

        except Exception as e:
            logger.error(f"Worker error: {e}")
            await asyncio.sleep(5)
```

---

## 管理APIレート制限

### 管理操作のレート制限

管理APIは重要な操作を含むため、厳格なレート制限を適用します。

### キーパターン

```
rate:admin:<user_id>:<endpoint>:<yyyyMMddHH>
```

### 実装例

```python
# app/routers/admin.py

@router.delete("/admin/users/{user_id}")
async def delete_user(
    user_id: str,
    rate_limiter: RateLimiter = Depends(get_rate_limiter),
    current_user: User = Depends(require_admin),
    db: Session = Depends(get_db)
):
    """
    ユーザー削除（管理者のみ、レート制限: 10回/時間）
    """

    # レート制限チェック
    await rate_limiter.check_rate_limit(
        user_id=str(current_user.id),
        endpoint="/admin/users/delete",
        limit=10
    )

    # ユーザー削除処理
    user = db.query(User).filter(User.id == user_id).first()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found"
        )

    db.delete(user)
    db.commit()

    return {"message": "User deleted successfully"}

@router.post("/admin/documents/{document_id}/reprocess")
async def reprocess_document(
    document_id: str,
    rate_limiter: RateLimiter = Depends(get_rate_limiter),
    current_user: User = Depends(require_admin),
    job_manager: JobManager = Depends(get_job_manager),
    db: Session = Depends(get_db)
):
    """
    ドキュメント再処理（管理者のみ、レート制限: 20回/時間）
    """

    # レート制限チェック
    await rate_limiter.check_rate_limit(
        user_id=str(current_user.id),
        endpoint="/admin/documents/reprocess",
        limit=20
    )

    # ドキュメント取得
    document = db.query(Document).filter(Document.id == document_id).first()

    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )

    # ジョブ作成
    job_id = job_manager.create_job(
        job_type="document_reprocess",
        document_id=document_id,
        user_id=str(current_user.id),
        total_pages=document.total_pages
    )

    # 処理開始
    # ...

    return {
        "message": "Document reprocessing started",
        "job_id": job_id
    }
```

---

## OCR処理の進捗管理

### ページ単位の進捗追跡

OCR処理の進捗をページ単位でリアルタイム追跡します。

### 実装例

```python
# app/services/ocr_processor.py

async def process_document_ocr(
    document_id: str,
    job_id: str,
    file_path: str
):
    """
    ドキュメントOCR処理（ページ単位で進捗更新）
    """

    job_manager = JobManager(redis_client)

    try:
        # PDF を開く
        pdf_document = fitz.open(file_path)
        total_pages = len(pdf_document)

        # ステータスを "processing" に更新
        job_manager.update_job_status(
            job_id,
            status="processing",
            progress=0
        )

        ocr_results = []

        # ページごとに処理
        for page_num in range(total_pages):
            page = pdf_document[page_num]

            # OCR 実行
            ocr_result = await perform_ocr(page)
            ocr_results.append(ocr_result)

            # 進捗を計算
            processed_pages = page_num + 1
            progress = int((processed_pages / total_pages) * 100)

            # Redis の進捗を更新
            job_manager.update_job_status(
                job_id,
                status="processing",
                progress=progress,
                processed_pages=processed_pages,
                current_page=page_num + 1
            )

            logger.info(
                f"Job {job_id}: Processed page {processed_pages}/{total_pages} ({progress}%)"
            )

        # すべてのページが完了
        job_manager.update_job_status(
            job_id,
            status="completed",
            progress=100,
            processed_pages=total_pages
        )

        # データベースに保存
        save_ocr_results_to_db(document_id, ocr_results)

        logger.info(f"Job {job_id}: Completed successfully")

    except Exception as e:
        logger.error(f"Job {job_id}: Failed with error: {e}")

        # エラー状態に更新
        job_manager.update_job_status(
            job_id,
            status="failed",
            error=str(e)
        )

        raise
```

### リアルタイム進捗表示（WebSocket）

```python
# app/routers/websocket.py

from fastapi import WebSocket, WebSocketDisconnect

@app.websocket("/ws/jobs/{job_id}")
async def websocket_job_status(
    websocket: WebSocket,
    job_id: str,
    job_manager: JobManager = Depends(get_job_manager)
):
    """
    WebSocket でジョブステータスをリアルタイム配信
    """

    await websocket.accept()

    try:
        while True:
            # Redis からジョブステータスを取得
            job_status = job_manager.get_job_status(job_id)

            if not job_status:
                await websocket.send_json({"error": "Job not found"})
                break

            # クライアントに送信
            await websocket.send_json(job_status)

            # 完了または失敗したら接続を閉じる
            if job_status["status"] in ["completed", "failed", "cancelled"]:
                break

            # 1秒待機
            await asyncio.sleep(1)

    except WebSocketDisconnect:
        logger.info(f"WebSocket disconnected for job: {job_id}")
```

---

## 実装詳細

### 依存性注入

```python
# app/dependencies.py

from app.services.job_manager import JobManager
from app.services.document_queue import DocumentQueue

def get_job_manager(redis_client: Redis = Depends(get_redis_client)):
    return JobManager(redis_client)

def get_document_queue(redis_client: Redis = Depends(get_redis_client)):
    return DocumentQueue(redis_client)
```

### バックグラウンドワーカーの起動

```python
# app/main.py

from fastapi import FastAPI
import asyncio

app = FastAPI()

@app.on_event("startup")
async def startup_event():
    """アプリケーション起動時にワーカーを開始"""

    # ドキュメント処理ワーカーを起動
    queue = DocumentQueue(redis_client)
    job_manager = JobManager(redis_client)

    asyncio.create_task(
        document_processing_worker(queue, job_manager)
    )

    logger.info("Background workers started")
```

---

## エラーハンドリングとリトライ

### ジョブのリトライ機能

```python
# app/services/job_manager.py

class JobManager:
    def retry_job(self, job_id: str, max_retries: int = 3):
        """
        失敗したジョブをリトライ
        """

        job_status = self.get_job_status(job_id)

        if not job_status:
            raise ValueError(f"Job not found: {job_id}")

        # リトライ回数を取得
        retry_count = job_status.get("retry_count", 0)

        if retry_count >= max_retries:
            logger.warning(f"Job {job_id} exceeded max retries ({max_retries})")
            self.update_job_status(
                job_id,
                status="failed",
                error=f"Exceeded max retries ({max_retries})"
            )
            return False

        # リトライ回数をインクリメント
        job_status["retry_count"] = retry_count + 1
        job_status["status"] = "pending"
        job_status["error"] = None

        job_key = f"job:status:{job_id}"
        self.redis.setex(
            job_key,
            86400,
            json.dumps(job_status, ensure_ascii=False)
        )

        # キューに再度追加
        queue = DocumentQueue(self.redis)
        queue.enqueue(job_id)

        logger.info(f"Job {job_id} retried (attempt {retry_count + 1}/{max_retries})")
        return True
```

---

## 監視とメトリクス

### ジョブメトリクスの収集

```bash
# アクティブジョブ数
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "job:status:*" | wc -l

# キュー内のジョブ数
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} llen "queue:document:processing"

# 処理中のジョブを検索
docker exec ai-micro-redis redis-cli -a ${REDIS_PASSWORD} --scan --pattern "job:status:*" | \
  xargs -I {} redis-cli -a ${REDIS_PASSWORD} get {} | \
  jq 'select(.status == "processing")'
```

---

## 関連ドキュメント

- [Redis 概要](./01-overview.md)
- [データ構造概要](./02-data-structure-overview.md)
- [Admin API Service 概要](/03-admin-api/01-overview.md)

---

**次のステップ**: [キャッシュ戦略](./06-cache-strategy.md) を参照して、効果的なキャッシュ設計とパターンを確認してください。