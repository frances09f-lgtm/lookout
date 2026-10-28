import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lookout/data/sqflite_repository.dart';
import 'package:sqflite_common_ffi/sqflite_common_ffi.dart';

/// Regression test for the v1.1.13 task-history failure: the Workmanager
/// isolate opened the same database file and closed it after each cycle.
/// sqflite's default shares one native connection per path process-wide
/// (ffi's single-instance cache reproduces the same sharing), so that close
/// broke the foreground app's live connection - every later read threw
/// DatabaseException(database_closed) (tekartik/sqflite#558).
/// open() now passes singleInstance: false, so every opener owns its
/// connection and a background close cannot touch a foreground one.
void main() {
  late Directory dir;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lookout_closed');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('a background opener closing its store leaves the UI store open',
      () async {
    final dbPath = '${dir.path}/lookout.db';
    final ui = await SqfliteAgentRepository.open(path: dbPath);
    await ui.putKv('k', 'v');

    // The Workmanager isolate: open the same file, work, close.
    final background = await SqfliteAgentRepository.open(path: dbPath);
    await background.putKv('lastBackgroundRunAt', 'now');
    await background.close();

    // The foreground connection survives and sees the worker's writes.
    expect(await ui.getKv('k'), 'v');
    expect(await ui.getKv('lastBackgroundRunAt'), 'now');
    await ui.close();
  });

  test('with the old shared-instance default the bug is real', () async {
    // Guards the test above: under singleInstance: true the same sequence
    // DOES poison the foreground connection, proving the regression test
    // exercises the failure mode rather than passing vacuously.
    final dbPath = '${dir.path}/shared.db';
    final ui = await databaseFactory.openDatabase(dbPath,
        options: OpenDatabaseOptions(version: 1));
    final background = await databaseFactory.openDatabase(dbPath,
        options: OpenDatabaseOptions(version: 1));
    await background.close();
    await expectLater(ui.query('sqlite_master'), throwsA(anything));
  });
}
