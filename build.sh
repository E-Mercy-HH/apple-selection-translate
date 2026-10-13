#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
build_dir="${project_dir}/.build"
app_dir="${project_dir}/dist/AppleSelectionTranslate.app"
binary_dir="${app_dir}/Contents/MacOS"
resource_dir="${app_dir}/Contents/Resources"
sdk_args=()
if [[ -n "${MACOS_SDK_PATH:-}" ]]; then
    sdk_args=(-sdk "${MACOS_SDK_PATH}")
fi

mkdir -p "${build_dir}/module-cache" "${binary_dir}" "${resource_dir}"
cp "${project_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
cp "${project_dir}/Resources/AppIcon.icns" "${resource_dir}/AppIcon.icns"
/usr/bin/plutil -lint "${app_dir}/Contents/Info.plist"

/usr/bin/xcrun swiftc \
    "${sdk_args[@]}" \
    -swift-version 6 \
    -parse-as-library \
    -target arm64-apple-macosx26.4 \
    -module-cache-path "${build_dir}/module-cache" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework NaturalLanguage \
    -framework SwiftUI \
    -framework Translation \
    "${project_dir}"/Sources/*.swift \
    -o "${binary_dir}/AppleSelectionTranslate"

# An ad-hoc signature gives this local build an app identity without a certificate or Keychain access.
/usr/bin/codesign --force --sign - --timestamp=none "${app_dir}"

print "Built ${app_dir}"
