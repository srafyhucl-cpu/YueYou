import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 加载正式签名配置；Release 不允许回退 debug 签名。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
val releaseSigningRequired = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true) || it.contains("bundle", ignoreCase = true)
}

fun signingValue(name: String, envName: String): String? {
    return (keystoreProperties[name] as String?) ?: System.getenv(envName)
}

fun requiredSigningValue(name: String, envName: String): String {
    return signingValue(name, envName)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Release 签名缺少 $name，请在 android/key.properties 或 $envName 中配置。")
}

fun requiredSigningFile(): java.io.File {
    val storeFilePath = requiredSigningValue("storeFile", "ANDROID_STORE_FILE")
    val storeFile = rootProject.file(storeFilePath)
    if (!storeFile.exists()) {
        throw GradleException("Release 签名文件不存在：$storeFilePath。")
    }
    return storeFile
}

android {
    namespace = "cn.hclstudio.yueyou"
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
        applicationId = "cn.hclstudio.yueyou"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningRequired) {
                keyAlias = requiredSigningValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = requiredSigningValue("keyPassword", "ANDROID_KEY_PASSWORD")
                storeFile = requiredSigningFile()
                storePassword = requiredSigningValue("storePassword", "ANDROID_STORE_PASSWORD")
            } else {
                keyAlias = signingValue("keyAlias", "ANDROID_KEY_ALIAS")
                keyPassword = signingValue("keyPassword", "ANDROID_KEY_PASSWORD")
                storeFile = signingValue("storeFile", "ANDROID_STORE_FILE")?.let { rootProject.file(it) }
                storePassword = signingValue("storePassword", "ANDROID_STORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}
