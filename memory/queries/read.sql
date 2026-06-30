-- Latest mission artifact by kind
-- ?1 mission_id, ?2 kind
SELECT id, phase, agent, payload, created_at
FROM artifacts
WHERE mission_id = ?1 AND kind = ?2
ORDER BY created_at DESC
LIMIT 1;

-- Mission by id
-- ?1 id
SELECT id, goal, status, priority, constraints, parent_id, created_at, updated_at
FROM missions
WHERE id = ?1;

-- Active mission (most recently updated non-terminal)
SELECT id, goal, status, priority, constraints, parent_id, created_at, updated_at
FROM missions
WHERE status NOT IN ('done', 'blocked')
ORDER BY updated_at DESC
LIMIT 1;

-- Agent event replay for mission
-- ?1 mission_id
SELECT id, from_agent, to_agent, event_type, payload, created_at
FROM agent_events
WHERE mission_id = ?1
ORDER BY created_at ASC;
