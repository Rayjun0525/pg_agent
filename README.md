# pg_agent

PostgreSQL 내부에 **에이전트 메모리(장기 기억)** 를 저장하고 검색하기 위한 SQL 확장 + Python 인터페이스(CLI/Web) 프로젝트입니다.

- 메모리는 `pgagent.memory`, `pgagent.chunk`, `pgagent.session` 테이블에 저장됩니다.
- 검색은 **벡터 유사도(pgvector)** + **Full-Text Search(FTS)** 하이브리드로 동작합니다.
- LLM/임베딩 공급자는 OpenAI, Anthropic, Gemini, Voyage, **Ollama(로컬 모델)** 을 지원합니다.

---

## 목차

1. [프로젝트 목적](#1-프로젝트-목적)
2. [구성 요소](#2-구성-요소)
3. [요구사항](#3-요구사항)
4. [빠른 설치](#4-빠른-설치)
5. [Ollama 연동](#5-ollama-연동)
6. [실행 방법](#6-실행-방법)
7. [사용방법 백과](#7-사용방법-백과)
   - [SQL API 전체 레퍼런스](#71-sql-api-전체-레퍼런스)
   - [REST API 전체 레퍼런스](#72-rest-api-전체-레퍼런스)
   - [CLI 명령어 레퍼런스](#73-cli-명령어-레퍼런스)
   - [Web GUI 사용법](#74-web-gui-사용법)
   - [Python 라이브러리 레퍼런스](#75-python-라이브러리-레퍼런스)
   - [실전 시나리오별 가이드](#76-실전-시나리오별-가이드)
8. [설정 키](#8-설정-키)
9. [테스트/검증](#9-테스트검증)
10. [트러블슈팅](#10-트러블슈팅)
11. [개발 메모](#11-개발-메모)
12. [License](#license)

---

## 1) 프로젝트 목적

일반적인 에이전트 프레임워크는 메모리가 외부 벡터 DB/파일에 분산되어 추적이 어렵습니다. `pg_agent`는 메모리를 PostgreSQL 표준 객체로 관리하여 다음을 가능하게 합니다.

- SQL로 메모리 상태를 즉시 점검
- 트랜잭션/인덱스/백업 등 PostgreSQL 운영 도구 재사용
- 잘못 저장된 기억을 UPDATE/DELETE로 직접 수정

---

## 2) 구성 요소

### SQL Extension
- 스키마: `pgagent`
- 핵심 함수: `store`, `search`, `search_fts`, `search_vector`, `search_chunks`, `find_similar`, `store_document`, `chunk_text`, `stats`, `session_*` 등

### Python 라이브러리
- `lib/database.py`: DB 래퍼 (자동 재연결 지원)
- `lib/embeddings.py`: 임베딩 제공자 라우팅 (OpenAI, Gemini, Voyage, Ollama)
- `lib/chat.py`: 채팅 모델 제공자 라우팅 (OpenAI, Anthropic, Gemini, Ollama)

### 실행 인터페이스
- CLI: `cli/chat.py`
- Web GUI(FastAPI + 정적 HTML): `gui/server.py`, `gui/static/index.html`

---

## 3) 요구사항

- Ubuntu/Linux 또는 macOS
- PostgreSQL 14+ (문서 예시는 16)
- pgvector
- Python 3.10+

---

## 4) 빠른 설치

### 4.1 PostgreSQL + pgvector 설치

```bash
# Ubuntu
apt -y update
apt -y install postgresql postgresql-contrib
apt -y install postgresql-16-pgvector

# macOS (Homebrew)
brew install postgresql@16 pgvector
```

### 4.2 PostgreSQL 시작 및 접속 준비

```bash
service postgresql start   # Linux
brew services start postgresql@16  # macOS

sudo -u postgres psql -c "SELECT version();"
```

### 4.3 확장 설치

```bash
# 의존 확장 확인
sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"
sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# pg_agent 설치 파일 배치
make install

# 데이터베이스에 확장 생성
sudo -u postgres psql -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_agent;"
```

### 4.4 Python 환경

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

최소 환경변수:

```env
DATABASE_URL=postgresql://postgres@localhost:5432/postgres
OLLAMA_HOST=http://127.0.0.1:11434
```

---

## 5) Ollama 연동

### 5.1 설치/실행

```bash
ollama serve
```

### 5.2 모델 준비

```bash
ollama pull llama3.1:8b          # 채팅
ollama pull nomic-embed-text     # 임베딩 (768차원)
```

### 5.3 연결 확인

```bash
curl http://127.0.0.1:11434/api/tags
```

### 5.4 설정 전환

```sql
SELECT pgagent.set_setting('chat_provider', '"ollama"');
SELECT pgagent.set_setting('chat_model', '"llama3.1:8b"');
SELECT pgagent.set_setting('embedding_provider', '"ollama"');
SELECT pgagent.set_setting('embedding_model', '"nomic-embed-text"');
```

---

## 6) 실행 방법

### 6.1 CLI

```bash
source .venv/bin/activate
python cli/chat.py --db postgresql://postgres@localhost:5432/postgres
```

### 6.2 Web GUI

```bash
source .venv/bin/activate
python gui/server.py --host 0.0.0.0 --port 8000
```

브라우저: `http://localhost:8000`

---

## 7) 사용방법 백과

### 7.1 SQL API 전체 레퍼런스

#### 메모리 저장

##### `pgagent.store()`

메모리를 저장합니다. 카테고리는 자동 감지됩니다.

```sql
-- 기본 사용
SELECT pgagent.store('사용자가 다크 모드를 선호함');

-- 임베딩 포함
SELECT pgagent.store(
  '커피를 좋아함',     -- 내용
  '[0.1,0.2,...]'::vector,  -- 임베딩 (어떤 차원이든 OK)
  'user',              -- 소스
  0.9,                 -- 중요도 (0.0~1.0)
  '{"tag":"preference"}'::jsonb  -- 메타데이터
);

-- 중복 저장 시 자동 병합 (SHA256 해시 기반)
-- 같은 내용을 다시 store하면 importance가 높은 쪽이 유지됨
SELECT pgagent.store('커피를 좋아함', NULL, 'user', 1.0);
```

**반환값:** `uuid` (memory_id)

##### `pgagent.store_document()`

긴 문서를 자동 청킹하여 저장합니다.

```sql
-- 문서 저장 (자동으로 chunk_text 호출)
SELECT pgagent.store_document(
  '긴 문서 내용...여러 줄...',  -- 전체 내용
  NULL,                         -- 청크별 임베딩 배열 (선택)
  '문서 제목',                   -- 제목 (NULL이면 내용 앞 100자)
  'document',                    -- 소스
  '{"type":"report"}'::jsonb     -- 메타데이터
);
```

---

#### 검색

##### `pgagent.search()` — 하이브리드 검색

벡터 유사도 + FTS를 결합한 메인 검색 함수입니다.

```sql
-- 벡터 + FTS 하이브리드 (기본 가중치: 벡터 70%, FTS 30%)
SELECT * FROM pgagent.search(
  'dark mode',          -- 쿼리 텍스트
  '[0.1,0.2,...]'::vector,  -- 쿼리 임베딩
  10,                   -- 최대 반환 수
  0.7,                  -- 벡터 가중치
  0.3,                  -- FTS 가중치
  0.3                   -- 최소 유사도
);

-- 임베딩 없이 FTS만 사용 (자동 fallback)
SELECT * FROM pgagent.search('dark mode', NULL, 5);
```

**반환 컬럼:**

| 컬럼 | 타입 | 설명 |
|---|---|---|
| `memory_id` | uuid | 메모리 ID |
| `content` | text | 메모리 내용 |
| `category` | text | 카테고리 |
| `source` | text | 소스 |
| `score` | float | 최종 점수 (가중 합) |
| `vector_score` | float | 벡터 유사도 점수 |
| `text_score` | float | FTS 점수 |

##### `pgagent.search_vector()` — 벡터 전용 검색

```sql
SELECT * FROM pgagent.search_vector(
  '[0.1,0.2,...]'::vector,  -- 쿼리 임베딩
  10,                        -- 최대 반환 수
  0.5                        -- 최소 유사도
);
```

##### `pgagent.search_fts()` — FTS 전용 검색

```sql
-- websearch 구문 지원 ("OR", "-", 따옴표 등)
SELECT * FROM pgagent.search_fts('dark mode', 10);
SELECT * FROM pgagent.search_fts('"exact phrase"', 5);
SELECT * FROM pgagent.search_fts('coffee -tea', 5);
```

##### `pgagent.search_chunks()` — 청크 단위 검색

문서 청크를 벡터 검색합니다.

```sql
SELECT * FROM pgagent.search_chunks(
  '[0.1,0.2,...]'::vector,  -- 쿼리 임베딩
  10,                        -- 최대 반환 수
  0.5                        -- 최소 유사도
);
```

**반환 컬럼:** `chunk_id`, `memory_id`, `content`, `start_line`, `end_line`, `score`

##### `pgagent.find_similar()` — 유사 메모리 검색

특정 메모리와 유사한 다른 메모리를 찾습니다.

```sql
-- 메모리 ID로 유사한 메모리 5개 찾기
SELECT * FROM pgagent.find_similar(
  'a1b2c3d4-...'::uuid,  -- 기준 메모리 ID
  5                        -- 최대 반환 수
);
```

---

#### 메모리 관리

##### `pgagent.delete_memory()`

```sql
SELECT pgagent.delete_memory('a1b2c3d4-...'::uuid);
-- 반환: true(삭제 성공) / false(없음)
-- 연결된 chunk도 CASCADE 삭제됨
```

##### `pgagent.clear_all()`

```sql
-- ⚠️ 모든 메모리, 세션, 임베딩 캐시 삭제
SELECT pgagent.clear_all();
```

##### 직접 SQL로 관리

```sql
-- 특정 카테고리만 조회
SELECT * FROM pgagent.memory WHERE category = 'preference';

-- 특정 메모리 내용 수정
UPDATE pgagent.memory
SET content = '수정된 내용', importance = 1.0
WHERE memory_id = 'uuid-here';

-- 오래된 메모리 삭제
DELETE FROM pgagent.memory
WHERE created_at < now() - interval '30 days'
  AND importance < 0.5;

-- 카테고리별 개수
SELECT category, count(*) FROM pgagent.memory GROUP BY category;
```

---

#### 자동 분류 도구

##### `pgagent.should_capture()`

텍스트가 메모리로 저장할 가치가 있는지 판단합니다.

```sql
SELECT pgagent.should_capture('I prefer dark mode');     -- true
SELECT pgagent.should_capture('ok');                      -- false (너무 짧음)
SELECT pgagent.should_capture('my email is a@b.com');    -- true (엔티티)
SELECT pgagent.should_capture('I decided to use Python'); -- true (결정)
```

**규칙:**
- 10자 미만 또는 500자 초과 → `false`
- XML 태그 포함 → `false` (주입된 컨텍스트 방지)
- "ok", "yes", "thanks" 등 단순 응답 → `false`
- prefer, like, love, hate, remember 등 → `true`
- decided, will use, plan to 등 → `true`
- 전화번호, 이메일, 이름 패턴 → `true`

##### `pgagent.detect_category()`

텍스트를 카테고리로 자동 분류합니다.

```sql
SELECT pgagent.detect_category('I prefer dark mode');       -- 'preference'
SELECT pgagent.detect_category('I decided to use Redis');   -- 'decision'
SELECT pgagent.detect_category('my email is test@x.com');   -- 'entity'
SELECT pgagent.detect_category('PostgreSQL supports JSONB'); -- 'fact'
SELECT pgagent.detect_category('안녕하세요');                 -- 'other'
```

---

#### 세션 (대화 컨텍스트)

키-값 기반의 JSON 컨텍스트 저장소입니다.

```sql
-- 세션 생성/덮어쓰기
SELECT pgagent.session_set('user:123', '{"topic":"postgres","mood":"good"}'::jsonb);

-- 세션 조회
SELECT pgagent.session_get('user:123');
-- → {"topic": "postgres", "mood": "good"}

-- 세션에 키 추가/병합 (기존 키는 유지, 새 키 추가)
SELECT pgagent.session_append('user:123', '{"step": 3}'::jsonb);
SELECT pgagent.session_get('user:123');
-- → {"topic": "postgres", "mood": "good", "step": 3}

-- 세션 삭제
SELECT pgagent.session_delete('user:123');
-- → true (삭제됨)
```

---

#### 텍스트 처리

##### `pgagent.chunk_text()`

긴 텍스트를 청크로 분할합니다.

```sql
SELECT * FROM pgagent.chunk_text(
  '긴 텍스트...',   -- 원본 텍스트
  500,               -- 청크당 최대 토큰 (기본 500, 1토큰≈4자)
  50                 -- 오버랩 토큰 (기본 50)
);
```

**반환 컬럼:** `chunk_index`, `content`, `start_line`, `end_line`, `hash`

##### `pgagent.hash_text()`

```sql
SELECT pgagent.hash_text('Hello World');
-- → SHA256 해시 (hex 문자열)
```

##### `pgagent.get_cached_embedding()`

이전에 저장한 임베딩을 해시로 조회합니다.

```sql
SELECT pgagent.get_cached_embedding('Hello World');
-- → vector 또는 NULL
```

---

#### 통계

##### `pgagent.stats()`

```sql
SELECT * FROM pgagent.stats();
```

| 컬럼 | 설명 |
|---|---|
| `total_memories` | 총 메모리 수 |
| `total_chunks` | 총 청크 수 |
| `total_sessions` | 총 세션 수 |
| `cached_embeddings` | 캐시된 임베딩 수 |
| `memories_with_vector` | 벡터가 있는 메모리 수 |
| `category_counts` | 카테고리별 개수 (JSON) |

---

#### 설정 관리

```sql
-- 개별 설정 조회
SELECT pgagent.get_setting('chat_provider');

-- 전체 설정 조회
SELECT pgagent.get_all_settings();

-- 설정 변경 (값은 JSON 형식으로 감쌈)
SELECT pgagent.set_setting('chat_provider', '"ollama"');
SELECT pgagent.set_setting('search_limit', '10');
SELECT pgagent.set_setting('auto_capture', 'true');

-- 설정 초기화
SELECT pgagent.reset_settings();
```

---

### 7.2 REST API 전체 레퍼런스

Web GUI 서버 (`gui/server.py`)가 제공하는 API입니다.

#### 헬스체크

```bash
curl http://localhost:8000/api/health
# → {"status":"ok","service":"pg_agent"}
```

#### 채팅

```bash
# 대화 보내기
curl -X POST http://localhost:8000/api/chat \
  -H "Content-Type: application/json" \
  -d '{"message":"안녕하세요", "session_id":"user1"}'

# 응답:
# {
#   "response": "안녕하세요! 무엇을 도와드릴까요?",
#   "memories_used": [...],
#   "memory_saved": true
# }

# 대화 기록 초기화
curl -X POST "http://localhost:8000/api/chat/clear?session_id=user1"
```

#### 설정

```bash
# 전체 설정 조회
curl http://localhost:8000/api/settings
# → {"chat_provider":"ollama", "chat_model":"llama3.1:8b", ...}

# 설정 변경
curl -X POST http://localhost:8000/api/settings \
  -H "Content-Type: application/json" \
  -d '{"key":"chat_provider","value":"ollama"}'
```

#### 메모리

```bash
# 메모리 목록 조회
curl "http://localhost:8000/api/memories?limit=10&offset=0"
# → {"memories":[...], "limit":10, "offset":0}

# 메모리 수동 저장
curl -X POST http://localhost:8000/api/memories \
  -H "Content-Type: application/json" \
  -d '{"content":"중요한 정보입니다","source":"manual"}'
# → {"memory_id":"uuid-here"}

# 메모리 삭제
curl -X DELETE http://localhost:8000/api/memories/{memory_id}
```

#### 통계

```bash
curl http://localhost:8000/api/stats
# → {"total_memories":42, "total_chunks":15, "total_sessions":3, ...}
```

---

### 7.3 CLI 명령어 레퍼런스

```bash
python cli/chat.py --db postgresql://postgres@localhost:5432/postgres
```

대화 중 사용 가능한 명령:

| 명령 | 설명 | 예시 |
|---|---|---|
| `stats` | 메모리/청크/세션 통계 출력 | `stats` |
| `clear` | 현재 대화 히스토리 초기화 | `clear` |
| `setting key=value` | 설정 값 실시간 변경 | `setting chat_model=llama3.1:8b` |
| `quit` / `exit` / `q` | CLI 종료 | `quit` |

**대화 흐름 예시:**

```
🧠 pg_agent CLI
📡 Chat: ollama / llama3.1:8b
🔢 Embedding: ollama / nomic-embed-text
----------------------------------------

👤 You: 나는 커피를 좋아해
🤖 Assistant: 커피를 좋아하시는군요! 어떤 종류의 커피를 선호하시나요?
   💾 (memory saved)

👤 You: 아메리카노를 제일 좋아해
🤖 Assistant: 아메리카노를 좋아하시는군요! 그 정보를 기억하겠습니다.
   💾 (memory saved)

👤 You: 내가 뭘 좋아한다고 했지?
🤖 Assistant: 커피, 특히 아메리카노를 좋아한다고 하셨습니다!

👤 You: stats
📊 Stats: 2 memories, 0 chunks, 0 sessions

👤 You: setting search_limit=10
⚙️  Set search_limit = 10

👤 You: quit
👋 Goodbye!
```

---

### 7.4 Web GUI 사용법

#### Chat 탭
- 메시지 입력 후 **전송** 버튼 또는 `Enter` 키로 전송
- 자동으로 관련 메모리를 검색하여 LLM에 컨텍스트로 전달
- 메시지 하단에 `📚 N memories used` / `💾 saved` 표시
- `should_capture` 조건에 맞으면 자동으로 메모리 저장

#### Settings 탭
- **채팅 공급자** 선택: OpenAI / Anthropic / Gemini / Ollama
- **채팅 모델** 선택: 공급자별 모델명
- **임베딩 공급자** 선택
- **임베딩 모델** 선택
- **검색 제한**, **최소 유사도**, **자동 캡처** 등 실시간 변경
- 변경 즉시 DB에 반영

#### Memory 탭
- **통계**: 총 메모리/청크/세션 수 표시
- **메모리 목록**: 카테고리, 소스, 내용 확인
- **삭제**: 각 메모리 옆 🗑️ 버튼으로 개별 삭제

---

### 7.5 Python 라이브러리 레퍼런스

코드에서 직접 `pg_agent`를 사용할 수 있습니다.

```python
from lib.database import Database
from lib.embeddings import get_embedding, get_embeddings_batch
from lib.chat import get_chat_response

# DB 연결 (자동 재연결 지원)
db = Database("postgresql://postgres@localhost:5432/postgres")

# 설정 조회/변경
settings = db.get_all_settings()
db.set_setting("chat_provider", "ollama")

# 임베딩 생성
embedding = get_embedding("커피를 좋아함", settings)
# → [0.123, -0.456, ...] (차원은 모델에 따라 다름)

# 배치 임베딩
embeddings = get_embeddings_batch(["텍스트1", "텍스트2"], settings)

# 메모리 저장
memory_id = db.store("커피를 좋아함", embedding, source="user", importance=0.9)

# 하이브리드 검색
results = db.search("음료 선호", embedding, limit=5, min_similarity=0.3)
for r in results:
    print(f"[{r['category']}] {r['content']} (score: {r['score']:.2f})")

# FTS 전용 검색 (임베딩 불필요)
results = db.search_fts("커피", limit=5)

# 자동 캡처 판단
if db.should_capture("사용자가 Python을 선호한다고 말함"):
    db.store("사용자가 Python을 선호함", embedding)

# 통계
stats = db.get_stats()
print(f"메모리 {stats['total_memories']}개")

# 채팅 (메모리 연동)
context = "\n".join(f"- {r['content']}" for r in results)
response = get_chat_response(
    "나의 음료 선호도가 뭐야?",
    history=[],           # 이전 대화
    context=context,      # 검색된 메모리
    settings=settings     # 공급자/모델 설정
)
print(response)

# 정리
db.close()
```

---

### 7.6 실전 시나리오별 가이드

#### 시나리오 1: 사용자 선호/프로필 관리

```sql
-- 선호도 저장
SELECT pgagent.store('사용자가 다크 모드를 선호', NULL, 'user', 0.9);
SELECT pgagent.store('사용자 이메일: user@example.com', NULL, 'user', 1.0);

-- 사용자 선호 검색
SELECT content, category, importance
FROM pgagent.memory
WHERE category = 'preference'
ORDER BY importance DESC;

-- 엔티티(연락처 등) 검색
SELECT * FROM pgagent.search_fts('email', 5);
```

#### 시나리오 2: 문서/지식 베이스 구축

```sql
-- 문서 저장 (자동 청킹)
SELECT pgagent.store_document(
  pg_read_file('/tmp/guide.md'),
  NULL,
  'Setup Guide',
  'document'
);

-- 청크 확인
SELECT c.chunk_index, c.content, c.start_line, c.end_line
FROM pgagent.chunk c
JOIN pgagent.memory m ON c.memory_id = m.memory_id
WHERE m.content = 'Setup Guide';

-- 청크 단위 검색 (임베딩 필요)
-- Python에서 임베딩 생성 후:
SELECT * FROM pgagent.search_chunks('[0.1,0.2,...]'::vector, 5, 0.5);
```

#### 시나리오 3: 멀티턴 대화 세션 관리

```sql
-- 세션 생성
SELECT pgagent.session_set('chat:user123', '{"topic":"postgres","step":1}'::jsonb);

-- 대화 진행에 따라 세션 업데이트
SELECT pgagent.session_append('chat:user123', '{"step":2,"last_query":"인덱스 설명"}'::jsonb);

-- 세션 확인
SELECT pgagent.session_get('chat:user123');
-- {"topic":"postgres","step":2,"last_query":"인덱스 설명"}

-- 대화 종료 시 삭제
SELECT pgagent.session_delete('chat:user123');
```

#### 시나리오 4: 유사 메모리 발견 및 정리

```sql
-- 가장 유사한 메모리 찾기
SELECT * FROM pgagent.find_similar(
  (SELECT memory_id FROM pgagent.memory LIMIT 1),
  5
);

-- 중복 가능성 있는 메모리 찾기 (높은 유사도)
SELECT m1.memory_id, m1.content, m2.memory_id, m2.content,
       1 - (m1.embedding <=> m2.embedding) as similarity
FROM pgagent.memory m1
JOIN pgagent.memory m2 ON m1.memory_id < m2.memory_id
WHERE m1.embedding IS NOT NULL AND m2.embedding IS NOT NULL
  AND 1 - (m1.embedding <=> m2.embedding) > 0.95;
```

#### 시나리오 5: 공급자 전환

```sql
-- OpenAI → Ollama 전환
SELECT pgagent.set_setting('chat_provider', '"ollama"');
SELECT pgagent.set_setting('chat_model', '"llama3.1:8b"');
SELECT pgagent.set_setting('embedding_provider', '"ollama"');
SELECT pgagent.set_setting('embedding_model', '"nomic-embed-text"');

-- ⚠️ 임베딩 차원이 달라지면 기존 벡터 검색 결과가 부정확해집니다.
-- 공급자 번경 후 메모리를 재생성하려면:
SELECT pgagent.clear_all();
```

#### 시나리오 6: 백업과 복원

```bash
# 메모리만 백업
pg_dump -d postgres -t 'pgagent.*' -f pgagent_backup.sql

# 복원
psql -d postgres -f pgagent_backup.sql
```

---

## 8) 설정 키

| key | 설명 | 기본값 | 예시 |
|---|---|---|---|
| `chat_provider` | 채팅 공급자 | `openai` | `"ollama"` |
| `chat_model` | 채팅 모델명 | `gpt-4o-mini` | `"llama3.1:8b"` |
| `embedding_provider` | 임베딩 공급자 | `openai` | `"ollama"` |
| `embedding_model` | 임베딩 모델명 | `text-embedding-3-small` | `"nomic-embed-text"` |
| `embedding_dims` | 임베딩 차원 (참고용) | `1536` | `768` |
| `system_prompt` | 시스템 프롬프트 | `You are a helpful assistant...` | 커스텀 프롬프트 |
| `auto_capture` | 자동 메모리 저장 | `true` | `false` |
| `search_limit` | 검색 최대 반환 수 | `5` | `10` |
| `min_similarity` | 최소 유사도 임계값 | `0.3` | `0.5` |

---

## 9) 테스트/검증

### 9.1 SQL smoke test

```bash
sudo -u postgres psql -d postgres -f tests/smoke_test.sql
```

### 9.2 Python 유닛 테스트

```bash
python3 -m unittest tests.test_lib -v
# Ran 15 tests in 0.003s — OK
```

### 9.3 API 헬스체크

```bash
curl http://127.0.0.1:8000/api/health
```

### 9.4 직접 점검 쿼리

```sql
SELECT count(*) FROM pgagent.memory;
SELECT * FROM pgagent.get_all_settings();
SELECT * FROM pgagent.stats();
```

---

## 10) 트러블슈팅

### `extension "vector" is not available`
- pgvector 패키지 설치 누락
- `postgresql-<major>-pgvector` 설치 여부 확인

### `permission denied` 또는 인증 오류
- `DATABASE_URL` 사용자/호스트 재확인
- 로컬 peer 인증 환경이면 `postgres` 사용자로 실행

### Ollama 연결 실패
- `ollama serve` 실행 여부 확인
- `OLLAMA_HOST` 값 확인 (기본: `http://127.0.0.1:11434`)
- `curl $OLLAMA_HOST/api/tags` 성공 여부 점검

### 임베딩 차원 불일치 경고
- 공급자 변경 시 기존 벡터와 새 벡터의 차원이 다르면 검색 불가
- `pgagent.clear_all()` 후 재저장 권장

### 모델명 오류
- `ollama list`로 설치된 모델명 정확히 입력

---

## 11) 개발 메모

- SQL 원본: `sql/*.sql`
- 배포용 단일 파일: `pg_agent--0.1.0.sql` (Makefile로 생성)
- SQL 재생성: `make pg_agent--0.1.0.sql`
- 테스트 SQL: `tests/smoke_test.sql`
- Python 테스트: `tests/test_lib.py`

---

## License

GPL v3. `LICENSE` 참고.
