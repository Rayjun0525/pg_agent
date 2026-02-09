-- ============================================================================
-- pg_agent: Chunking
-- Purpose: Text chunking and document storage
-- ============================================================================

-- Function: chunk_text
CREATE OR REPLACE FUNCTION pg_agent.chunk_text(
    p_content text,
    p_max_tokens int DEFAULT 500,
    p_overlap_tokens int DEFAULT 50
)
RETURNS TABLE (
    chunk_index int,
    content text,
    start_line int,
    end_line int,
    hash text
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_lines text[];
    v_max_chars int;
    v_overlap_chars int;
    v_current_text text := '';
    v_current_start int := 1;
    v_chunk_idx int := 0;
    v_line_num int;
    v_line text;
BEGIN
    -- Approximate: 1 token ≈ 4 characters
    v_max_chars := GREATEST(128, p_max_tokens * 4);
    v_overlap_chars := GREATEST(0, p_overlap_tokens * 4);
    
    v_lines := string_to_array(p_content, E'\n');
    
    FOR v_line_num IN 1..array_length(v_lines, 1) LOOP
        v_line := v_lines[v_line_num];
        
        IF length(v_current_text) + length(v_line) + 1 > v_max_chars AND length(v_current_text) > 0 THEN
            chunk_index := v_chunk_idx;
            content := v_current_text;
            start_line := v_current_start;
            end_line := v_line_num - 1;
            hash := pg_agent.hash_text(v_current_text);
            RETURN NEXT;
            
            v_chunk_idx := v_chunk_idx + 1;
            
            IF v_overlap_chars > 0 AND length(v_current_text) > v_overlap_chars THEN
                v_current_text := right(v_current_text, v_overlap_chars);
                v_current_start := v_line_num - 1;
            ELSE
                v_current_text := '';
                v_current_start := v_line_num;
            END IF;
        END IF;
        
        IF length(v_current_text) > 0 THEN
            v_current_text := v_current_text || E'\n' || v_line;
        ELSE
            v_current_text := v_line;
        END IF;
    END LOOP;
    
    IF length(v_current_text) > 0 THEN
        chunk_index := v_chunk_idx;
        content := v_current_text;
        start_line := v_current_start;
        end_line := array_length(v_lines, 1);
        hash := pg_agent.hash_text(v_current_text);
        RETURN NEXT;
    END IF;
END;
$$;

-- Function: store_document
CREATE OR REPLACE FUNCTION pg_agent.store_document(
    p_content text,
    p_chunk_embeddings vector(1536)[] DEFAULT NULL,
    p_title text DEFAULT NULL,
    p_source text DEFAULT 'user',
    p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_memory_id uuid;
    v_chunk record;
    v_chunk_idx int := 0;
BEGIN
    INSERT INTO pg_agent.memory (
        content, source, metadata, category
    ) VALUES (
        COALESCE(p_title, left(p_content, 100)),
        p_source,
        p_metadata || jsonb_build_object('type', 'document', 'full_content_length', length(p_content)),
        'fact'
    ) RETURNING memory_id INTO v_memory_id;
    
    FOR v_chunk IN SELECT * FROM pg_agent.chunk_text(p_content) LOOP
        INSERT INTO pg_agent.chunk (
            memory_id, chunk_index, content, start_line, end_line, hash, embedding
        ) VALUES (
            v_memory_id,
            v_chunk.chunk_index,
            v_chunk.content,
            v_chunk.start_line,
            v_chunk.end_line,
            v_chunk.hash,
            CASE 
                WHEN p_chunk_embeddings IS NOT NULL AND v_chunk_idx < array_length(p_chunk_embeddings, 1)
                THEN p_chunk_embeddings[v_chunk_idx + 1]
                ELSE NULL
            END
        );
        v_chunk_idx := v_chunk_idx + 1;
    END LOOP;
    
    RETURN v_memory_id;
END;
$$;

-- Function: delete_memory
CREATE OR REPLACE FUNCTION pg_agent.delete_memory(p_memory_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    v_deleted boolean;
BEGIN
    DELETE FROM pg_agent.memory WHERE memory_id = p_memory_id;
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
    RETURN v_deleted > 0;
END;
$$;

-- Function: clear_all
CREATE OR REPLACE FUNCTION pg_agent.clear_all()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    TRUNCATE pg_agent.memory CASCADE;
    TRUNCATE pg_agent.session;
    TRUNCATE pg_agent.embedding_cache;
END;
$$;

-- Function: stats
CREATE OR REPLACE FUNCTION pg_agent.stats()
RETURNS TABLE (
    total_memories bigint,
    total_chunks bigint,
    total_sessions bigint,
    cached_embeddings bigint,
    memories_with_vector bigint,
    category_counts jsonb
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    RETURN QUERY
    SELECT
        (SELECT count(*) FROM pg_agent.memory)::bigint,
        (SELECT count(*) FROM pg_agent.chunk)::bigint,
        (SELECT count(*) FROM pg_agent.session)::bigint,
        (SELECT count(*) FROM pg_agent.embedding_cache)::bigint,
        (SELECT count(*) FROM pg_agent.memory WHERE embedding IS NOT NULL)::bigint,
        (SELECT jsonb_object_agg(category, cnt) 
         FROM (SELECT category, count(*) as cnt FROM pg_agent.memory GROUP BY category) sub);
END;
$$;
