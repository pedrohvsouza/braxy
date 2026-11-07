-- Puts the database back to a fixed state before a benchmark run: messages
-- accumulated by earlier runs are dropped and every group/lobby gets the
-- same 100-message history (members have 10 unread each).
BEGIN;
TRUNCATE messages, reactions RESTART IDENTITY;
DELETE FROM notifications WHERE kind IN ('mention', 'reply');
DELETE FROM xp_events WHERE kind = 'message';
INSERT INTO messages (conversation_id, author_id, body, client_id, created_at, updated_at)
SELECT c.id, m.user_id, 'mensagem de histórico ' || g, 'seed-' || c.id || '-' || g,
       now() - (101 - g) * interval '1 minute', now() - (101 - g) * interval '1 minute'
FROM conversations c
CROSS JOIN generate_series(1, 100) g
CROSS JOIN LATERAL (
  SELECT user_id FROM memberships WHERE conversation_id = c.id
  ORDER BY id OFFSET (g % greatest(1, (SELECT count(*) FROM memberships WHERE conversation_id = c.id))) LIMIT 1
) m
WHERE c.kind IN ('group', 'lobby');
UPDATE conversations c SET last_message_id = x.mid, last_message_at = x.at
FROM (SELECT conversation_id, max(id) mid, max(created_at) at FROM messages GROUP BY 1) x
WHERE x.conversation_id = c.id;
UPDATE conversations SET last_message_id = NULL, last_message_at = NULL WHERE kind = 'dm';
UPDATE memberships mb SET last_read_message_id = greatest(0, coalesce(c.last_message_id, 0) - 10)
FROM conversations c WHERE c.id = mb.conversation_id;
COMMIT;
VACUUM (ANALYZE) messages;
VACUUM (ANALYZE) memberships;
VACUUM (ANALYZE) conversations;
CHECKPOINT;
