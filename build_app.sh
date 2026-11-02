#!/bin/zsh
set -eu
package_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$package_dir"
build_dir="${REUSE_BUILD_DIR:-$package_dir/.build/app}"
[[ "$build_dir" = /* ]] || build_dir="$package_dir/$build_dir"
packages_dir="${REUSE_PACKAGES_DIR:-$build_dir/packages}"
sdk="${1:-iphoneos}"
case "$sdk" in
  iphoneos) destination='generic/platform=iOS'; derived='device-build' ;;
  iphonesimulator) destination='generic/platform=iOS Simulator'; derived='simulator-build' ;;
  *) print -u2 'Usage: build_app.sh [iphoneos|iphonesimulator] [xcodebuild arguments...]'; exit 2 ;;
esac
if (( $# > 0 )); then shift; fi
mkdir -p "$build_dir"
python3 - "$build_dir" <<'CHECK_DISK'
import shutil,sys
if shutil.disk_usage(sys.argv[1]).free < 2 * 1024**3:
    raise RuntimeError('Less than 2 GiB free; app build not started')
CHECK_DISK
python3 make_notices.py --check
REUSE_BUILD_DIR="$build_dir" python3 make_project.py
app_product="$build_dir/$derived/Build/Products/Release-$sdk/ReuseLab.app"
if [[ -d "$app_product/ModelPack" || -f "$app_product/Samples/noisy16.wav" ]]; then
  # Xcode can retain removed resources in an old product. Recreate this product.
  python3 - "$app_product" <<'CLEAN_PRODUCT'
import shutil,sys
shutil.rmtree(sys.argv[1])
CLEAN_PRODUCT
fi
xcodebuild -project "$build_dir/ReuseLab.xcodeproj" -scheme ReuseLab \
  -configuration Release -sdk "$sdk" -destination "$destination" \
  -derivedDataPath "$build_dir/$derived" \
  -clonedSourcePackagesDirPath "$packages_dir" \
  -jobs 4 ARCHS=arm64 "$@"
