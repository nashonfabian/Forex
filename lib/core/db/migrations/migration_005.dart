// Schema version 5: local visual strategy tests and screenshot annotations.
import '../migration.dart';

const migration005 = Migration(5, 'visual backtesting', <String>[
  '''
  CREATE TABLE visual_strategies (
    id TEXT PRIMARY KEY NOT NULL,
    name TEXT NOT NULL,
    entry_conditions TEXT NOT NULL,
    exit_conditions TEXT NOT NULL,
    stop_loss_rules TEXT NOT NULL,
    take_profit_rules TEXT NOT NULL,
    stay_out_conditions TEXT NOT NULL,
    sessions_json TEXT NOT NULL,
    timeframes_json TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE TABLE visual_tests (
    id TEXT PRIMARY KEY NOT NULL,
    strategy_id TEXT NOT NULL REFERENCES visual_strategies(id),
    strategy_name_snapshot TEXT NOT NULL,
    strategy_snapshot_json TEXT NOT NULL,
    tested_at TEXT NOT NULL,
    outcome TEXT NOT NULL DEFAULT 'pending',
    result_r REAL,
    notes TEXT,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    deleted_at TEXT
  )
  ''',
  '''
  CREATE TABLE visual_test_images (
    id TEXT PRIMARY KEY NOT NULL,
    test_id TEXT NOT NULL REFERENCES visual_tests(id) ON DELETE CASCADE,
    image_id TEXT NOT NULL REFERENCES images(id),
    sort_order INTEGER NOT NULL DEFAULT 0,
    UNIQUE (test_id, image_id)
  )
  ''',
  '''
  CREATE TABLE visual_annotations (
    id TEXT PRIMARY KEY NOT NULL,
    test_id TEXT NOT NULL REFERENCES visual_tests(id) ON DELETE CASCADE,
    image_id TEXT NOT NULL REFERENCES images(id),
    kind TEXT NOT NULL,
    x REAL NOT NULL,
    y REAL NOT NULL,
    price REAL,
    label TEXT,
    created_at TEXT NOT NULL
  )
  ''',
  'CREATE INDEX idx_visual_tests_strategy ON visual_tests(strategy_id, tested_at)',
  'CREATE INDEX idx_visual_test_images_image ON visual_test_images(image_id)',
  'CREATE INDEX idx_visual_annotations_test ON visual_annotations(test_id, image_id)',
]);
