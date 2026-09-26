/// No database backend for this target.
///
/// Reached only if a build targets neither `dart:io` nor `dart:js_interop`.
/// Throwing here (instead of failing to compile) is what lets
/// `openSessionStore()` fall back to the `shared_preferences` store: the app
/// still runs, it just does not get a database.
library;

import 'package:sembast/sembast.dart';

Future<Database> openPlatformDatabase() async => throw UnsupportedError(
  'no embedded database backend is available on this platform',
);
