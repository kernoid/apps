# SPDX-License-Identifier: MIT
# What only native code calls, kept through shrinking: the core of the file shells (JNI, rust/src/provider/jni.rs)
# and the Kotlin part of rustls-platform-verifier, which reqwest checks certificates with on Android.
-keep class dev.kernoid.kernoid.ProviderCore { native <methods>; }
-keep, includedescriptorclasses class org.rustls.platformverifier.** { *; }
