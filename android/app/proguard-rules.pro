-keep class io.agora.**{*;}
-keep class androidx.media.**{*;}

# flutter_local_notifications stores scheduled notifications with Gson; R8
# strips the generic signatures Gson's TypeToken needs, so cancel()/schedule
# threw "TypeToken must be created with a type argument" in release builds.
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.** { *; }
