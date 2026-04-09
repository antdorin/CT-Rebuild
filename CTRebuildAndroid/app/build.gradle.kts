import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.chasetactical.ctrebuild"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.chasetactical.ctrebuild"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        compose = true
    }

    packaging {
        jniLibs {
            // Compress native libs so page-alignment of .so files in AARs is irrelevant
            useLegacyPackaging = true
        }
    }

    androidResources {
        // .tflite files must be stored uncompressed so MappedByteBuffer can
        // memory-map them directly via assets.openFd(). Compressed assets throw
        // "This file can not be opened as a file descriptor" at runtime.
        noCompress += "tflite"
    }
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("androidx.core:core-ktx:1.18.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.10.0")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation(platform("androidx.compose:compose-bom:2026.03.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.animation:animation")
    implementation("com.squareup.okhttp3:okhttp:5.3.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    // Camera2 is part of the Android framework; no extra dependency needed.
    // ML Kit barcode scanning
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
    // ViewModel + Lifecycle Compose
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.10.0")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.10.0")
    // OpenCV (CSRT optical tracking) — 4.13.0 fixes 16 KB alignment
    implementation("org.opencv:opencv:4.13.0")
    // LiteRT (TFLite successor) for Super-Resolution inference.
    // V1 packages support Interpreter API + GPU delegate; 16 KB page-aligned from 1.4.x.
    // org.tensorflow:tensorflow-lite was relocated here — class names (org.tensorflow.lite.*) unchanged.
    implementation("com.google.ai.edge.litert:litert:1.4.2")
    implementation("com.google.ai.edge.litert:litert-gpu:1.4.2")
    // JSON parsing for weather/scrape data
    implementation("com.google.code.gson:gson:2.11.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
