-- Keyword fallback recall when sqlite-vector is unavailable
-- Bind ?1 = search term, ?2 = limit

SELECT id, content, meta, created_at
FROM episodic_memory
WHERE content LIKE '%' || ?1 || '%'
ORDER BY created_at DESC
LIMIT ?2;
