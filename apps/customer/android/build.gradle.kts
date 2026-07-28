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
// Pull every plugin's Java target back to 17.
//
// `maplibre_gl` 0.26.2 declares `sourceCompatibility 21`, and this project's
// JDK is pinned at 17 (ENGINEERING_RULES.md Rule 3 — the toolchain does not move
// without an approved upgrade task). A JDK 17 compiler cannot emit a class file
// for source release 21, so the plugin fails to compile and the build stops at
// `:maplibre_gl:compileDebugJavaWithJavac`.
//
// Lowering it here rather than raising the JDK is the smaller change and the
// reversible one. It is safe because the declaration is a build setting, not a
// language requirement: the plugin's Java and Kotlin sources use nothing newer
// than 17, which is what compiling clean against this proves.
//
// Delete this block when the project's JDK moves to 21.
subprojects {
    afterEvaluate {
        extensions.findByName("android")?.let { android ->
            (android as com.android.build.gradle.BaseExtension).compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
            )
        }
    }
}

// Must stay below the block above: this forces every subproject to evaluate, and
// `afterEvaluate` cannot be registered on a project that has already evaluated.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
