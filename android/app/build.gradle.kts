import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key, kept outside the repository. android/key.properties
// (git-ignored) holds storeFile, storePassword, keyAlias and keyPassword.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null

android {
    namespace = "com.lucchetta.rankingBeachTennis"
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
        applicationId = "com.lucchetta.rankingBeachTennis"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without android/key.properties (e.g. another machine), release builds
            // fall back to the debug key so `flutter run --release` still works.
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

flutter {
    source = "../.."
}

// Shareable copy of the release APK named after the app version (pubspec.yaml),
// e.g. build/app/outputs/shareable/ranking-beach-tennis-1.0.0.apk. The original
// app-release.apk is left alone (own folder), since the Flutter tool looks for it.
val shareableReleaseApk = tasks.register<Copy>("shareableReleaseApk") {
    from(layout.buildDirectory.file("outputs/apk/release/app-release.apk"))
    into(layout.buildDirectory.dir("outputs/shareable"))
    rename { "ranking-beach-tennis-${flutter.versionName}.apk" }
}

// Optional local archive of releases: android/release.properties (git-ignored)
// may set releaseCopyDir. Each release build copies the shareable APK there and
// deletes the APKs of older versions (same or newer versions are kept).
val releaseProperties = Properties().apply {
    val file = rootProject.file("release.properties")
    if (file.exists()) {
        file.inputStream().use { load(it) }
    }
}
val archiveReleaseApk = tasks.register("archiveReleaseApk") {
    dependsOn(shareableReleaseApk)
    val archiveDir = releaseProperties.getProperty("releaseCopyDir")?.let { File(it) }
    val version = flutter.versionName
    val apk = layout.buildDirectory.file("outputs/shareable/ranking-beach-tennis-${version}.apk")
    onlyIf { archiveDir != null }
    doLast {
        val dir = archiveDir!!
        dir.mkdirs()
        fun parts(v: String) = v.split(".").map { it.toIntOrNull() ?: 0 }
        fun older(v: String, than: String): Boolean {
            val (a, b) = parts(v) to parts(than)
            for (i in 0 until maxOf(a.size, b.size)) {
                val x = a.getOrElse(i) { 0 }
                val y = b.getOrElse(i) { 0 }
                if (x != y) return x < y
            }
            return false
        }
        val name = Regex("""ranking-beach-tennis-(\d+(?:\.\d+)*)\.apk""")
        dir.listFiles().orEmpty()
            .filter { file -> name.matchEntire(file.name)?.let { older(it.groupValues[1], version) } ?: false }
            .forEach { file ->
                file.delete()
                logger.lifecycle("Deleted older release ${file.name}")
            }
        apk.get().asFile.copyTo(File(dir, "ranking-beach-tennis-${version}.apk"), overwrite = true)
        logger.lifecycle("Release copied to ${dir}")
    }
}
tasks.matching { it.name == "assembleRelease" }.configureEach { finalizedBy(shareableReleaseApk, archiveReleaseApk) }
