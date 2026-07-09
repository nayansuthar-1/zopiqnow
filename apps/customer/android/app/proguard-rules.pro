# Zopiqnow — R8/ProGuard keep rules for release builds.
# Flutter ships most rules via proguard-android-optimize.txt + plugin consumer rules.
# Add app-/plugin-specific keeps below as dependencies are introduced.

# Flutter engine / embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Keep annotations & generic signatures (needed by reflection-based libs, e.g. JSON).
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
