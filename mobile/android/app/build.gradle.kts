import java.net.URI

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.example.srs_review_ai_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.srs_review_ai_mobile"
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

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// network_security_config.xml được SINH khi build để địa chỉ VPS không nằm trong git:
// host lấy từ SRS_API_BASE_URL (mobile/.env, hoặc biến môi trường cùng tên). Android 9+
// chặn HTTP cleartext, nên chỉ host này + host dev cục bộ được miễn; còn lại HTTPS-only.
val srsApiBaseUrl: String = run {
    val envFile = rootProject.projectDir.parentFile.resolve(".env")
    val fromFile = if (envFile.exists()) {
        envFile.readLines()
            .map { it.trim() }
            .firstOrNull { it.startsWith("SRS_API_BASE_URL=") }
            ?.substringAfter("=")?.trim()?.trim('"', '\'')
    } else null
    (fromFile?.takeIf { it.isNotEmpty() } ?: System.getenv("SRS_API_BASE_URL") ?: "").trim()
}
val srsApiHost: String? = runCatching { URI(srsApiBaseUrl).host }.getOrNull()?.takeIf { it.isNotEmpty() }

val generateNetworkSecurityConfig by tasks.registering {
    val out = layout.projectDirectory.file("src/main/res/xml/network_security_config.xml")
    val host = srsApiHost
    inputs.property("host", host ?: "")
    outputs.file(out)
    doLast {
        val domains = listOfNotNull(host, "10.0.2.2", "localhost", "127.0.0.1").distinct()
            .joinToString("\n") { "        <domain includeSubdomains=\"false\">$it</domain>" }
        out.asFile.parentFile.mkdirs()
        out.asFile.writeText(
            """<?xml version="1.0" encoding="utf-8"?>
<!-- FILE SINH TỰ ĐỘNG bởi app/build.gradle.kts (đã gitignore) - đừng sửa tay. -->
<network-security-config>
    <base-config cleartextTrafficPermitted="false"/>
    <domain-config cleartextTrafficPermitted="true">
$domains
    </domain-config>
</network-security-config>
"""
        )
    }
}
tasks.named("preBuild") { dependsOn(generateNetworkSecurityConfig) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
