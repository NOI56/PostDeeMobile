import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Workflows build release apps and handle repository secrets. They should run
// with a read-only token, not leave it in .git/config, and only execute pinned
// third-party code.
void main() {
  const workflowPaths = [
    '../../.github/workflows/ci.yml',
    '../../.github/workflows/build_ios.yml',
  ];

  for (final path in workflowPaths) {
    final name = path.split('/').last;
    final workflow = File(path).readAsStringSync().replaceAll('\r\n', '\n');

    test('$name runs with a read-only default token', () {
      expect(workflow, contains('\npermissions:\n  contents: read\n'));
    });

    test('$name pins every action to a full commit SHA', () {
      final uses = RegExp(r'uses:\s*(\S+)').allMatches(workflow).map((match) => match[1]!);
      expect(uses, isNotEmpty);
      for (final action in uses) {
        expect(action, matches(RegExp(r'^[\w.-]+/[\w.-]+@[0-9a-f]{40}$')),
            reason: '$action must be pinned by commit SHA');
      }
    });

    test('$name does not persist checkout credentials', () {
      final checkouts = RegExp(r'uses: actions/checkout@[0-9a-f]{40}[^\n]*\n((?:\s{8,}.*\n)*)')
          .allMatches(workflow)
          .toList();
      expect(checkouts, isNotEmpty);
      for (final checkout in checkouts) {
        expect(checkout[1], contains('persist-credentials: false'));
      }
    });
  }

  test('ci.yml only builds an apk_source_ref that is on a branch of this repository', () {
    final workflow = File('../../.github/workflows/ci.yml').readAsStringSync();

    expect(workflow, contains("fetch-depth: \${{ inputs.apk_source_ref != '' && '0' || '1' }}"));
    expect(workflow, contains('git for-each-ref --contains HEAD refs/remotes/origin'));
  });
}
