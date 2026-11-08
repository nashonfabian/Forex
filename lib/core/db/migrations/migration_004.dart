// Schema version 4: preserve the currency and unit used for each recorded trade.
import '../migration.dart';

const migration004 = Migration(4, 'trade currency and volume unit', <String>[
  'ALTER TABLE trades ADD COLUMN currency_code TEXT',
  'ALTER TABLE trades ADD COLUMN size_unit TEXT',
]);
