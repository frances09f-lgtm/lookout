plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

// Persistent release signing (in-place updates). CI writes these properties
// from repo secrets; without them (local dev) the release build falls back to
// the debug key.
val lookoutKeystoreFile = providers.gradleProperty("LOOKOUT_KEYSTORE_FILE").orNull

android {
    namespace = "com.ambi.lookout"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (lookoutKeystoreFile != null) {
            create("release") {
                storeFile = file(lookoutKeystoreFile)
                storePassword = providers.gradleProperty("LOOKOUT_KEYSTORE_PASSWORD").orNull
                keyAlias = providers.gradleProperty("LOOKOUT_KEY_ALIAS").orNull
                keyPassword = providers.gradleProperty("LOOKOUT_KEY_PASSWORD").orNull
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time APIs
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.ambi.lookout"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (lookoutKeystoreFile != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
