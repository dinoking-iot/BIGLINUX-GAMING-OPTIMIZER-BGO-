#!/usr/bin/env bash
# ==============================================================================
# Script Name: biglinux_gaming_optimizer.sh
# Description: Automated, production-grade Gaming & Compatibility Suite for BigLinux
# Supported:   BigLinux, Arch Linux, Manjaro, Debian, Ubuntu, Fedora & Derivatives
# Language:    Bilingual (English Primary & Vietnamese)
# ==============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source all modular libraries
# shellcheck source=lib/bgo_core.sh
source "${SCRIPT_DIR}/lib/bgo_core.sh"
# shellcheck source=lib/bgo_multilib.sh
source "${SCRIPT_DIR}/lib/bgo_multilib.sh"
# shellcheck source=lib/bgo_gpu.sh
source "${SCRIPT_DIR}/lib/bgo_gpu.sh"
# shellcheck source=lib/bgo_kernel.sh
source "${SCRIPT_DIR}/lib/bgo_kernel.sh"
# shellcheck source=lib/bgo_runtimes.sh
source "${SCRIPT_DIR}/lib/bgo_runtimes.sh"
# shellcheck source=lib/bgo_system.sh
source "${SCRIPT_DIR}/lib/bgo_system.sh"
# shellcheck source=lib/bgo_wine.sh
source "${SCRIPT_DIR}/lib/bgo_wine.sh"
# shellcheck source=lib/bgo_rollback.sh
source "${SCRIPT_DIR}/lib/bgo_rollback.sh"

# Signal handling for user abort
trap 'echo -e "\n${BGO_COLOR_YELLOW}[EN] Process interrupted by user. / [VI] Tiến trình đã bị hủy bởi người dùng.${BGO_COLOR_RESET}"; exit 130' SIGINT
trap 'echo -e "\n${BGO_COLOR_YELLOW}[EN] Process terminated. / [VI] Tiến trình đã bị dừng.${BGO_COLOR_RESET}"; exit 143' SIGTERM

# Root Elevation Check
bgo_check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${BGO_COLOR_YELLOW}[EN] Root privileges required. Re-launching with sudo...${BGO_COLOR_RESET}"
        echo -e "${BGO_COLOR_GRAY}[VI] Yêu cầu quyền Root. Đang tự động gọi sudo...${BGO_COLOR_RESET}"
        exec sudo bash "$0" "$@"
    fi
}

# Display Bilingual Help
bgo_show_help() {
    bgo_banner
    echo -e "${BGO_COLOR_BOLD}USAGE / HƯỚNG DẪN SỬ DỤNG:${BGO_COLOR_RESET}"
    echo -e "  sudo $0 [OPTION]"
    echo ""
    echo -e "${BGO_COLOR_BOLD}OPTIONS / TÙY CHỌN:${BGO_COLOR_RESET}"
    echo -e "  ${BGO_COLOR_CYAN}--install${BGO_COLOR_RESET}      (Default) Full automated gaming optimization & runtime setup"
    echo -e "                 (Mặc định) Toàn bộ tiến trình tối ưu hóa và cài đặt runtimes"
    echo -e "  ${BGO_COLOR_CYAN}--status${BGO_COLOR_RESET}       Inspect and audit system gaming readiness without changes"
    echo -e "                 Kiểm tra trạng thái hệ thống gaming hiện tại (không thay đổi cấu hình)"
    echo -e "  ${BGO_COLOR_CYAN}--uninstall${BGO_COLOR_RESET}    Rollback optimizer configurations and restore defaults"
    echo -e "  ${BGO_COLOR_CYAN}--rollback${BGO_COLOR_RESET}     Gỡ bỏ các cấu hình tinh chỉnh và hoàn nguyên hệ thống"
    echo -e "  ${BGO_COLOR_CYAN}--clean-cache${BGO_COLOR_RESET}  Execute immediate Pacman / Pamac package cache cleanup"
    echo -e "                 Dọn dẹp tức thì bộ nhớ đệm gói phần mềm Pacman / Pamac"
    echo -e "  ${BGO_COLOR_CYAN}--help, -h${BGO_COLOR_RESET}     Display this bilingual help menu"
    echo -e "                 Hiển thị bảng trợ giúp này"
    echo ""
}

# System Readiness Audit Mode
bgo_status_check() {
    bgo_banner
    echo -e "${BGO_COLOR_BOLD}🔍 SYSTEM GAMING AUDIT / KIỂM TRA TRẠNG THÁI HỆ THỐNG:${BGO_COLOR_RESET}"
    echo -e "------------------------------------------------------------------------"
    
    # 1. Kernel Audit
    local kver
    kver="$(uname -r)"
    echo -ne " [Kernel / Nhân hệ điều hành]: ${kver} -> "
    if echo "${kver}" | grep -qiE "xanmod|zen|cachyos|tkg"; then
        echo -e "${BGO_COLOR_GREEN}Gaming Kernel Active (XanMod/Zen)${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_YELLOW}Generic Kernel (Gaming Kernel Recommended)${BGO_COLOR_RESET}"
    fi

    # 2. Multilib Audit
    echo -ne " [Multilib 32-bit Architecture]: "
    if grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
        echo -e "${BGO_COLOR_GREEN}Enabled / Đã kích hoạt${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_RED}Disabled / Chưa kích hoạt${BGO_COLOR_RESET}"
    fi

    # 3. Vulkan & GPU Audit
    echo -ne " [Vulkan 64-bit ICD]: "
    if [[ -d /usr/share/vulkan/icd.d && $(ls -A /usr/share/vulkan/icd.d 2>/dev/null) ]]; then
        echo -e "${BGO_COLOR_GREEN}Available / Sẵn sàng${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_RED}Not Found / Chưa tìm thấy${BGO_COLOR_RESET}"
    fi

    echo -ne " [Vulkan 32-bit ICD]: "
    if [[ -d /usr/share/vulkan/icd.d && -f /usr/lib32/libvulkan.so.1 ]]; then
        echo -e "${BGO_COLOR_GREEN}Available / Sẵn sàng${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_YELLOW}Missing or Incomplete / Thiếu thư viện 32-bit${BGO_COLOR_RESET}"
    fi

    # 4. Sysctl Gaming Parameters Audit
    local cur_map
    cur_map="$(sysctl -n vm.max_map_count 2>/dev/null || echo 0)"
    echo -ne " [vm.max_map_count]: ${cur_map} -> "
    if (( cur_map >= 2147483642 )); then
        echo -e "${BGO_COLOR_GREEN}Optimal (>= 2147483642)${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_YELLOW}Suboptimal (Fix required for Star Citizen / EAC)${BGO_COLOR_RESET}"
    fi

    # 5. Wine & WoW64
    echo -ne " [Wine / WoW64 Engine]: "
    if command -v wine &>/dev/null; then
        echo -e "${BGO_COLOR_GREEN}$(wine --version 2>/dev/null)${BGO_COLOR_RESET}"
    else
        echo -e "${BGO_COLOR_RED}Not Installed / Chưa cài đặt${BGO_COLOR_RESET}"
    fi

    echo -e "------------------------------------------------------------------------"
    echo -e "Run '${BGO_COLOR_CYAN}sudo $0 --install${BGO_COLOR_RESET}' to automatically optimize all components."
    echo ""
}

# Main Full Execution Routine
bgo_main_install() {
    bgo_banner
    bgo_start_logging_daemon

    bgo_info "[EN] Starting automated gaming optimization pipeline..." \
             "[VI] Khởi động tiến trình tối ưu hóa hệ thống chơi game tự động..."

    # Step 1: Multilib and Hybrid 32/64-bit Architecture
    bgo_step 1 6 \
        "Configuring Multilib & Hybrid 32/64-bit Architecture" \
        "Cấu hình kiến trúc Multilib và môi trường hỗn hợp 32/64-bit"
    bgo_configure_multilib

    # Step 2: GPU Drivers & Vulkan & Controllers
    bgo_step 2 6 \
        "Detecting GPU & Installing 32/64-bit Vulkan Drivers & Controllers" \
        "Nhận diện GPU, cài đặt Driver Vulkan 32/64-bit và bộ điều khiển đồ họa"
    bgo_detect_and_install_gpu

    # Step 3: Low-Latency Gaming Kernel
    bgo_step 3 6 \
        "Auditing & Installing Low-Latency Gaming Kernel (BigLinux/XanMod/Zen)" \
        "Kiểm tra và cài đặt Kernel Gaming độ trễ thấp (BigLinux/XanMod/Zen)"
    bgo_optimize_kernel

    # Step 4: Essential Runtimes (DirectX, .NET, VC++, Java, WebView2)
    bgo_step 4 6 \
        "Installing Essential Runtimes (DirectX 9-12, .NET, VC++, Java, WebView2)" \
        "Cài đặt toàn bộ Runtime bắt buộc (DirectX 9-12, .NET, VC++, Java, WebView2)"
    bgo_install_essential_runtimes

    # Step 5: System Tuning, Audio & Network Fixes
    bgo_step 5 6 \
        "Applying Audio, USB Hub & Network Fixes, Virtual Memory & GameMode Tuning" \
        "Sửa lỗi âm thanh, USB Hub & mất mạng, tối ưu bộ nhớ ảo và GameMode"
    bgo_optimize_system

    # Step 6: Pure Wine WOW64, Click-to-Run & Cache Cleaner
    bgo_step 6 6 \
        "Configuring Pure Wine WOW64, Click-to-Run & Auto Cache Cleaner" \
        "Thiết lập Wine WOW64 thuần túy, Click là chạy và Tự dọn dẹp Cache"
    bgo_setup_wine_and_cache

    # Display Final Report
    bgo_show_summary

    echo -e "${BGO_COLOR_CYAN}ℹ [EN] Continuous background logging daemon is actively running until reboot.${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_GRAY}  [VI] Tiến trình ghi log gỡ lỗi hệ thống ngầm đang hoạt động cho đến khi khởi động lại máy.${BGO_COLOR_RESET}"
    echo ""
    echo -e "${BGO_COLOR_GREEN}${BGO_COLOR_BOLD}💡 RECOMMENDATION / KHUYẾN NGHỊ:${BGO_COLOR_RESET}"
    echo -e " [EN] A system reboot is strongly recommended to load all updated kernel modules & sysctl parameters."
    echo -e " [VI] Khuyến nghị khởi động lại máy để nạp đầy đủ các module kernel và thông số tối ưu mới nhất."
    echo ""
}

# Entrypoint Dispatcher
main() {
    bgo_detect_user
    bgo_detect_environment

    local action="${1:---install}"

    case "${action}" in
        --install)
            bgo_check_root "$@"
            bgo_main_install
            ;;
        --uninstall|--rollback)
            bgo_check_root "$@"
            bgo_perform_rollback
            ;;
        --status|--check)
            bgo_status_check
            ;;
        --clean-cache)
            bgo_check_root "$@"
            if [[ -x /usr/local/bin/bgo-clean-cache ]]; then
                /usr/local/bin/bgo-clean-cache
            else
                bgo_setup_cache_cleaner
                /usr/local/bin/bgo-clean-cache
            fi
            ;;
        --help|-h)
            bgo_show_help
            ;;
        *)
            echo -e "${BGO_COLOR_RED}Unknown option: ${action}${BGO_COLOR_RESET}"
            bgo_show_help
            exit 1
            ;;
    esac
}

main "$@"
