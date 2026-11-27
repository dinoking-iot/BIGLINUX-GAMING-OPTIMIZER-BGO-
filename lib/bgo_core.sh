#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Core Library
# Bilingual: English (Primary) & Vietnamese
# ==============================================================================

# Strict mode safety, but allow handled errors
set -uo pipefail

# Script Version & Patch Architecture
export BGO_VERSION="1.1.0"

# ANSI Colors & Formatting
export BGO_COLOR_RESET='\033[0m'
export BGO_COLOR_BOLD='\033[1m'
export BGO_COLOR_DIM='\033[2m'
export BGO_COLOR_RED='\033[38;5;196m'
export BGO_COLOR_GREEN='\033[38;5;46m'
export BGO_COLOR_YELLOW='\033[38;5;226m'
export BGO_COLOR_BLUE='\033[38;5;39m'
export BGO_COLOR_MAGENTA='\033[38;5;201m'
export BGO_COLOR_CYAN='\033[38;5;51m'
export BGO_COLOR_WHITE='\033[38;5;231m'
export BGO_COLOR_GRAY='\033[38;5;244m'

# Execution Counters & Patch Tracking
export BGO_TOTAL_TASKS=0
export BGO_SUCCESS_TASKS=0
export BGO_WARNING_TASKS=0
export BGO_ERROR_TASKS=0
declare -a BGO_APPLIED_PATCHES=()
declare -a BGO_WARNING_MESSAGES=()
declare -a BGO_ERROR_MESSAGES=()

# Paths & Execution Context
BGO_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BGO_SCRIPT_DIR
export BGO_LOG_DIR="${BGO_SCRIPT_DIR}/logs"
mkdir -p "${BGO_LOG_DIR}"

TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
export BGO_LOG_FILE="${BGO_LOG_DIR}/biglinux_gaming_${TIMESTAMP}.log"
export BGO_NOTIFICATION_CACHE="/tmp/.bgo_notify_cache_${UID:-1000}"
export BGO_STATE_FILE="/etc/biglinux-gaming-optimizer/state.json"
export BGO_DAEMON_PID_FILE="/tmp/.bgo_daemon_${UID:-1000}.pid"

# Dynamic Target User Detection
bgo_detect_user() {
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        export BGO_USER="${SUDO_USER}"
    elif [[ -n "${USER:-}" && "${USER}" != "root" ]]; then
        export BGO_USER="${USER}"
    else
        export BGO_USER="$(getent passwd 1000 2>/dev/null | cut -d: -f1 || logname 2>/dev/null || whoami)"
    fi

    export BGO_USER_HOME="$(getent passwd "${BGO_USER}" | cut -d: -f6)"
    if [[ -z "${BGO_USER_HOME}" || ! -d "${BGO_USER_HOME}" ]]; then
        export BGO_USER_HOME="/home/${BGO_USER}"
    fi

    export BGO_USER_UID="$(id -u "${BGO_USER}" 2>/dev/null || echo 1000)"
    export BGO_USER_GID="$(id -g "${BGO_USER}" 2>/dev/null || echo 1000)"
}

# Run command as target regular user
bgo_run_as_user() {
    local cmd="$*"
    if [[ "$(id -u)" -eq 0 && "${BGO_USER}" != "root" ]]; then
        su - "${BGO_USER}" -c "export HOME='${BGO_USER_HOME}'; export XDG_RUNTIME_DIR='/run/user/${BGO_USER_UID}'; ${cmd}"
    else
        bash -c "${cmd}"
    fi
}

# OS & Environment Detection
bgo_detect_environment() {
    export BGO_OS_NAME="Linux"
    export BGO_OS_ID="unknown"
    export BGO_PKG_MGR="unknown"
    export BGO_DISTRO_FAMILY="unknown"

    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        BGO_OS_NAME="${PRETTY_NAME:-$NAME}"
        BGO_OS_ID="${ID:-unknown}"
        BGO_ID_LIKE="${ID_LIKE:-}"
    fi

    # Determine Package Manager
    if command -v pacman &>/dev/null; then
        BGO_PKG_MGR="pacman"
        BGO_DISTRO_FAMILY="arch"
        if command -v pamac &>/dev/null; then
            export BGO_HAS_PAMAC=true
        else
            export BGO_HAS_PAMAC=false
        fi
    elif command -v apt-get &>/dev/null; then
        BGO_PKG_MGR="apt"
        BGO_DISTRO_FAMILY="debian"
        export BGO_HAS_PAMAC=false
    elif command -v dnf &>/dev/null; then
        BGO_PKG_MGR="dnf"
        BGO_DISTRO_FAMILY="fedora"
        export BGO_HAS_PAMAC=false
    fi

    # Detect Display Server & Desktop
    export BGO_DISPLAY_SERVER="${XDG_SESSION_TYPE:-unknown}"
    if [[ "${BGO_DISPLAY_SERVER}" == "unknown" ]]; then
        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            BGO_DISPLAY_SERVER="wayland"
        elif [[ -n "${DISPLAY:-}" ]]; then
            BGO_DISPLAY_SERVER="x11"
        else
            BGO_DISPLAY_SERVER="headless/tty"
        fi
    fi
    export BGO_DESKTOP_ENV="${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

# Pacman Database Lock Guard
# Waits up to 30 seconds for pacman DB lock to clear, then removes stale lock if safe
bgo_pacman_wait_lock() {
    local lock_file="/var/lib/pacman/db.lck"
    local wait_secs=0
    local max_wait=30

    while [[ -f "${lock_file}" ]] && (( wait_secs < max_wait )); do
        # Check if any pacman process is actually running
        if ! pgrep -x pacman &>/dev/null && ! pgrep -x pamac &>/dev/null; then
            bgo_log_raw "WARN" "[EN] Stale pacman DB lock detected (no pacman process running). Removing lock. | [VI] Phát hiện lock database pacman lỗi thời (không có tiến trình pacman). Đang xóa lock."
            rm -f "${lock_file}" 2>/dev/null || true
            break
        fi
        bgo_log_raw "INFO" "[EN] Pacman DB is locked by an active process. Waiting... (${wait_secs}s) | [VI] Database pacman đang bị khóa. Đang chờ... (${wait_secs}s)"
        sleep 2
        (( wait_secs += 2 )) || true
    done

    if [[ -f "${lock_file}" ]] && (( wait_secs >= max_wait )); then
        bgo_log_raw "WARN" "[EN] Pacman lock timed out after ${max_wait}s. Forcing lock removal. | [VI] Hết thời gian chờ lock pacman (${max_wait}s). Buộc xóa lock."
        rm -f "${lock_file}" 2>/dev/null || true
    fi
}

# Intelligent Package & Virtual Provider Satisfaction Checker
bgo_is_pkg_installed() {
    local pkg="$1"
    if [[ "${BGO_PKG_MGR}" == "pacman" ]]; then
        pacman -T "${pkg}" &>/dev/null
    elif [[ "${BGO_PKG_MGR}" == "apt" ]]; then
        dpkg -s "${pkg}" &>/dev/null
    elif [[ "${BGO_PKG_MGR}" == "dnf" ]]; then
        rpm -q "${pkg}" &>/dev/null
    else
        command -v "${pkg}" &>/dev/null
    fi
}

# Logging Helpers
bgo_log_raw() {
    local level="$1"
    shift
    local msg="$*"
    local log_time
    log_time="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "[${log_time}] [${level}] ${msg}" >> "${BGO_LOG_FILE}" 2>/dev/null || true
}

# Bilingual Terminal Output
bgo_banner() {
    clear 2>/dev/null || true
    echo -e "${BGO_COLOR_CYAN}${BGO_COLOR_BOLD}========================================================================${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_CYAN}${BGO_COLOR_BOLD}   🚀 BIGLINUX GAMING OPTIMIZER & COMPATIBILITY SUITE (v${BGO_VERSION}) 🎮   ${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_GRAY}   Automated Drivers | Gaming Kernel | DirectX | .NET | Wine WoW64    ${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_CYAN}${BGO_COLOR_BOLD}========================================================================${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_WHITE}System:${BGO_COLOR_RESET} ${BGO_OS_NAME} (${BGO_DISTRO_FAMILY}) | ${BGO_DISPLAY_SERVER} / ${BGO_DESKTOP_ENV}"
    echo -e "${BGO_COLOR_WHITE}Target User:${BGO_COLOR_RESET} ${BGO_USER} (Home: ${BGO_USER_HOME})"
    echo -e "${BGO_COLOR_WHITE}Session Log:${BGO_COLOR_RESET} ${BGO_LOG_FILE}"
    echo -e "${BGO_COLOR_CYAN}------------------------------------------------------------------------${BGO_COLOR_RESET}"
    echo ""
}

bgo_step() {
    local cur="$1"
    local total="$2"
    local en="$3"
    local vi="$4"
    echo ""
    echo -e "${BGO_COLOR_BLUE}${BGO_COLOR_BOLD}[${cur}/${total}] ${en}${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_GRAY}        ${vi}${BGO_COLOR_RESET}"
    bgo_log_raw "STEP" "Step [${cur}/${total}]: ${en} | ${vi}"
    bgo_notify "BigLinux Gaming Optimizer [${cur}/${total}]" "${en}\n${vi}" "dialog-information"
}

bgo_info() {
    local en="$1"
    local vi="${2:-}"
    echo -e " ${BGO_COLOR_CYAN}ℹ${BGO_COLOR_RESET} ${en}"
    if [[ -n "${vi}" ]]; then
        echo -e "   ${BGO_COLOR_GRAY}↳ ${vi}${BGO_COLOR_RESET}"
    fi
    bgo_log_raw "INFO" "${en} | ${vi}"
}

bgo_success() {
    local en="$1"
    local vi="${2:-}"
    echo -e " ${BGO_COLOR_GREEN}✔${BGO_COLOR_RESET} ${BGO_COLOR_GREEN}${en}${BGO_COLOR_RESET}"
    if [[ -n "${vi}" ]]; then
        echo -e "   ${BGO_COLOR_GRAY}↳ ${vi}${BGO_COLOR_RESET}"
    fi
    bgo_log_raw "SUCCESS" "${en} | ${vi}"
    ((BGO_SUCCESS_TASKS++)) || true
}

bgo_warn() {
    local en="$1"
    local vi="${2:-}"
    echo -e " ${BGO_COLOR_YELLOW}⚠${BGO_COLOR_RESET} ${BGO_COLOR_YELLOW}${en}${BGO_COLOR_RESET}"
    if [[ -n "${vi}" ]]; then
        echo -e "   ${BGO_COLOR_GRAY}↳ ${vi}${BGO_COLOR_RESET}"
    fi
    bgo_log_raw "WARN" "${en} | ${vi}"
    BGO_WARNING_MESSAGES+=("${en} / ${vi}")
    ((BGO_WARNING_TASKS++)) || true
}

bgo_error() {
    local en="$1"
    local vi="${2:-}"
    echo -e " ${BGO_COLOR_RED}✖${BGO_COLOR_RESET} ${BGO_COLOR_RED}${BGO_COLOR_BOLD}${en}${BGO_COLOR_RESET}"
    if [[ -n "${vi}" ]]; then
        echo -e "   ${BGO_COLOR_GRAY}↳ ${vi}${BGO_COLOR_RESET}"
    fi
    bgo_log_raw "ERROR" "${en} | ${vi}"
    BGO_ERROR_MESSAGES+=("${en} / ${vi}")
    ((BGO_ERROR_TASKS++)) || true
}

# Record an applied patch for auditing and rollback
bgo_record_patch() {
    local patch_id="$1"
    local en_desc="$2"
    local vi_desc="$3"
    BGO_APPLIED_PATCHES+=("[${patch_id}] ${en_desc} (${vi_desc})")
    bgo_log_raw "PATCH" "Applied patch: [${patch_id}] ${en_desc} | ${vi_desc}"
}

# Desktop Notification with Anti-Spam Control
bgo_notify() {
    local title="$1"
    local message="$2"
    local icon="${3:-applications-games}"

    local msg_hash
    msg_hash="$(echo -n "${title}_${message}" | md5sum | awk '{print $1}')"
    local current_time
    current_time=$(date +%s)

    if [[ -f "${BGO_NOTIFICATION_CACHE}" ]]; then
        local last_hash last_time
        read -r last_hash last_time < "${BGO_NOTIFICATION_CACHE}" 2>/dev/null || true
        if [[ "${last_hash}" == "${msg_hash}" ]]; then
            local diff=$(( current_time - last_time ))
            if (( diff < 10 )); then
                return 0
            fi
        fi
    fi
    echo "${msg_hash} ${current_time}" > "${BGO_NOTIFICATION_CACHE}" 2>/dev/null || true

    if command -v notify-send &>/dev/null; then
        local user_dbus="/run/user/${BGO_USER_UID}/bus"
        if [[ -S "${user_dbus}" && "$(id -u)" -eq 0 && "${BGO_USER}" != "root" ]]; then
            sudo -u "${BGO_USER}" DBUS_SESSION_BUS_ADDRESS="unix:path=${user_dbus}" notify-send -a "BigLinux Gaming Optimizer" -i "${icon}" "${title}" "${message}" 2>/dev/null || true
        elif [[ -n "${DISPLAY:-}" || -n "${WAYLAND_DISPLAY:-}" ]]; then
            notify-send -a "BigLinux Gaming Optimizer" -i "${icon}" "${title}" "${message}" 2>/dev/null || true
        fi
    fi
}

# Spinner & Progress Execution Wrapper
bgo_run_task() {
    local en_desc="$1"
    local vi_desc="$2"
    shift 2
    local cmd="$*"

    ((BGO_TOTAL_TASKS++)) || true
    bgo_info "[Working] ${en_desc}..." "${vi_desc}..."

    # Auto-clear stale pacman DB lock before any pacman/pamac operation
    if echo "${cmd}" | grep -qE "^(pacman|pamac) "; then
        bgo_pacman_wait_lock
    fi

    local spin_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_idx=0
    local tmp_err
    tmp_err=$(mktemp "/tmp/bgo_task_err_XXXXXX")

    eval "${cmd}" >> "${BGO_LOG_FILE}" 2> "${tmp_err}" &
    local task_pid=$!

    while kill -0 "${task_pid}" 2>/dev/null; do
        printf "\r   ${BGO_COLOR_CYAN}%s${BGO_COLOR_RESET} %s [Processing / Đang xử lý...]" "${spin_chars[spin_idx]}" "${en_desc}"
        spin_idx=$(( (spin_idx + 1) % 10 ))
        sleep 0.1
    done

    wait "${task_pid}"
    local exit_code=$?
    printf "\r\033[K"

    if [[ ${exit_code} -eq 0 ]]; then
        bgo_success "${en_desc} completed successfully." "${vi_desc} hoàn tất thành công."
        rm -f "${tmp_err}"
        return 0
    else
        local err_detail
        err_detail=$(head -n 5 "${tmp_err}" 2>/dev/null)
        bgo_error "${en_desc} failed (Exit code: ${exit_code})!" "${vi_desc} thất bại (Mã lỗi: ${exit_code})!"
        if [[ -n "${err_detail}" ]]; then
            echo -e "   ${BGO_COLOR_RED}Detail: ${err_detail}${BGO_COLOR_RESET}"
            bgo_log_raw "TASK_STDERR" "${err_detail}"
        fi
        rm -f "${tmp_err}"
        return "${exit_code}"
    fi
}

# Continuous Background Logging Daemon (telemetry monitor until reboot)
bgo_start_logging_daemon() {
    if [[ -f "${BGO_DAEMON_PID_FILE}" ]]; then
        local old_pid
        old_pid="$(cat "${BGO_DAEMON_PID_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${old_pid}" ]] && kill -0 "${old_pid}" 2>/dev/null; then
            return 0
        fi
    fi

    (
        trap 'rm -f "${BGO_DAEMON_PID_FILE}"; exit 0' SIGTERM SIGINT SIGHUP EXIT
        echo $$ > "${BGO_DAEMON_PID_FILE}"
        bgo_log_raw "DAEMON" "Background health and system monitor daemon started (PID: $$)."

        while true; do
            local mem_info cpu_load temp_info
            mem_info="$(free -m | awk '/Mem:/ {printf "RAM: %d/%dMB (%.1f%%)", $3, $2, $3/$2*100}' 2>/dev/null || echo "RAM: N/A")"
            cpu_load="$(uptime | awk -F'load average:' '{print $2}' | xargs 2>/dev/null || echo "N/A")"
            temp_info="$(sensors 2>/dev/null | grep -E 'Package id 0|Tctl|edge' | grep -oE '\+[0-9]+(\.[0-9]+)?°C' | head -n1 || echo "N/A")"

            bgo_log_raw "METRIC" "Monitor: ${mem_info} | Load Avg: ${cpu_load} | Temp: ${temp_info}"
            sleep 20
        done
    ) &
    disown
}

bgo_stop_logging_daemon() {
    if [[ -f "${BGO_DAEMON_PID_FILE}" ]]; then
        local daemon_pid
        daemon_pid="$(cat "${BGO_DAEMON_PID_FILE}" 2>/dev/null || echo "")"
        if [[ -n "${daemon_pid}" ]] && kill -0 "${daemon_pid}" 2>/dev/null; then
            kill "${daemon_pid}" 2>/dev/null || true
            bgo_log_raw "DAEMON" "Background logging daemon stopped (PID: ${daemon_pid})."
        fi
        rm -f "${BGO_DAEMON_PID_FILE}"
    fi
}

# Final Execution Summary (Mirrored to console and persistent log file)
bgo_show_summary() {
    local summary_text
    summary_text=$(cat << EOF
========================================================================
             📋 EXECUTION SUMMARY / BẢNG TỔNG KẾT TIẾN TRÌNH           
========================================================================
 Total Operations Executed / Tổng số tác vụ:  ${BGO_TOTAL_TASKS}
 Successful / Thành công:                     ${BGO_SUCCESS_TASKS}
 Warnings / Cảnh báo:                         ${BGO_WARNING_TASKS}
 Errors / Lỗi phát sinh:                      ${BGO_ERROR_TASKS}
 Applied Patches / Bản vá đã áp dụng:         ${#BGO_APPLIED_PATCHES[@]}
------------------------------------------------------------------------
EOF
)

    echo ""
    echo -e "${BGO_COLOR_CYAN}${BGO_COLOR_BOLD}${summary_text}${BGO_COLOR_RESET}"
    bgo_log_raw "SUMMARY" "${summary_text}"

    if ((${#BGO_APPLIED_PATCHES[@]} > 0)); then
        echo -e "${BGO_COLOR_WHITE}${BGO_COLOR_BOLD}Patches Applied History / Danh mục bản vá đã ghi nhận:${BGO_COLOR_RESET}"
        bgo_log_raw "SUMMARY" "Patches Applied History:"
        for patch in "${BGO_APPLIED_PATCHES[@]}"; do
            echo -e "  ${BGO_COLOR_GREEN}✔${BGO_COLOR_RESET} ${patch}"
            bgo_log_raw "SUMMARY" "  ✔ ${patch}"
        done
        echo ""
    fi

    if ((${#BGO_WARNING_MESSAGES[@]} > 0)); then
        echo -e "${BGO_COLOR_YELLOW}${BGO_COLOR_BOLD}Warnings Encountered / Các cảnh báo ghi nhận:${BGO_COLOR_RESET}"
        bgo_log_raw "SUMMARY" "Warnings Encountered:"
        for warn in "${BGO_WARNING_MESSAGES[@]}"; do
            echo -e "  ${BGO_COLOR_YELLOW}⚠${BGO_COLOR_RESET} ${warn}"
            bgo_log_raw "SUMMARY" "  ⚠ ${warn}"
        done
        echo ""
    fi

    if ((${#BGO_ERROR_MESSAGES[@]} > 0)); then
        echo -e "${BGO_COLOR_RED}${BGO_COLOR_BOLD}Errors Encountered / Danh sách lỗi cần kiểm tra:${BGO_COLOR_RESET}"
        bgo_log_raw "SUMMARY" "Errors Encountered:"
        for err in "${BGO_ERROR_MESSAGES[@]}"; do
            echo -e "  ${BGO_COLOR_RED}✖${BGO_COLOR_RESET} ${err}"
            bgo_log_raw "SUMMARY" "  ✖ ${err}"
        done
        echo ""
    fi

    echo -e "Full Audit Log / Toàn bộ nhật ký kiểm tra:"
    echo -e "${BGO_COLOR_CYAN}${BGO_LOG_FILE}${BGO_COLOR_RESET}"
    echo -e "${BGO_COLOR_CYAN}========================================================================${BGO_COLOR_RESET}"
    bgo_log_raw "SUMMARY" "Audit log location: ${BGO_LOG_FILE}"

    if (( BGO_ERROR_TASKS == 0 )); then
        bgo_notify "BigLinux Gaming Optimizer" "All optimizations completed successfully! / Tất cả tối ưu hoàn tất thành công!" "emblem-default"
    else
        bgo_notify "BigLinux Gaming Optimizer" "Completed with ${BGO_ERROR_TASKS} errors. Check log file! / Hoàn tất với ${BGO_ERROR_TASKS} lỗi. Hãy xem file log!" "dialog-warning"
    fi
}
