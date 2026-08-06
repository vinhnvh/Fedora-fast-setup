#!/usr/bin/env bash
#
# fedora-post-install.sh
# Script tối ưu post-install cho Fedora
#
# Chạy: chmod +x fedora-post-install.sh && ./fedora-post-install.sh
# Yêu cầu: chạy bằng user thường có quyền sudo (KHÔNG chạy bằng root trực tiếp,
# script sẽ tự gọi sudo khi cần).

set -euo pipefail

# ------------------------- Cấu hình chung -------------------------
HOSTNAME_NEW="MSI-GF63"          # đổi tên máy tại đây
NVIDIA_PKG="akmod-nvidia"        # xem ghi chú ở bước 10 bên dưới
LOG_FILE="/var/log/fedora-post-install.log"

# ------------------------- Helper functions -------------------------
log() {
    echo -e "\n\033[1;32m==> $1\033[0m" | sudo tee -a "$LOG_FILE" >/dev/null
    echo -e "\n\033[1;32m==> $1\033[0m"
}

confirm() {
    read -rp "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

require_reboot=false

if [[ $EUID -eq 0 ]]; then
    echo "Đừng chạy script bằng root. Chạy với user thường, script sẽ tự sudo khi cần." >&2
    exit 1
fi

sudo touch "$LOG_FILE"

# ------------------------- 1. Cấu hình dnf.conf -------------------------
log "1. Cấu hình /etc/dnf/dnf.conf"
DNF_CONF="/etc/dnf/dnf.conf"
sudo cp "$DNF_CONF" "${DNF_CONF}.bak.$(date +%s)" 2>/dev/null || true

declare -A DNF_OPTS=(
    [fastestmirror]=True
    [max_parallel_downloads]=20
    [defaultyes]=True
    [keepcache]=True
    [ip_resolve]=4
    [installonly_limit]=2
    [install_weak_deps]=False
)

for key in "${!DNF_OPTS[@]}"; do
    value="${DNF_OPTS[$key]}"
    if sudo grep -qE "^${key}=" "$DNF_CONF"; then
        sudo sed -i "s/^${key}=.*/${key}=${value}/" "$DNF_CONF"
    else
        echo "${key}=${value}" | sudo tee -a "$DNF_CONF" >/dev/null
    fi
done
echo "Đã cập nhật $DNF_CONF (backup đã lưu cạnh file gốc)."

# ------------------------- 2. Update hệ thống -------------------------
log "2. dnf update"
sudo dnf -y update

# ------------------------- 3. RPM Fusion -------------------------
log "3. Cài RPM Fusion (free + nonfree)"
FEDORA_VER=$(rpm -E %fedora)
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
else
    echo "RPM Fusion đã được cài, bỏ qua."
fi

# ------------------------- 4. Fix repo rawhide/updates -------------------------
log "4. Chỉnh cấu hình repo RPM Fusion"
sudo dnf config-manager setopt rpmfusion-free.enabled=1
sudo dnf config-manager setopt rpmfusion-free-updates.enabled=1
sudo dnf config-manager setopt rpmfusion-free-rawhide.enabled=0

# ------------------------- 5. Swap ffmpeg-free -> ffmpeg -------------------------
log "5. Swap ffmpeg-free sang ffmpeg full"
if rpm -q ffmpeg-free &>/dev/null; then
    sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
else
    echo "ffmpeg-free không có sẵn hoặc đã swap trước đó, bỏ qua."
fi

# ------------------------- 6-7. Group upgrade -------------------------
log "6. Nâng cấp nhóm multimedia"
sudo dnf group upgrade -y multimedia || echo "Cảnh báo: group multimedia upgrade lỗi hoặc không có gì để nâng cấp."

log "7. Nâng cấp nhóm core"
sudo dnf group upgrade -y core || echo "Cảnh báo: group core upgrade lỗi hoặc không có gì để nâng cấp."

# ------------------------- 8. Terra repo -------------------------
log "8. Cài Terra repo"
if ! rpm -q terra-release &>/dev/null; then
    sudo dnf install -y --nogpgcheck --repofrompath \
        "terra,https://repos.fyralabs.com/terra\$releasever" terra-release
else
    echo "Terra repo đã cài, bỏ qua."
fi

# ------------------------- 9. fwupd firmware update -------------------------
log "9. Cập nhật firmware qua fwupd"
if command -v fwupdmgr &>/dev/null; then
    sudo fwupdmgr refresh --force || true
    sudo fwupdmgr get-devices || true
    sudo fwupdmgr get-updates || true
    if confirm "Có muốn cài firmware update ngay bây giờ không? (có thể cần khởi động lại)"; then
        sudo fwupdmgr update
        require_reboot=true
    fi
else
    echo "fwupdmgr không có sẵn, cài gói fwupd trước."
    sudo dnf install -y fwupd
fi

# ------------------------- 10-11. NVIDIA driver -------------------------
log "10-11. Cài driver NVIDIA (akmod-nvidia + CUDA)"
echo "Lưu ý: gói 'akmod-nvidia-580xx' không tồn tại trên RPM Fusion — tên gói đúng là"
echo "'akmod-nvidia' (phiên bản driver được repo tự chọn theo GPU/driver mới nhất)."
if confirm "Tiếp tục cài akmod-nvidia + xorg-x11-drv-nvidia-cuda?"; then
    sudo dnf install -y "$NVIDIA_PKG" xorg-x11-drv-nvidia-cuda
    require_reboot=true
    echo "Sau khi cài xong, đợi vài phút để akmod build kernel module rồi reboot."
else
    echo "Bỏ qua cài driver NVIDIA."
fi

# ------------------------- 12. Flathub -------------------------
log "12. Thêm Flathub remote"
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# ------------------------- 13. fuse-libs -------------------------
log "13. Cài fuse-libs"
sudo dnf install -y fuse-libs

# ------------------------- 14. Đổi hostname -------------------------
log "14. Đổi hostname thành ${HOSTNAME_NEW}"
sudo hostnamectl set-hostname "$HOSTNAME_NEW"

# ------------------------- 15. /etc/hosts cho Steam -------------------------
log "15. Thêm entry Steam vào /etc/hosts"
HOSTS_FILE="/etc/hosts"
add_host_entry() {
    local ip="$1" domain="$2"
    if ! grep -qE "^\s*${ip}\s+${domain}\s*$" "$HOSTS_FILE"; then
        echo "${ip} ${domain}" | sudo tee -a "$HOSTS_FILE" >/dev/null
        echo "Đã thêm: ${ip} ${domain}"
    else
        echo "Entry ${domain} đã tồn tại, bỏ qua."
    fi
}
add_host_entry "23.15.141.198" "store.steampowered.com"
add_host_entry "184.87.199.210" "steamcommunity.com"

# ------------------------- 16. Reinstall bluez -------------------------
log "16. Reinstall bluez"
sudo dnf reinstall -y bluez bluez-libs

# ------------------------- 17. RTC local time (dual boot) -------------------------
log "17. Set RTC local time cho dual boot Windows"
sudo timedatectl set-local-rtc 1 --adjust-system-clock

# ------------------------- 18. MOK enroll cho NVIDIA (Secure Boot) -------------------------
log "18. Enroll MOK cho akmod-nvidia (chỉ cần nếu Secure Boot đang bật)"
if command -v mokutil &>/dev/null; then
    SB_STATE=$(mokutil --sb-state 2>/dev/null || echo "unknown")
    echo "Trạng thái Secure Boot: $SB_STATE"
    if [[ "$SB_STATE" == *"enabled"* ]]; then
        CERT="/etc/pki/akmods/certs/public_key.der"
        if [[ ! -f "$CERT" ]]; then
            echo "Chưa thấy cert akmods, thử tạo bằng kmodgenca..."
            sudo kmodgenca -a || true
        fi
        if mokutil --list-enrolled 2>/dev/null | grep -q "akmods"; then
            echo "Key akmods đã được enroll vào MOK trước đó, bỏ qua."
        elif [[ -f "$CERT" ]]; then
            if confirm "Enroll MOK key ngay? (sẽ hỏi bạn đặt password, dùng lúc reboot ở màn hình xanh MOK Manager)"; then
                sudo mokutil --import "$CERT"
                require_reboot=true
                echo -e "\033[1;33mQUAN TRỌNG: sau khi reboot, màn hình xanh 'MOK Manager' sẽ hiện ra.\033[0m"
                echo "Chọn: Enroll MOK -> Continue -> Yes -> nhập đúng password vừa đặt -> Reboot."
                echo "Nếu bỏ qua bước này, module nvidia sẽ KHÔNG load được khi Secure Boot bật."
            fi
        else
            echo "Không tìm thấy cert để enroll, kiểm tra lại sau khi akmod-nvidia build xong (dkms/akmods log)."
        fi
    else
        echo "Secure Boot đang tắt hoặc không xác định được — không cần enroll MOK."
    fi
else
    echo "Không tìm thấy mokutil, cài gói mokutil trước nếu cần dùng Secure Boot."
fi

# ------------------------- Kết thúc -------------------------
log "Hoàn tất post-install."
if $require_reboot; then
    echo -e "\n\033[1;33mCần khởi động lại máy để hoàn tất (driver NVIDIA / firmware update / MOK enroll).\033[0m"
    if confirm "Reboot ngay bây giờ?"; then
        sudo reboot
    fi
fi
