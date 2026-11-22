#!/usr/bin/env bash
# Installs the Godot Android Gradle build template (the same thing as the editor's
# "Project -> Install Android Build Template") into android/build, taken from the export templates.
# Usage: tools/install_android_template.sh [GODOT_VERSION]    e.g. 4.7.stable  (default: 4.7.stable)
# The template version MUST equal the Godot editor version that exports the project.
set -euo pipefail
VER="${1:-4.7.stable}"
ZIP="${ANDROID_SOURCE_ZIP:-$HOME/.local/share/godot/export_templates/$VER/android_source.zip}"
if [ ! -f "$ZIP" ]; then echo "android_source.zip not found: $ZIP (install the export templates first)"; exit 1; fi
rm -rf android/build
mkdir -p android/build
unzip -q -o "$ZIP" -d android/build
printf "%s" "$VER" > android/.build_version
: > android/build/.gdignore      # keep Godot from importing the Gradle project
echo "Android build template $VER installed in android/build ($(du -sh android | cut -f1))"
