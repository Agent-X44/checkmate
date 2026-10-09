import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val releaseKeyPropertiesFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties()
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyPropertiesFile.inputStream().use { releaseKeyProperties.load(it) }
}

android {
    namespace = "com.checkmate.checkmate"
    compileSdk = flutter.compileSdkVersion
    buildToolsVersion = "35.0.0"
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.checkmate.checkmate"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "edition"
    productFlavors {
        create("production") {
            dimension = "edition"
            resValue("string", "app_name", "CheckMate")
            manifestPlaceholders["deepLinkScheme"] = "checkmate"
        }
        create("developer") {
            dimension = "edition"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "CheckMate Dev")
            manifestPlaceholders["deepLinkScheme"] = "checkmate-dev"
        }
    }

    if (releaseKeyPropertiesFile.exists()) {
        signingConfigs {
            create("release") {
                keyAlias = releaseKeyProperties.getProperty("keyAlias")
                keyPassword = releaseKeyProperties.getProperty("keyPassword")
                storeFile = rootProject.file(releaseKeyProperties.getProperty("storeFile"))
                storePassword = releaseKeyProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (releaseKeyPropertiesFile.exists()) "release" else "debug")
        }
    }


}

// Flutter 3.44 can miss changed JNI inputs in flavored builds. Refresh this
// small merge step so incremental APKs package the freshly compiled app.
// https://github.com/flutter/flutter/issues/187553
tasks.configureEach {
    if (name.startsWith("merge") && name.endsWith("JniLibFolders")) {
        outputs.upToDateWhen { false }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.concurrent:concurrent-futures:1.2.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")
}

// The offline developer edition does not need a Firebase Android registration.
// Supply its own configuration later to enable push notifications there.
if (!file("src/developer/google-services.json").exists()) {
    tasks.configureEach {
        if (name.startsWith("processDeveloper") && name.endsWith("GoogleServices")) enabled = false
    }
}
