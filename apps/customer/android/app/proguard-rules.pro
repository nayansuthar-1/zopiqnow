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

# Razorpay (razorpay_flutter 1.4.5) — the SDK's own documented keep rules. Its
# checkout runs in a WebView and calls back over @JavascriptInterface, which R8
# would otherwise strip from a minified release build.
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keep class com.razorpay.** { *; }
-dontwarn com.razorpay.**
-optimizations !method/inlining/*
-keepclasseswithmembers class * {
    public void onPayment*(...);
}
