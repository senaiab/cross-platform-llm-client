// Linux desktop stub — Firebase Core is not supported on Linux.
// All calls are guarded by Platform.isAndroid/isIOS at runtime; this stub
// ensures the Dart code compiles for Linux builds.

class FirebaseApp {
  final String name;
  const FirebaseApp({required this.name});
}

class FirebaseOptions {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  const FirebaseOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
  });
}

class Firebase {
  static final List<FirebaseApp> apps = const [];

  static Future<FirebaseApp> initializeApp({
    FirebaseOptions? options,
    String? name,
  }) async {
    return const FirebaseApp(name: '[DEFAULT]');
  }
}
