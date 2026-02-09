-- OpenClaw-PG Smoke Test
-- Run: psql -d postgres -f tests/smoke_test.sql

\echo '=== OpenClaw-PG Smoke Test ==='

-- Test should_capture
\echo 'Testing should_capture...'
SELECT 'should_capture preference' AS test, 
       openclaw.should_capture('I prefer dark mode') = true AS passed;
SELECT 'should_capture short' AS test, 
       openclaw.should_capture('ok') = false AS passed;
SELECT 'should_capture email' AS test, 
       openclaw.should_capture('my email is test@example.com') = true AS passed;

-- Test detect_category
\echo 'Testing detect_category...'
SELECT 'detect preference' AS test, 
       openclaw.detect_category('I prefer dark mode') = 'preference' AS passed;
SELECT 'detect decision' AS test, 
       openclaw.detect_category('I decided to use PostgreSQL') = 'decision' AS passed;
SELECT 'detect entity' AS test, 
       openclaw.detect_category('my email is test@example.com') = 'entity' AS passed;

-- Test store
\echo 'Testing store...'
SELECT 'store memory' AS test, 
       openclaw.store('Test user preference: likes coffee', NULL) IS NOT NULL AS passed;
SELECT 'store memory 2' AS test, 
       openclaw.store('Another test: prefers tea', NULL) IS NOT NULL AS passed;

-- Test search (FTS only)
\echo 'Testing search...'
SELECT 'search FTS' AS test, 
       (SELECT count(*) > 0 FROM openclaw.search('coffee', NULL, 10)) AS passed;

-- Test session
\echo 'Testing session...'
SELECT openclaw.session_set('test:session:1', '{"topic": "testing"}'::jsonb);
SELECT 'session set/get' AS test,
       openclaw.session_get('test:session:1') = '{"topic": "testing"}'::jsonb AS passed;

SELECT openclaw.session_append('test:session:1', '{"user": "alice"}'::jsonb);
SELECT 'session append' AS test,
       (openclaw.session_get('test:session:1'))->>'user' = 'alice' AS passed;

-- Test chunk_text
\echo 'Testing chunk_text...'
SELECT 'chunking' AS test,
       (SELECT count(*) FROM openclaw.chunk_text(
           E'Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8',
           100, 20
       )) > 0 AS passed;

-- Test stats
\echo 'Testing stats...'
SELECT * FROM openclaw.stats();

-- Cleanup
\echo 'Cleaning up...'
SELECT openclaw.session_delete('test:session:1');

\echo '=== All Tests Complete ==='
