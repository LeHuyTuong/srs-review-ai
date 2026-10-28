/// The mobile/desktop half of the session database: one file on disk.
///
/// The location comes from `path_provider` (`getApplicationSupportDirectory`),
/// which on every one of this app's targets is a per-app directory the user is
/// not expected to browse: Windows `%APPDATA%…`, macOS `~/Library/Application
/// Support`, Android's private files dir. Documents would be the wrong choice —
/// a history file is app state, not a document the user manages.
///
/// `path_provider` is a plugin, so it throws `MissingPluginException` in a plain
/// `flutter test` run and in any target without a platform implementation.
/// That is not an error to swallow silently: `openSessionStore()` catches it and
/// falls back to the `shared_preferences` store, which is exactly why the app
/// keeps working in the test runner (see the tests for the database, which pass
/// an explicit path instead).
library;

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// File name inside the app support directory.
const String sessionDatabaseFileName = 'srs_review_ai.db';

Future<Database> openPlatformDatabase() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  // Joined by hand rather than with `package:path`: Dart's file APIs accept '/'
  // on Windows too, and a separator is not worth a dependency that CI would
  // then have to audit.
  return databaseFactoryIo.openDatabase(
    '${directory.path}/$sessionDatabaseFileName',
  );
}
