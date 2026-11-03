#!/bin/sh

echo "========================================" 
echo "Launcher started at $(date)"
echo "========================================"

CURRENT_UID=$(id -u)

export GDK_SCALE=3
export GTK_IM_MODULE=Maliit
export GTK_IM_MODULE_FILE=$PWD/lib/aarch64-linux-gnu/gtk-3.0/3.0.0/immodules/immodules.cache
export GDK_BACKEND=x11 
export DISABLE_WAYLAND=1 
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

# Load optional user configuration for scale, user-agent, or custom flags
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

# Browser flags:
# - Removed --simulate-touch-screen-with-mouse (fixes 3-dots menu crash, popup/dropdown dismissal, and enables copy/cut/paste selection)
# - Retained --touch-events=enabled for native mobile touchscreen interaction
# - Removed --disable-frame-rate-limit and --disable-gpu-vsync (fixes excessive battery drain and GPU thermal crashes)
# - Removed VaapiVideoDecoder (unsupported on ARM64 SOCs, caused GPU crashes on Redmi Note 9 / Poco X3)
# - Removed invalid/typo flags (--adaboost, --enable-gpu-msemory-buffer-video-frames)
# - Added --password-store=basic to prevent D-Bus keyring hangs on password fields
# - Added --test-type to suppress the yellow "--no-sandbox" info banner on mobile screen
gpuoptions="--no-sandbox --test-type --ignore-gpu-blocklist --use-gl=egl --touch-events=enabled --enable-features=UseSkiaRenderer,OverlayScrollbar,kEnableQuic,OverlayScrollbarFlashAfterAnyScrollUpdate,OverlayScrollbarFlashWhenMouseEnter --enable-smooth-scrolling --disable-low-res-tiling --enable-gpu --enable-gpu-rasterization --enable-zero-copy --font-render-hinting=none --disable-font-subpixel-positioning --enable-oop-rasterization --password-store=basic"

# Modern mobile User-Agent without WebView identifiers ('wv', 'Version/4.0')
# This allows Google Account login and prevents "Cannot login in my account" blocks
DEFAULT_UA="Mozilla/5.0 (Linux; Android 15; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Mobile Safari/537.36"
CURRENT_UA="${USER_AGENT:-$DEFAULT_UA}"

echo "Checking for Chrome binary..."
if [ -f "./usr/lib/chromium-browser/chrome" ]; then
    echo "Chrome found, launching..."
else
    echo "ERROR: Chrome binary not found at ./usr/lib/chromium-browser/chrome"
fi

initpwd=$PWD
echo "Starting Chrome..."
exec $initpwd/usr/lib/chromium-browser/chrome --user-agent="$CURRENT_UA" $dpioptions $gpuoptions $EXTRA_FLAGS "$@"
