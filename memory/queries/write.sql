-- Mission
-- ?1 id, ?2 goal, ?3 status, ?4 priority, ?5 constraints JSON, ?6 parent_id, ?7 created_at, ?8 updated_at
INSERT INTO missions (id, goal, status, priority, constraints, parent_id, created_at, updated_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
ON CONFLICT(id) DO UPDATE SET
  goal = excluded.goal,
  status = excluded.status,
  priority = excluded.priority,
  constraints = excluded.constraints,
  updated_at = excluded.updated_at;

-- Artifact
-- ?1 mission_id, ?2 phase, ?3 agent, ?4 kind, ?5 payload JSON, ?6 created_at
INSERT INTO artifacts (mission_id, phase, agent, kind, payload, created_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);

-- Episodic memory
-- ?1 mission_id, ?2 agent, ?3 content, ?4 embedding BLOB, ?5 meta JSON, ?6 created_at
INSERT INTO episodic_memory (mission_id, agent, content, embedding, meta, created_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);

-- Audit (append-only)
-- ?1 mission_id, ?2 agent, ?3 event, ?4 detail JSON, ?5 created_at
INSERT INTO audit_log (mission_id, agent, event, detail, created_at)
VALUES (?1, ?2, ?3, ?4, ?5);

-- Agent bus event
-- ?1 mission_id, ?2 from_agent, ?3 to_agent, ?4 event_type, ?5 payload JSON, ?6 created_at
INSERT INTO agent_events (mission_id, from_agent, to_agent, event_type, payload, created_at)
VALUES (?1, ?2, ?3, ?4, ?5, ?6);
