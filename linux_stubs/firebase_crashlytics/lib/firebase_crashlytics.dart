// Linux desktop stub — Firebase Crashlytics is not supported on Linux.
// All calls are guarded by Platform.isAndroid/isIOS at runtime.

import 'package:flutter/foundation.dart' show FlutterErrorDetails;

class FirebaseCrashlytics {
  static final FirebaseCrashlytics instance = FirebaseCrashlytics._();
  FirebaseCrashlytics._();

  Future<void> setCrashlyticsCollectionEnabled(bool enabled) async {}

  Future<void> recordFlutterFatalError(FlutterErrorDetails details) async {}

  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
    bool printDetails = true,
  }) async {}

  void log(String message) {}

  Future<void> setCustomKey(String key, Object value) async {}
}
