// Imported rather than written as `java.util.Properties`: inside a Kotlin DSL
// build script `java` resolves to Gradle's own `java` extension, which shadows
// the package.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase config (google-services.json) for push. Phase 7, 2026-07-18.
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// The release signing key, read from `android/key.properties` — gitignored,
// alongside the `.jks` it points at. Both are ignored by
// `android/.gitignore`, and that is the only thing standing between this
// keystore and a public repository.
//
// **The keystore is not recoverable.** Lose the `.jks` or its password and this
// application id can never be updated on Play again — a new certificate means a
// new app listing. It must be backed up somewhere that outlives this laptop.
//
// Absent on a fresh checkout, and deliberately not fatal: the build falls back
// to debug signing so someone who clones this can still compile. Such a build
// is not publishable, which is the honest consequence.
val keystoreProperties: Properties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore: Boolean = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.siteonlab.zopiq_vendor"
    // compileSdk tracks the pinned Flutter SDK (3.44.5 -> API 36). See ENGINEERING_RULES.md Rule 3.
    compileSdk = 36
    // NDK pinned explicitly (frozen per Rule 3), independent of Flutter SDK swaps.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 18 uses java.time APIs that need desugaring
        // to keep our minSdk 24 floor (Android 7) reachable.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.siteonlab.zopiq_vendor"
        // The same floor as the customer app. A kitchen tablet is, if anything,
        // older than a customer's phone — this is not the app to raise it on.
        minSdk = 24        // Android 7.0 — broad reach
        targetSdk = 36     // Android 16 — Play requires it from 31 Aug 2026
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Crashlytics uploads the R8 mapping file over the network as part of
            // `assembleRelease`, and on 2026-08-02 that failed the whole build
            // with an SSL handshake error -- a release build that cannot be made
            // on a flaky connection is not a release process. Off, so the build
            // is offline and deterministic again.
            //
            // What it costs: Java frames in Crashlytics stay obfuscated. That is
            // a small bill for a Flutter app -- Dart stack traces are in the Dart
            // snapshot, are not what R8 renames, and arrive readable either way.
            // Turn it back on (and keep it on only if the build stays reliable)
            // when a native crash actually needs reading.
            configure<com.google.firebase.crashlytics.buildtools.gradle.CrashlyticsExtension> {
                mappingFileUploadEnabled = false
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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

dependencies {
    // Backs isCoreLibraryDesugaringEnabled above (flutter_local_notifications 18).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
