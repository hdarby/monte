plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ktor)
}

group = "com.pokerapp"
version = "0.0.1"

application {
    mainClass.set("com.pokerapp.ApplicationKt")

    // Allow JVM options / dev mode flags to be passed at runtime.
    val isDevelopment: Boolean = project.ext.has("development")
    applicationDefaultJvmArgs = listOf("-Dio.ktor.development=$isDevelopment")
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    implementation(libs.bundles.ktor.server)
    implementation(libs.kotlinx.serialization.json)

    // Persistence (Exposed + HikariCP + Postgres)
    implementation(libs.bundles.exposed)
    implementation(libs.hikari)
    implementation(libs.postgres)

    // Logging
    implementation(libs.logback.classic)

    // Testing
    testImplementation(libs.ktor.server.test.host)
    testImplementation(kotlin("test"))
}
