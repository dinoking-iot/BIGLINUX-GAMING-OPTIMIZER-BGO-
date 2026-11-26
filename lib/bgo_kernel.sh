#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Gaming Kernel Selection & Installation
# ==============================================================================

bgo_optimize_kernel() {
    local running_kernel
    running_kernel="$(uname -r)"
    bgo_info "[EN] Auditing current Linux kernel: ${running_kernel}" \
             "[VI] Đang kiểm tra phiên bản nhân Linux hiện tại: ${running_kernel}"

    local is_gaming_kernel=false
    if echo "${running_kernel}" | grep -qiE "xanmod|zen|cachyos|tkg|liquorix"; then
        is_gaming_kernel=true
    fi

    if [[ "${is_gaming_kernel}" == true ]]; then
        bgo_success "[EN] Active kernel (${running_kernel}) is already a specialized low-latency gaming kernel!" \
                    "[VI] Nhân đang chạy (${running_kernel}) đã là nhân hiệu năng cao chuyên biệt cho gaming!"
        
        # Verify headers are installed for DKMS support
        if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
            if ! pacman -Q "linux-xanmod-headers" &>/dev/null && ! pacman -Q "linux-zen-headers" &>/dev/null; then
                bgo_info "[EN] Installing matching kernel headers for DKMS compatibility..." \
                         "[VI] Cài đặt kernel headers tương ứng để hỗ trợ DKMS..."
                if echo "${running_kernel}" | grep -qi "xanmod"; then
                    pacman -S --needed --noconfirm linux-xanmod-headers 2>/dev/null || true
                elif echo "${running_kernel}" | grep -qi "zen"; then
                    pacman -S --needed --noconfirm linux-zen-headers 2>/dev/null || true
                fi
            fi
        fi
        return 0
    fi

    # Not currently running a specialized gaming kernel; install the best available
    bgo_info "[EN] Standard kernel detected. Installing latest gaming kernel with low-latency scheduler..." \
             "[VI] Phát hiện kernel thông thường. Đang cài kernel gaming mới nhất với bộ điều phối độ trễ thấp..."

    case "${BGO_DISTRO_FAMILY}" in
        arch)
            # BigLinux prioritizes linux-xanmod; Arch standard prioritizes linux-zen
            local target_kernel=""
            local target_headers=""

            # Check xanmod availability first (BigLinux/Manjaro priority)
            if pacman -Si linux-xanmod &>/dev/null 2>&1; then
                target_kernel="linux-xanmod"
                target_headers="linux-xanmod-headers"
            # Fallback to linux-zen if available
            elif pacman -Si linux-zen &>/dev/null 2>&1; then
                target_kernel="linux-zen"
                target_headers="linux-zen-headers"
            fi

            if [[ -n "${target_kernel}" ]]; then
                local task_rc=0
                bgo_run_task "Installing Gaming Kernel (${target_kernel}) & Headers" \
                             "Cài đặt Kernel Gaming (${target_kernel}) & Headers" \
                             "pacman -S --needed --noconfirm ${target_kernel} ${target_headers}" || task_rc=$?

                if [[ ${task_rc} -eq 0 ]]; then
                    bgo_record_patch "GAMING_KERNEL" "Installed ${target_kernel} gaming kernel" "Cài đặt nhân gaming ${target_kernel}"
                else
                    bgo_warn "[EN] Gaming kernel installation failed (Exit code: ${task_rc}). System will continue with current kernel." \
                             "[VI] Cài đặt kernel gaming thất bại (Mã lỗi: ${task_rc}). Hệ thống tiếp tục dùng kernel hiện tại."
                fi
            else
                bgo_warn "[EN] No gaming kernel (linux-xanmod, linux-zen) found in configured repositories. Skipping kernel installation." \
                         "[VI] Không tìm thấy kernel gaming (linux-xanmod, linux-zen) trong kho phần mềm đã cấu hình. Bỏ qua bước cài kernel."
                bgo_info "[EN] Tip: Enable the AUR or BigLinux-testing repo to access linux-xanmod." \
                         "[VI] Gợi ý: Bật kho AUR hoặc kho BigLinux-testing để truy cập linux-xanmod."
            fi
            ;;

        debian)
            local task_rc=0
            bgo_run_task "Installing Linux low-latency / generic-hwe kernel (Debian/Ubuntu)" \
                         "Cài đặt nhân low-latency độ trễ thấp (Debian/Ubuntu)" \
                         "apt-get install -y linux-lowlatency linux-headers-lowlatency" || task_rc=$?
            if [[ ${task_rc} -eq 0 ]]; then
                bgo_record_patch "DEBIAN_LOWLATENCY" "Installed linux-lowlatency kernel" "Cài đặt linux-lowlatency"
            else
                bgo_warn "[EN] linux-lowlatency kernel not available in repos. Skipping." \
                         "[VI] Không tìm thấy gói linux-lowlatency trong kho phần mềm. Bỏ qua."
            fi
            ;;

        fedora)
            bgo_info "[EN] Fedora standard kernel features high-tickrate timers; ensuring kernel-devel is present." \
                     "[VI] Kernel Fedora đã tối ưu timer tần số cao; bảo đảm gói kernel-devel đã có."
            dnf install -y kernel-devel &>/dev/null || true
            ;;
    esac

    # Safe Bootloader Update
    bgo_update_bootloader
}

bgo_update_bootloader() {
    bgo_info "[EN] Updating bootloader configuration to register new gaming kernel..." \
             "[VI] Cập nhật cấu hình bộ khởi động bootloader để nhận diện kernel mới..."

    if command -v update-grub &>/dev/null; then
        bgo_run_task "Updating GRUB configuration (update-grub)" \
                     "Cập nhật cấu hình GRUB (update-grub)" \
                     "update-grub"
    elif [[ -f /boot/grub/grub.cfg ]] && command -v grub-mkconfig &>/dev/null; then
        bgo_run_task "Regenerating GRUB config (/boot/grub/grub.cfg)" \
                     "Tạo lại cấu hình GRUB (/boot/grub/grub.cfg)" \
                     "grub-mkconfig -o /boot/grub/grub.cfg"
    elif command -v bootctl &>/dev/null && [[ -d /boot/loader ]]; then
        bgo_run_task "Updating systemd-boot entries" \
                     "Cập nhật mục khởi động systemd-boot" \
                     "bootctl update"
    fi
}
