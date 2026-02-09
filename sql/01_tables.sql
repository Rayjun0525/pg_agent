-- ============================================================================
-- pg_agent: Core Tables
-- Purpose: Memory storage, chunking, and session management
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Table: memory
-- Purpose: Main memory storage (Vector + FTS)
-- ----------------------------------------------------------------------------
CREATE TABLE pg_agent.memory (
    memory_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Content
    content text NOT NULL,
    embedding vector(1536),
    
    -- Metadata
    importance float DEFAULT 0.7 CHECK (importance >= 0 AND importance <= 1),
    category text DEFAULT 'other',
    source text DEFAULT 'user' CHECK (source IN ('user', 'agent', 'system')),
    
    -- Full-text search (auto-generated)
    tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED,
    
    -- Extra data
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX idx_memory_category ON pg_agent.memory(category);
CREATE INDEX idx_memory_tsv ON pg_agent.memory USING GIN(tsv);
CREATE INDEX idx_memory_created ON pg_agent.memory(created_at DESC);

-- Vector index (HNSW for better performance)
CREATE INDEX idx_memory_embedding ON pg_agent.memory 
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

COMMENT ON TABLE pg_agent.memory IS 'Core memory storage with vector embeddings and FTS';

-- ----------------------------------------------------------------------------
-- Table: chunk
-- Purpose: Document chunks for large content
-- ----------------------------------------------------------------------------
CREATE TABLE pg_agent.chunk (
    chunk_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    memory_id uuid NOT NULL REFERENCES pg_agent.memory(memory_id) ON DELETE CASCADE,
    
    -- Chunk content
    chunk_index int NOT NULL,
    content text NOT NULL,
    embedding vector(1536),
    
    -- Line tracking
    start_line int,
    end_line int,
    
    -- Deduplication hash
    hash text NOT NULL,
    
    -- FTS
    tsv tsvector GENERATED ALWAYS AS (to_tsvector('english', content)) STORED,
    
    created_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE (memory_id, chunk_index)
);

-- Indexes
CREATE INDEX idx_chunk_memory ON pg_agent.chunk(memory_id);
CREATE INDEX idx_chunk_tsv ON pg_agent.chunk USING GIN(tsv);
CREATE INDEX idx_chunk_embedding ON pg_agent.chunk 
    USING hnsw (embedding vector_cosine_ops) WITH (m = 16, ef_construction = 64);

COMMENT ON TABLE pg_agent.chunk IS 'Document chunks with embeddings for large content';

-- ----------------------------------------------------------------------------
-- Table: embedding_cache
-- Purpose: Cache embeddings to avoid redundant API calls
-- ----------------------------------------------------------------------------
CREATE TABLE pg_agent.embedding_cache (
    hash text PRIMARY KEY,
    embedding vector(1536) NOT NULL,
    model text DEFAULT 'text-embedding-3-small',
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_cache_created ON pg_agent.embedding_cache(created_at DESC);

COMMENT ON TABLE pg_agent.embedding_cache IS 'Embedding cache for deduplication';

-- ----------------------------------------------------------------------------
-- Table: session
-- Purpose: Session-scoped memory (Conversation History)
-- ----------------------------------------------------------------------------
CREATE TABLE pg_agent.session (
    session_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Session key (e.g., 'user:123:conversation:456')
    key text UNIQUE NOT NULL,
    
    -- Session context
    context jsonb DEFAULT '{}'::jsonb,
    
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_session_key ON pg_agent.session(key);
CREATE INDEX idx_session_updated ON pg_agent.session(updated_at DESC);

COMMENT ON TABLE pg_agent.session IS 'Session-scoped memory for conversations';
