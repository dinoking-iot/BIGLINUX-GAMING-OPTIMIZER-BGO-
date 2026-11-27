#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Gaming Kernel Selection & Installation
# ==============================================================================

bgo_optimize_kernel() {
    local running_kernel
    running_kernel="$(uname -r)"
    bgo_info "[EN] Auditing current Linux kernel: ${running_kernel}" \
             "[VI] Đang kiểm tra phiên bản nhân Linux hiện tại: ${running_kernel}"

    # Detect BigLinux-managed kernels (big-kernel: BORE + Clang ThinLTO)
    # and other known low-latency gaming kernels
    local is_gaming_kernel=false
    local kernel_type="standard"

    if echo "${running_kernel}" | grep -qiE "xanmod|zen|cachyos|tkg|liquorix"; then
        is_gaming_kernel=true
        kernel_type="xanmod/zen"
    elif pacman -Qsq "^linux-big[0-9]*$" 2>/dev/null | grep -qE "^linux-big[0-9]*$"; then
        # BigLinux big-kernel base package is installed (BORE + Clang ThinLTO + Intel fixes)
        # Use anchored regex to avoid matching variant packages (linux-big73-zfs, linux-big73-nvidia, etc.)
        local installed_bigkern
        installed_bigkern="$(pacman -Qsq "^linux-big[0-9]*$" 2>/dev/null | grep -E "^linux-big[0-9]*$" | head -n1)"
        if [[ -n "${installed_bigkern}" ]]; then
            is_gaming_kernel=true
            kernel_type="biglinux-big-kernel"
        fi
    fi

    if [[ "${is_gaming_kernel}" == true ]]; then
        bgo_success "[EN] Active gaming/optimized kernel detected (type: ${kernel_type}, version: ${running_kernel}). Skipping kernel install." \
                    "[VI] Đã phát hiện kernel gaming/tối ưu (loại: ${kernel_type}, phiên bản: ${running_kernel}). Bỏ qua bước cài kernel."

        # Verify headers are installed for DKMS support
        if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
            bgo_ensure_kernel_headers "${running_kernel}"
        fi
        return 0
    fi

    # Not running a specialized gaming kernel — install the best available
    bgo_info "[EN] Standard/generic kernel detected. Searching for best available gaming kernel..." \
             "[VI] Phát hiện kernel thông thường. Đang tìm kernel gaming tốt nhất có sẵn..."

    case "${BGO_DISTRO_FAMILY}" in
        arch)
            _bgo_install_arch_gaming_kernel
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

# Install the best available gaming kernel on Arch/BigLinux/Manjaro
# Priority: linux-big* (BigLinux) > linux-xanmod > linux-zen > warn
_bgo_install_arch_gaming_kernel() {
    local target_kernel=""
    local target_headers=""
    local kernel_label=""

    # 1st priority: BigLinux big-kernel (BORE + Clang ThinLTO + Intel fixes)
    # Match ONLY base kernel packages: linux-big, linux-big72, linux-big73...
    # Exclude variant/module packages: linux-big73-zfs, linux-big73-nvidia, etc.
    # Pattern: ^linux-big[0-9]*$ — anchored end ($) prevents matching variants with suffixes
    local bigkern_candidate
    bigkern_candidate="$(pacman -Ssq "^linux-big[0-9]*$" 2>/dev/null | grep -E "^linux-big[0-9]*$" | sort -V | tail -n1)"
    # Verify the matched kernel actually has a -headers companion package in the repo
    if [[ -n "${bigkern_candidate}" ]] && pacman -Si "${bigkern_candidate}" &>/dev/null 2>&1 && pacman -Si "${bigkern_candidate}-headers" &>/dev/null 2>&1; then
        target_kernel="${bigkern_candidate}"
        target_headers="${bigkern_candidate}-headers"
        kernel_label="BigLinux big-kernel (BORE + ThinLTO)"
    # 2nd priority: linux-xanmod
    elif pacman -Si linux-xanmod &>/dev/null 2>&1; then
        target_kernel="linux-xanmod"
        target_headers="linux-xanmod-headers"
        kernel_label="XanMod"
    # 3rd priority: linux-zen
    elif pacman -Si linux-zen &>/dev/null 2>&1; then
        target_kernel="linux-zen"
        target_headers="linux-zen-headers"
        kernel_label="Zen"
    fi

    if [[ -n "${target_kernel}" ]]; then
        bgo_info "[EN] Selected gaming kernel: ${target_kernel} (${kernel_label})" \
                 "[VI] Kernel gaming được chọn: ${target_kernel} (${kernel_label})"
        local task_rc=0
        bgo_run_task "Installing Gaming Kernel (${target_kernel}) & Headers" \
                     "Cài đặt Kernel Gaming (${target_kernel}) & Headers" \
                     "pacman -S --needed --noconfirm ${target_kernel} ${target_headers}" || task_rc=$?

        if [[ ${task_rc} -eq 0 ]]; then
            bgo_record_patch "GAMING_KERNEL" "Installed ${target_kernel} gaming kernel (${kernel_label})" "Cài đặt nhân gaming ${target_kernel} (${kernel_label})"
        else
            bgo_warn "[EN] Gaming kernel installation failed (Exit code: ${task_rc}). System will continue with current kernel." \
                     "[VI] Cài đặt kernel gaming thất bại (Mã lỗi: ${task_rc}). Hệ thống tiếp tục dùng kernel hiện tại."
        fi
    else
        bgo_warn "[EN] No gaming kernel (linux-big*, linux-xanmod, linux-zen) found in configured repositories. Skipping kernel installation." \
                 "[VI] Không tìm thấy kernel gaming nào (linux-big*, linux-xanmod, linux-zen) trong kho đã cấu hình. Bỏ qua bước cài kernel."
        bgo_info "[EN] Tip: BigLinux big-kernels (linux-big*) are available via Big Driver Manager." \
                 "[VI] Gợi ý: Kernel BigLinux (linux-big*) có thể cài qua Big Driver Manager."
    fi
}

# Ensure kernel headers matching the running kernel are installed (for DKMS)
bgo_ensure_kernel_headers() {
    local running_kernel="$1"
    local headers_installed=false

    # Check for common header package patterns
    for hdr_pkg in linux-xanmod-headers linux-zen-headers linux-headers; do
        if pacman -Q "${hdr_pkg}" &>/dev/null; then
            headers_installed=true
            break
        fi
    done

    # Also check for linux-big*-headers
    if ! ${headers_installed} && pacman -Qsq "^linux-big[0-9].*-headers" 2>/dev/null | grep -q "headers"; then
        headers_installed=true
    fi

    if ! ${headers_installed}; then
        bgo_info "[EN] Installing matching kernel headers for DKMS compatibility..." \
                 "[VI] Cài đặt kernel headers tương ứng để hỗ trợ DKMS..."

        if echo "${running_kernel}" | grep -qi "xanmod"; then
            pacman -S --needed --noconfirm linux-xanmod-headers 2>/dev/null || true
        elif echo "${running_kernel}" | grep -qi "zen"; then
            pacman -S --needed --noconfirm linux-zen-headers 2>/dev/null || true
        else
            # Try to find and install matching big-kernel headers
            local bigkern_hdr
            bigkern_hdr="$(pacman -Qsq "^linux-big[0-9].*-headers" 2>/dev/null | head -n1)"
            if [[ -n "${bigkern_hdr}" ]]; then
                pacman -S --needed --noconfirm "${bigkern_hdr}" 2>/dev/null || true
            fi
        fi
    fi
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
