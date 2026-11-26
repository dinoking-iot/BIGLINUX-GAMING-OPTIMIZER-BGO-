#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Audio & Network Fixes, Virtual Memory, Sysctl
# ==============================================================================

bgo_optimize_system() {
    bgo_fix_audio_drops
    bgo_fix_network_drops
    bgo_optimize_virtual_memory
    bgo_optimize_limits
    bgo_setup_gamemode
}

# ------------------------------------------------------------------------------
# 1. Audio Fix: Prevent Sound Drops on Login / Idle
# ------------------------------------------------------------------------------
bgo_fix_audio_drops() {
    bgo_info "[EN] Fixing audio loss and crackling on login (Disabling audio power-saving)..." \
             "[VI] Khắc phục lỗi mất âm thanh khi đăng nhập (Tắt chế độ tiết kiệm điện chip âm thanh)..."

    # Disable snd_hda_intel and snd_ac97 power saving
    mkdir -p /etc/modprobe.d
    cat << 'EOF' > /etc/modprobe.d/99-bgo-audio-powersave.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
# Disable power saving on audio codecs to eliminate audio cut-offs on login/resume
options snd_hda_intel power_save=0 power_save_controller=N
options snd_ac97_codec power_save=0
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    bgo_record_patch "AUDIO_POWERSAVE" "Disabled audio power saving in modprobe" "Tắt tiết kiệm điện âm thanh"

    # Configure WirePlumber / PipeWire to prevent suspending audio sinks
    local wp_conf_dir="/etc/wireplumber/wireplumber.conf.d"
    mkdir -p "${wp_conf_dir}"
    cat << 'EOF' > "${wp_conf_dir}/99-bgo-disable-suspend.conf"
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
# Keep PipeWire audio sinks awake to prevent audio dropouts during gaming and login
monitor.alsa.rules = [
  {
    matches = [
      { node.name = "~alsa_input.*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  },
  {
    matches = [
      { node.name = "~alsa_output.*" }
    ]
    actions = {
      update-props = {
        session.suspend-timeout-seconds = 0
      }
    }
  }
]
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    bgo_record_patch "PIPEWIRE_KEEP_ALIVE" "Configured PipeWire keep-alive timeout" "Thiết lập giữ kết nối PipeWire"
    bgo_success "[EN] Audio persistent configuration applied." \
                "[VI] Cấu hình ổn định âm thanh không ngắt kết nối đã áp dụng."
}

# ------------------------------------------------------------------------------
# 2. Network Fix: Prevent WiFi/Ethernet Drops on Login
# ------------------------------------------------------------------------------
bgo_fix_network_drops() {
    bgo_info "[EN] Fixing WiFi & Network disconnection on login (Disabling powersave & BBR tuning)..." \
             "[VI] Khắc phục mất mạng khi đăng nhập (Tắt tiết kiệm pin WiFi & Tối ưu thuật toán BBR)..."

    local nm_conf_dir="/etc/NetworkManager/conf.d"
    mkdir -p "${nm_conf_dir}"
    cat << 'EOF' > "${nm_conf_dir}/99-bgo-disable-wifi-powersave.conf"
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
[connection]
# wifi.powersave: 2 = disable, 3 = enable
wifi.powersave = 2
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    bgo_record_patch "WIFI_POWERSAVE" "Disabled WiFi power saving in NetworkManager" "Tắt tiết kiệm điện WiFi"

    # Network Low-Latency & Throughput Tuning
    cat << 'EOF' > /etc/sysctl.d/99-bgo-network.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
# Enable BBR Congestion Control & Cake queue discipline for low latency gaming
net.core.default_qdisc = fq_codel
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    sysctl -p /etc/sysctl.d/99-bgo-network.conf &>/dev/null || sysctl --system &>/dev/null || true
    bgo_record_patch "NETWORK_BBR" "Enabled BBR congestion control and fq_codel" "Kích hoạt điều phối mạng BBR"
    bgo_success "[EN] Network stability and gaming ping optimizations applied." \
                "[VI] Cấu hình ổn định mạng và tối ưu ping chơi game đã áp dụng."
}

# ------------------------------------------------------------------------------
# 3. Virtual Memory & Gaming Sysctl Optimizations
# ------------------------------------------------------------------------------
bgo_optimize_virtual_memory() {
    bgo_info "[EN] Applying High-Performance Virtual Memory & Gaming Kernel Sysctl tweaks..." \
             "[VI] Thiết lập tinh chỉnh bộ nhớ ảo và thông số kernel tối ưu hóa game..."

    cat << 'EOF' > /etc/sysctl.d/99-bgo-gaming-performance.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
# Essential for modern Windows games, EAC, BattlEye, and Star Citizen
vm.max_map_count = 2147483642

# Prioritize physical RAM over disk swap during gameplay
vm.swappiness = 10

# Retain directory and inode cache in RAM
vm.vfs_cache_pressure = 50

# Prevent sudden write-burst freezing by smoothing dirty pages
vm.dirty_background_ratio = 5
vm.dirty_ratio = 10

# Maximum open file descriptors
fs.file-max = 2097152

# Disable split-lock mitigation (prevents severe stuttering in modern games like God of War)
kernel.split_lock_mitigate = 0

# CPU scheduling latency tuning
kernel.sched_cfs_bandwidth_slice_us = 3000
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    sysctl -p /etc/sysctl.d/99-bgo-gaming-performance.conf &>/dev/null || sysctl --system &>/dev/null || true
    bgo_record_patch "SYSCTL_GAMING" "Applied vm.max_map_count, swappiness, and split-lock fixes" "Tối ưu bộ nhớ ảo và giảm giật lag split-lock"
    bgo_success "[EN] Virtual memory tuned for maximum FPS and zero micro-stutters." \
                "[VI] Bộ nhớ ảo đã được tinh chỉnh cho FPS cao và loại bỏ giật khung hình."
}

# ------------------------------------------------------------------------------
# 4. Security PAM Limits (Esync & Fsync Prerequisite)
# ------------------------------------------------------------------------------
bgo_optimize_limits() {
    bgo_info "[EN] Configuring system limits for Esync & Fsync support..." \
             "[VI] Cấu hình giới hạn tài nguyên hệ thống hỗ trợ Esync & Fsync..."

    mkdir -p /etc/security/limits.d
    cat << 'EOF' > /etc/security/limits.d/99-bgo-gaming.conf
# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
root soft nofile 1048576
root hard nofile 1048576
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
    bgo_record_patch "PAM_LIMITS" "Increased open file and memlock limits for Esync/Fsync" "Tăng giới hạn file descriptior cho Esync/Fsync"
    bgo_success "[EN] Esync / Fsync limits configured." \
                "[VI] Đã cấu hình giới hạn Esync / Fsync."
}

# ------------------------------------------------------------------------------
# 5. GameMode Daemon & CPU Performance Automation
# ------------------------------------------------------------------------------
bgo_setup_gamemode() {
    bgo_info "[EN] Setting up Feral GameMode daemon & CPU governor automation..." \
             "[VI] Thiết lập dịch vụ Feral GameMode và tự động tăng tốc CPU..."

    local task_rc=0
    if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
        bgo_run_task "Installing GameMode (64-bit & 32-bit)" \
                     "Cài đặt GameMode (64-bit & 32-bit)" \
                     "pacman -S --needed --noconfirm gamemode lib32-gamemode" || task_rc=$?
    elif [[ "${BGO_DISTRO_FAMILY}" == "debian" ]]; then
        bgo_run_task "Installing GameMode (Debian/Ubuntu)" \
                     "Cài đặt GameMode (Debian/Ubuntu)" \
                     "apt-get install -y gamemode" || task_rc=$?
    fi

    if [[ ${task_rc} -ne 0 ]]; then
        bgo_warn "[EN] GameMode installation failed (Exit code: ${task_rc}). GameMode optimizations will be unavailable." \
                 "[VI] Cài đặt GameMode thất bại (Mã lỗi: ${task_rc}). Tính năng tối ưu GameMode sẽ không khả dụng."
        return 0
    fi

    # Configure user group for gamemode
    usermod -aG gamemode "${BGO_USER}" 2>/dev/null || true

    # Enable gamemoded service for user if possible
    systemctl --user -M "${BGO_USER}@" enable --now gamemoded.service 2>/dev/null || true
    bgo_record_patch "GAMEMODE" "Enabled GameMode integration" "Kích hoạt GameMode"
}
