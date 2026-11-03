#!/bin/bash
set -e  # Exit immediately on error



# ========================
# PROJECT CONFIGURATION
# ========================
PROJECT_NAME="chromiumut"
SNAP_FILE="${BUILD_DIR}/chromium-desktop.snap"
EXTRACT_DIR="${BUILD_DIR}/squashfs-root"
INSTALL_DIR="${BUILD_DIR}/install"


# ========================
# STEP 1: PREPARATION
# ========================
echo "[1/9] Cleaning up..."
rm -rf "$EXTRACT_DIR" "$INSTALL_DIR"
mkdir -p "$EXTRACT_DIR" "$INSTALL_DIR"


# ========================
# STEP 2: DOWNLOAD THE LATEST Chrome SNAP USING SNAP
# ========================
echo "[2/9] Downloading latest Chromium via Snapcraft API..."
mkdir -p "$EXTRACT_DIR"

cd "${BUILD_DIR}"
SNAP_INFO=$(curl -s https://api.snapcraft.io/v2/snaps/info/chromium -H "Snap-Device-Series: 16" -H "Snap-Architecture: arm64")
DOWNLOAD_URL=$(echo "$SNAP_INFO" | jq -r '.["channel-map"][] 
            | select(.channel.architecture=="arm64" and .channel.name=="stable") 
            | .download.url'
            )
EXPECTED_SIZE=$(echo "$SNAP_INFO" | jq -r '.["channel-map"][] 
            | select(.channel.architecture=="arm64" and .channel.name=="stable") 
            | .download.size'
            )

if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" = "null" ]; then
    echo "ERROR: Failed to fetch Chromium snap download URL from Snapcraft API." >&2
    exit 1
fi

NEED_DOWNLOAD=true
if [ -f "$SNAP_FILE" ] && [ -n "$EXPECTED_SIZE" ] && [ "$EXPECTED_SIZE" != "null" ]; then
    CURRENT_SIZE=$(stat -c%s "$SNAP_FILE" 2>/dev/null || wc -c < "$SNAP_FILE")
    if [ "$CURRENT_SIZE" -eq "$EXPECTED_SIZE" ]; then
        echo "Cached snap package verified: $CURRENT_SIZE bytes."
        NEED_DOWNLOAD=false
    fi
fi

if [ "$NEED_DOWNLOAD" = true ]; then
    echo "Downloading snap from $DOWNLOAD_URL..."
    curl -L -f -o "$SNAP_FILE" "$DOWNLOAD_URL"

    if [ -n "$EXPECTED_SIZE" ] && [ "$EXPECTED_SIZE" != "null" ]; then
        ACTUAL_SIZE=$(stat -c%s "$SNAP_FILE" 2>/dev/null || wc -c < "$SNAP_FILE")
        if [ "$ACTUAL_SIZE" -ne "$EXPECTED_SIZE" ]; then
            echo "ERROR: Downloaded snap size ($ACTUAL_SIZE) does not match expected size ($EXPECTED_SIZE)." >&2
            exit 1
        fi
        echo "Snap package integrity check: size $ACTUAL_SIZE bytes matches."
    fi
fi

# ========================
# STEP 3: EXTRACTION
# ========================
echo "[3/9] Extracting .snap package..."
rm -rf "$EXTRACT_DIR"
echo "Extracting $SNAP_FILE to $EXTRACT_DIR"
unsquashfs "$SNAP_FILE"
rm -f "$EXTRACT_DIR/usr/bin/xdg-email"

# ===================================
# STEP 4: BUILD THE FAKE xdg-open
# ===================================
echo "[4/9] Building fake xdg-open ..."
cp -r "${ROOT}/utils/xdg-open/" "${BUILD_DIR}/"
cd "${BUILD_DIR}/xdg-open/"
mkdir -p build
cd build
cmake ..
make

# ===================================
# STEP 5: Install DEPENDENCIES
# ===================================
echo "[5/9] Install dependencies..."

cd "${BUILD_DIR}"
DEPENDENCIES="libhybris-utils xdotool libmaliit-glib2 libxdo3 x11-utils"

for dep in $DEPENDENCIES ; do
    apt download "$dep:arm64"
    mv "${dep}_"*.deb "${dep}.deb"
    rm -rf "${dep}.deb_extract_chsdjksd"
    mkdir "${dep}.deb_extract_chsdjksd"
    dpkg-deb -x "${dep}.deb" "${dep}.deb_extract_chsdjksd"
done

# =================================================
# STEP 6: Downloading maliit-inputcontext-gtk3
# =================================================

echo "[6/9] Building maliit-inputcontext-gtk3 and download dependencies..."


PKGNAME="maliit-inputcontext-gtk"
VERSION="0.99.1+git20151116.72d7576"
ORIG_URL="https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/maliit-inputcontext-gtk/0.99.1+git20151116.72d7576-3build3/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576.orig.tar.xz"
DEBIAN_URL="https://launchpad.net/ubuntu/+archive/primary/+sourcefiles/maliit-inputcontext-gtk/0.99.1+git20151116.72d7576-3build3/maliit-inputcontext-gtk_0.99.1+git20151116.72d7576-3build3.debian.tar.xz"



WORKDIR_MALIIT="${PKGNAME}-${VERSION}"
rm -rf "$WORKDIR_MALIIT"
mkdir -p "$WORKDIR_MALIIT"
cd "$WORKDIR_MALIIT"

echo "📦 Download sources..."
wget -q "$ORIG_URL" -O "${PKGNAME}_${VERSION}.orig.tar.xz"
wget -q "$DEBIAN_URL" -O "${PKGNAME}_${VERSION}.debian.tar.xz"

echo "📂 Extract original code..."
tar -xf "${PKGNAME}_${VERSION}.orig.tar.xz"
SRC_DIR_MALIIT=$(tar -tf "${PKGNAME}_${VERSION}.orig.tar.xz" | head -1 | cut -d/ -f1)

echo "📂 Extract debian files..."
tar -xf "${PKGNAME}_${VERSION}.debian.tar.xz" -C "$SRC_DIR_MALIIT"

echo "Apply patch..."
cd "${BUILD_DIR}/$SRC_DIR_MALIIT/maliit-inputcontext-gtk-$VERSION/"
patch -p1 < "${ROOT}/patches/maliit-inputcontext-gtk/client-imcontext-gtk.c.patch"

echo "Compile..."
EDITOR=true dpkg-source --commit . fix-keyboard
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -us -uc -a arm64

echo "[7/9] Copying files..." 


echo "Copying dependencies..."
cd "${BUILD_DIR}"
rm -rf "$INSTALL_DIR/lib"
mkdir -p "$INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/"
for DIR in *_extract_chsdjksd; do
    if [ -d "$DIR/usr/lib/aarch64-linux-gnu/" ]; then
        cp -r "$DIR/usr/lib/aarch64-linux-gnu/"* "$INSTALL_DIR/lib/aarch64-linux-gnu/"
    fi
done

echo "done"
# Copy binaries in bin/
mkdir -p "$INSTALL_DIR/bin"
cp *_extract_chsdjksd/usr/bin/xdotool "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/getprop "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/xprop "$INSTALL_DIR/bin/"
cp *_extract_chsdjksd/usr/bin/xev "$INSTALL_DIR/bin/"

echo "Copying maliit-input-context..."
cp "${ROOT}/patches/maliit-inputcontext-gtk/immodules.cache" "$INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/"
cp "${BUILD_DIR}/$WORKDIR_MALIIT/maliit-inputcontext-gtk-$VERSION/builddir/gtk3/gtk-3.0/im-maliit.so" "$INSTALL_DIR/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/"

echo "Building X11 popup fix library for aarch64..."
CROSS_CC="aarch64-linux-gnu-gcc"
if ! command -v "$CROSS_CC" >/dev/null 2>&1; then
    CROSS_CC="gcc"
fi
$CROSS_CC -shared -fPIC -O2 -Wall "${ROOT}/patches/x11_popup_fix.c" -o "$INSTALL_DIR/lib/aarch64-linux-gnu/libx11-popup-fix.so" -ldl




echo "[8/9] Copying Chrome to $INSTALL_DIR/usr..."
mkdir -p "$INSTALL_DIR/usr/"
cp -r "$EXTRACT_DIR/usr/" "$INSTALL_DIR/" || true


mkdir -p "$INSTALL_DIR/utils/"
cp "${ROOT}/utils/sleep.sh" "$INSTALL_DIR/utils/"
cp "${ROOT}/utils/get-scale.sh" "$INSTALL_DIR/utils/"
cp "${BUILD_DIR}/xdg-open/build/xdg-open" "$INSTALL_DIR/bin/"

# Copy project files
mkdir -p "$INSTALL_DIR/assets/"
cp -r "${ROOT}/assets/"* "$INSTALL_DIR/assets/" 2>/dev/null || true
cp "${ROOT}/launcher.sh" "$INSTALL_DIR/"
cp "${ROOT}/chromiumut.desktop" "$INSTALL_DIR/"
cp "${ROOT}/icon.png" "$INSTALL_DIR/"
cp "${ROOT}/icon-splash.png" "$INSTALL_DIR/"
cp "${ROOT}/manifest.json" "$INSTALL_DIR/"
cp "${ROOT}/chromiumut.apparmor" "$INSTALL_DIR/"

chmod +x "$INSTALL_DIR/utils/sleep.sh"
chmod +x "$INSTALL_DIR/utils/get-scale.sh"
chmod +x "$INSTALL_DIR/launcher.sh"
chmod +x "$INSTALL_DIR/usr/lib/chromium-browser/chrome" 2>/dev/null || true
chmod +x "$INSTALL_DIR/usr/lib/chromium-browser/chrome_crashpad_handler" 2>/dev/null || true

# ========================
# STEP 9: BUILD THE CLICK PACKAGE
# ========================
echo "[9/9] Preparation done, building the .click package..."
