from pathlib import Path
root=Path(__file__).resolve().parents[1]/'quranak_flutter_app'/'android'

# Flutter templates differ by release: support both Groovy and Kotlin DSL.
settings = next((p for p in (root/'settings.gradle.kts', root/'settings.gradle') if p.exists()), None)
if settings:
    s=settings.read_text()
    if 'com.google.gms.google-services' not in s:
        if settings.suffix == '.kts':
            s=s.replace('plugins {', 'plugins {\n    id("com.google.gms.google-services") version "4.4.2" apply false',1)
        else:
            s=s.replace('plugins {', 'plugins {\n    id "com.google.gms.google-services" version "4.4.2" apply false',1)
    settings.write_text(s)

app = next((p for p in (root/'app'/'build.gradle.kts', root/'app'/'build.gradle') if p.exists()), None)
if app:
    s=app.read_text()
    if 'com.google.gms.google-services' not in s:
        if app.suffix == '.kts':
            s=s.replace('plugins {', 'plugins {\n    id("com.google.gms.google-services")',1)
        else:
            s=s.replace('plugins {', 'plugins {\n    id "com.google.gms.google-services"',1)
    if app.suffix == '.kts':
        if 'isCoreLibraryDesugaringEnabled = true' not in s:
            s=s.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n        sourceCompatibility = JavaVersion.VERSION_17\n        targetCompatibility = JavaVersion.VERSION_17',1)
        if 'kotlinOptions {' in s and 'jvmTarget = "17"' not in s:
            s=s.replace('kotlinOptions {', 'kotlinOptions {\n        jvmTarget = "17"',1)
        if 'coreLibraryDesugaring(' not in s:
            s=s.replace('dependencies {', 'dependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")',1)
    else:
        if 'coreLibraryDesugaringEnabled true' not in s:
            s=s.replace('compileOptions {', 'compileOptions {\n        coreLibraryDesugaringEnabled true\n        sourceCompatibility JavaVersion.VERSION_17\n        targetCompatibility JavaVersion.VERSION_17',1)
        if 'kotlinOptions {' in s and "jvmTarget = '17'" not in s:
            s=s.replace('kotlinOptions {', "kotlinOptions {\n        jvmTarget = '17'",1)
        if 'coreLibraryDesugaring ' not in s:
            s=s.replace('dependencies {', "dependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'",1)
    # AndroidX notification/alarm plugins require core library desugaring.
    # Keep the dependency in the generated app module; otherwise Gradle fails
    # while creating :app:l8DexDesugarLibRelease.
    if app.suffix == '.kts':
        if 'coreLibraryDesugaring(' not in s:
            if 'dependencies {' in s:
                s=s.replace('dependencies {', 'dependencies {\\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")', 1)
    else:
        if 'coreLibraryDesugaring ' not in s:
            if 'dependencies {' in s:
                s=s.replace('dependencies {', "dependencies {\\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'", 1)
    app.write_text(s)
