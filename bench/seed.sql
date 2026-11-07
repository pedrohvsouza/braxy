-- Benchmark users: bench_00001..bench_25000 (password123, bcrypt cost 4 so
-- logging 20k users in is not the bottleneck), all in the lobby, plus 400
-- groups of 50 members ("rooms" scenario). Idempotent.
BEGIN;
INSERT INTO users (name, username, email, password_digest, role, xp, level, created_at, updated_at)
SELECT 'Bench ' || n, 'bench_' || lpad(n::text, 5, '0'), 'bench_' || lpad(n::text, 5, '0') || '@bench.local',
       '$2a$04$HbpjnwfbhzTFdLSw2RAcMOV3JvzNzkl30W/8sroQ19uXpYwhmctla', 'member', 0, 1, now(), now()
FROM generate_series(1, 25000) AS n
ON CONFLICT (username) DO NOTHING;

INSERT INTO conversations (kind, name, created_at, updated_at)
SELECT 'lobby', 'Grupo', now(), now()
WHERE NOT EXISTS (SELECT 1 FROM conversations WHERE kind = 'lobby');

INSERT INTO memberships (conversation_id, user_id, role, last_read_message_id, created_at, updated_at)
SELECT (SELECT id FROM conversations WHERE kind = 'lobby' ORDER BY id LIMIT 1), u.id, 'member', 0, now(), now()
FROM users u WHERE u.username LIKE 'bench\_%'
ON CONFLICT (conversation_id, user_id) DO NOTHING;

INSERT INTO conversations (kind, name, owner_id, created_at, updated_at)
SELECT 'group', 'bench-room-' || lpad(r::text, 3, '0'),
       (SELECT id FROM users WHERE username = 'bench_' || lpad(((r - 1) * 50 + 1)::text, 5, '0')), now(), now()
FROM generate_series(1, 500) AS r
WHERE NOT EXISTS (SELECT 1 FROM conversations WHERE name = 'bench-room-' || lpad(r::text, 3, '0'));

INSERT INTO memberships (conversation_id, user_id, role, last_read_message_id, created_at, updated_at)
SELECT c.id, u.id, CASE WHEN u.id = c.owner_id THEN 'owner' ELSE 'member' END, 0, now(), now()
FROM users u
JOIN conversations c ON c.name = 'bench-room-' || lpad((((substring(u.username from 7)::int) - 1) / 50 + 1)::text, 3, '0')
WHERE u.username LIKE 'bench\_%'
ON CONFLICT (conversation_id, user_id) DO NOTHING;
COMMIT;
ANALYZE;
SELECT (SELECT count(*) FROM users WHERE username LIKE 'bench\_%') AS bench_users,
       (SELECT count(*) FROM conversations WHERE name LIKE 'bench-room-%') AS rooms,
       (SELECT count(*) FROM memberships) AS memberships;
