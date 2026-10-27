import 'dart:async';

/// One announcement that rows in some tables changed.
/// [fromSync] is true when the change came from the cloud, so the sync
/// service does not treat it as a new local edit.
class TableChange {
  const TableChange(this.tables, {this.fromSync = false});

  final Set<String> tables;
  final bool fromSync;
}

/// sqflite has no change streams, so repositories announce which tables they
/// changed (after the transaction commits) and watchers reload.
class TableChanges {
  final StreamController<TableChange> _controller =
      StreamController<TableChange>.broadcast();

  Stream<TableChange> get stream => _controller.stream;

  void notify(Iterable<String> tables, {bool fromSync = false}) {
    if (!_controller.isClosed) {
      _controller.add(TableChange(tables.toSet(), fromSync: fromSync));
    }
  }

  Future<void> dispose() => _controller.close();
}

/// A live query: emits once on listen, then again whenever any of [tables] change.
Stream<T> watchQuery<T>(
  TableChanges changes,
  Set<String> tables,
  Future<T> Function() load,
) {
  late final StreamController<T> controller;
  StreamSubscription<TableChange>? subscription;
  var cancelled = false;
  var latest = 0;

  Future<void> emit() async {
    final mine = ++latest;
    try {
      final value = await load();
      if (!cancelled && mine == latest) controller.add(value);
    } catch (error, stack) {
      if (!cancelled && mine == latest) controller.addError(error, stack);
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = changes.stream
          .where((change) => change.tables.any(tables.contains))
          .listen((_) => emit());
      emit();
    },
    onCancel: () {
      cancelled = true;
      return subscription?.cancel();
    },
  );
  return controller.stream;
}
