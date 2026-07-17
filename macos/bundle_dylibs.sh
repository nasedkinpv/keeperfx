#!/bin/bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 APP_BUNDLE CODESIGN_IDENTITY" >&2
    exit 2
fi

app_bundle=$1
codesign_identity=$2
executable="$app_bundle/Contents/MacOS/keeperfx"
frameworks="$app_bundle/Contents/Frameworks"
queue=("$executable")
homebrew_prefix=${HOMEBREW_PREFIX:-$(brew --prefix)}

mkdir -p "$frameworks"
codesign --remove-signature "$executable" 2>/dev/null || true

# Homebrew's SDL2 compatibility library loads SDL3 at runtime, so SDL3 does
# not appear in the normal Mach-O dependency list.
sdl3_library="$homebrew_prefix/opt/sdl3/lib/libSDL3.0.dylib"
if [[ -e "$sdl3_library" ]]; then
    cp -L "$sdl3_library" "$frameworks/libSDL3.0.dylib"
    chmod u+w "$frameworks/libSDL3.0.dylib"
    codesign --remove-signature "$frameworks/libSDL3.0.dylib" 2>/dev/null || true
    ln -s libSDL3.0.dylib "$frameworks/libSDL3.dylib"
    queue+=("$frameworks/libSDL3.0.dylib")
fi

dependencies() {
    otool -L "$1" | awk 'NR > 1 { print $1 }'
}

while [[ ${#queue[@]} -gt 0 ]]; do
    current=${queue[0]}
    queue=("${queue[@]:1}")

    if [[ $(basename "$current") == libSDL2-2.0.0.dylib ]]; then
        install_name_tool -rpath '@loader_path/../../../../opt/sdl3/lib' '@loader_path' "$current"
    fi

    while IFS= read -r dependency; do
        case "$dependency" in
            /opt/homebrew/*)
                library_name=$(basename "$dependency")
                bundled_library="$frameworks/$library_name"
                if [[ ! -e "$bundled_library" ]]; then
                    cp -L "$dependency" "$bundled_library"
                    chmod u+w "$bundled_library"
                    codesign --remove-signature "$bundled_library" 2>/dev/null || true
                    queue+=("$bundled_library")
                fi
                install_name_tool -change "$dependency" "@rpath/$library_name" "$current"
                ;;
            @rpath/*)
                library_name=${dependency#@rpath/}
                bundled_library="$frameworks/$library_name"
                if [[ ! -e "$bundled_library" ]]; then
                    source_library=$(find -L "$homebrew_prefix/opt" -type f -name "$library_name" -print -quit)
                    if [[ -z "$source_library" ]]; then
                        echo "cannot resolve $dependency required by $current" >&2
                        exit 1
                    fi
                    cp -L "$source_library" "$bundled_library"
                    chmod u+w "$bundled_library"
                    codesign --remove-signature "$bundled_library" 2>/dev/null || true
                    queue+=("$bundled_library")
                fi
                ;;
        esac
    done < <(dependencies "$current")
done

for library in "$frameworks"/*.dylib; do
    install_name_tool -id "@rpath/$(basename "$library")" "$library"
done

if ! otool -l "$executable" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$executable"
fi

for file in "$executable" "$frameworks"/*.dylib; do
    if dependencies "$file" | grep -q '^/opt/homebrew/'; then
        echo "unbundled Homebrew dependency in $file" >&2
        exit 1
    fi
    while IFS= read -r dependency; do
        case "$dependency" in
            @rpath/*)
                if [[ ! -e "$frameworks/${dependency#@rpath/}" ]]; then
                    echo "unresolved dependency $dependency in $file" >&2
                    exit 1
                fi
                ;;
        esac
    done < <(dependencies "$file")
done

codesign_options=(--force --sign "$codesign_identity")
if [[ "$codesign_identity" == - ]]; then
    codesign_options+=(--timestamp=none)
else
    codesign_options+=(--options runtime --timestamp)
fi

while IFS= read -r -d '' library; do
    codesign "${codesign_options[@]}" "$library"
done < <(find "$frameworks" -type f -name '*.dylib' -print0)
codesign "${codesign_options[@]}" "$executable"
codesign "${codesign_options[@]}" "$app_bundle"
codesign --verify --deep --strict "$app_bundle"
