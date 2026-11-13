#!/usr/bin/env bash
set -euo pipefail

ndk=$(realpath "${1:?Pass Android NDK r27c for Linux}")
work=$(realpath -m "${2:?Pass a build directory}")
bin="$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin"
mkdir -p "$work/sources" "$work/output"
cd "$work/sources"

fetch() {
    local url=$1 name=$2 hash=$3
    if [[ ! -f "$name" ]]; then curl -fsSL --retry 2 "$url" -o "$name.tmp"; mv "$name.tmp" "$name"; fi
    echo "$hash  $name" | sha256sum --check
}

fetch https://download.gnome.org/sources/libxml2/2.9/libxml2-2.9.8.tar.xz libxml2.tar.xz dcca21d624bbbe094fcc104e1f15f2eacfb65aecd0e38ed220aeca56b62c81e2
fetch https://download.gnome.org/sources/libxslt/1.1/libxslt-1.1.32.tar.xz libxslt.tar.xz b7da90eaa6b0dae9e9a3769e29a757342eef0edb9a7b431424814375414422af
fetch https://download.savannah.gnu.org/releases/freetype/freetype-2.9.1.tar.gz freetype.tar.gz ec391504e55498adceb30baceebd147a6e963f636eb617424bcfc47a169898ce
fetch https://codeload.github.com/libjpeg-turbo/libjpeg-turbo/tar.gz/refs/tags/1.5.3 jpeg.tar.gz 1a17020f859cb12711175a67eab5c71fc1904e04b587046218e36106e07eabde

build_abi() (
    local abi=$1 host=$2
    local prefix="$work/$abi/prefix"
    mkdir -p "$prefix"
    cd "$work/$abi"
    for archive in libxml2.tar.xz libxslt.tar.xz freetype.tar.gz jpeg.tar.gz; do tar xf "$work/sources/$archive"; done
    export CC="$bin/$host"21-clang CXX="$bin/$host"21-clang++ AR="$bin/llvm-ar" RANLIB="$bin/llvm-ranlib"
    export CFLAGS="-O2 -fPIC" LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
    local jobs=${JOBS:-4}
    (
        cd libxml2-2.9.8
        # These symbols are unavailable in this Android configuration.
        sed -i '/^  docb[A-Za-z]*;/d; /^  xmlDllMain;/d' libxml2.syms
        ./configure --host="$host" --prefix="$prefix" --without-python --without-lzma --without-iconv
        make -j "$jobs"
        make install
    )
    (
        cd libxslt-1.1.32
        sed -i 's/^                          xmlChar \* name ATTRIBUTE_UNUSED)/                          const xmlChar * name ATTRIBUTE_UNUSED)/' libxslt/extensions.c
        ./configure --host="$host" --prefix="$prefix" --with-libxml-prefix="$prefix" --without-crypto --without-python
        make -j "$jobs"
        make install
    )
    (
        cd freetype-2.9.1
        ./configure --host="$host" --prefix="$prefix" --without-harfbuzz --without-png --without-bzip2
        make -j "$jobs"
        make install
    )
    (
        cd libjpeg-turbo-1.5.3
        autoreconf -fiv
        ./configure --host="$host" --prefix="$prefix" --libdir="$prefix/lib" --without-turbojpeg --without-simd
        make -j "$jobs"
        "$CC" -shared $LDFLAGS -Wl,-soname,libjpeg_chaquopy.so -o "$prefix/lib/libjpeg_chaquopy.so" -Wl,--whole-archive .libs/libjpeg.a -Wl,--no-whole-archive
    )
    python3 "$(dirname "$script")/build_python_native_wheels.py" "$abi" "$prefix" "$work/output"
)

script=$(realpath "${BASH_SOURCE[0]}")
build_abi arm64_v8a aarch64-linux-android >"$work/arm64_v8a.log" 2>&1 &
arm=$!
build_abi x86_64 x86_64-linux-android >"$work/x86_64.log" 2>&1 &
x86=$!
status=0
wait "$arm" || status=1
wait "$x86" || status=1
exit "$status"
