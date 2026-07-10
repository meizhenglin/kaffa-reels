buildscript {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://mvn.mob.com/android") }
        maven { url = uri("https://mvn.zztfly.com/android") }
    }
    dependencies {
        classpath("com.mob.sdk:MobSDK:+")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://mvn.mob.com/android") }
        maven { url = uri("https://mvn.zztfly.com/android") }
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
