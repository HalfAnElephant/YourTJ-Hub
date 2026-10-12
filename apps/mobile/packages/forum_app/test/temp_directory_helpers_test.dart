import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'temp_directory_helpers.dart';

/// Stands in for a directory another process still holds open. Windows reports
/// that as a sharing violation (errno 32) from the first [failures] deletions.
class _LockedDirectory implements Directory {
  _LockedDirectory(this.path, {required this.failures});
  int failures;
  int attempts = 0;

  @override
  final String path;

  @override
  Uri get uri => Directory(path).uri;

  @override
  Future<Directory> delete({bool recursive = false}) async {
    attempts++;
    if (failures > 0) {
      failures--;
      throw PathAccessException(
        path,
        const OSError('The process cannot access the file.', 32),
        'Deletion failed',
      );
    }
    return Directory(path);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const noDelay = [Duration.zero, Duration.zero, Duration.zero];

  test('a temporary directory is deleted with everything in it', () async {
    final directory = await Directory.systemTemp.createTemp('temp-dir-helper-');
    await File('${directory.path}/cache.sqlite').writeAsString('fixture');
    await deleteTempDirectory(directory);
    expect(await directory.exists(), isFalse);
  });

  test('a lock that clears shortly after the delete is retried', () async {
    final directory = _LockedDirectory('/locked', failures: 2);
    await deleteTempDirectory(directory, backoff: noDelay);
    expect(directory.attempts, 3);
  });

  test(
    'a directory that stays locked fails once the budget is spent',
    () async {
      final directory = _LockedDirectory('/locked', failures: 100);
      await expectLater(
        deleteTempDirectory(directory, backoff: noDelay),
        throwsA(isA<PathAccessException>()),
      );
      expect(directory.attempts, noDelay.length + 1);
    },
  );
}
