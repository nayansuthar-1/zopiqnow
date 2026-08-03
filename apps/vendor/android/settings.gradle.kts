pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Reads google-services.json into the build so Firebase can wake the app.
    // Phase 7 push (2026-07-18). Applied in :app.
    id("com.google.gms.google-services") version "4.4.2" apply false
    // Uploads the R8 mapping file so a Java-side stack trace in Crashlytics is
    // readable rather than a list of one-letter class names. Dart traces need
    // no such thing -- they are not what R8 renames -- so if this plugin ever
    // fights the toolchain, dropping it costs symbolication and not reporting.
    // Launch C3, 2026-08-02.
    id("com.google.firebase.crashlytics") version "3.0.2" apply false
}

include(":app")
