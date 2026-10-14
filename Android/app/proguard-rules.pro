# Kotlin serialization uses generated serializers; retain their lookup methods and metadata.
-keepattributes *Annotation*,InnerClasses,EnclosingMethod,Signature
-keepclassmembers class **$$serializer { *; }
-keepclassmembers class * {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keepclasseswithmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}
