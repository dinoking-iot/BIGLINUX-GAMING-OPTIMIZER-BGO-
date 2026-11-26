#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Safe Rollback & Uninstaller
# ==============================================================================

bgo_perform_rollback() {
    bgo_banner
    bgo_info "[EN] Initiating rollback and cleanup of BigLinux Gaming Optimizer tweaks..." \
             "[VI] Bắt đầu gỡ bỏ và hoàn nguyên các cấu hình của BigLinux Gaming Optimizer..."

    local removed_count=0

    # List of configuration files installed by BGO
    local config_files=(
        "/etc/modprobe.d/99-bgo-amdgpu.conf"
        "/etc/modprobe.d/99-bgo-nvidia.conf"
        "/etc/modprobe.d/99-bgo-audio-powersave.conf"
        "/etc/wireplumber/wireplumber.conf.d/99-bgo-disable-suspend.conf"
        "/etc/NetworkManager/conf.d/99-bgo-disable-wifi-powersave.conf"
        "/etc/sysctl.d/99-bgo-gaming-performance.conf"
        "/etc/sysctl.d/99-bgo-network.conf"
        "/etc/security/limits.d/99-bgo-gaming.conf"
        "/usr/local/bin/bgo-wine-launcher"
        "/usr/share/applications/bgo-wine-launcher.desktop"
        "/usr/local/bin/bgo-clean-cache"
    )

    # 1. Stop and remove systemd timer
    if systemctl is-active --quiet bgo-cache-clean.timer 2>/dev/null; then
        systemctl disable --now bgo-cache-clean.timer 2>/dev/null || true
    fi
    rm -f /etc/systemd/system/bgo-cache-clean.timer /etc/systemd/system/bgo-cache-clean.service
    systemctl daemon-reload 2>/dev/null || true

    # 2. Remove generated configuration files
    for file in "${config_files[@]}"; do
        if [[ -f "${file}" ]]; then
            rm -f "${file}"
            bgo_info "[EN] Removed: ${file}" "[VI] Đã gỡ bỏ: ${file}"
            ((removed_count++)) || true
        fi
    done

    # 3. Reload kernel parameters & sysctl to system defaults
    bgo_run_task "Reloading default sysctl system settings" \
                 "Tải lại thiết lập mặc định của sysctl" \
                 "sysctl --system"

    # Update desktop database
    update-desktop-database /usr/share/applications &>/dev/null || true

    bgo_success "[EN] Rollback complete. ${removed_count} configuration files cleanly removed." \
                "[VI] Hoàn nguyên hoàn tất. Đã gỡ bỏ sạch sẽ ${removed_count} tệp cấu hình."
    bgo_info "[EN] Note: Core drivers and system runtimes were kept intact to ensure system stability." \
             "[VI] Lưu ý: Các driver và runtime lõi được giữ lại để tránh ảnh hưởng đến ứng dụng của bạn."
}
