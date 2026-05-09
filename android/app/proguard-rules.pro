# Keep Flutter classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Suppress missing Play Core classes referenced by Flutter engine (not used at runtime)
-dontwarn com.google.android.play.core.**

# Keep Firebase and Google Play services
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep Gson/serialization (if used by dependencies)
-keep class com.google.gson.** { *; }
