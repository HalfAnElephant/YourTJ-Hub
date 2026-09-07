import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeysFile = rootProject.file("key.properties")
if (releaseKeysFile.exists()) {
    releaseKeysFile.inputStream().use { releaseKeys.load(it) }
}

android {
    namespace = "tj.yourtj.forum_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "tj.yourtj.forum_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // flutter_appauth:OIDC custom scheme 回跳(yourtj://callback)。
        manifestPlaceholders["appAuthRedirectScheme"] = "yourtj"
    }

    signingConfigs {
        create("release") {
            if (releaseKeysFile.exists()) {
                keyAlias = releaseKeys.getProperty("keyAlias")
                keyPassword = releaseKeys.getProperty("keyPassword")
                storeFile = releaseKeys.getProperty("storeFile")?.let { file(it) }
                storePassword = releaseKeys.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // A release must never silently fall back to the development key.
            signingConfig = signingConfigs.getByName("release")
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

tasks.configureEach {
    if (name in listOf("validateSigningRelease", "packageRelease", "signReleaseBundle")) {
        doFirst {
            require(releaseKeysFile.exists()) { "Release signing requires android/key.properties" }
            for (key in listOf("keyAlias", "keyPassword", "storeFile", "storePassword")) {
                require(!releaseKeys.getProperty(key).isNullOrBlank()) { "Missing release signing property: $key" }
            }
        }
    }
}
