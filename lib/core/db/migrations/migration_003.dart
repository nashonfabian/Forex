// Schema version 3: local historical datasets and replay progress.
import '../migration.dart';

const migration003 = Migration(3, 'historical replay storage', <String>[
  '''
  CREATE TABLE historical_datasets (
    id TEXT PRIMARY KEY NOT NULL,
    instrument TEXT NOT NULL,
    timeframe TEXT NOT NULL,
    source_name TEXT NOT NULL,
    timezone_mode TEXT NOT NULL,
    first_timestamp_ms INTEGER NOT NULL,
    last_timestamp_ms INTEGER NOT NULL,
    candle_count INTEGER NOT NULL,
    gap_count INTEGER NOT NULL DEFAULT 0,
    sha256 TEXT NOT NULL,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE TABLE historical_candles (
    dataset_id TEXT NOT NULL REFERENCES historical_datasets(id) ON DELETE CASCADE,
    timestamp_ms INTEGER NOT NULL,
    open REAL NOT NULL,
    high REAL NOT NULL,
    low REAL NOT NULL,
    close REAL NOT NULL,
    tick_volume REAL,
    real_volume REAL,
    spread REAL,
    PRIMARY KEY (dataset_id, timestamp_ms)
  )
  ''',
  '''
  CREATE INDEX idx_historical_candles_time
  ON historical_candles(dataset_id, timestamp_ms)
  ''',
  '''
  CREATE TABLE replay_sessions (
    id TEXT PRIMARY KEY NOT NULL,
    dataset_id TEXT NOT NULL REFERENCES historical_datasets(id) ON DELETE CASCADE,
    start_timestamp_ms INTEGER NOT NULL,
    cursor_timestamp_ms INTEGER NOT NULL,
    speed_candles_per_second REAL NOT NULL DEFAULT 1,
    research_case_id TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  ''',
  '''
  CREATE INDEX idx_replay_sessions_dataset
  ON replay_sessions(dataset_id, updated_at)
  ''',
  '''
  CREATE TABLE replay_annotations (
    id TEXT PRIMARY KEY NOT NULL,
    dataset_id TEXT NOT NULL REFERENCES historical_datasets(id) ON DELETE CASCADE,
    replay_session_id TEXT REFERENCES replay_sessions(id) ON DELETE CASCADE,
    timestamp_ms INTEGER NOT NULL,
    kind TEXT NOT NULL,
    points_json TEXT NOT NULL,
    label TEXT,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  ALTER TABLE research_cases
  ADD COLUMN is_historical INTEGER NOT NULL DEFAULT 0
  ''',
  '''
  ALTER TABLE research_cases
  ADD COLUMN historical_dataset_id TEXT
  ''',
  '''
  ALTER TABLE research_cases
  ADD COLUMN historical_timestamp_ms INTEGER
  ''',
  '''
  ALTER TABLE research_cases
  ADD COLUMN historical_session_id TEXT
  ''',
]);
