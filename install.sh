#!/usr/bin/env bash
# Umbra: a monochrome KDE Plasma 6 rice
# Installer for Arch-based systems (Arch, CachyOS, EndeavourOS, ...)

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.local/state/umbra-backup/$(date +%Y%m%d-%H%M%S)"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

info() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  -> %s\033[0m\n' "$*"; }

backup() {
    if [[ -e "$1" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$1" "$BACKUP_DIR/"
        warn "Backed up $1 to $BACKUP_DIR"
    fi
}

# ---------------------------------------------------------------- checks

if ! command -v pacman >/dev/null; then
    echo "This installer only supports Arch-based systems." >&2
    exit 1
fi

if command -v yay >/dev/null; then
    AUR=yay
elif command -v paru >/dev/null; then
    AUR=paru
else
    echo "Please install an AUR helper (yay or paru) first." >&2
    exit 1
fi

if [[ "${XDG_CURRENT_DESKTOP:-}" != *KDE* ]]; then
    warn "You don't seem to be in a KDE Plasma session. Settings will still be written,"
    warn "but some of them only apply after you log into Plasma."
fi

# -------------------------------------------------------------- packages

info "Installing packages from the official repos"
sudo pacman -S --needed \
    git base-devel \
    ttf-jetbrains-mono ttf-jetbrains-mono-nerd \
    ghostty

info "Installing AUR packages (Klassy, YAMIS icons, konsave)"
"$AUR" -S --needed klassy yamis-icon-theme-git konsave

info "Installing Quick Tile Gaps KWin script"
git clone --depth=1 https://github.com/NasreddinHodja/quicktilegaps.git "$BUILD_DIR/quicktilegaps"
kpackagetool6 --type=KWin/Script -i "$BUILD_DIR/quicktilegaps" 2>/dev/null \
    || kpackagetool6 --type=KWin/Script -u "$BUILD_DIR/quicktilegaps"

# ----------------------------------------------------------------- files

info "Copying config files"
mkdir -p "$HOME/.local/share/color-schemes" "$HOME/.local/share/konsole" "$HOME/.config/ghostty"

cp "$REPO_DIR/colors/Umbra.colors" "$HOME/.local/share/color-schemes/"
cp "$REPO_DIR/konsole/Umbra.colorscheme" "$HOME/.local/share/konsole/"

backup "$HOME/.config/ghostty/config.ghostty"
cp "$REPO_DIR/ghostty/config.ghostty" "$HOME/.config/ghostty/config.ghostty"
# An old-style config file next to config.ghostty gets loaded as well, so move it away
if [[ -f "$HOME/.config/ghostty/config" ]]; then
    backup "$HOME/.config/ghostty/config"
    rm "$HOME/.config/ghostty/config"
fi

# Optional: exported Klassy settings, if they exist in the repo
if [[ -f "$REPO_DIR/klassy/klassyrc" ]]; then
    mkdir -p "$HOME/.config/klassy"
    backup "$HOME/.config/klassy/klassyrc"
    cp "$REPO_DIR/klassy/klassyrc" "$HOME/.config/klassy/klassyrc"
fi

# --------------------------------------------------------------- apply

info "Applying settings"

backup "$HOME/.config/kdeglobals"
backup "$HOME/.config/kwinrc"

# Colors (switch away first so Plasma really reloads the file)
plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
plasma-apply-colorscheme Umbra || warn "Could not apply color scheme, select 'Umbra' in System Settings"

# Application style and Plasma style: Breeze, the only styles that fully follow the color scheme
kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
plasma-apply-desktoptheme default >/dev/null 2>&1 || warn "Could not set Plasma style, select Breeze in System Settings"

# Window decoration: Klassy without side and bottom borders
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.klassy
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme Klassy
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSize None
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key BorderSizeAuto false

# KWin script for gaps around maximized and tiled windows
kwriteconfig6 --file kwinrc --group Plugins --key quicktilegapsEnabled true

# Icon theme
ICON_THEME="$(find /usr/share/icons -maxdepth 1 -iname '*monochrome*' -printf '%f\n' | head -n1)"
if [[ -n "$ICON_THEME" && -x /usr/lib/plasma-changeicons ]]; then
    /usr/lib/plasma-changeicons "$ICON_THEME" || warn "Could not set icon theme, select YAMIS in System Settings"
else
    warn "Could not set icon theme automatically, select YAMIS in System Settings > Icons"
fi

# Dolphin can keep its own color scheme override, which ignores the system scheme
if [[ -f "$HOME/.config/dolphinrc" ]]; then
    sed -i '/^ColorScheme=/d' "$HOME/.config/dolphinrc"
fi

qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# --------------------------------------------------------------- ghostty

info "Enabling the Ghostty background service (instant new windows)"
systemctl --user enable --now app-com.mitchellh.ghostty.service \
    || warn "Could not start the Ghostty service, try again after logging in to Plasma"

# --------------------------------------------------------------- konsave

KNSV="$(find "$REPO_DIR/konsave" -maxdepth 1 -name '*.knsv' | head -n1)"
if [[ -n "$KNSV" ]]; then
    info "Importing the konsave profile (panel layout)"
    konsave -i "$KNSV" || warn "konsave import failed or the profile already exists"
    warn "Apply it with 'konsave -l' to see its name, then 'konsave -a <name>'"
fi

# ------------------------------------------------------------------ done

info "Done!"
cat << 'EOF'

A few things still have to be done by hand, see the README:
  - Fonts: System Settings > Fonts > Adjust All Fonts > JetBrains Mono 10
  - Panels: top bar and floating dock (unless you applied the konsave profile)
  - Klassy: turn on the window outline with the plain accent color
  - Quick Tile Gaps: set the gap size in System Settings > KWin Scripts
  - Wallpaper: pick any greyscale photo you like

Log out and back in once so every app picks up the new style.
EOF
