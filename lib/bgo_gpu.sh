#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - GPU Driver & Graphic Controllers
# ==============================================================================

bgo_detect_and_install_gpu() {
    bgo_info "[EN] Scanning PCI bus for GPU hardware (AMD / Intel / NVIDIA)..." \
             "[VI] Đang quét bus PCI nhận diện phần cứng đồ họa (AMD / Intel / NVIDIA)..."

    local pci_gpus
    pci_gpus="$(lspci -nnk | grep -iE 'vga|3d|display' || true)"
    bgo_log_raw "HARDWARE" "Detected GPUs:\n${pci_gpus}"

    local has_amd=false
    local has_nvidia=false
    local has_intel=false

    if echo "${pci_gpus}" | grep -qiE "amd|ati|advanced micro devices"; then
        has_amd=true
    fi
    if echo "${pci_gpus}" | grep -qi "nvidia"; then
        has_nvidia=true
    fi
    if echo "${pci_gpus}" | grep -qi "intel"; then
        has_intel=true
    fi

    bgo_info "[EN] GPU Detection Status: AMD=${has_amd}, NVIDIA=${has_nvidia}, INTEL=${has_intel}" \
             "[VI] Kết quả nhận diện GPU: AMD=${has_amd}, NVIDIA=${has_nvidia}, INTEL=${has_intel}"

    # Install Universal Vulkan Loaders & Diagnostic Tools if needed
    if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
        local base_vk_pkgs=()
        for pkg in vulkan-icd-loader lib32-vulkan-icd-loader vulkan-tools mesa-utils lib32-mesa-utils; do
            if ! bgo_is_pkg_installed "${pkg}"; then
                base_vk_pkgs+=("${pkg}")
            fi
        done

        if ((${#base_vk_pkgs[@]} > 0)); then
            bgo_run_task "Installing missing Vulkan ICD Loaders & Tools (${base_vk_pkgs[*]})" \
                         "Cài đặt trình nạp Vulkan ICD và công cụ chẩn đoán (${base_vk_pkgs[*]})" \
                         "pacman -S --needed --noconfirm ${base_vk_pkgs[*]}"
        else
            bgo_success "[EN] Vulkan ICD Loaders and tools are already installed." \
                        "[VI] Trình nạp Vulkan ICD và công cụ chẩn đoán đã có sẵn trên hệ thống."
        fi
    fi

    # --------------------------------------------------------------------------
    # 1. AMD Graphics & Vulkan Driver Configuration
    # --------------------------------------------------------------------------
    if [[ "${has_amd}" == true ]]; then
        bgo_info "[EN] Optimizing AMD Radeon Graphics Stack (Mesa RADV & Controllers)..." \
                 "[VI] Đang tối ưu hóa hệ sinh thái đồ họa AMD Radeon (Mesa RADV & Trình điều khiển)..."

        if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
            local amd_pkgs=()

            # Smart Mesa Provider Detection (Preserves BigLinux mesa-tkg-stable / mesa-tkg-git)
            for pkg in mesa lib32-mesa vulkan-radeon lib32-vulkan-radeon xf86-video-amdgpu; do
                if ! bgo_is_pkg_installed "${pkg}"; then
                    amd_pkgs+=("${pkg}")
                fi
            done

            if ((${#amd_pkgs[@]} > 0)); then
                bgo_run_task "Installing AMD Vulkan (RADV) & Mesa Drivers (${amd_pkgs[*]})" \
                             "Cài đặt Driver AMD Vulkan (RADV) & Mesa (${amd_pkgs[*]})" \
                             "pacman -S --needed --noconfirm ${amd_pkgs[*]}"
            else
                bgo_success "[EN] AMD Mesa & Vulkan (RADV) 32/64-bit drivers are already satisfied." \
                            "[VI] Driver AMD Mesa & Vulkan (RADV) 32/64-bit đã được đáp ứng đầy đủ."
            fi

            # GCN 1.0 (Southern Islands) & GCN 2.0 (Sea Islands) Vulkan Support Enabler
            bgo_info "[EN] Applying AMDGPU kernel driver support for legacy GCN 1.0/2.0 cards..." \
                     "[VI] Kích hoạt hỗ trợ driver kernel amdgpu cho các dòng card GCN 1.0/2.0 đời cũ..."

            mkdir -p /etc/modprobe.d
            cat << 'EOF' > /etc/modprobe.d/99-bgo-amdgpu.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
# Enable AMDGPU kernel driver for GCN 1.0 (Southern Islands) and GCN 2.0 (Sea Islands)
# This enables modern Vulkan & DXVK compatibility on legacy AMD Radeon GPUs
options amdgpu si_support=1 cik_support=1
options radeon si_support=0 cik_support=0
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
            bgo_record_patch "AMD_GCN_VULKAN" "Enabled AMDGPU kernel driver for GCN 1/2 legacy GPUs" "Kích hoạt Vulkan cho AMD GCN 1/2 cũ"

            # Graphic Controller Tools
            local amd_tools=()
            for tool in mangohud lib32-mangohud goverlay lact; do
                if ! bgo_is_pkg_installed "${tool}"; then
                    if [[ "${tool}" == "lact" ]] && pacman -Ss "^lact-git" &>/dev/null; then
                        amd_tools+=(lact-git)
                    else
                        amd_tools+=("${tool}")
                    fi
                fi
            done

            if ((${#amd_tools[@]} > 0)); then
                bgo_run_task "Installing Graphic Controllers (${amd_tools[*]})" \
                             "Cài đặt trình điều khiển đồ họa (${amd_tools[*]})" \
                             "pacman -S --needed --noconfirm ${amd_tools[*]}"
            else
                bgo_success "[EN] Graphic Controllers (MangoHud, GOverlay, LACT) are already satisfied." \
                            "[VI] Các bộ điều khiển đồ họa (MangoHud, GOverlay, LACT) đã có sẵn."
            fi

            # Enable LACT daemon if installed
            if systemctl list-unit-files 2>/dev/null | grep -q "lactd.service"; then
                systemctl enable --now lactd.service 2>/dev/null || true
                bgo_record_patch "LACT_DAEMON" "Enabled LACT GPU controller daemon" "Kích hoạt dịch vụ LACT GPU"
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # 2. NVIDIA Graphics & Vulkan Driver Configuration
    # --------------------------------------------------------------------------
    if [[ "${has_nvidia}" == true ]]; then
        bgo_info "[EN] Optimizing NVIDIA Graphics Stack (Proprietary / Open Modules & 32-bit Utils)..." \
                 "[VI] Đang tối ưu hóa hệ sinh thái NVIDIA (Kernel modules & Tiện ích 32-bit)..."

        if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
            local running_kernel
            running_kernel="$(uname -r)"
            local nvd_pkg="nvidia-dkms"

            if echo "${running_kernel}" | grep -q "xanmod"; then
                if pacman -Ss "linux-xanmod-nvidia" &>/dev/null; then
                    nvd_pkg="linux-xanmod-nvidia"
                fi
            fi

            local nvidia_pkgs=()
            for pkg in "${nvd_pkg}" nvidia-utils lib32-nvidia-utils nvidia-settings opencl-nvidia lib32-opencl-nvidia mangohud lib32-mangohud goverlay; do
                if ! bgo_is_pkg_installed "${pkg}"; then
                    nvidia_pkgs+=("${pkg}")
                fi
            done

            if ((${#nvidia_pkgs[@]} > 0)); then
                bgo_run_task "Installing NVIDIA Drivers & 32/64-bit Vulkan/OpenCL Stacks" \
                             "Cài đặt Driver NVIDIA và ngăn xếp Vulkan/OpenCL 32/64-bit" \
                             "pacman -S --needed --noconfirm ${nvidia_pkgs[*]}"
            else
                bgo_success "[EN] NVIDIA drivers and utilities are already installed." \
                            "[VI] Driver NVIDIA và các tiện ích đã có sẵn."
            fi

            # NVIDIA High Performance & Wayland Stability Tweaks
            mkdir -p /etc/modprobe.d
            cat << 'EOF' > /etc/modprobe.d/99-bgo-nvidia.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
options nvidia-drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
            bgo_record_patch "NVIDIA_DRM_MODESET" "Enabled NVIDIA DRM modesetting and memory preservation" "Kích hoạt DRM modeset và bảo toàn VRAM NVIDIA"

            systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service 2>/dev/null || true
        fi
    fi

    # --------------------------------------------------------------------------
    # 3. Intel Graphics & Vulkan Driver Configuration
    # --------------------------------------------------------------------------
    if [[ "${has_intel}" == true ]]; then
        bgo_info "[EN] Optimizing Intel Graphics Stack (ANV Vulkan & Hardware Acceleration)..." \
                 "[VI] Đang tối ưu hóa đồ họa Intel (Vulkan ANV & Tăng tốc phần cứng)..."

        if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
            local intel_pkgs=()
            for pkg in mesa lib32-mesa vulkan-intel lib32-vulkan-intel intel-media-driver libva-intel-driver mangohud lib32-mangohud goverlay; do
                if ! bgo_is_pkg_installed "${pkg}"; then
                    intel_pkgs+=("${pkg}")
                fi
            done

            if ((${#intel_pkgs[@]} > 0)); then
                bgo_run_task "Installing Intel Vulkan (ANV) & Media Acceleration (32/64-bit)" \
                             "Cài đặt Driver Intel Vulkan (ANV) & Tăng tốc Media (32/64-bit)" \
                             "pacman -S --needed --noconfirm ${intel_pkgs[*]}"
            else
                bgo_success "[EN] Intel drivers and utilities are already satisfied." \
                            "[VI] Driver Intel và các tiện ích đã có sẵn."
            fi
        fi
    fi

    # --------------------------------------------------------------------------
    # 4. Universal High-FPS MangoHud Gaming Configuration
    # --------------------------------------------------------------------------
    bgo_configure_mangohud_profile
}

bgo_configure_mangohud_profile() {
    local mh_dir="${BGO_USER_HOME}/.config/MangoHud"
    mkdir -p "${mh_dir}"
    local mh_conf="${mh_dir}/MangoHud.conf"

    if [[ ! -f "${mh_conf}" ]]; then
        cat << 'EOF' > "${mh_conf}"
# BigLinux Gaming Optimizer - MangoHud Preset
fps_limit=0
vsync=0
gl_vsync=0
legacy_layout=0
gpu_stats
gpu_temp
gpu_core_clock
gpu_mem_clock
gpu_power
cpu_stats
cpu_temp
cpu_mhz
cpu_power
ram
vram
fps
frametime=1
frame_timing=1
gamemode
arch
wine
position=top-left
round_corners=8
font_size=20
toggle_hud=Shift_R+F12
EOF
        chown -R "${BGO_USER_UID}:${BGO_USER_GID}" "${mh_dir}" 2>/dev/null || true
        bgo_record_patch "MANGOHUD_PRESET" "Installed high-performance MangoHud preset" "Thiết lập cấu hình hiển thị MangoHud FPS"
    fi
}
