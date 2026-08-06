#!/usr/bin/env bash
#
# fedora-install-apps.sh
# Cài các app mặc định sau khi post-install Fedora
#
# Yêu cầu chạy sau fedora-post-install.sh (đã có RPM Fusion, Flathub, dnf-plugins-core...)
# Chạy: chmod +x fedora-install-apps.sh && ./fedora-install-apps.sh

set -euo pipefail

FISH_CONFIG="$HOME/.config/fish/config.fish"
LOG_FILE="/var/log/fedora-install-apps.log"

log() {
    echo -e "\n\033[1;32m==> $1\033[0m" | sudo tee -a "$LOG_FILE" >/dev/null
    echo -e "\n\033[1;32m==> $1\033[0m"
}

confirm() {
    read -rp "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

if [[ $EUID -eq 0 ]]; then
    echo "Đừng chạy script bằng root. Chạy với user thường, script sẽ tự sudo khi cần." >&2
    exit 1
fi

sudo touch "$LOG_FILE"
mkdir -p "$(dirname "$FISH_CONFIG")"
touch "$FISH_CONFIG"

# ------------------------- 1. Steam -------------------------
log "1. Cài Steam"
# Cần RPM Fusion nonfree đã enable (xem script post-install)
if ! rpm -q steam &>/dev/null; then
    sudo dnf install -y steam
else
    echo "Steam đã cài, bỏ qua."
fi

# ------------------------- 2. Discord -------------------------
log "2. Cài Discord (gói native qua dnf, từ Terra repo)"
if ! rpm -q discord &>/dev/null; then
    sudo dnf install -y discord
else
    echo "Discord đã cài, bỏ qua."
fi

# ------------------------- 3. Brave Origin Nightly -------------------------
log "3. Cài Brave Origin Nightly"
sudo dnf install -y dnf-plugins-core
if ! dnf repolist 2>/dev/null | grep -qi "brave-browser-nightly"; then
    sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-nightly.s3.brave.com/brave-browser-nightly.repo
else
    echo "Repo Brave nightly đã có, bỏ qua bước add repo."
fi
if ! rpm -q brave-origin-nightly &>/dev/null; then
    sudo dnf install -y brave-origin-nightly
else
    echo "brave-origin-nightly đã cài, bỏ qua."
fi

# ------------------------- 4. kitty + fish + starship -------------------------
log "4. Cài kitty, fish, starship"
sudo dnf install -y kitty fish

if ! dnf copr list 2>/dev/null | grep -qi "atim/starship"; then
    sudo dnf copr enable -y atim/starship
fi
if ! rpm -q starship &>/dev/null; then
    sudo dnf install -y starship
else
    echo "starship đã cài, bỏ qua."
fi

if ! grep -q "starship init fish" "$FISH_CONFIG"; then
    echo 'starship init fish | source' >>"$FISH_CONFIG"
    echo "Đã thêm 'starship init fish | source' vào $FISH_CONFIG"
else
    echo "starship init đã có trong $FISH_CONFIG, bỏ qua."
fi

if confirm "Đổi shell mặc định sang fish cho user $(whoami)?"; then
    FISH_BIN="$(command -v fish)"
    if ! grep -qx "$FISH_BIN" /etc/shells; then
        echo "$FISH_BIN" | sudo tee -a /etc/shells >/dev/null
    fi
    chsh -s "$FISH_BIN"
    echo "Đã đổi shell mặc định. Cần đăng xuất/đăng nhập lại để có hiệu lực."
fi

# ------------------------- 5. Bộ gõ tiếng Việt (fcitx5-lotus) -------------------------
log "5. Cài bộ gõ tiếng Việt fcitx5-lotus"
RELEASEVER="$(grep '^VERSION_ID=' /etc/os-release | cut -d'=' -f2 | tr -d '"')"
echo "Fedora release: $RELEASEVER"

sudo rpm --import https://fcitx5-lotus.pages.dev/pubkey.gpg

if ! dnf repolist 2>/dev/null | grep -qi "fcitx5-lotus"; then
    sudo dnf config-manager addrepo \
        --from-repofile="https://fcitx5-lotus.pages.dev/rpm/fedora/fcitx5-lotus-${RELEASEVER}.repo"
else
    echo "Repo fcitx5-lotus đã có, bỏ qua bước add repo."
fi

if ! rpm -q fcitx5-lotus &>/dev/null; then
    sudo dnf install -y fcitx5-lotus
else
    echo "fcitx5-lotus đã cài, bỏ qua."
fi

CURRENT_USER="$(whoami)"
if ! systemctl is-enabled "fcitx5-lotus-server@${CURRENT_USER}.service" &>/dev/null; then
    if ! sudo systemctl enable --now "fcitx5-lotus-server@${CURRENT_USER}.service"; then
        echo "Enable trực tiếp thất bại, thử chạy systemd-sysusers rồi enable lại..."
        sudo systemd-sysusers
        sudo systemctl enable --now "fcitx5-lotus-server@${CURRENT_USER}.service"
    fi
else
    echo "Service fcitx5-lotus-server đã enable, bỏ qua."
fi

# Tắt ibus nếu đang chạy để tránh xung đột
if command -v ibus &>/dev/null; then
    ibus exit &>/dev/null || true
fi
pkill ibus-daemon &>/dev/null || true

ENV_BLOCK='if status is-login
    set -Ux GTK_IM_MODULE fcitx
    set -Ux QT_IM_MODULE fcitx
    set -Ux XMODIFIERS @im=fcitx
    set -Ux SDL_IM_MODULE fcitx
    set -Ux GLFW_IM_MODULE ibus
end'

if ! grep -q "GTK_IM_MODULE fcitx" "$FISH_CONFIG"; then
    echo "$ENV_BLOCK" >>"$FISH_CONFIG"
    echo "Đã thêm biến môi trường input method vào $FISH_CONFIG"
else
    echo "Biến môi trường input method đã có trong $FISH_CONFIG, bỏ qua."
fi

# ------------------------- 6. Zed editor -------------------------
log "6. Cài Zed editor (bản native qua script cài chính thức)"
if ! command -v zed &>/dev/null; then
    curl -f https://zed.dev/install.sh | sh
else
    echo "Zed đã cài, bỏ qua."
fi

# ------------------------- 7. Font + cursor theme (chỉ tải, không apply) -------------------------
log "7. Tải JetBrains Mono font + Bibata cursor theme (chưa apply theme)"

if ! rpm -q jetbrains-mono-fonts &>/dev/null; then
   sudo dnf install -y jetbrains-mono-fonts
else
   echo "jetbrains-mono-fonts đã cài, bỏ qua."
fi

# Bibata có sẵn qua Terra repo (đã add ở script post-install), không cần COPR
if ! rpm -q bibata-cursor-theme &>/dev/null; then
   sudo dnf install -y bibata-cursor-theme
else
   echo "Bibata cursor theme đã cài, bỏ qua."
fi

echo "Đã tải xong font/cursor theme. Chưa apply — tự chọn trong GNOME Tweaks / cosmic-settings / KDE System Settings khi cần."

# ------------------------- Kết thúc -------------------------
log "Hoàn tất cài app mặc định."
echo -e "\033[1;33mLưu ý:\033[0m"
echo "- Đăng xuất/đăng nhập lại (hoặc reboot) để fcitx5 và fish shell (nếu đổi) có hiệu lực."
echo "- Mở fcitx5-configtool để thêm layout Unikey/Telex của fcitx5-lotus nếu chưa tự động thêm."
