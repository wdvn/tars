-- sqlite-vector setup (run AFTER loading the vector extension)
-- https://github.com/sqliteai/sqlite-vector
--
--   SELECT load_extension('./vector');
--   .read memory/schema_vector.sql

SELECT vector_init(
  'episodic_memory',
  'embedding',
  'type=FLOAT32,dimension=384,distance=COSINE'
);

-- Recommended for recall-heavy workloads (see sqlite-vector QUANTIZATION.md)
-- Run after inserting embeddings:
--   SELECT vector_quantize('episodic_memory', 'embedding', 'qtype=TURBO,qbits=4');
--   SELECT vector_quantize_preload('episodic_memory', 'embedding');

INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('vector_initialized', '1');
