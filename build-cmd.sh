#!/usr/bin/env bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

JSONCPP_SOURCE_DIR="jsoncpp-src"
# version number is conveniently found in a file with no other content
JSONCPP_VERSION="1.9.5" #"$(<$JSONCPP_SOURCE_DIR/version)"

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)/stage"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${JSONCPP_VERSION}.${build}" > "${stage}/VERSION.txt"

mkdir -p "$stage/lib/debug"
mkdir -p "$stage/lib/release"
mkdir -p "$stage/include/json"

pushd "$JSONCPP_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            # Debug Build
            mkdir -p "build_debug"
            pushd "build_debug"
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/debug" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            # Release Build
            mkdir -p "build_release"
            pushd "build_release"
                cmake .. -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" \
                    -DCMAKE_INSTALL_PREFIX="$(cygpath -m $stage)/release" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/debug/lib/*.lib ${stage}/lib/debug/
            cp -a ${stage}/release/lib/*.lib ${stage}/lib/release/

            # copy headers
            cp -a $stage/release/include/json/* $stage/include/json/
        ;;
        darwin*)
            export CCFLAGS="-arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
            export CXXFLAGS="$CCFLAGS"
            ./scons.py platform=darwin

            mkdir -p "$stage/lib/release"
            mkdir -p "$stage/include/json"
            cp lib/release/*.a "$stage/lib/release"
            cp include/json/*.h "$stage/include/json"
        ;;
        linux*)
            # Default target per --address-size
            opts="${TARGET_OPTS:--m$AUTOBUILD_ADDRSIZE}"
            DEBUG_COMMON_FLAGS="$opts -Og -g -fPIC"
            RELEASE_COMMON_FLAGS="$opts -O3 -g -fPIC -fstack-protector-strong"
            DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
            RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
            DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
            RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
            DEBUG_CPPFLAGS="-DPIC"
            RELEASE_CPPFLAGS="-DPIC -D_FORTIFY_SOURCE=2"

            mkdir -p "build_debug"
            pushd "build_debug"
                CFLAGS="$DEBUG_CFLAGS" \
                CXXFLAGS="$DEBUG_CXXFLAGS" \
                CPPFLAGS="$DEBUG_CPPFLAGS" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_BUILD_TYPE="Debug" \
                    -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$DEBUG_CXXFLAGS" \
                    -DCMAKE_INSTALL_PREFIX="$stage/debug" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF

                cmake --build . --config Debug
                cmake --install . --config Debug

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug
                fi
            popd

            mkdir -p "build_release"
            pushd "build_release"
                CFLAGS="$RELEASE_CFLAGS" \
                CXXFLAGS="$RELEASE_CXXFLAGS" \
                CPPFLAGS="$RELEASE_CPPFLAGS" \
                cmake .. -GNinja -DBUILD_SHARED_LIBS:BOOL=OFF -DBUILD_TESTING=ON \
                    -DCMAKE_BUILD_TYPE="Release" \
                    -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                    -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                    -DCMAKE_INSTALL_PREFIX="$stage/release" \
                    -DBUILD_SHARED_LIBS=OFF \
                    -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF

                cmake --build . --config Release
                cmake --install . --config Release

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release
                fi
            popd

            # Copy libraries
            cp -a ${stage}/debug/lib/*.a ${stage}/lib/debug/
            cp -a ${stage}/release/lib/*.a ${stage}/lib/release/

            # copy headers
            cp -a ${stage}/release/include/* ${stage}/include/
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    cp LICENSE "$stage/LICENSES/jsoncpp.txt"
popd
