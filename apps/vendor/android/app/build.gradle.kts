plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
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
    }

    defaultConfig {
        applicationId = "com.siteonlab.zopiq_vendor"
        // The same floor as the customer app. A kitchen tablet is, if anything,
        // older than a customer's phone — this is not the app to raise it on.
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
