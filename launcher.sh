#!/bin/sh

echo "========================================" 
echo "Launcher started"
echo "========================================"

CURRENT_UID="${UID:-32011}"

# Fix display scaling conflict:
export GDK_SCALE=1
export GDK_DPI_SCALE=1

export GTK_IM_MODULE=Maliit
export GTK_IM_MODULE_FILE=$PWD/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/immodules.cache
export GDK_BACKEND=x11 
export DISABLE_WAYLAND=1 
unset WAYLAND_DISPLAY  # Isolate from Wayland to ensure Ozone uses X11 popups cleanly
export DCONF_PROFILE=/nonexistent

# Confine user paths and temporary socket directory to writable Click app directories (avoids AppArmor denials)
export XDG_CONFIG_HOME="${HOME:-/home/phablet}/.config/chromiumut.shapa"
export XDG_CACHE_HOME="${HOME:-/home/phablet}/.cache/chromiumut.shapa"
export TMPDIR="$XDG_CACHE_HOME"

export LD_LIBRARY_PATH=$PWD/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH

# Preload X11 popup fix:
# In Lomiri staged/phone mode, X11 override_redirect windows (such as the 3-dots menu and dropdowns)
# without WM_TRANSIENT_FOR are treated by Mir as new top-level application windows.
# This caused Lomiri to animate a stage slide transition sideways and immediately dismiss the menu.
# This library automatically marks all child/popup windows as transient for the main browser window.
if [ -f "$PWD/lib/aarch64-linux-gnu/libx11-popup-fix.so" ]; then
    export LD_PRELOAD="$PWD/lib/aarch64-linux-gnu/libx11-popup-fix.so${LD_PRELOAD:+:$LD_PRELOAD}"
    echo "Loaded X11 popup fix library"
fi

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

# Scaling resolution:
# On modern 1080p+ mobile displays, auto-density (2.54) cramps toolbar icons, creates an overflow '>>' chevron,
# and pushes the 3-dots menu directly against the Lomiri right-edge gesture zone.
# Default to scale 2.0 (or user-defined SCALE in chromiumut.conf), which ensures all toolbar buttons fit cleanly
# and gives plenty of clearance from the edge gesture barrier.
scale=""
if [ -n "$SCALE" ]; then
    scale="$SCALE"
    echo "Scale override from config: $scale"
elif [ -f "./utils/get-scale.sh" ]; then
    scale=$(./utils/get-scale.sh 2>/dev/null)
    echo "Scale retrieved: $scale"
fi

if [ -z "$scale" ]; then
    scale="2.0"
fi

case "$scale" in
    2.[3-9]*|[3-9]*)
        echo "Adjusting scale from $scale to 2.0 for phone toolbar ergonomics"
        scale="2.0"
        ;;
esac

dpioptions="--high-dpi-support=1 --force-device-scale-factor=$scale"
if [ -n "$GRID_UNIT_PX" ]; then
    dpioptions="$dpioptions --grid-unit-px=$GRID_UNIT_PX"
fi

# UI & Touch options:
# 1. Force Ozone to X11 so menus/popups use native X11 windows in XWayland
# 2. Use --top-chrome-touch-ui=enabled so toolbar buttons and touch targets are easy to tap
# 3. Use --touch-events=enabled for mobile touchscreen interaction
# 4. Suppress first run screens with --no-first-run --no-default-browser-check
uioptions="--ozone-platform=x11 --top-chrome-touch-ui=enabled --touch-events=enabled --no-first-run --no-default-browser-check"

# Hardware Acceleration & Performance flags:
# - Use --in-process-gpu to share the existing X11 display connection and eliminate GPU crash loops / 84% CPU lag
# - Enable GPU rasterization, zero-copy, and SkiaRenderer
# - Use --num-raster-threads=2 for smooth multi-threaded rendering without core exhaustion
gpuoptions="--no-sandbox --test-type --in-process-gpu --ignore-gpu-blocklist --enable-gpu-rasterization --enable-zero-copy --num-raster-threads=2 --enable-features=UseSkiaRenderer,OverlayScrollbar,kEnableQuic,OverlayScrollbarFlashAfterAnyScrollUpdate,OverlayScrollbarFlashWhenMouseEnter --enable-smooth-scrolling --disable-low-res-tiling --enable-oop-rasterization --password-store=basic"

# Custom GL backend override if user configured it
if [ -n "$GL_BACKEND" ]; then
    gpuoptions="$gpuoptions --use-gl=$GL_BACKEND"
fi

# Modern mobile User-Agent without WebView identifiers ('wv', 'Version/4.0')
# This allows Google Account login and prevents "Cannot login in my account" blocks
DEFAULT_UA="Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36"
CURRENT_UA="${USER_AGENT:-$DEFAULT_UA}"

# Mobile-adapted start page:
# Provide a fast, offline-capable, responsive mobile start page with Google search and quick links.
if [ -f "$PWD/assets/startpage.html" ]; then
    DEFAULT_START_PAGE="file://$PWD/assets/startpage.html"
else
    DEFAULT_START_PAGE="https://www.google.com"
fi
START_PAGE="${HOMEPAGE:-$DEFAULT_START_PAGE}"

echo "Checking for Chrome binary..."
if [ -f "./usr/lib/chromium-browser/chrome" ]; then
    echo "Chrome found, launching..."
else
    echo "ERROR: Chrome binary not found at ./usr/lib/chromium-browser/chrome"
fi

if [ $# -eq 0 ]; then
    set -- "$START_PAGE"
fi

initpwd=$PWD
echo "Starting Chrome with: $1"
exec $initpwd/usr/lib/chromium-browser/chrome --user-agent="$CURRENT_UA" $dpioptions $uioptions $gpuoptions $EXTRA_FLAGS "$@"
