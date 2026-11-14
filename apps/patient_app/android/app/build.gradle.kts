import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (docs/02-setup.md §7b): android/key.properties points to the
// upload keystore. Both files stay on Sarbuland's machine and are git-ignored.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) keystoreProperties.load(FileInputStream(keystorePropertiesFile))

// A Play Store (prod release) build must never be signed with the debug key.
// (Checks the requested tasks: the Flutter plugin wires tasks of every variant.)
gradle.taskGraph.whenReady {
    val requested = gradle.startParameter.taskNames.map { it.substringAfterLast(':') }
    if (!hasReleaseKey && requested.any { it.contains("ProdRelease") }) {
        throw GradleException(
            "Release signing is not set up: android/key.properties is missing. " +
                "See docs/02-setup.md §7b. (Dev release builds still use the debug key.)",
        )
    }
}

android {
    namespace = "app.asani.patient_app"
    // 37: flutter_local_notifications 23 and androidx.core 1.19 need it (target stays Flutter's default).
    compileSdk = 37
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

    signingConfigs {
        if (hasReleaseKey) {
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
            // The upload key when android/key.properties exists. Without it only
            // dev release builds fall back to the debug key (prod is blocked above).
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
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
