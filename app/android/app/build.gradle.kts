import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Load upload-keystore credentials from android/key.properties if it exists.
// That file holds signing secrets and must never be committed (see .gitignore).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val repoRootDir = rootProject.file("../..").canonicalFile
val whisperCppSourceDir = repoRootDir.resolve("third_party/whisper.cpp")
val whisperReproducibleCompileFlags =
    listOf(
        "-ffile-prefix-map=${whisperCppSourceDir.absolutePath}=third_party/whisper.cpp",
        "-ffile-prefix-map=${repoRootDir.absolutePath}=.",
        "-no-canonical-prefixes",
    ).joinToString(" ")

android {
    namespace = "co.rorystandley.notes_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // --- Reproducible builds (ROADMAP #1) ---------------------------------------
    // Drop the Play "dependency metadata" block from the APK and AAB. AGP otherwise
    // embeds a blob describing the dependency tree, encrypted to a Google public key.
    // That blob is non-deterministic (fresh bytes every build) and would by itself
    // defeat any bit-for-bit comparison, so it is the first thing F-Droid's
    // reproducible-build verification requires turned off. It also leaks the full
    // dependency graph, which we have no reason to ship. See
    // RELEASE.md → "Reproducible / verifiable builds".
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "co.rorystandley.rune"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags.add("-std=c++17")
                arguments.addAll(
                    listOf(
                        "-DWHISPER_CPP_SOURCE_DIR=${whisperCppSourceDir.absolutePath}",
                        "-DANDROID_STL=c++_shared",
                        "-DCMAKE_C_FLAGS=$whisperReproducibleCompileFlags",
                        "-DCMAKE_CXX_FLAGS=$whisperReproducibleCompileFlags",
                        "-DCMAKE_SHARED_LINKER_FLAGS=-Wl,--build-id=none",
                    ),
                )
            }
        }

        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }
    }

    signingConfigs {
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            // R8 / code shrinking is intentionally left OFF. R8's output is not
            // guaranteed byte-stable across toolchain versions, which would put the
            // reproducible-build goal at risk; the app is small and ships no Java/Kotlin
            // hot paths, so there is little to gain. If shrinking is enabled later it
            // must be re-verified against the double-build check (see RELEASE.md).
            isMinifyEnabled = false
            isShrinkResources = false
            // Uses the upload keystore when android/key.properties exists; otherwise
            // falls back to debug signing so `flutter run --release` still works locally.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../../native/whisper/CMakeLists.txt")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
