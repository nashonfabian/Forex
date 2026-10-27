// Schema version 2: record whether the hypothesis was supported, contradicted or inconclusive.
import '../migration.dart';

const migration002 = Migration(2, 'hypothesis verdict', <String>[
  'ALTER TABLE research_cases ADD COLUMN hypothesis_verdict TEXT',
]);
