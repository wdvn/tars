-- Semantic recall (Analyst Agent · ORIENT)
-- Bind ?1 = query embedding BLOB (FLOAT32×384)
-- Bind ?2 = limit (INTEGER)

SELECT
  e.id,
  e.mission_id,
  e.agent,
  e.content,
  e.meta,
  e.created_at,
  v.distance
FROM episodic_memory AS e
JOIN vector_quantize_scan('episodic_memory', 'embedding', ?1, ?2) AS v
  ON e.id = v.rowid
WHERE e.embedding IS NOT NULL
ORDER BY v.distance ASC;
