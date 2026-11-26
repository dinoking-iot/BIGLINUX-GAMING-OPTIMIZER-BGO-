#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Wine Pure WoW64, Click-to-Run & Cache Cleaner
# ==============================================================================

bgo_setup_wine_and_cache() {
    bgo_setup_click_to_run
    bgo_setup_cache_cleaner
}

# ------------------------------------------------------------------------------
# 1. Pure Wine "Click-to-Run" Desktop Integration (.exe / .msi)
# ------------------------------------------------------------------------------
bgo_setup_click_to_run() {
    bgo_info "[EN] Setting up Wine 'Click-to-Run' desktop integration for .exe & .msi..." \
             "[VI] Thiết lập tính năng 'Click là chạy' cho file .exe và .msi qua Wine..."

    # Create optimized system launcher script
    mkdir -p /usr/local/bin
    cat << 'EOF' > /usr/local/bin/bgo-wine-launcher
#!/usr/bin/env bash
# BigLinux Gaming Optimizer - Click-to-Run Wine WOW64 Launcher
TARGET_FILE="$1"
if [[ -z "${TARGET_FILE}" || ! -f "${TARGET_FILE}" ]]; then
    zenity --error --title="Wine Launcher" --text="No executable file specified!" 2>/dev/null || true
    exit 1
fi

# Set gaming environment variables
export WINEPREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/gaming64}"
export WINEARCH=win64
export WINEDEBUG=-all
export DXVK_HUD=0
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1

# Execute with GameMode if available
if command -v gamemoderun &>/dev/null; then
    exec gamemoderun wine "${TARGET_FILE}" "${@:2}"
else
    exec wine "${TARGET_FILE}" "${@:2}"
fi
EOF
    chmod +x /usr/local/bin/bgo-wine-launcher

    # Create Desktop Entry for MIME Associations
    mkdir -p /usr/share/applications
    cat << 'EOF' > /usr/share/applications/bgo-wine-launcher.desktop
[Desktop Entry]
Type=Application
Name=Run with Wine Gaming (WOW64)
Name[vi]=Chạy bằng Wine Gaming (WOW64)
Comment=Optimized Wine 32/64-bit launcher with DXVK and GameMode
Comment[vi]=Trình khởi chạy Wine 32/64-bit tối ưu với DXVK và GameMode
Exec=/usr/local/bin/bgo-wine-launcher %f
Icon=wine
Terminal=false
Categories=Game;Emulator;
MimeType=application/x-msdos-program;application/x-msi;application/x-wine-extension-msp;
StartupNotify=true
EOF

    # Update MIME database and register default handler
    update-desktop-database /usr/share/applications &>/dev/null || true
    if command -v xdg-mime &>/dev/null; then
        su - "${BGO_USER}" -c "xdg-mime default bgo-wine-launcher.desktop application/x-msdos-program application/x-msi" 2>/dev/null || true
    fi

    bgo_record_patch "WINE_CLICK2RUN" "Installed bgo-wine-launcher and registered .exe/.msi associations" "Kích hoạt click là chạy cho file exe/msi"
    bgo_success "[EN] 'Click-to-Run' desktop integration enabled." \
                "[VI] Tính năng 'Click là chạy' đã được cấu hình thành công."
}

# ------------------------------------------------------------------------------
# 2. Automated Pacman / Pamac Cache Cleaner
# ------------------------------------------------------------------------------
bgo_setup_cache_cleaner() {
    bgo_info "[EN] Setting up automated Pacman / Pamac package cache cleaner..." \
             "[VI] Thiết lập công cụ tự động dọn dẹp bộ nhớ đệm cache của Pacman / Pamac..."

    if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
        # Ensure pacman-contrib is installed for paccache
        pacman -S --needed --noconfirm pacman-contrib 2>/dev/null || true

        # Write standalone cleaner script
        cat << 'EOF' > /usr/local/bin/bgo-clean-cache
#!/usr/bin/env bash
# BigLinux / Arch Cache Cleanup Script
echo "=========================================================="
echo " [EN] Cleaning Pacman & Pamac Package Cache..."
echo " [VI] Đang dọn dẹp bộ nhớ đệm Pacman & Pamac..."
echo "=========================================================="

# Retain last 2 package versions in cache
if command -v paccache &>/dev/null; then
    paccache -rk2 || true
    paccache -ruk0 || true
fi

# Clean pamac cache if available
if command -v pamac &>/dev/null; then
    pamac clean --keep 2 --no-confirm 2>/dev/null || true
fi

# Clean orphan packages safely
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [[ -n "${orphans}" ]]; then
    echo " [EN] Removing orphan packages: ${orphans}"
    echo " [VI] Xóa các gói mồ côi không dùng: ${orphans}"
    pacman -Rns --noconfirm ${orphans} 2>/dev/null || true
fi

echo " [EN] Cache cleanup complete!"
echo " [VI] Dọn dẹp bộ nhớ đệm hoàn tất!"
EOF
        chmod +x /usr/local/bin/bgo-clean-cache

        # Setup automated weekly systemd service and timer
        mkdir -p /etc/systemd/system
        cat << 'EOF' > /etc/systemd/system/bgo-cache-clean.service
[Unit]
Description=BigLinux Package Cache Cleanup Service
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/bgo-clean-cache
EOF

        cat << 'EOF' > /etc/systemd/system/bgo-cache-clean.timer
[Unit]
Description=Weekly BigLinux Package Cache Cleanup Timer

[Timer]
OnCalendar=weekly
Persistent=true

[Install]
WantedBy=timers.target
EOF

        systemctl daemon-reload 2>/dev/null || true
        systemctl enable --now bgo-cache-clean.timer 2>/dev/null || true
        bgo_record_patch "CACHE_CLEANER_TIMER" "Installed bgo-clean-cache and enabled weekly timer" "Thiết lập hẹn giờ tự động dọn cache tuần"
        bgo_success "[EN] Pacman/Pamac cache cleaner scheduled (runs weekly & on-demand via 'bgo-clean-cache')." \
                    "[VI] Trình dọn cache đã kích hoạt (chạy tự động hàng tuần hoặc chạy lệnh 'bgo-clean-cache')."
    fi
}
