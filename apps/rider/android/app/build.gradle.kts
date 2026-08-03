// Imported rather than written as `java.util.Properties`: inside a Kotlin DSL
// build script `java` resolves to Gradle's own `java` extension, which shadows
// the package.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase config (google-services.json) for push. B0, 2026-07-25.
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// The Google Maps key, read from `android/local.properties` — gitignored, and
// where it must stay. See the customer app's build file for why the protection
// is the Cloud console's key restriction rather than secrecy. This app needs its
// own entry in the restriction list: a key restricted to Android apps is
// restricted to specific package names, and this is a different package.
//
// Empty when unset, so a checkout with no key still builds.
val mapsApiKey: String = run {
    val properties = Properties()
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { properties.load(it) }
    properties.getProperty("MAPS_API_KEY") ?: ""
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
        // flutter_local_notifications 18 uses java.time APIs that need desugaring
        // to keep our minSdk 24 floor (Android 7) reachable.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.siteonlab.zopiq_rider"
        // Read by the meta-data element in AndroidManifest.xml.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
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

            // Off for the same reason as the customer app: the upload is a
            // network call inside `assembleRelease`, and it failed the build
            // outright on 2026-08-02. Crash *reporting* is unaffected; what it
            // costs is that Java frames stay obfuscated, which is a small bill
            // for a Flutter app whose stack traces are Dart.
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
