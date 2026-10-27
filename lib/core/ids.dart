import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Every record gets a client-generated UUID v4, so the same record can be
/// pushed to the cloud any number of times without creating duplicates.
String newId() => _uuid.v4();
