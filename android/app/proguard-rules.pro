# ML Kit Text Recognition - keep all language recognizer options
# (fixes R8 "Missing classes" error for Chinese/Japanese/Korean/Devanagari)
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.**

-keep class com.google.mlkit.vision.text.chinese.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**

-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-dontwarn com.google.mlkit.vision.text.devanagari.**

-keep class com.google.mlkit.vision.text.japanese.** { *; }
-dontwarn com.google.mlkit.vision.text.japanese.**

-keep class com.google.mlkit.vision.text.korean.** { *; }
-dontwarn com.google.mlkit.vision.text.korean.**

# TensorFlow Lite - keep GPU delegate classes (avoids similar R8 issues)
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# General ML Kit safety net
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**