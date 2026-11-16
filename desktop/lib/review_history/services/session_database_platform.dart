/// The platform half of the session database, chosen at COMPILE time.
///
/// `sembast_web` is built on `dart:js_interop` and `package:web`, so it cannot
/// even be imported into a mobile/desktop build; `sembast_io` needs a file path,
/// which a browser does not have. Conditional exports are the standard way to
/// keep both out of each other's way — the VM build never compiles the web file,
/// and the web build never compiles the io one.
///
/// The stub is a third case on purpose: an unknown target must fail with a
/// readable sentence (and let the caller fall back), not fail to compile.
library;

export 'session_database_platform_stub.dart'
    if (dart.library.io) 'session_database_platform_io.dart'
    if (dart.library.js_interop) 'session_database_platform_web.dart';
