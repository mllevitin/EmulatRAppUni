#!/usr/bin/env bash
set -euo pipefail

build_type="${CMAKE_BUILD_TYPE:-Release}"
case "$build_type" in
    Release|RelWithDebInfo|Debug|MinSizeRel) ;;
    *)
        printf 'Unsupported CMAKE_BUILD_TYPE: %s\n' "$build_type" >&2
        exit 2
        ;;
esac

build_dir="/workspace/out/build/container-${build_type,,}"
cmake -S /workspace -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE="$build_type" \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    "$@"
cmake --build "$build_dir" --target Emulatr Emulatr_tests
printf '\nBuild outputs: %s/{Emulatr,Emulatr_tests}\n' "$build_dir"
