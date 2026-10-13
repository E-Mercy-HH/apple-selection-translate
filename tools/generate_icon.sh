#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
source_png="${project_dir}/Resources/AppIcon-1024.png"
iconset="${project_dir}/.build/AppIcon.iconset"
output_icns="${project_dir}/Resources/AppIcon.icns"
render_binary="${project_dir}/.build/render_icon"
sdk_args=()
if [[ -n "${MACOS_SDK_PATH:-}" ]]; then
    sdk_args=(-sdk "${MACOS_SDK_PATH}")
fi

mkdir -p "${iconset}" "${project_dir}/.build/module-cache"
/usr/bin/xcrun swiftc \
    "${sdk_args[@]}" \
    -target arm64-apple-macosx26.4 \
    -module-cache-path "${project_dir}/.build/module-cache" \
    -framework AppKit \
    "${project_dir}/tools/render_icon.swift" \
    -o "${render_binary}"
"${render_binary}" "${source_png}"

for spec in \
    16:icon_16x16.png \
    32:icon_16x16@2x.png \
    32:icon_32x32.png \
    64:icon_32x32@2x.png \
    128:icon_128x128.png \
    256:icon_128x128@2x.png \
    256:icon_256x256.png \
    512:icon_256x256@2x.png \
    512:icon_512x512.png \
    1024:icon_512x512@2x.png; do
    size=${spec%%:*}
    name=${spec#*:}
    /usr/bin/sips -z "${size}" "${size}" "${source_png}" \
        --out "${iconset}/${name}" >/dev/null
done

/usr/bin/python3 "${project_dir}/tools/pack_icns.py" "${iconset}" "${output_icns}"
print "Generated ${source_png} and ${output_icns}"
