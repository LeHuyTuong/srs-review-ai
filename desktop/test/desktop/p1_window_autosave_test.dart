/// P1-5, macOS half — the window remembers its size and position.
///
/// There is no way to exercise AppKit from `flutter test`, and faking it would
/// assert nothing. What this file guards is the thing that can actually go
/// wrong in review: the two Swift calls that implement the feature, and the
/// ORDER of them. Reversing `setFrameAutosaveName` and `setFrame` makes the
/// stored frame dead code — the app would open at the hardcoded size forever
/// and still look correct in a screenshot.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The Swift file, found by walking up from wherever the runner started.
///
/// `flutter test` runs from the package root, but `flutter test app` from the
/// repo root is a legitimate invocation too, so neither path is assumed.
File _macosWindowSwift() {
  final candidates = ['macos', 'app/macos'];
  for (var dir = Directory.current; ; dir = dir.parent) {
    for (final candidate in candidates) {
      final file = File(
        '${dir.path}/$candidate/Runner/MainFlutterWindow.swift',
      );
      if (file.existsSync()) return file;
    }
    if (dir.parent.path == dir.path) {
      fail('could not locate macos/Runner/MainFlutterWindow.swift');
    }
  }
}

void main() {
  test('MainFlutterWindow saves and restores its frame', () {
    // Comments are stripped before matching: the rationale for the ordering
    // names both calls, and a naive `indexOf` would find the comment first and
    // assert the opposite of what the code does.
    final source = _macosWindowSwift()
        .readAsStringSync()
        .split('\n')
        .map((line) => line.split('//').first)
        .join('\n');

    expect(source, contains('setFrameAutosaveName'));
    expect(source, contains('setFrameUsingName'));

    // The name has to exist before it can be restored, and the restore has to
    // run before the fallback frame, or the fallback always wins.
    expect(
      source.indexOf('setFrameAutosaveName'),
      lessThan(source.indexOf('setFrameUsingName')),
    );
    expect(
      source.indexOf('setFrameUsingName'),
      lessThan(source.indexOf('self.setFrame(NSRect')),
    );

    // Ordering alone is not enough: moving `setFrame` past the closing brace of
    // the `if` would keep every index above in the same relative order while
    // making the stored frame dead code. So assert the fallback frame is
    // actually INSIDE the block — before the first `}` that closes it.
    final blockStart = source.indexOf('if !self.setFrameUsingName');
    final blockEnd = source.indexOf('}', blockStart);
    expect(blockStart, isNonNegative);
    expect(blockEnd, greaterThan(blockStart));
    expect(
      source.indexOf('self.setFrame(NSRect'),
      inInclusiveRange(blockStart, blockEnd),
    );

    // The P0 minimum must survive: a restored frame that ignores it would let
    // the user reopen the app at a size the layout cannot render.
    expect(source, contains('minSize'));
  });
}
