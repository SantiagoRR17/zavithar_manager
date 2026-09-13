# R8 keep rules for the release build.
#
# ## flutter_local_notifications
#
# A scheduled notification is not held in memory: the plugin serialises it to
# disk with Gson, and `ScheduledNotificationReceiver` deserialises it when the
# alarm fires. Gson works by reflection on field names, so R8 renaming those
# model classes breaks the round trip.
#
# The failure is completely silent and took a while to find. In a release build
# the alarm is registered, `dumpsys alarm` confirms the receiver is woken at the
# right moment, the channel exists and permissions are granted — and no
# notification appears, with nothing in logcat. Debug builds work, because debug
# does not minify.
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# Gson needs generic signatures to reconstruct parameterised types, and R8
# strips attributes it considers unused.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Any class whose fields Gson reads by reflection must keep those fields.
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
