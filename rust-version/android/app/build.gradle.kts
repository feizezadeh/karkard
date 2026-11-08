plugins {
    id("com.android.application")
}

android {
    namespace = "ir.karkard.rust"
    compileSdk = 35
    buildToolsVersion = "36.1.0"
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ir.karkard.rust"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0-rust"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
