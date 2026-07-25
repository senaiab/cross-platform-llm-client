plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.orailnoor.privatelm"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    val releaseStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")?.let { file(it) }
        ?: file("upload-keystore.jks")
    val releaseStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val releaseKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
    val releaseKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")
    val hasReleaseSigning = releaseStoreFile.exists() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.orailnoor.privatelm"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/x86_64/libc++_shared.so",
                "lib/x86/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                // Use model-matched 684KB backend (packaged with v79 PTE) over AAR's version
                "lib/arm64-v8a/libqnn_executorch_backend.so",
            )
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // QNN-enabled AAR: libexecutorch.so (JNI) links against libqnn_executorch_backend.so
    // (runtime+QNN), sharing one registry — unlike the generic AAR which had separate registries.
    implementation("org.pytorch:executorch-android-qnn:1.2.0")
    // fbjni is required by libexecutorch.so from the QNN AAR
    implementation("com.facebook.fbjni:fbjni:0.5.0")
}

flutter {
    source = "../.."
}
