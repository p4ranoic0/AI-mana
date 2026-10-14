plugins { alias(libs.plugins.android.application); alias(libs.plugins.kotlin.serialization); alias(libs.plugins.kotlin.compose) }
android {
    namespace = "com.henrrygarcia.aimana"
    compileSdk = 37
    defaultConfig { applicationId = "com.henrrygarcia.aimana"; minSdk = 26; targetSdk = 37; versionCode = 10200; versionName = "1.2.0" }
    signingConfigs {
        create("release") {
            val keystore = System.getenv("ANDROID_KEYSTORE_PATH")
            val password = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            val alias = System.getenv("ANDROID_KEY_ALIAS")
            if (!keystore.isNullOrBlank() && !password.isNullOrBlank() && !alias.isNullOrBlank()) {
                storeFile = file(keystore)
                storePassword = password
                keyAlias = alias
                keyPassword = password
            }
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            if (!System.getenv("ANDROID_KEYSTORE_PATH").isNullOrBlank()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
    buildFeatures { compose = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    testOptions { unitTests.isReturnDefaultValues = true }
}
dependencies {
    implementation(project(":core"))
    implementation(libs.serialization.json)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons)
    implementation(libs.activity.compose)
    implementation(libs.lifecycle.viewmodel.compose)
    implementation(libs.lifecycle.runtime.compose)
    implementation(libs.navigation.compose)
    implementation(libs.datastore.preferences)
    implementation(libs.coroutines.android)
    debugImplementation(libs.compose.ui.tooling)
    testImplementation(libs.junit)
}
