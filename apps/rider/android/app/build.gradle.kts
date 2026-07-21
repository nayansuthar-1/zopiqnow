plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.siteonlab.zopiq_rider"
    // Pinned to the same values the vendor app pins, rather than tracking
    // `flutter.*`, so a Flutter SDK swap cannot silently move an app's SDK floor
    // out from under it (ENGINEERING_RULES.md Rule 3).
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.siteonlab.zopiq_rider"
        // The same floor as the other two apps. A delivery partner's phone is the
        // oldest device in this system by some margin — this is the last app to
        // raise a minimum on.
        minSdk = 24        // Android 7.0 — broad reach
        targetSdk = 35     // Android 15 — Play 2026 requirement
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    buildTypes {
        release {
            // TODO: Replace debug signing with a real release keystore before publishing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
