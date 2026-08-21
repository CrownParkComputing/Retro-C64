import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, written by CI's "Set up release signing" step (and
// creatable by hand for local release builds). Absent on forks and PRs, where
// the release build falls back to the debug key below.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.crownpark.retroc64"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Retro-C64 is a fresh Play Store listing. applicationId is also the
        // namespace Play Console keys on, so changing it later would mean
        // publishing as a brand-new app. Pick once and keep.
        applicationId = "com.retroc64"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Pinned, not inherited from the Flutter SDK.
        //
        // Play requires the target to stay within a year of the latest
        // Android release - 36 or higher from 31 August 2026 - and refuses
        // updates outright below that. flutter.targetSdkVersion floats with
        // whichever Flutter version happens to run the build, so an older SDK
        // on a CI runner or another machine could drop it under the bar
        // without a line of this project changing. Compliance is a decision,
        // so it is written down.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // libvicecore.so / libvicecore_vsid.so (native/vice_core/android/build.sh
        // output) only exist for arm64-v8a -- the Retroid Pocket Flip2 and every
        // other device this app targets. AGP already auto-packages
        // src/main/jniLibs/<abi>/*.so with no extra sourceSets config needed
        // (that's the default jniLibs.srcDirs).
        //
        // abiFilters constrains what AGP itself builds/merges, but it does NOT
        // constrain the Flutter Gradle Plugin: `flutter build apk|appbundle`
        // defaults to android-arm + android-arm64 + android-x64 and injects
        // libflutter.so/libapp.so for all three straight into the packaging
        // step. The result was an APK with armeabi-v7a and x86_64 folders that
        // had Flutter's libs but no libvicecore.so -- the app installed on
        // those devices and then died at "Failed to load libvicecore". The
        // packaging excludes below are what actually keeps them out, because
        // they are applied at package time to everything, Flutter included.
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    packaging {
        jniLibs {
            // Keep this list in sync with abiFilters above: arm64-v8a only.
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/armeabi/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
        }
    }

    signingConfigs {
        // Only declared when key.properties is present; referencing a config
        // with null fields fails the build outright rather than falling back.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // With key.properties present (CI with the signing secrets set, or a
            // local release build) this is a real upload-signed build. Without
            // it, fall back to the debug key so forks, PRs and `flutter run
            // --release` still work -- that output is NOT uploadable to Play.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
