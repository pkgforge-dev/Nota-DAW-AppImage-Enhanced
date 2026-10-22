#!/bin/sh

set -eu

ARCH=$(uname -m)

echo "Installing package dependencies..."
echo "---------------------------------------------------------------"
pacman -Syu --noconfirm \
	alsa-lib           \
	aspnet-targeting-pack-10.0 \
	cmake              \
	dotnet-sdk-10.0    \
	libx11             \
	libxcursor         \
	libxext            \
	libxinerama        \
	libxrandr          \
	ninja              \
	nodejs             \
	npm

echo "Installing debloated packages..."
echo "---------------------------------------------------------------"
get-debloated-pkgs --add-common --prefer-nano

echo "Building the native engine..."
echo "---------------------------------------------------------------"
git clone https://github.com/nota-daw/nota.git ./nota-src && (
	cd ./nota-src

	git fetch --tags origin
	TAG=$(git tag --sort=-v:refname | grep -vi 'rc\|alpha\|beta\|nightly' | head -1)
	git checkout "$TAG"
	echo "${TAG#v}" > ~/version

	git submodule update --init --recursive

	# The engine is a .so that gets loaded into the AppImage, statically link
	# libstdc++/libgcc so it doesn't demand the build host's C++ runtime
	cmake -G Ninja -S src/native/nota.engine -B ./build-native \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON \
		-DCMAKE_SHARED_LINKER_FLAGS="-static-libstdc++ -static-libgcc" \
		-DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"
	cmake --build ./build-native --parallel
)

echo "Publishing Nota as a self-contained .NET app..."
echo "---------------------------------------------------------------"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export DOTNET_NOLOGO=1

case "$ARCH" in
	x86_64)  rid=linux-x64;;
	aarch64) rid=linux-arm64;;
	*) echo "Unsupported arch: $ARCH" >&2; exit 1;;
esac

dotnet publish ./nota-src/src/managed/Nota.App \
	-c Release                          \
	-r "$rid"                           \
	--self-contained true               \
	"-p:NotaNativeDir=$PWD/nota-src/build-native" \
	-p:DebugType=none                   \
	-p:DebugSymbols=false               \
	-o ./nota-publish

# dlopen'd lazily only when tracing, would drag in liblttng-ust
rm -f ./nota-publish/libcoreclrtraceptprovider.so

# Ship one HarfBuzz: SkiaSharp's libHarfBuzzSharp.so exports the same hb_* symbols
# as the host's libharfbuzz.so.0, so one frees what the other allocated and the
# first launch dies with 'free(): invalid pointer'
# https://github.com/lseurttyuu/GPU-T/issues/110
cp -v /usr/lib/libharfbuzz.so ./nota-publish/libharfbuzz.so.0
rm -f ./nota-publish/libHarfBuzzSharp.so
ln -s libharfbuzz.so.0 ./nota-publish/libHarfBuzzSharp.so

mkdir -p ./AppDir/bin
cp -a ./nota-publish/. ./AppDir/bin
