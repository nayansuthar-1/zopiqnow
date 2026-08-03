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

# No Razorpay block here, unlike the customer and vendor files: this app has no
# `razorpay_flutter` dependency and a rider never takes a payment. Firebase,
# geolocator and google_maps_flutter all ship their own consumer rules inside
# their AARs, which R8 applies without anything being restated here.
