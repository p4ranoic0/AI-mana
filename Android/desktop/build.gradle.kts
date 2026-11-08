import org.jetbrains.compose.desktop.application.dsl.TargetFormat

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.compose.multiplatform)
}

kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
java { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }

dependencies {
    implementation(project(":core"))
    implementation(compose.desktop.currentOs)
    implementation(compose.material3)
    implementation(libs.serialization.json)
    implementation(libs.coroutines.swing)
    implementation(libs.jna.platform)
    testImplementation(libs.junit)
}

compose.desktop {
    application {
        mainClass = "com.henrrygarcia.aimana.desktop.MainKt"
        // A tray app idles most of the time: a small heap that is handed back to the OS after the panel closes.
        jvmArgs += listOf("-XX:+UseSerialGC", "-Xms16m", "-Xmx128m", "-XX:MinHeapFreeRatio=10", "-XX:MaxHeapFreeRatio=20",
                          "-XX:TieredStopAtLevel=1")
        nativeDistributions {
            targetFormats(TargetFormat.Msi, TargetFormat.Deb)
            packageName = "AImana"
            packageVersion = "1.3.0"
            modules("java.net.http", "jdk.crypto.ec")
            windows { menuGroup = "AI·mana"; upgradeUuid = "5B0C1E6A-0D0F-4E52-9B8C-7A1D2E3F4A5B" }
        }
        buildTypes.release.proguard {
            configurationFiles.from(project.file("proguard-rules.pro"))
            obfuscate.set(false)
        }
    }
}
