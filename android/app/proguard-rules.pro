# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Play Services (google_sign_in, geolocator)
-keep class com.google.android.gms.** { *; }
-keep class com.google.api.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.api.**

# PDF / Printing
-keep class net.nfet.flutter.printing.** { *; }

# SQLite
-keep class com.tekartik.sqflite.** { *; }

# Share Plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# Path Provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Image Picker
-keep class io.flutter.plugins.imagepicker.** { *; }

# General
-dontwarn android.**
-dontwarn com.google.**
-dontwarn java.lang.**
