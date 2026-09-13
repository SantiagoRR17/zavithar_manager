import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from android/key.properties — which is gitignored and
// never leaves this machine.
//
// **The keystore is not recoverable.** Android identifies an app by its
// signature, so losing the file or its password means this app can never be
// updated again, only uninstalled and reinstalled under a new identity. It
// lives outside the repository and has to be backed up somewhere else.
//
// Absent, the build falls back to debug signing rather than failing. That
// keeps `flutter build apk` working on a fresh clone — for anyone checking the
// project out, and for CI — instead of demanding a secret before it will
// compile at all.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.zavithar.zavithar_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (Milestone 3): the plugin
        // uses java.time APIs that do not exist below API 26, and desugaring is
        // what back-ports them to the minSdk this app supports. Without it the
        // build fails at checkDebugAarMetadata with the plugin naming this flag
        // directly — an unusually honest error message.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zavithar.zavithar_manager"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Loud on purpose: an APK signed with debug keys installs fine
                // and is indistinguishable until the day it has to be updated
                // from a machine that does not have this exact debug keystore.
                logger.warn(
                    "WARNING: no android/key.properties — signing the release " +
                    "build with DEBUG keys. This APK cannot be updated from " +
                    "any other machine."
                )
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // The desugaring runtime itself. Pinned rather than floating: a silent
    // major bump here changes which APIs are back-ported, and the failure mode
    // is a crash on an old device that no emulator in this project would catch.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
