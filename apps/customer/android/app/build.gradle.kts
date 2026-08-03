// Imported rather than written as `java.util.Properties`: inside a Kotlin DSL
// build script `java` resolves to Gradle's own `java` extension, which shadows
// the package and makes the qualified name an unresolved reference.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase config (google-services.json) for push. B0, 2026-07-25.
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// The Google Maps key, read from `android/local.properties` — which is
// gitignored, and is where it must stay.
//
// Unlike the Supabase publishable key, this one is not merely "not a secret":
// it is billed. The protection is not secrecy — an Android app's key is
// extractable from any APK — it is the **key restriction** you set in the Cloud
// console: restrict it to Android apps, to this exact package name and signing
// certificate, and to the Maps SDK for Android alone. Then a copied key is
// worthless in anyone else's app.
//
// Empty when unset, so a checkout with no key still builds. The map then shows
// Google's "authorization failure" tile rather than failing the build, which is
// the right trade for a repo more than one person clones.
val mapsApiKey: String = run {
    val properties = Properties()
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { properties.load(it) }
    properties.getProperty("MAPS_API_KEY") ?: ""
}

// The release signing key, read from `android/key.properties` — gitignored,
// alongside the `.jks` it points at.
//
// **Why this app stopped being signed with the debug key.** Google enforces a
// *global* uniqueness rule on the pair (package name, signing certificate): a
// given pair may be registered to exactly one OAuth client across every Cloud
// project on earth. Ours was claimed by a project whose owning account is gone,
// and whose OAuth client Google has since disabled — so native Google sign-in
// failed with `Invalid key value: <sha1>:com.siteonlab.zopiqnow`, and the pair
// could not be re-registered anywhere else because the dead project still holds
// it. A different certificate is a different pair, which is the way out.
//
// **The keystore is not recoverable.** Lose the `.jks` or its password and this
// application id can never be updated on Play again — a new certificate means a
// new app. It is backed up outside this repo, and it is not in it.
//
// Absent on a fresh checkout, and deliberately not fatal: the build falls back
// to debug signing so someone who clones this can still compile. Such a build
// simply cannot do Google sign-in, which is the honest consequence.
val keystoreProperties: Properties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore: Boolean = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.siteonlab.zopiqnow"
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
        applicationId = "com.siteonlab.zopiqnow"
        // Read by the meta-data element in AndroidManifest.xml, which is where
        // the Maps SDK looks for it.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
        // Locked per ENGINEERING_RULES.md Rule 1 (Android 10+ broad reach) & DEVELOPMENT_SETUP.md.
        minSdk = 24        // Android 7.0 — broad reach
        targetSdk = 35     // Android 15 — Play 2026 requirement
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Only ship the ABIs we actually support (keeps APK/AAB lean).
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
