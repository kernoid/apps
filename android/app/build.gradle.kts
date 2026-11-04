plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.kernoid.kernoid"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // 64-bit ARM only (the same Platforms): libraries a plugin carries for other processors stay out of the APK.
    packaging {
        jniLibs {
            excludes += setOf("lib/armeabi-v7a/**", "lib/x86_64/**", "lib/x86/**")
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.kernoid.kernoid"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Android 13 and later (falkoss/starterpack, docs/practices.md, Platforms).
        minSdk = 33
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles("proguard-rules.pro")
        }
    }
}

// The Kotlin part of rustls-platform-verifier, through which the Rust side checks certificates against Android's trust
// store. Published by the rustls project as a Maven repository on GitHub (MIT OR Apache-2.0), taken from there for
// this one group only. Its version must be the one of the crate `rustls-platform-verifier-android` in rust/Cargo.lock –
// checked here, as a different one may crash at run time.
repositories {
    maven {
        url = uri("https://github.com/rustls/rustls-platform-verifier/raw/maven-archive/android-release-support/maven/")
        content { includeGroup("org.rustls") }
    }
}

val rustlsPlatformVerifier = "0.2.0"

run {
    val lock = rootProject.file("../rust/Cargo.lock").readLines()
    val at = lock.indexOfFirst { it.trim() == "name = \"rustls-platform-verifier-android\"" }
    val locked = lock.getOrNull(at + 1)?.substringAfter('"')?.substringBefore('"')
    check(at < 0 || locked == rustlsPlatformVerifier) {
        "rustls-platform-verifier-android is $locked in rust/Cargo.lock, but $rustlsPlatformVerifier here"
    }
}

dependencies {
    implementation("org.rustls:rustls-platform-verifier:$rustlsPlatformVerifier")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
