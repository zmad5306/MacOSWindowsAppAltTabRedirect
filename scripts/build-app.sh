#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
configuration="${CONFIGURATION:-release}"
app_name="Windows Alt-Tab Redirect"
bundle_path="$repo_root/dist/$app_name.app"
contents_path="$bundle_path/Contents"
swift_bin="${SWIFT_BIN:-$(command -v swift)}"
swift_args=()

# Prefer Xcode's matched compiler/SDK when xcode-select still points at a
# separately updated Command Line Tools installation.
xcode_developer_dir="/Applications/Xcode.app/Contents/Developer"
if [[ -x "$xcode_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
    swift_bin="$xcode_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    sdk_path="$xcode_developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    export SDKROOT="$sdk_path"
    export CLANG_MODULE_CACHE_PATH="$repo_root/.build/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/swiftpm-module-cache"
    swift_args=(--build-system native --disable-sandbox --sdk "$sdk_path")
fi

cd "$repo_root"
"$swift_bin" build "${swift_args[@]}" -c "$configuration" --product WindowsAltTabRedirect
bin_path="$("$swift_bin" build "${swift_args[@]}" -c "$configuration" --show-bin-path)"

/bin/rm -rf "$bundle_path"
/bin/mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
/bin/cp "$bin_path/WindowsAltTabRedirect" "$contents_path/MacOS/WindowsAltTabRedirect"
/bin/cp "$repo_root/Packaging/Info.plist" "$contents_path/Info.plist"
/usr/bin/codesign --force --deep --sign - "$bundle_path"
/usr/bin/codesign --verify --deep --strict "$bundle_path"

echo "$bundle_path"
