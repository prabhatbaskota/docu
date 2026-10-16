import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeysFile = rootProject.file("key.properties")
if (releaseKeysFile.isFile) {
    releaseKeysFile.inputStream().use { releaseKeys.load(it) }
}
val docuApplicationId = providers.environmentVariable("DOCU_APPLICATION_ID")
    .orElse(providers.gradleProperty("docuApplicationId"))
    .orElse("com.yourname.docapp").get()
val signingStoreFile = providers.environmentVariable("DOCU_KEYSTORE_PATH").orNull
    ?: releaseKeys.getProperty("storeFile")
val signingStorePassword = providers.environmentVariable("DOCU_STORE_PASSWORD").orNull
    ?: releaseKeys.getProperty("storePassword")
val signingKeyAlias = providers.environmentVariable("DOCU_KEY_ALIAS").orNull
    ?: releaseKeys.getProperty("keyAlias")
val signingKeyPassword = providers.environmentVariable("DOCU_KEY_PASSWORD").orNull
    ?: releaseKeys.getProperty("keyPassword")
val hasReleaseSigning = listOf(signingStoreFile, signingStorePassword,
    signingKeyAlias, signingKeyPassword).all { !it.isNullOrBlank() }
if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
    require(docuApplicationId != "com.yourname.docapp") {
        "Set docuApplicationId to your registered Google Play package name."
    }
    require(hasReleaseSigning) {
        "Configure release signing with android/key.properties or the DOCU_* environment variables."
    }
}

android {
    namespace = "com.yourname.docapp"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = docuApplicationId
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = requireNotNull(signingKeyAlias)
                keyPassword = requireNotNull(signingKeyPassword)
                storeFile = file(requireNotNull(signingStoreFile))
                storePassword = requireNotNull(signingStorePassword)
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
