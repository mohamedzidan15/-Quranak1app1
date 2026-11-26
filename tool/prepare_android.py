from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "quranak_flutter_app" / "android"
SETTINGS_CANDIDATES = (ROOT / "settings.gradle.kts", ROOT / "settings.gradle")
APP_CANDIDATES = (ROOT / "app" / "build.gradle.kts", ROOT / "app" / "build.gradle")


def first_existing(paths):
    return next((path for path in paths if path.exists()), None)


def add_plugin(settings_file, app_file):
    # Firebase's Google Services plugin is only valid when the project actually
    # supplies google-services.json. This repository intentionally does not
    # commit that secret/configuration file.
    google_services_json = ROOT / "app" / "google-services.json"
    if not google_services_json.exists():
        return

    settings_text = settings_file.read_text() if settings_file else ""
    if settings_file and "com.google.gms.google-services" not in settings_text:
        line = '    id("com.google.gms.google-services") version "4.4.2" apply false'
        settings_text = settings_text.replace("plugins {", "plugins {\\n" + line, 1)
        settings_file.write_text(settings_text)

    app_text = app_file.read_text()
    if "com.google.gms.google-services" not in app_text:
        plugin = ('    id("com.google.gms.google-services")' if app_file.suffix == ".kts"
                  else '    id "com.google.gms.google-services"')
        app_text = app_text.replace("plugins {", "plugins {\\n" + plugin, 1)
        app_file.write_text(app_text)


def configure_desugaring(app_file):
    text = app_file.read_text()
    is_kotlin = app_file.suffix == ".kts"

    if is_kotlin:
        enabled = "isCoreLibraryDesugaringEnabled = true"
        dependency = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
        if enabled not in text:
            if "compileOptions {" not in text:
                raise RuntimeError("Android app Gradle file has no compileOptions block")
            text = text.replace(
                "compileOptions {",
                "compileOptions {\\n        " + enabled +
                "\\n        sourceCompatibility = JavaVersion.VERSION_17" +
                "\\n        targetCompatibility = JavaVersion.VERSION_17",
                1,
            )
        if "coreLibraryDesugaring(" not in text:
            if "dependencies {" not in text:
                text += "\\ndependencies {\\n    " + dependency + "\\n}\\n"
            else:
                text = text.replace("dependencies {", "dependencies {\\n    " + dependency, 1)
    else:
        enabled = "coreLibraryDesugaringEnabled true"
        dependency = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        if enabled not in text:
            if "compileOptions {" not in text:
                raise RuntimeError("Android app Gradle file has no compileOptions block")
            text = text.replace(
                "compileOptions {",
                "compileOptions {\\n        " + enabled +
                "\\n        sourceCompatibility JavaVersion.VERSION_17" +
                "\\n        targetCompatibility JavaVersion.VERSION_17",
                1,
            )
        if "coreLibraryDesugaring " not in text:
            if "dependencies {" not in text:
                text += "\\ndependencies {\\n    " + dependency + "\\n}\\n"
            else:
                text = text.replace("dependencies {", "dependencies {\\n    " + dependency, 1)

    # Fail early rather than allowing Gradle to fail much later.
    if enabled not in text or dependency not in text:
        raise RuntimeError("Failed to configure Android core library desugaring")
    if "\\\\n" in text:
        raise RuntimeError("Invalid literal \\n sequence found in generated Gradle file")
    app_file.write_text(text)


def main():
    settings_file = first_existing(SETTINGS_CANDIDATES)
    app_file = first_existing(APP_CANDIDATES)
    if not app_file:
        raise FileNotFoundError("Flutter did not generate android/app/build.gradle(.kts)")

    add_plugin(settings_file, app_file)
    configure_desugaring(app_file)
    print(f"Android Gradle configuration verified: {app_file}")


if __name__ == "__main__":
    main()
