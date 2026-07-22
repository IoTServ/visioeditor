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

// Flutter plugins often ship an outdated compileSdk; AndroidX / peer plugins
// may require 36+. Raise the floor after each module evaluates (or immediately
// if evaluationDependsOn already evaluated the project).
subprojects {
    fun bumpCompileSdk() {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.apply {
            if ((compileSdk ?: 0) < 36) {
                compileSdk = 36
            }
        }
    }
    if (state.executed) {
        bumpCompileSdk()
    } else {
        afterEvaluate { bumpCompileSdk() }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
