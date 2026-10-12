// Turns a `flutter test --file-reporter json:<file>` log into GitHub Actions
// error annotations, one per test file, so failure messages can be read from
// the run summary without opening the job log.
//
// Usage: dart tool/ci/report_test_failures.dart build/test-results.json
import 'dart:convert';
import 'dart:io';

const _maxFailureChars = 1500;

void main(List<String> args) {
  final file = File(args.isEmpty ? 'build/test-results.json' : args.first);
  if (!file.existsSync()) {
    stdout.writeln('No test results at ${file.path}.');
    return;
  }

  final suitePaths = <int, String>{};
  final tests = <int, ({String name, int suiteId})>{};
  final errors = <int, StringBuffer>{};
  final failed = <int>[];

  for (final line in file.readAsLinesSync()) {
    if (!line.startsWith('{')) continue;
    final event = jsonDecode(line) as Map<String, dynamic>;
    switch (event['type']) {
      case 'suite':
        final suite = event['suite'] as Map<String, dynamic>;
        suitePaths[suite['id'] as int] = suite['path'] as String? ?? '?';
      case 'testStart':
        final test = event['test'] as Map<String, dynamic>;
        tests[test['id'] as int] =
            (name: test['name'] as String, suiteId: test['suiteID'] as int);
      case 'error':
        errors.putIfAbsent(event['testID'] as int, StringBuffer.new)
          ..writeln(event['error'])
          ..writeln(_firstFrames(event['stackTrace'] as String? ?? ''));
      case 'testDone':
        if (event['result'] != 'success' && event['hidden'] != true) {
          failed.add(event['testID'] as int);
        }
    }
  }

  final byFile = <String, List<String>>{};
  for (final id in failed) {
    final test = tests[id];
    final path = _relative(suitePaths[test?.suiteId] ?? 'loading');
    var message = errors[id]?.toString().trim() ?? 'No error message.';
    if (message.length > _maxFailureChars) {
      message = '${message.substring(0, _maxFailureChars)}…';
    }
    byFile.putIfAbsent(path, () => []).add('■ ${test?.name}\n$message');
  }

  final summary = StringBuffer('## Flutter test failures\n\n');
  for (final entry in byFile.entries) {
    final body = entry.value.join('\n\n');
    stdout.writeln('::error file=${entry.key},'
        'title=${entry.value.length} failing in ${entry.key}::${_escape(body)}');
    summary
      ..writeln('### ${entry.key}\n')
      ..writeln('```\n$body\n```\n');
  }
  if (byFile.isEmpty) summary.writeln('All tests passed.');

  final summaryPath = Platform.environment['GITHUB_STEP_SUMMARY'];
  if (summaryPath != null) {
    File(summaryPath).writeAsStringSync(summary.toString(), mode: FileMode.append);
  }
}

String _firstFrames(String stackTrace) =>
    stackTrace.split('\n').where((l) => l.contains('checkmate')).take(4).join('\n');

String _relative(String path) {
  final index = path.indexOf('test/');
  return index < 0 ? path : path.substring(index);
}

String _escape(String value) => value
    .replaceAll('%', '%25')
    .replaceAll('\r', '%0D')
    .replaceAll('\n', '%0A');
