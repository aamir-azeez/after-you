plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.aamirazeez.afteryou.nativebridge"
    compileSdk = 35
    defaultConfig {
        minSdk = 24
        // Exercise the same platform camera/privacy behavior as the exported game.
        targetSdk = 35
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
    implementation("com.google.firebase:firebase-messaging:25.1.3") // Messaging only; no Analytics/KTX.
    implementation("androidx.core:core:1.8.0") // Explicit floor for temporary photo URI grants; FCM may raise the locked version.
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

dependencyLocking { lockAllConfigurations() }

// Optional build-only public Firebase Android configuration. The input file stays private;
// server service-account/signing credentials are never accepted by this task.
val firebaseConfigFile = providers.gradleProperty("afterYouFirebaseConfig").map { rootProject.file(it) }
val firebaseResources = layout.buildDirectory.dir("generated/res/afterYouFirebase/main")
val generateFirebaseResources by tasks.registering {
    inputs.files(firebaseConfigFile).optional().withPropertyName("afterYouFirebaseConfig")
    outputs.dir(firebaseResources)
    doLast {
        val target = firebaseResources.get().file("values/after_you_firebase.xml").asFile
        val source = firebaseConfigFile.orNull
        if (source == null) {
            // One known generated file only; prevents a previous configured build leaking into
            // a later unconfigured artifact without deleting unrelated build/source contents.
            if (target.exists()) check(target.delete())
            target.parentFile.mkdirs()
        } else {
            require(source.isFile && source.length() in 1..1_048_576) { "Invalid Firebase Android configuration file." }
            val root = groovy.json.JsonSlurper().parse(source) as? Map<*, *>
                ?: error("Invalid Firebase Android configuration object.")
            val project = root["project_info"] as? Map<*, *> ?: error("Missing Firebase project configuration.")
            val clients = root["client"] as? List<*> ?: error("Missing Firebase Android app configuration.")
            require(clients.size in 1..16) { "Invalid Firebase Android app count." }
            val matches = clients.mapNotNull { it as? Map<*, *> }.filter {
                val info = it["client_info"] as? Map<*, *>
                val android = info?.get("android_client_info") as? Map<*, *>
                android?.get("package_name") == "com.aamirazeez.afteryou"
            }
            require(matches.size == 1) { "Firebase configuration must match the After You Android package exactly once." }
            val client = matches.single()
            val info = client["client_info"] as Map<*, *>
            val appId = info["mobilesdk_app_id"] as? String ?: error("Missing Firebase Android app ID.")
            val sender = project["project_number"] as? String ?: error("Missing Firebase sender ID.")
            val projectId = project["project_id"] as? String ?: error("Missing Firebase project ID.")
            val keys = client["api_key"] as? List<*> ?: error("Missing Firebase public API configuration.")
            require(keys.size == 1) { "Expected one Firebase public Android API key." }
            val key = (keys.single() as? Map<*, *>)?.get("current_key") as? String ?: error("Missing Firebase public Android API key.")
            require(appId.matches(Regex("1:[0-9]{6,20}:android:[A-Fa-f0-9]{16,64}")) &&
                sender.matches(Regex("[0-9]{6,20}")) && appId.split(':')[1] == sender &&
                projectId.matches(Regex("[a-z][a-z0-9-]{4,62}")) && key.matches(Regex("AIza[A-Za-z0-9_-]{35}"))) {
                "Malformed Firebase Android public resource values."
            }
            val values = linkedMapOf("google_app_id" to appId, "google_api_key" to key,
                "gcm_defaultSenderId" to sender, "project_id" to projectId)
            check(target.parentFile.isDirectory || target.parentFile.mkdirs())
            target.writeText("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n" +
                values.entries.joinToString("\n") { "    <string name=\"${it.key}\" translatable=\"false\">${it.value}</string>" } +
                "\n</resources>\n")
        }
    }
}
android.sourceSets.getByName("main").res.srcDir(firebaseResources)
tasks.named("preBuild").configure { dependsOn(generateFirebaseResources) }

tasks.register<Copy>("packagePlugin") {
    dependsOn("assembleDebug", "assembleRelease")
    into(rootProject.layout.projectDirectory.dir("../game/addons/after_you_android"))
    from(rootProject.layout.projectDirectory.dir("export"))
    from(layout.buildDirectory.file("outputs/aar/plugin-debug.aar")) { rename { "after-you-debug.aar" } }
    from(layout.buildDirectory.file("outputs/aar/plugin-release.aar")) { rename { "after-you-release.aar" } }
    doLast { destinationDir.resolve(".gitignore").writeText("*.aar\n") }
}
