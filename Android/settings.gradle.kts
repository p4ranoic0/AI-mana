pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "AImanaAndroid"
include(":core", ":desktop")
// The Android app needs the Android SDK; desktop-only machines (Windows/Linux builds) pass -PdesktopOnly=true.
if (providers.gradleProperty("desktopOnly").orNull != "true") include(":app")
