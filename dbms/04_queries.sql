-- ============================================================================
--  TalkArena -- AP Capstone: every SQL query the app uses (checkpoint CP3)
--  Team T0122 | PostgreSQL 15 or newer
--  Runs on top of dbms/03_schema.sql.
--
--  Marking rules (CHECKPOINTS.md): every query is marked -- READ or -- WRITE
--  and has an id (R1 ... Rn for reads, W1 ... Wn for writes).
--  Literal sample values stand in for the parameters the FastAPI layer binds
--  (e.g. $1 with psycopg); they assume the sample data is seeded.
--  All writes run inside BEGIN ... ROLLBACK so the sample data does not change.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
--  READ queries
-- ----------------------------------------------------------------------------

-- R1 -- READ: Login by email (uses the UNIQUE index on users.email)
SELECT user_id, handle, password_hash, is_active
FROM users
WHERE email = 'diya@college.edu';

-- R2 -- READ: Profile page, user looked up by handle
SELECT user_id, handle, email, full_name, created_at, is_active
FROM users
WHERE handle = 'diya_rocks';

-- R3 -- READ: Dashboard: rooms the user has joined and not left
SELECT r.room_id, r.room_name, t.topic_name, t.category,
       dm.mode_name, rm.role, r.status, r.created_at
FROM room_members rm
JOIN rooms r            ON r.room_id  = rm.room_id
JOIN topics t           ON t.topic_id = r.topic_id
JOIN discussion_modes dm ON dm.mode_id = r.mode_id
WHERE rm.user_id = 2
  AND rm.left_at IS NULL
  AND r.status = 'ACTIVE'
ORDER BY r.created_at DESC;

-- R4 -- READ: Join by invite link: room details from the invite code
SELECT r.room_id, r.room_name, r.status, r.ai_enabled,
       t.topic_name, dm.mode_name, u.handle AS host_handle
FROM rooms r
JOIN topics t            ON t.topic_id = r.topic_id
JOIN discussion_modes dm ON dm.mode_id = r.mode_id
JOIN users u             ON u.user_id  = r.host_user_id
WHERE r.invite_code = 'TALK7XK2';

-- R5 -- READ: Room controls: current members with their names
SELECT u.handle, u.full_name, rm.role, rm.joined_at
FROM room_members rm
JOIN users u ON u.user_id = rm.user_id
WHERE rm.room_id = 1
  AND rm.left_at IS NULL
ORDER BY rm.role, rm.joined_at;

-- R6 -- READ: Membership check before a chat socket is opened
SELECT 1
FROM room_members
WHERE room_id = 1
  AND user_id = 2
  AND left_at IS NULL;

-- R7 -- READ: Chat history, last 50 messages of a room (author or persona name)
SELECT m.message_id, m.body, m.sent_at,
       u.handle AS author_handle, p.persona_name
FROM messages m
LEFT JOIN users u       ON u.user_id   = m.author_user_id
LEFT JOIN ai_personas p ON p.persona_id = m.persona_id
WHERE m.room_id = 1
ORDER BY m.sent_at DESC, m.message_id DESC
LIMIT 50;

-- R8 -- READ: The AI persona that is active in a room (AI Mode)
SELECT p.persona_id, p.persona_name, p.model_name, p.system_prompt
FROM room_ai_persona rap
JOIN ai_personas p ON p.persona_id = rap.persona_id
WHERE rap.room_id = 1;

-- R9 -- READ: Personas available for a discussion mode (AI toggle screen)
SELECT p.persona_id, p.persona_name, p.model_name
FROM ai_personas p
JOIN discussion_modes dm ON dm.mode_id = p.mode_id
WHERE dm.mode_name = 'Study Mode'
ORDER BY p.persona_name;

-- R10 -- READ: Video calls of a room with the number of people who joined
SELECT vs.session_id, vs.started_at, vs.ended_at,
       count(vp.user_id) AS participants
FROM video_sessions vs
LEFT JOIN video_participants vp ON vp.session_id = vs.session_id
WHERE vs.room_id = 1
GROUP BY vs.session_id, vs.started_at, vs.ended_at
ORDER BY vs.started_at DESC;

-- R11 -- READ: Who is on a live call right now
SELECT u.handle, vp.joined_at
FROM video_participants vp
JOIN users u ON u.user_id = vp.user_id
WHERE vp.session_id = 5
  AND vp.left_at IS NULL;

-- R12 -- READ: Popular topics in the last 7 days (analytics, by rooms created)
SELECT t.topic_name, t.category, count(r.room_id) AS rooms_created
FROM topics t
JOIN rooms r ON r.topic_id = t.topic_id
WHERE r.created_at >= now() - interval '7 days'
GROUP BY t.topic_name, t.category
ORDER BY rooms_created DESC, t.topic_name
LIMIT 10;

-- R13 -- READ: Most active rooms in the last 24 hours (analytics, by messages)
SELECT r.room_id, r.room_name, count(m.message_id) AS messages
FROM rooms r
JOIN messages m ON m.room_id = r.room_id
WHERE m.sent_at >= now() - interval '24 hours'
GROUP BY r.room_id, r.room_name
ORDER BY messages DESC
LIMIT 10;

-- R14 -- READ: User engagement: messages sent and rooms used, human authors only
SELECT u.handle,
       count(m.message_id)        AS messages,
       count(DISTINCT m.room_id)  AS rooms_active
FROM users u
JOIN messages m ON m.author_user_id = u.user_id
GROUP BY u.user_id, u.handle
ORDER BY messages DESC
LIMIT 20;

-- R15 -- READ: Fact checks attached to one message
SELECT fc.claim_text, fc.verdict, fc.source_url, fc.checked_at,
       p.persona_name
FROM fact_checks fc
LEFT JOIN ai_personas p ON p.persona_id = fc.persona_id
WHERE fc.message_id = 100
ORDER BY fc.checked_at;

-- R16 -- READ: Fact-check summary for every message of a room
SELECT m.message_id, fc.verdict, count(*) AS checks
FROM fact_checks fc
JOIN messages m ON m.message_id = fc.message_id
WHERE m.room_id = 1
GROUP BY m.message_id, fc.verdict
ORDER BY m.message_id;

-- R17 -- READ: Discussion modes (dropdown when creating a room)
SELECT mode_id, mode_name, description
FROM discussion_modes
ORDER BY mode_name;

-- R18 -- READ: Topics in one category (topic picker)
SELECT topic_id, topic_name
FROM topics
WHERE category = 'Movies'
ORDER BY topic_name;

-- ----------------------------------------------------------------------------
--  WRITE queries
-- ----------------------------------------------------------------------------

-- W1 -- WRITE: Sign up a new user
INSERT INTO users (handle, email, full_name, password_hash)
VALUES ('kabir_k', 'kabir@college.edu', 'Kabir Khanna', '$2b$12$samplehashonly');

-- W2 -- WRITE: Create a room: the room row and the host's membership together
WITH new_room AS (
    INSERT INTO rooms (room_name, invite_code, host_user_id, topic_id, mode_id)
    VALUES ('DSA Doubts', 'DSA8K4P1Q2', 2, 3, 2)
    RETURNING room_id, host_user_id
)
INSERT INTO room_members (room_id, user_id, role)
SELECT room_id, host_user_id, 'HOST'
FROM new_room;

-- W3 -- WRITE: Join a room through an invite link (or rejoin after leaving)
INSERT INTO room_members (room_id, user_id, role)
VALUES (1, 3, 'MEMBER')
ON CONFLICT (room_id, user_id)
DO UPDATE SET left_at = NULL, joined_at = now();

-- W4 -- WRITE: A human posts a chat message
INSERT INTO messages (room_id, author_user_id, body)
VALUES (1, 3, 'Loki is alive, change my mind');

-- W5 -- WRITE: The AI persona posts a message (exclusive arc: persona set, author NULL)
INSERT INTO messages (room_id, persona_id, body)
VALUES (1, 1, 'What if the timeline itself is the twist?');

-- W6 -- WRITE: Turn AI Mode on (the trigger checks the persona matches the room's mode)
INSERT INTO room_ai_persona (room_id, persona_id)
VALUES (1, 1);

UPDATE rooms
SET ai_enabled = TRUE
WHERE room_id = 1;

-- W7 -- WRITE: Start a video call in a room
INSERT INTO video_sessions (room_id)
VALUES (1)
RETURNING session_id;

-- W8 -- WRITE: Join a video call (or rejoin)
INSERT INTO video_participants (session_id, user_id)
VALUES (5, 3)
ON CONFLICT (session_id, user_id)
DO UPDATE SET left_at = NULL, joined_at = now();

-- W9 -- WRITE: Leave a room (row kept, left_at set, so history survives)
UPDATE room_members
SET left_at = now()
WHERE room_id = 1
  AND user_id = 3
  AND left_at IS NULL;

-- W10 -- WRITE: Save an AI fact check for a message
INSERT INTO fact_checks (message_id, persona_id, claim_text, verdict, source_url)
VALUES (100, 1, 'Loki survives the events of the film', 'UNVERIFIED',
        'https://example.com/source');

-- W11 -- WRITE: End a room (status and ended_at change together, as the CHECK requires)
UPDATE rooms
SET status = 'ENDED', ended_at = now()
WHERE room_id = 1
  AND status = 'ACTIVE';

-- W12 -- WRITE: Turn AI Mode off
DELETE FROM room_ai_persona
WHERE room_id = 1;

UPDATE rooms
SET ai_enabled = FALSE
WHERE room_id = 1;

ROLLBACK;
