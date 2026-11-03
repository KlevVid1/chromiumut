#!/bin/sh

echo "========================================" 
echo "Launcher started at $(date)"
echo "========================================"

CURRENT_UID=$(id -u)

# Fix display scaling conflict:
# GDK_SCALE was previously hardcoded to 3, which caused severe coordinate offsets
# on X11 and prevented taps on top-right buttons (3-dots menu and >> overflow) from registering.
export GDK_SCALE=1
export GDK_DPI_SCALE=1

export GTK_IM_MODULE=Maliit
export GTK_IM_MODULE_FILE=$PWD/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/immodules.cache
export GDK_BACKEND=x11 
export DISABLE_WAYLAND=1 
unset WAYLAND_DISPLAY  # Isolate from Wayland to ensure Ozone uses X11 popups cleanly
export DCONF_PROFILE=/nonexistent
export XDG_CONFIG_HOME="${HOME:-/home/phablet}/.config/chromiumut.shapa"
mkdir -p "$XDG_CONFIG_HOME"

export LD_LIBRARY_PATH=$PWD/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH

# Detect Maliit socket
if [ -S "/run/user/$CURRENT_UID/maliit" ]; then
    export MALIIT_SOCKET_ADDRESS="unix:path=/run/user/$CURRENT_UID/maliit"
elif [ -S "/run/user/32011/maliit" ]; then
    export MALIIT_SOCKET_ADDRESS="unix:path=/run/user/32011/maliit"
fi

# Detect PulseAudio server for audio playback and microphone capture
if [ -n "$XDG_RUNTIME_DIR" ] && [ -S "$XDG_RUNTIME_DIR/pulse/native" ]; then
    export PULSE_SERVER="unix:$XDG_RUNTIME_DIR/pulse/native"
elif [ -S "/run/user/$CURRENT_UID/pulse/native" ]; then
    export PULSE_SERVER="unix:/run/user/$CURRENT_UID/pulse/native"
fi

export GTK_MODULES=gail:atk-bridge:maliitplatforminputcontextplugin
export QT_IM_MODULE=maliit
export XMODIFIERS=@im=Maliit

echo "Environment variables set"
echo "GTK_IM_MODULE=$GTK_IM_MODULE"
echo "GTK_IM_MODULE_FILE=$GTK_IM_MODULE_FILE"
echo "LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

if [ -z "$DISPLAY" ]; then
    echo "DISPLAY is empty, detecting X11 display..."
    i=0
    while [ -e "/tmp/.X11-unix/X$i" ] ; do 
        i=$(( i + 1 ))
    done
    i=$(( i - 1 ))
    display=":$i"
    export DISPLAY=$display
    echo "Set DISPLAY=$DISPLAY"
else
    echo "DISPLAY already set to: $DISPLAY"
fi

export PATH=$PWD/bin:$PATH
echo "PATH updated: $PATH"

# Load optional user configuration for scale, user-agent, homepage, or custom flags
CONFIG_FILE="$XDG_CONFIG_HOME/chromiumut.conf"
if [ -f "$CONFIG_FILE" ]; then
    echo "Loading user config from $CONFIG_FILE"
    . "$CONFIG_FILE"
fi

# Scaling resolution
scale=""
if [ -n "$SCALE" ]; then
    scale="$SCALE"
    echo "Scale override from config: $scale"
elif [ -f "./utils/get-scale.sh" ]; then
    scale=$(./utils/get-scale.sh 2>/dev/null)
    echo "Scale retrieved: $scale"
fi

if [ -z "$scale" ]; then
    echo "Warning: scale not determined, defaulting to 2.0"
    scale="2.0"
fi

dpioptions="--high-dpi-support=1 --force-device-scale-factor=$scale"
if [ -n "$GRID_UNIT_PX" ]; then
    dpioptions="$dpioptions --grid-unit-px=$GRID_UNIT_PX"
fi

# UI & Touch fixes:
# 1. Force Ozone to X11 so menus/popups use native X11 windows in XWayland
# 2. Use --touch-events=auto instead of forcing enabled (forcing enabled breaks MenuButton/toolbar clicks)
# 3. Suppress first run screens with --no-first-run --no-default-browser-check
uioptions="--ozone-platform=x11 --touch-events=auto --no-first-run --no-default-browser-check"

# Hardware Acceleration & GPU flags:
# - Do NOT force --use-gl=egl on X11, as direct EGL creation on X11 windows fails on mobile drivers
#   and forces a fallback to SwiftShader (CPU rendering). Letting Chromium auto-negotiate or use ANGLE
#   enables real hardware acceleration on Mesa/libhybris.
# - Force-enable GPU rasterization, zero-copy, and native GPU memory buffers.
gpuoptions="--no-sandbox --test-type --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --enable-native-gpu-memory-buffers --enable-features=UseSkiaRenderer,CanvasOopRasterization,AcceleratedVideoDecodeLinuxGL,AcceleratedVideoDecodeLinuxZeroCopyGL,AcceleratedVideoEncoder,OverlayScrollbar,kEnableQuic,OverlayScrollbarFlashAfterAnyScrollUpdate,OverlayScrollbarFlashWhenMouseEnter --enable-smooth-scrolling --disable-low-res-tiling --enable-oop-rasterization --password-store=basic"

# Custom GL backend override if user configured it
if [ -n "$GL_BACKEND" ]; then
    gpuoptions="$gpuoptions --use-gl=$GL_BACKEND"
fi

# Modern mobile User-Agent without WebView identifiers ('wv', 'Version/4.0')
# This allows Google Account login and prevents "Cannot login in my account" blocks
DEFAULT_UA="Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36"
CURRENT_UA="${USER_AGENT:-$DEFAULT_UA}"

# Mobile-adapted start page:
# The desktop New Tab Page (chrome://newtab) is non-responsive on mobile screens.
# Setting a responsive start page (e.g. Google Mobile Search) provides an adapted mobile start experience.
DEFAULT_START_PAGE="https://www.google.com"
START_PAGE="${HOMEPAGE:-$DEFAULT_START_PAGE}"

echo "Checking for Chrome binary..."
if [ -f "./usr/lib/chromium-browser/chrome" ]; then
    echo "Chrome found, launching..."
else
    echo "ERROR: Chrome binary not found at ./usr/lib/chromium-browser/chrome"
fi

# If launched without URL arguments, open the mobile-adapted start page
if [ $# -eq 0 ]; then
    set -- "$START_PAGE"
fi

initpwd=$PWD
echo "Starting Chrome with start page: $1"
exec $initpwd/usr/lib/chromium-browser/chrome --homepage="$START_PAGE" --user-agent="$CURRENT_UA" $dpioptions $uioptions $gpuoptions $EXTRA_FLAGS "$@"
