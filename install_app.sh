#!/bin/zsh
set -eu
package_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${REUSE_BUILD_DIR:-$package_dir/.build/app}"
[[ "$build_dir" = /* ]] || build_dir="$package_dir/$build_dir"
device_id="${1:-${REUSE_DEVICE:-}}"
if [[ -z "$device_id" ]]; then
  print -u2 'Usage: install_app.sh <device UDID/name>, or set REUSE_DEVICE'
  exit 2
fi
app_dir="$build_dir/device-build/Build/Products/Release-iphoneos/ReuseLab.app"
codesign --verify --deep --strict "$app_dir"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app_dir/Info.plist")"
xcrun devicectl device install app --device "$device_id" "$app_dir"
xcrun devicectl device process launch --device "$device_id" "$bundle_id"
