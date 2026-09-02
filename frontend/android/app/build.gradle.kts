import java.io.File
import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Android 正式签名是应用的长期身份，不能跟代码仓库一起分发，也不能在 release
// 构建时回退到 debug key。默认从当前 Windows 用户目录读取；换机器时可用
// KANKAN_SIGNING_PROPERTIES 指向安全迁移后的同一份 signing.properties。
val signingPropertiesFile = System.getenv("KANKAN_SIGNING_PROPERTIES")
    ?.takeIf { it.isNotBlank() }
    ?.let(::File)
    ?: File(System.getProperty("user.home"), ".kankan-signing/signing.properties")
val signingProperties = Properties()
val hasReleaseSigning = signingPropertiesFile.isFile
if (hasReleaseSigning) {
    FileInputStream(signingPropertiesFile).use(signingProperties::load)
}

fun requiredSigningValue(name: String): String =
    signingProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("Missing '$name' in ${signingPropertiesFile.absolutePath}")

val releaseKeystoreFile = if (hasReleaseSigning) {
    File(signingPropertiesFile.parentFile, requiredSigningValue("storeFile"))
} else {
    null
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

// Flutter 把 --dart-define 以逗号分隔的 Base64 字符串传给 Gradle。正式 APK
// 必须明确指向唯一生产 API；否则即使签名正确，也会构建出连接本机地址的“空白包”。
fun decodedDartDefines(): Map<String, String> {
    val encoded = providers.gradleProperty("dart-defines").orNull.orEmpty()
    if (encoded.isBlank()) return emptyMap()
    return encoded.split(',').mapNotNull { item ->
        runCatching {
            val decoded = String(Base64.getDecoder().decode(item), Charsets.UTF_8)
            val separator = decoded.indexOf('=')
            if (separator <= 0) null
            else decoded.substring(0, separator) to decoded.substring(separator + 1)
        }.getOrNull()
    }.toMap()
}

if (releaseRequested) {
    val defines = decodedDartDefines()
    val expectedApi = "https://lovluu.com/api/v1"
    if (defines["USE_REMOTE"] != "true" || defines["API_BASE_URL"] != expectedApi) {
        throw GradleException(
            "Kankan release requires --dart-define=USE_REMOTE=true and " +
                "--dart-define=API_BASE_URL=$expectedApi. Refusing to build a signed but unusable APK."
        )
    }
}
if (releaseRequested && (!hasReleaseSigning || releaseKeystoreFile?.isFile != true)) {
    throw GradleException(
        "Kankan release signing is unavailable. Restore the original signing set; " +
            "never generate a replacement key or fall back to the debug key. See docs/ANDROID_RELEASE_SIGNING.md."
    )
}

android {
    namespace = "com.kankan.kankan_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // 已发布身份的一部分：不要改 applicationId；否则 Android 会当成另一款 App。
        applicationId = "com.kankan.kankan_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 管理员版：设环境变量 KANKAN_ADMIN=true 构建 → 换独立包名+名字，可与客户端版共存装机。
        // 不设（普通 flutter run / 客户端构建）时默认客户端版，行为不变。
        val isAdmin = System.getenv("KANKAN_ADMIN") == "true"
        if (isAdmin) {
            applicationIdSuffix = ".admin"
        }
        manifestPlaceholders["appLabel"] = if (isAdmin) "看看·管理" else "看看"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = requiredSigningValue("storePassword")
                keyAlias = requiredSigningValue("keyAlias")
                keyPassword = requiredSigningValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 正式包只能使用固定 release key；releaseRequested 的检查负责缺钥匙时硬失败。
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
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
