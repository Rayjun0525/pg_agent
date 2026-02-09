"""
pg_agent Database Interface
"""

import json
import psycopg2
from psycopg2.extras import RealDictCursor


class Database:
    def __init__(self, connection_url: str):
        self.conn = psycopg2.connect(connection_url)
        self.conn.autocommit = True
        
    def close(self):
        self.conn.close()
        
    def execute(self, query: str, params=None):
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            try:
                return cur.fetchall()
            except psycopg2.ProgrammingError:
                return None
                
    def execute_one(self, query: str, params=None):
        results = self.execute(query, params)
        return results[0] if results else None
        
    # Settings
    def get_setting(self, key: str):
        result = self.execute_one(
            "SELECT pg_agent.get_setting(%s) as value",
            (key,)
        )
        if result and result['value']:
            return json.loads(result['value']) if isinstance(result['value'], str) else result['value']
        return None
        
    def set_setting(self, key: str, value):
        if isinstance(value, str) and not value.startswith('"'):
            value = f'"{value}"'
        self.execute(
            "SELECT pg_agent.set_setting(%s, %s::jsonb)",
            (key, value if isinstance(value, str) else json.dumps(value))
        )
        
    def get_all_settings(self) -> dict:
        result = self.execute_one("SELECT pg_agent.get_all_settings() as settings")
        if result and result['settings']:
            settings = result['settings']
            # Parse JSON strings
            return {k: (json.loads(v) if isinstance(v, str) and v.startswith('"') else v) 
                    for k, v in settings.items()}
        return {}
        
    # Memory
    def store(self, content: str, embedding=None, source: str = 'user', 
              importance: float = 0.7, metadata: dict = None):
        embedding_str = f"[{','.join(map(str, embedding))}]" if embedding else None
        result = self.execute_one(
            """SELECT pg_agent.store(%s, %s::vector(1536), %s, %s, %s::jsonb) as memory_id""",
            (content, embedding_str, source, importance, json.dumps(metadata or {}))
        )
        return result['memory_id'] if result else None
        
    def search(self, query: str, embedding, limit: int = 5, min_similarity: float = 0.3):
        embedding_str = f"[{','.join(map(str, embedding))}]" if embedding else None
        return self.execute(
            """SELECT * FROM pg_agent.search(%s, %s::vector(1536), %s, 0.7, 0.3, %s)""",
            (query, embedding_str, limit, min_similarity)
        )
        
    def search_fts(self, query: str, limit: int = 5):
        return self.execute(
            """SELECT * FROM pg_agent.search_fts(%s, %s)""",
            (query, limit)
        )
        
    def should_capture(self, text: str) -> bool:
        result = self.execute_one(
            "SELECT pg_agent.should_capture(%s) as should",
            (text,)
        )
        return result['should'] if result else False
        
    def get_stats(self) -> dict:
        result = self.execute_one("SELECT * FROM pg_agent.stats()")
        return dict(result) if result else {}
        
    def get_memories(self, limit: int = 50, offset: int = 0):
        return self.execute(
            """SELECT memory_id, content, category, source, importance, created_at 
               FROM pg_agent.memory 
               ORDER BY created_at DESC 
               LIMIT %s OFFSET %s""",
            (limit, offset)
        )
        
    def delete_memory(self, memory_id: str) -> bool:
        result = self.execute_one(
            "SELECT pg_agent.delete_memory(%s::uuid) as deleted",
            (memory_id,)
        )
        return result['deleted'] if result else False
