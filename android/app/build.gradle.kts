import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: load key.properties when present (local + CI).
// Never commit key.properties or *.jks / *.keystore (see .gitignore).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.privi.app"
    // receive_sharing_intent requires 37+; higher compileSdk is backward compatible.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.privi.app"
        // Product baseline documented in the architecture and install guides.
        minSdk = 26
        // Keep current Play / Play Protect baseline (API 34+ required; 36 is fine).
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Drop x86/x86_64 native libs for smaller APK.
        // Real Android devices are ARM-only since API 26+.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Prefer a permanent release keystore (Play Protect reputation).
            // Falls back to debug only for local `flutter run --release` convenience
            // when key.properties is missing — CI must always provide the release key.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 + resource shrink: smaller APK and fewer generic-scanner false positives.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.media3:media3-exoplayer:1.5.1")
    implementation("androidx.media3:media3-datasource:1.5.1")
    implementation("androidx.media3:media3-common:1.5.1")

    // libVLC: FFmpeg-based fallback engine for broad format support.
    implementation("org.videolan.android:libvlc-all:3.6.4")
}