// Schema version 6: immutable strategy versions and auditable test execution.
import '../migration.dart';

const migration006 =
    Migration(6, 'strategy execution and test history', <String>[
  '''
  CREATE TABLE visual_strategy_versions (
    id TEXT PRIMARY KEY NOT NULL,
    strategy_id TEXT NOT NULL REFERENCES visual_strategies(id),
    version_number INTEGER NOT NULL,
    name TEXT NOT NULL,
    definition_json TEXT,
    legacy_snapshot_json TEXT,
    legacy_entry_conditions TEXT,
    legacy_exit_conditions TEXT,
    legacy_stop_loss_rules TEXT,
    legacy_take_profit_rules TEXT,
    legacy_stay_out_conditions TEXT,
    legacy_sessions_json TEXT,
    legacy_timeframes_json TEXT,
    created_at TEXT NOT NULL
  )
  ''',
  '''
  INSERT INTO visual_strategy_versions (
    id, strategy_id, version_number, name,
    legacy_entry_conditions, legacy_exit_conditions,
    legacy_stop_loss_rules, legacy_take_profit_rules,
    legacy_stay_out_conditions, legacy_sessions_json,
    legacy_timeframes_json, created_at
  )
  SELECT
    'legacy-current-' || id, id, 1, name,
    entry_conditions, exit_conditions, stop_loss_rules,
    take_profit_rules, stay_out_conditions, sessions_json,
    timeframes_json, created_at
  FROM visual_strategies
  ''',
  '''
  INSERT INTO visual_strategy_versions (
    id, strategy_id, version_number, name, legacy_snapshot_json, created_at
  )
  SELECT
    'legacy-test-' || id, strategy_id, 0, strategy_name_snapshot,
    strategy_snapshot_json, created_at
  FROM visual_tests
  ''',
  'CREATE UNIQUE INDEX idx_visual_strategy_version_number ON visual_strategy_versions(strategy_id, version_number) WHERE version_number > 0',
  'ALTER TABLE visual_tests ADD COLUMN strategy_version_id TEXT REFERENCES visual_strategy_versions(id)',
  "UPDATE visual_tests SET strategy_version_id = 'legacy-test-' || id",
  "ALTER TABLE visual_tests ADD COLUMN mode TEXT NOT NULL DEFAULT 'manual'",
  'ALTER TABLE visual_tests ADD COLUMN scenario_id TEXT',
  'ALTER TABLE visual_tests ADD COLUMN instrument TEXT',
  'ALTER TABLE visual_tests ADD COLUMN timeframe TEXT',
  'ALTER TABLE visual_tests ADD COLUMN session TEXT',
  'ALTER TABLE visual_tests ADD COLUMN market_context TEXT',
  'ALTER TABLE visual_tests ADD COLUMN direction TEXT',
  'ALTER TABLE visual_tests ADD COLUMN entry_price REAL',
  'ALTER TABLE visual_tests ADD COLUMN stop_loss_price REAL',
  'ALTER TABLE visual_tests ADD COLUMN take_profit_price REAL',
  'ALTER TABLE visual_tests ADD COLUMN exit_price REAL',
  'ALTER TABLE visual_tests ADD COLUMN risk_config_json TEXT NOT NULL DEFAULT \'{}\'',
  'ALTER TABLE visual_tests ADD COLUMN execution_config_json TEXT NOT NULL DEFAULT \'{}\'',
  'ALTER TABLE visual_tests ADD COLUMN decision_locked_at TEXT',
  'ALTER TABLE visual_tests ADD COLUMN rule_adherence TEXT',
  'ALTER TABLE visual_tests ADD COLUMN dataset_id TEXT REFERENCES historical_datasets(id)',
  'ALTER TABLE visual_tests ADD COLUMN decision_timestamp_ms INTEGER',
  'ALTER TABLE visual_tests ADD COLUMN experiment_id TEXT',
  'ALTER TABLE visual_tests ADD COLUMN experiment_variant TEXT',
  'ALTER TABLE visual_tests ADD COLUMN entry_decision TEXT',
  'ALTER TABLE visual_tests ADD COLUMN result_cash REAL',
  'ALTER TABLE visual_tests ADD COLUMN result_currency TEXT',
  "ALTER TABLE visual_test_images ADD COLUMN role TEXT NOT NULL DEFAULT 'legacy'",
  'ALTER TABLE visual_test_images ADD COLUMN cutoff_x REAL',
  'ALTER TABLE visual_test_images ADD COLUMN visible_through_timestamp_ms INTEGER',
  'ALTER TABLE visual_test_images ADD COLUMN decision_at_ms INTEGER',
  '''
  CREATE TABLE visual_test_rule_events (
    id TEXT PRIMARY KEY NOT NULL,
    test_id TEXT NOT NULL REFERENCES visual_tests(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL,
    rule_id TEXT NOT NULL,
    previous_state TEXT,
    state TEXT NOT NULL,
    observed_value TEXT,
    explanation TEXT,
    decision TEXT,
    event_timestamp_ms INTEGER,
    created_at TEXT NOT NULL,
    UNIQUE(test_id, sequence)
  )
  ''',
  '''
  CREATE INDEX idx_visual_test_rule_events_history
  ON visual_test_rule_events(test_id, rule_id, created_at, id)
  ''',
  '''
  CREATE TABLE visual_test_events (
    id TEXT PRIMARY KEY NOT NULL,
    test_id TEXT NOT NULL REFERENCES visual_tests(id) ON DELETE CASCADE,
    sequence INTEGER NOT NULL,
    kind TEXT NOT NULL,
    decision TEXT,
    event_timestamp_ms INTEGER,
    price REAL,
    quantity REAL,
    details_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    UNIQUE(test_id, sequence)
  )
  ''',
  '''
  CREATE INDEX idx_visual_test_events_history
  ON visual_test_events(test_id, sequence)
  ''',
  '''
  CREATE TABLE visual_experiments (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    baseline_version_id TEXT NOT NULL REFERENCES visual_strategy_versions(id),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE TABLE visual_experiment_variants (
    id TEXT PRIMARY KEY NOT NULL,
    experiment_id TEXT NOT NULL REFERENCES visual_experiments(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    strategy_version_id TEXT NOT NULL REFERENCES visual_strategy_versions(id),
    parameter_overrides_json TEXT NOT NULL DEFAULT '{}',
    created_at TEXT NOT NULL,
    UNIQUE(experiment_id, name)
  )
  ''',
  'ALTER TABLE visual_tests ADD COLUMN experiment_variant_id TEXT REFERENCES visual_experiment_variants(id)',
  'CREATE INDEX idx_visual_tests_version ON visual_tests(strategy_version_id, tested_at)',
  'CREATE INDEX idx_visual_tests_segment ON visual_tests(instrument, timeframe, session, tested_at)',
]);
