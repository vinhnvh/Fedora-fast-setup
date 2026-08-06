# Fedora Post-Install Scripts

Bộ 2 script tự động hoá quá trình setup máy Fedora mới cài xong: tối ưu dnf, cài driver/repo cần thiết, và cài các app dùng hàng ngày.

## Nội dung

| File | Mô tả |
|---|---|
| `fedora-post-install.sh` | Tối ưu `dnf.conf`, update hệ thống, cài RPM Fusion + Terra repo, driver NVIDIA, firmware update, đổi hostname, fix Steam qua `/etc/hosts`, MOK enroll cho Secure Boot, v.v. |
| `fedora-install-apps.sh` | Cài app dùng hàng ngày: Steam, Discord, Brave Nightly, kitty + fish + starship, bộ gõ tiếng Việt fcitx5-lotus, Zed editor. |

## Yêu cầu

- Fedora Workstation (bản mới cài, chưa chỉnh gì).
- User thường có quyền `sudo` (**không chạy bằng root**).
- Có kết nối mạng.
- Chạy `fedora-post-install.sh` **trước**, vì script thứ 2 phụ thuộc vào RPM Fusion, Terra repo, Flathub đã được thêm ở script đầu.

## Cài đặt nhanh

```bash
git clone https://github.com/vinhnvh/Fedora-fast-setup.git
cd Fedora-fast-setup
chmod +x fedora-post-install.sh fedora-install-apps.sh
```

Hoặc tải riêng lẻ không cần clone:

```bash
curl -O https://raw.githubusercontent.com/vinhnvh/Fedora-fast-setup/main/fedora-post-install.sh
curl -O https://raw.githubusercontent.com/vinhnvh/Fedora-fast-setup/main/fedora-install-apps.sh

chmod +x fedora-post-install.sh fedora-install-apps.sh
```

## Sử dụng

### 1. Post-install (chạy trước)

```bash
./fedora-post-install.sh
```

Script sẽ tự làm lần lượt:

1. Sửa `/etc/dnf/dnf.conf` (song song tải nhanh hơn, tắt weak deps...)
2. `dnf -y update`
3. Cài RPM Fusion (free + nonfree)
4. Enable đúng repo RPM Fusion (tắt rawhide)
5. Swap `ffmpeg-free` → `ffmpeg` full
6. Nâng cấp group `multimedia`
7. Nâng cấp group `core`
8. Thêm Terra repo
9. Cập nhật firmware qua `fwupd` (hỏi xác nhận)
10–11. Cài driver NVIDIA (`akmod-nvidia` + CUDA) (hỏi xác nhận)
12. Thêm Flathub remote
13. Cài `fuse-libs`
14. Đổi hostname máy (mặc định `MSI-GF63`, sửa biến `HOSTNAME_NEW` đầu file nếu cần)
15. Thêm entry Steam vào `/etc/hosts` (fix lỗi kết nối Steam ở một số mạng)
16. Reinstall `bluez`, `bluez-libs`
17. Set RTC local time (tránh lệch giờ khi dual-boot Windows)
18. Enroll MOK cho `akmod-nvidia` nếu Secure Boot đang bật (hỏi xác nhận, cần password để nhập lại lúc reboot ở màn hình MOK Manager)

> ⚠️ **Một số bước hỏi xác nhận (y/N)** vì có rủi ro cao (firmware update, driver GPU, MOK enroll). Đọc kỹ trước khi gõ `y`.
>
> ⚠️ Nếu có cài driver NVIDIA hoặc enroll MOK, máy cần **reboot** để có hiệu lực — script sẽ hỏi có muốn reboot ngay không.

### 2. Cài app mặc định

```bash
./fedora-install-apps.sh
```

Script sẽ cài lần lượt:

1. Steam
2. Discord (gói native qua Terra repo)
3. Brave Origin Nightly
4. kitty, fish, starship (COPR `atim/starship`) (+ hỏi có muốn đổi shell mặc định sang fish không)
5. Bộ gõ tiếng Việt `fcitx5-lotus` (tự enable service, tắt ibus, thêm biến môi trường vào `~/.config/fish/config.fish`)
6. Zed editor (qua script cài chính thức)
7. JetBrains Mono font + Bibata cursor theme (chỉ tải gói, **không** tự apply — tự chọn trong GNOME Tweaks / cosmic-settings / KDE System Settings)

> ⚠️ Sau khi cài xong, **đăng xuất/đăng nhập lại** (hoặc reboot) để fcitx5 và shell mới (nếu đổi) có hiệu lực. Mở `fcitx5-configtool` để thêm layout Telex/VNI nếu chưa tự động thêm.

## Idempotent — chạy lại an toàn

Cả 2 script đều kiểm tra trạng thái trước khi cài/sửa (gói đã cài, repo đã có, dòng config đã tồn tại...), nên chạy lại nhiều lần không bị lỗi trùng lặp hay ghi đè config không cần thiết.

## Log

- `fedora-post-install.sh` ghi log vào `/var/log/fedora-post-install.log`
- `fedora-install-apps.sh` ghi log vào `/var/log/fedora-install-apps.log`

## Tuỳ chỉnh

Mở đầu mỗi script có vài biến có thể sửa trước khi chạy:

```bash
# fedora-post-install.sh
HOSTNAME_NEW="MSI-GF63"     # tên máy
NVIDIA_PKG="akmod-nvidia"   # gói driver NVIDIA
```

## Cảnh báo

- Đọc qua script trước khi chạy trên máy thật, đặc biệt các phần đổi `/etc/hosts`, hostname, driver GPU và Secure Boot/MOK.
- Script viết cho **Fedora Workstation**, chưa test trên Silverblue/Kinoite hay các spin khác dùng `rpm-ostree`.
- Một số gói (Terra, fcitx5-lotus, Brave nightly) đến từ repo bên thứ ba — tự chịu trách nhiệm khi thêm các repo này.
