// Schema version 1 (initial schema). SQL verified against SQLite 3.45 before release.
// Rules for this file: never edit after release. Add migration_002.dart instead.
//
// Notes:
//  * Foreign keys are DEFERRABLE INITIALLY DEFERRED so that sync can re-write a parent row
//    (INSERT OR REPLACE) and children can arrive in any order inside one transaction.
//  * Only SQLite features available on old Android (3.22) are used: no UPSERT, no RETURNING.
//  * Triggers protect evidence: a locked hypothesis can never be edited or unlocked, and an
//    outcome can only be recorded after the lock.
import '../migration.dart';

const migration001TableNames = <String>[
  'study_plans',
  'lessons',
  'daily_tasks',
  'notes',
  'study_sessions',
  'research_cases',
  'trades',
  'images',
  'case_entries',
  'reviews',
  'tags',
  'entity_tags',
  'links',
  'app_meta',
  'sync_queue',
  'sync_state',
  'sync_conflicts',
  'image_files',
];

const migration001TriggerNames = <String>[
  'trg_cases_locked_fields_immutable',
  'trg_cases_lock_needs_hypothesis',
  'trg_cases_outcome_needs_lock_upd',
  'trg_cases_outcome_needs_lock_ins',
];

const migration001 = Migration(1, 'initial schema', <String>[
r'''
CREATE TABLE study_plans (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  title TEXT NOT NULL,
  description TEXT,
  start_date TEXT,
  length_days INTEGER NOT NULL DEFAULT 90,
  status TEXT NOT NULL DEFAULT 'active'
)
''',
r'''
CREATE TABLE lessons (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  plan_id TEXT NOT NULL REFERENCES study_plans(id) DEFERRABLE INITIALLY DEFERRED,
  phase_no INTEGER,
  phase_title TEXT,
  week_no INTEGER,
  day_no INTEGER,
  order_index INTEGER NOT NULL DEFAULT 0,
  title TEXT NOT NULL,
  objective TEXT,
  assignment TEXT,
  is_milestone INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'not_started',
  scheduled_date TEXT,
  completed_at TEXT
)
''',
r'''
CREATE TABLE daily_tasks (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  plan_date TEXT NOT NULL,
  title TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'custom',
  lesson_id TEXT REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  status TEXT NOT NULL DEFAULT 'todo',
  order_index INTEGER NOT NULL DEFAULT 0
)
''',
r'''
CREATE TABLE notes (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  kind TEXT NOT NULL DEFAULT 'note',
  title TEXT,
  body_md TEXT NOT NULL DEFAULT '',
  lesson_id TEXT REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  book TEXT,
  chapter TEXT,
  page TEXT,
  is_bookmarked INTEGER NOT NULL DEFAULT 0,
  question_status TEXT
)
''',
r'''
CREATE TABLE study_sessions (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  lesson_id TEXT REFERENCES lessons(id) DEFERRABLE INITIALLY DEFERRED,
  started_at TEXT NOT NULL,
  minutes INTEGER NOT NULL DEFAULT 0,
  focus TEXT
)
''',
r'''
CREATE TABLE research_cases (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  title TEXT NOT NULL,
  instrument TEXT,
  timeframe TEXT,
  observed_at TEXT,
  market_condition TEXT,
  reference_level TEXT,
  exploration_direction TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  hypothesis TEXT,
  evidence_for TEXT,
  evidence_against TEXT,
  acceptance_rejection TEXT,
  alternatives TEXT,
  invalidation TEXT,
  confidence INTEGER,
  hypothesis_locked_at TEXT,
  outcome TEXT,
  outcome_at TEXT,
  outcome_summary TEXT,
  final_lessons TEXT
)
''',
r'''
CREATE TABLE trades (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  case_id TEXT REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  account_type TEXT NOT NULL DEFAULT 'demo',
  instrument TEXT NOT NULL,
  direction TEXT NOT NULL,
  opened_at TEXT,
  closed_at TEXT,
  entry_price REAL,
  exit_price REAL,
  stop_price REAL,
  target_price REAL,
  size REAL,
  initial_risk_minor INTEGER,
  gross_pnl_minor INTEGER,
  costs_minor INTEGER NOT NULL DEFAULT 0,
  setup_rationale TEXT,
  rule_adherence TEXT,
  rule_notes TEXT,
  process_notes TEXT,
  review_text TEXT,
  status TEXT NOT NULL DEFAULT 'open'
)
''',
r'''
CREATE TABLE images (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  case_id TEXT REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  trade_id TEXT REFERENCES trades(id) DEFERRABLE INITIALLY DEFERRED,
  phase TEXT,
  caption TEXT,
  observation TEXT,
  instrument TEXT,
  timeframe TEXT,
  captured_at TEXT,
  mime TEXT,
  width INTEGER,
  height INTEGER,
  bytes INTEGER,
  sha256 TEXT,
  storage_path TEXT,
  uploaded_at TEXT,
  sort_order INTEGER NOT NULL DEFAULT 0
)
''',
r'''
CREATE TABLE case_entries (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  case_id TEXT NOT NULL REFERENCES research_cases(id) DEFERRABLE INITIALLY DEFERRED,
  phase TEXT NOT NULL DEFAULT 'during',
  kind TEXT NOT NULL DEFAULT 'observation',
  body TEXT NOT NULL,
  image_id TEXT REFERENCES images(id) DEFERRABLE INITIALLY DEFERRED
)
''',
r'''
CREATE TABLE reviews (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  kind TEXT NOT NULL,
  period_start TEXT NOT NULL,
  period_end TEXT NOT NULL,
  answers_json TEXT NOT NULL DEFAULT '{}',
  next_actions TEXT,
  stats_snapshot_json TEXT
)
''',
r'''
CREATE TABLE tags (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  name TEXT NOT NULL
)
''',
r'''
CREATE TABLE entity_tags (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  tag_id TEXT NOT NULL REFERENCES tags(id) DEFERRABLE INITIALLY DEFERRED,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL
)
''',
r'''
CREATE TABLE links (
  id TEXT PRIMARY KEY NOT NULL,
  owner_id TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  deleted_at TEXT,
  server_updated_at TEXT,
  from_type TEXT NOT NULL,
  from_id TEXT NOT NULL,
  to_type TEXT NOT NULL,
  to_id TEXT NOT NULL
)
''',
r'''
CREATE TABLE app_meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
)
''',
r'''
CREATE TABLE sync_queue (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  op TEXT NOT NULL DEFAULT 'upsert',
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TEXT,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE (entity_type, entity_id, op)
)
''',
r'''
CREATE TABLE sync_state (
  table_name TEXT PRIMARY KEY NOT NULL,
  cursor_server_updated_at TEXT,
  cursor_id TEXT,
  last_pull_at TEXT,
  last_push_at TEXT
)
''',
r'''
CREATE TABLE sync_conflicts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  local_json TEXT,
  remote_json TEXT,
  detected_at TEXT NOT NULL,
  resolved INTEGER NOT NULL DEFAULT 0
)
''',
r'''
CREATE TABLE image_files (
  image_id TEXT PRIMARY KEY NOT NULL REFERENCES images(id) DEFERRABLE INITIALLY DEFERRED,
  local_path TEXT NOT NULL,
  thumb_path TEXT,
  upload_state TEXT NOT NULL DEFAULT 'local',
  created_at TEXT NOT NULL
)
''',
r'''
CREATE INDEX idx_notes_created ON notes(created_at)
''',
r'''
CREATE INDEX idx_notes_lesson ON notes(lesson_id)
''',
r'''
CREATE INDEX idx_lessons_plan_order ON lessons(plan_id, order_index)
''',
r'''
CREATE INDEX idx_daily_tasks_date ON daily_tasks(plan_date)
''',
r'''
CREATE INDEX idx_cases_instrument_tf ON research_cases(instrument, timeframe)
''',
r'''
CREATE INDEX idx_cases_observed ON research_cases(observed_at)
''',
r'''
CREATE INDEX idx_images_case ON images(case_id)
''',
r'''
CREATE INDEX idx_images_trade ON images(trade_id)
''',
r'''
CREATE INDEX idx_entries_case ON case_entries(case_id, created_at)
''',
r'''
CREATE INDEX idx_trades_account ON trades(account_type)
''',
r'''
CREATE INDEX idx_trades_opened ON trades(opened_at)
''',
r'''
CREATE INDEX idx_reviews_kind_period ON reviews(kind, period_start)
''',
r'''
CREATE INDEX idx_tags_name ON tags(name)
''',
r'''
CREATE INDEX idx_entity_tags_entity ON entity_tags(entity_type, entity_id)
''',
r'''
CREATE INDEX idx_links_from ON links(from_type, from_id)
''',
r'''
CREATE INDEX idx_links_to ON links(to_type, to_id)
''',
r'''
CREATE INDEX idx_sync_queue_due ON sync_queue(status, next_attempt_at)
''',
r'''
CREATE TRIGGER trg_cases_locked_fields_immutable
BEFORE UPDATE ON research_cases
WHEN OLD.hypothesis_locked_at IS NOT NULL AND (
     NEW.hypothesis IS NOT OLD.hypothesis
  OR NEW.evidence_for IS NOT OLD.evidence_for
  OR NEW.evidence_against IS NOT OLD.evidence_against
  OR NEW.acceptance_rejection IS NOT OLD.acceptance_rejection
  OR NEW.alternatives IS NOT OLD.alternatives
  OR NEW.invalidation IS NOT OLD.invalidation
  OR NEW.confidence IS NOT OLD.confidence
  OR NEW.hypothesis_locked_at IS NOT OLD.hypothesis_locked_at)
BEGIN
  SELECT RAISE(ABORT, 'hypothesis_locked');
END
''',
r'''
CREATE TRIGGER trg_cases_lock_needs_hypothesis
BEFORE UPDATE OF hypothesis_locked_at ON research_cases
WHEN OLD.hypothesis_locked_at IS NULL AND NEW.hypothesis_locked_at IS NOT NULL
 AND (NEW.hypothesis IS NULL OR length(trim(NEW.hypothesis)) = 0)
BEGIN
  SELECT RAISE(ABORT, 'hypothesis_required');
END
''',
r'''
CREATE TRIGGER trg_cases_outcome_needs_lock_upd
BEFORE UPDATE ON research_cases
WHEN NEW.outcome IS NOT NULL AND NEW.hypothesis_locked_at IS NULL
BEGIN
  SELECT RAISE(ABORT, 'outcome_requires_locked_hypothesis');
END
''',
r'''
CREATE TRIGGER trg_cases_outcome_needs_lock_ins
BEFORE INSERT ON research_cases
WHEN NEW.outcome IS NOT NULL AND NEW.hypothesis_locked_at IS NULL
BEGIN
  SELECT RAISE(ABORT, 'outcome_requires_locked_hypothesis');
END
''',
]);
