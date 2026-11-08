# kotlinx.serialization: keep generated serializers and companions of @Serializable classes (core relay models).
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-keepclassmembers @kotlinx.serialization.Serializable class ** { *** Companion; *** serializer(...); }
-keep class **$$serializer { *; }
-keepclasseswithmembers class ** { kotlinx.serialization.KSerializer serializer(...); }
-dontnote kotlinx.serialization.**
# JNA (Windows APIs) is reached through reflection.
-keep class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**
# java.net.http and coroutines.
-dontwarn kotlinx.coroutines.**
-dontwarn org.slf4j.**
