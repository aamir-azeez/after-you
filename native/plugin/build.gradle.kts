plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aamirazeez.afteryou.nativebridge"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    compileOnly("org.godotengine:godot:4.7.2.stable")
    implementation("com.revenuecat.purchases:purchases:10.15.1")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

dependencyLocking { lockAllConfigurations() }

tasks.register<Copy>("packagePlugin") {
    dependsOn("assembleDebug", "assembleRelease")
    into(rootProject.layout.projectDirectory.dir("../game/addons/after_you_android"))
    from(rootProject.layout.projectDirectory.dir("export"))
    from(layout.buildDirectory.file("outputs/aar/plugin-debug.aar")) { rename { "after-you-debug.aar" } }
    from(layout.buildDirectory.file("outputs/aar/plugin-release.aar")) { rename { "after-you-release.aar" } }
    doLast { destinationDir.resolve(".gitignore").writeText("*.aar\n") }
}
