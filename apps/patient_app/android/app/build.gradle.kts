plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.asani.patient_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Needed by flutter_local_notifications (queue_alerts channel).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "pk.asani.patient"
        minSdk = 26 // Android 8.0+ (PRD §6)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Needed for the per-flavor app_name below.
    buildFeatures {
        resValues = true
    }

    // docs/02 §4: dev → Firebase asani-dev, prod → asani-prod.
    // Each flavor gets its google-services.json in src/dev/ or src/prod/.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationId = "pk.asani.patient.dev"
            resValue("string", "app_name", "Asani Dev")
        }
        create("prod") {
            dimension = "env"
            applicationId = "pk.asani.patient"
            resValue("string", "app_name", "Asani")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
