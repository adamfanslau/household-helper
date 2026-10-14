plugins {
    alias(libs.plugins.android.application)   // AGP 9: built-in Kotlin (no org.jetbrains.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.householdhelper.app"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.householdhelper.app"
        minSdk = 28
        targetSdk = 37
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // dev: Firebase Auth emulator + local API reached on the device's loopback through
    // `adb reverse tcp:9099 / tcp:8091` (scripts/dev/android.sh sets it up; works on USB devices too,
    // and the app's own connects to 10.0.2.2 timed out on API 37 images). Fabricated google-services.json
    // committed. prod: real project (google-services.json git-ignored) and the VPS API.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            buildConfigField("String", "API_BASE_URL", "\"http://127.0.0.1:8091\"")
            buildConfigField("String", "AUTH_EMULATOR_HOST", "\"127.0.0.1:9099\"")
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"\"")
            buildConfigField("boolean", "DEV_LOGIN", "true")
            buildConfigField("boolean", "PUSH_ENABLED", "false")   // fabricated Firebase project: no FCM
            manifestPlaceholders["networkSecurityConfig"] = "@xml/network_security_config"
        }
        create("prod") {
            dimension = "env"
            buildConfigField("String", "API_BASE_URL", "\"https://hh-api.fanslau.me\"")
            buildConfigField("String", "AUTH_EMULATOR_HOST", "\"\"")
            // Web client id of the Firebase project (Credential Manager); injected from CI/local.properties.
            buildConfigField("String", "GOOGLE_WEB_CLIENT_ID", "\"${providers.gradleProperty("hh.googleWebClientId").orNull ?: ""}\"")
            buildConfigField("boolean", "DEV_LOGIN", "false")
            buildConfigField("boolean", "PUSH_ENABLED", "true")
            manifestPlaceholders["networkSecurityConfig"] = "@xml/network_security_config_prod"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlin {
        jvmToolchain(21)
        compilerOptions {
            // Expressive APIs are still opt-in on the 1.5 line; one module-wide opt-in instead of per file.
            freeCompilerArgs.addAll(
                "-opt-in=androidx.compose.material3.ExperimentalMaterial3ExpressiveApi",
                "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
                "-opt-in=kotlinx.serialization.ExperimentalSerializationApi",
            )
        }
    }

    sourceSets {
        // The API's golden fixtures are the contract; ModelsDecodingTest decodes the same files iOS does.
        getByName("test").resources.srcDir("../../api/internal/httpapi/testdata/golden")
    }

    testOptions {
        unitTests.isReturnDefaultValues = true   // android.util.Log in pure unit tests
    }

    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.viewmodel.navigation3)
    implementation(libs.androidx.lifecycle.process)
    implementation(libs.androidx.navigation3.runtime)
    implementation(libs.androidx.navigation3.ui)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.credentials)
    implementation(libs.androidx.credentials.play.services.auth)
    implementation(libs.googleid)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.auth)
    implementation(libs.firebase.messaging)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.client.auth)
    implementation(libs.ktor.serialization.kotlinx.json)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.coroutines.play.services)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
}
