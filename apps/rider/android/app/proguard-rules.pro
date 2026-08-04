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

# Firebase — components are discovered by reflection, never by a call site.
#
# **Found on a real device on 5 August 2026, in the release build already on
# Play's internal track.** `FirebaseInitProvider` reads a list of
# `ComponentRegistrar` class names out of the AARs' manifest metadata and
# instantiates each one with its no-argument constructor. Those are strings, so
# R8 sees classes that nobody constructs and removes the constructors:
#
#   ComponentDiscovery: Could not instantiate ...FirebaseMessagingKtxRegistrar
#   Caused by: java.lang.NoSuchMethodException: ...KtxRegistrar.<init> []
#
# The app then logs `FirebaseApp initialization successful` and carries on with
# **no messaging, no installations and no crash reporting** — which is why the
# customer app had never registered a push token and why Crashlytics was empty
# while we were reading it for answers. A minified build that compiles has not
# exercised a reflection path; this is that lesson arriving in person.
#
# Keeping the constructor is the whole fix. The classes are few and tiny, so
# this costs nothing worth measuring.
-keep class * implements com.google.firebase.components.ComponentRegistrar {
    <init>();
}
