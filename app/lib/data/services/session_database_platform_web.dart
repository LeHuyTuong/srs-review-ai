/// The web half of the session database: IndexedDB, via `sembast_web`.
///
/// This is the case that makes the change worth it on the web build. The old
/// store put the whole history in one `localStorage` value, which is capped at
/// ~5 MB *per origin* and — because the origin includes the port — lost the
/// history entirely when the dev server moved from 3000 to 3001. IndexedDB is
/// measured in hundreds of MB and is still per-origin, but a database that can
/// hold tens of documents beats a value that cannot hold one.
///
/// There is no path here: the browser identifies the database by name, and a
/// version so a future schema change can migrate instead of corrupting.
library;

import 'package:sembast_web/sembast_web.dart';

/// IndexedDB database name. Changing it starts a fresh database.
const String sessionDatabaseName = 'srs_review_ai';

/// Schema version handed to IndexedDB; bump it when the stores change.
const int sessionDatabaseVersion = 1;

Future<Database> openPlatformDatabase() => databaseFactoryWeb.openDatabase(
  sessionDatabaseName,
  version: sessionDatabaseVersion,
);
