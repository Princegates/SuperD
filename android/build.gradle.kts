plugins {
    // Only actually applied in app/build.gradle.kts, and only once
    // google-services.json exists there - see the guard in that file
    // and the README's "Push notifications" section. `apply false` here
    // just makes the plugin's classpath available without running it,
    // so a build with no Firebase project set up yet isn't affected.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
