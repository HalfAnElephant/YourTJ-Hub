import 'dart:async';
import 'dart:io';

/// Windows refuses to delete a file while any other process still has it open,
/// and antivirus or indexer scans of files a test just wrote are enough to hold
/// one for a moment. The delete of the whole directory then fails with a
/// sharing violation (`PathAccessException`, errno 32) that clears by itself —
/// see issue #1138. Delays double so a lock that clears quickly costs the suite
/// almost nothing, while a slow scan is still covered.
const _lockBackoff = <Duration>[
  Duration(milliseconds: 25),
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 400),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1600),
  Duration(milliseconds: 2000),
  Duration(milliseconds: 2000),
  Duration(milliseconds: 2000),
  Duration(milliseconds: 2000),
];

/// Removes a test-owned temporary directory and everything in it.
///
/// Unlike a bare `Directory.delete(recursive: true)`, a delete the OS refuses
/// because the path is still in use is retried for about eleven seconds: test
/// suites on Windows treat such a lock as a transient condition. A handle the
/// test genuinely leaked is not hidden — the last failure is rethrown once
/// [backoff] is spent.
Future<void> deleteTempDirectory(
  Directory directory, {
  List<Duration> backoff = _lockBackoff,
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      if (attempt >= backoff.length) rethrow;
      await Future<void>.delayed(backoff[attempt]);
    }
  }
}
