# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# Don't warn about Play Store deferred component classes (not bundled in APK, only in AAB)
-dontwarn com.google.android.play.core.**

# Dio (WebDAV HTTP client)
-keep class com.fluttercandies.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# Keep share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class io.flutter.plugins.share.** { *; }

# Keep window_manager
-keep class com.leanflutter.window_manager.** { *; }

# Keep url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# Keep shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# General
-keepattributes EnclosingMethod
-keepattributes InnerClasses
