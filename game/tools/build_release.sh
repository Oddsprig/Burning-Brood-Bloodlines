#!/bin/bash
# Burning Brood: Bloodlines - release builds (v0.099+), Linux build host.
# Makes build/windows/BurningBrood_Bloodlines.exe (one file, pack embedded) and
# build/android/BurningBrood_Bloodlines_v<NNNN>.apk (arm64, signed with the release key).
#
# Needs: Godot 4.7.2 on PATH; export templates 4.7.2.stable (windows_*_x86_64*.exe and
# android_*.apk) in ~/.local/share/godot/export_templates/4.7.2.stable; Java 17+;
# apksigner and adb (Ubuntu: apt-get install apksigner adb). Editor setting
# export/android/android_sdk_path must name a folder holding platform-tools/adb and
# build-tools/<ver>/apksigner (links to the apt tools are enough).
# Release key: never in Git. Pass it by environment:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
# Only one Godot process at a time: this waits for any running Godot or Unity first.
set -euo pipefail
cd "$(dirname "$0")/.."
ver=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
tag=$(echo "$ver" | tr -d .)
mkdir -p build/windows build/android
wait_free() { while pgrep -f "godot|Unity" >/dev/null; do sleep 2; done; }
wait_free; timeout 175 godot --headless --path . --import >/dev/null 2>&1 || true
wait_free; timeout 175 godot --headless --path . --export-release "Windows Desktop" build/windows/BurningBrood_Bloodlines.exe
if [ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
	wait_free; timeout 175 godot --headless --path . --export-release "Android" "build/android/BurningBrood_Bloodlines_v${tag}.apk"
	apksigner verify "build/android/BurningBrood_Bloodlines_v${tag}.apk"
else
	echo "No release key in the environment: Android build skipped."
fi
ls -l build/windows build/android
