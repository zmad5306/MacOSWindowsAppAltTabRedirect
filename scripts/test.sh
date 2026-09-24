#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
swift_bin="${SWIFT_BIN:-$(command -v swift)}"
swift_args=()
xctest_bin=""

xcode_developer_dir="/Applications/Xcode.app/Contents/Developer"
if [[ -x "$xcode_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift" ]]; then
    swift_bin="$xcode_developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift"
    xctest_bin="$xcode_developer_dir/usr/bin/xctest"
    sdk_path="$xcode_developer_dir/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
    developer_library="$xcode_developer_dir/Platforms/MacOSX.platform/Developer"
    export SDKROOT="$sdk_path"
    export CLANG_MODULE_CACHE_PATH="$repo_root/.build/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/swiftpm-module-cache"
    swift_args=(
        --build-system native
        --disable-sandbox
        --sdk "$sdk_path"
        -Xswiftc -I -Xswiftc "$developer_library/usr/lib"
        -Xswiftc -F -Xswiftc "$developer_library/Library/Frameworks"
        -Xlinker -L -Xlinker "$developer_library/usr/lib"
        -Xlinker -F -Xlinker "$developer_library/Library/Frameworks"
        -Xlinker -framework -Xlinker XCTest
        -Xlinker -lXCTestSwiftSupport
        -Xlinker -rpath -Xlinker "$developer_library/Library/Frameworks"
        -Xlinker -rpath -Xlinker "$developer_library/usr/lib"
    )
fi

cd "$repo_root"
if [[ -n "$xctest_bin" ]]; then
    "$swift_bin" build "${swift_args[@]}" --build-tests
    bin_path="$("$swift_bin" build "${swift_args[@]}" --show-bin-path)"
    test_bundle="$bin_path/WindowsAltTabRedirectPackageTests.xctest"
    DYLD_FRAMEWORK_PATH="$developer_library/Library/Frameworks" \
        DYLD_LIBRARY_PATH="$developer_library/usr/lib" \
        "$xctest_bin" "$test_bundle"
else
    "$swift_bin" test
fi
