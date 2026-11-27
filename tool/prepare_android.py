from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "quranak_flutter_app" / "android"
SETTINGS_CANDIDATES = (ROOT / "settings.gradle.kts", ROOT / "settings.gradle")
APP_CANDIDATES = (ROOT / "app" / "build.gradle.kts", ROOT / "app" / "build.gradle")


def first_existing(paths):
    return next((path for path in paths if path.exists()), None)


def add_plugin(settings_file, app_file):
    # Only apply Google Services when its configuration is actually supplied.
    google_services_json = ROOT / "app" / "google-services.json"
    if not google_services_json.exists():
        return
    if settings_file:
        settings_text = settings_file.read_text()
        if "com.google.gms.google-services" not in settings_text:
            line = '    id("com.google.gms.google-services") version "4.4.2" apply false'
            settings_file.write_text(settings_text.replace("plugins {", "plugins {\n" + line, 1))
    app_text = app_file.read_text()
    if "com.google.gms.google-services" not in app_text:
        plugin = ('    id("com.google.gms.google-services")' if app_file.suffix == ".kts"
                  else '    id "com.google.gms.google-services"')
        app_file.write_text(app_text.replace("plugins {", "plugins {\n" + plugin, 1))


def configure_desugaring(app_file):
    text = app_file.read_text()
    kotlin_dsl = app_file.suffix == ".kts"

    if kotlin_dsl:
        enabled = "isCoreLibraryDesugaringEnabled = true"
        dependency = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
        compile_settings = (
            "compileOptions {\n        " + enabled +
            "\n        sourceCompatibility = JavaVersion.VERSION_17" +
            "\n        targetCompatibility = JavaVersion.VERSION_17"
        )
        dependency_line = "    " + dependency
        dependency_check = "coreLibraryDesugaring("
    else:
        enabled = "coreLibraryDesugaringEnabled true"
        dependency = "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
        compile_settings = (
            "compileOptions {\n        " + enabled +
            "\n        sourceCompatibility JavaVersion.VERSION_17" +
            "\n        targetCompatibility JavaVersion.VERSION_17"
        )
        dependency_line = "    " + dependency
        dependency_check = "coreLibraryDesugaring "

    if enabled not in text:
        if "compileOptions {" not in text:
            raise RuntimeError("Android app Gradle file has no compileOptions block")
        text = text.replace("compileOptions {", compile_settings, 1)

    if dependency_check not in text:
        if "dependencies {" in text:
            text = text.replace("dependencies {", "dependencies {\n" + dependency_line, 1)
        else:
            text += "\ndependencies {\n" + dependency_line + "\n}\n"

    if enabled not in text or dependency not in text:
        raise RuntimeError("Failed to configure Android core library desugaring")
    if "\\n" in text:
        raise RuntimeError("Invalid literal backslash-n sequence found in Gradle file")
    app_file.write_text(text)



def configure_launch_background():
    # Flutter's generated default launch screen includes its own mark.
    # Keep the native hand-off clean; the app immediately shows the Quranak artwork.
    xml = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/quranak_splash_background" />
</layer-list>
'''
    res = ROOT / "app" / "src" / "main" / "res"
    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    colors = values / "colors.xml"
    color = '<color name="quranak_splash_background">#071915</color>'
    if colors.exists():
        content = colors.read_text()
        if "quranak_splash_background" not in content:
            colors.write_text(content.replace("</resources>", f"    {color}\n</resources>"))
    else:
        colors.write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    ' + color + '\n</resources>\n')
    for folder in ("drawable", "drawable-v21"):
        target = res / folder / "launch_background.xml"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(xml)

def main():
    settings_file = first_existing(SETTINGS_CANDIDATES)
    app_file = first_existing(APP_CANDIDATES)
    if not app_file:
        raise FileNotFoundError("Flutter did not generate android/app/build.gradle(.kts)")
    add_plugin(settings_file, app_file)
    configure_desugaring(app_file)
    configure_launch_background()
    print(f"Android Gradle configuration verified: {app_file}")


if __name__ == "__main__":
    main()
