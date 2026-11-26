#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Multilib & Hybrid 32/64-bit Architecture
# ==============================================================================

# Configure and verify 32-bit multilib support
bgo_configure_multilib() {
    bgo_info "[EN] Auditing and enabling 32-bit multilib architecture..." \
             "[VI] Kiểm tra và kích hoạt kiến trúc multilib 32-bit..."

    case "${BGO_DISTRO_FAMILY}" in
        arch)
            # Ensure /etc/pacman.conf has multilib enabled
            if grep -q "^\[multilib\]" /etc/pacman.conf; then
                bgo_info "[EN] Pacman [multilib] repository is already active." \
                         "[VI] Kho lưu trữ [multilib] của Pacman đã được kích hoạt từ trước."
            else
                bgo_info "[EN] Enabling [multilib] repository in /etc/pacman.conf..." \
                         "[VI] Đang mở kho [multilib] trong /etc/pacman.conf..."
                
                # Backup pacman.conf
                cp -f /etc/pacman.conf "/etc/pacman.conf.bgo_backup_$(date +%Y%m%d)"
                
                # Uncomment multilib section safely
                sed -i '/^#\[multilib\]/{s/^#//;n;s/^#//}' /etc/pacman.conf
                
                # If still not found (some custom configs have different comments), append it cleanly
                if ! grep -q "^\[multilib\]" /etc/pacman.conf; then
                    cat << 'EOF' >> /etc/pacman.conf

# >>> BIGLINUX-GAMING-OPTIMIZER BEGIN >>>
[multilib]
Include = /etc/pacman.d/mirrorlist
# <<< BIGLINUX-GAMING-OPTIMIZER END <<<
EOF
                fi
                bgo_record_patch "ARCH_MULTILIB" "Enabled multilib repository in /etc/pacman.conf" "Kích hoạt kho multilib trong /etc/pacman.conf"
            fi

            # Sync package databases
            bgo_run_task "Synchronizing pacman package databases" \
                         "Đồng bộ hóa cơ sở dữ liệu gói pacman" \
                         "pacman -Sy --noconfirm"

            # Install core 32-bit support libraries
            local core_32bit_pkgs=(
                lib32-glibc
                lib32-gcc-libs
                lib32-libx11
                lib32-libxext
                lib32-libxrandr
                lib32-libxinerama
                lib32-libxcursor
                lib32-alsa-plugins
                lib32-gnutls
                lib32-libpng
                lib32-freetype2
            )
            bgo_run_task "Installing essential 32-bit multilib runtime libraries" \
                         "Cài đặt các thư viện nền tảng multilib 32-bit thiết yếu" \
                         "pacman -S --needed --noconfirm ${core_32bit_pkgs[*]}"
            ;;

        debian)
            bgo_run_task "Adding i386 multiarch architecture" \
                         "Thêm kiến trúc đa nền tảng i386 (multiarch)" \
                         "dpkg --add-architecture i386 && apt-get update"
            bgo_record_patch "DEBIAN_I386" "Added i386 multiarch architecture" "Thêm kiến trúc i386"
            local deb_32bit_pkgs=(
                libc6:i386
                libstdc++6:i386
                libx11-6:i386
                libxext6:i386
                libasound2-plugins:i386
                libgnutls30:i386
            )
            bgo_run_task "Installing 32-bit runtime packages (Debian/Ubuntu)" \
                         "Cài đặt gói hỗ trợ 32-bit (Debian/Ubuntu)" \
                         "apt-get install -y ${deb_32bit_pkgs[*]}"
            ;;

        fedora)
            bgo_run_task "Installing 32-bit glibc & dependencies (Fedora)" \
                         "Cài đặt glibc 32-bit và gói phụ trợ (Fedora)" \
                         "dnf install -y glibc.i686 libstdc++.i686 libX11.i686 alsa-plugins-pulseaudio.i686"
            ;;

        *)
            bgo_warn "[EN] Distro not officially indexed for multilib automation; assuming manual configuration." \
                     "[VI] Bản phân phối chưa được lập chỉ mục cấu hình multilib tự động; giả định đã thiết lập."
            ;;
    esac

    bgo_success "[EN] 32-bit and 64-bit Multilib hybrid environment configured." \
                "[VI] Cấu hình môi trường hỗn hợp Multilib 32-bit và 64-bit hoàn tất."
}
