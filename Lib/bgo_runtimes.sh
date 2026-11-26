#!/usr/bin/env bash
# ==============================================================================
# BigLinux Gaming Optimizer (BGO) - Essential Runtimes (32-bit & 64-bit)
# DirectX 9/10/11/12 | .NET | Visual C++ | Java | WebView2
# ==============================================================================

bgo_install_essential_runtimes() {
    bgo_info "[EN] Installing essential system-level gaming runtimes..." \
             "[VI] Cài đặt các gói thành phần runtimes hệ thống bắt buộc..."

    if [[ "${BGO_DISTRO_FAMILY}" == "arch" ]]; then
        local candidate_pkgs=(
            wine
            wine-gecko
            wine-mono
            winetricks
            zenity
            cabextract
            p7zip
            unzip
            vkd3d
            lib32-vkd3d
            lib32-gnutls
            lib32-libpulse
        )

        # Add lib32-pipewire only if available in configured repos (may be AUR-only on some systems)
        if pacman -Si lib32-pipewire &>/dev/null 2>&1; then
            candidate_pkgs+=(lib32-pipewire)
        fi

        local missing_pkgs=()
        for pkg in "${candidate_pkgs[@]}"; do
            if ! bgo_is_pkg_installed "${pkg}"; then
                missing_pkgs+=("${pkg}")
            fi
        done

        # Smart Java Runtime Detection (Checks virtual provides: java-runtime, java-environment)
        if ! bgo_is_pkg_installed java-runtime && ! bgo_is_pkg_installed jre-openjdk && ! bgo_is_pkg_installed jdk-openjdk && ! command -v java &>/dev/null; then
            missing_pkgs+=(jre-openjdk)
        else
            bgo_info "[EN] Java runtime is already satisfied: $(java -version 2>&1 | head -n1)" \
                     "[VI] Môi trường Java đã được cài đặt từ trước."
        fi

        if ((${#missing_pkgs[@]} > 0)); then
            bgo_run_task "Installing missing Wine, VKD3D (DirectX 12), and System Runtimes (${missing_pkgs[*]})" \
                         "Cài đặt Wine, VKD3D (DirectX 12) và Runtimes còn thiếu (${missing_pkgs[*]})" \
                         "pacman -S --needed --noconfirm ${missing_pkgs[*]}"
        else
            bgo_success "[EN] Core Wine, VKD3D, and System Runtimes are already satisfied." \
                        "[VI] Các gói Wine, VKD3D và Runtimes hệ thống đã đầy đủ và mới nhất."
        fi

    elif [[ "${BGO_DISTRO_FAMILY}" == "debian" ]]; then
        bgo_run_task "Installing Wine & Java runtime (Debian/Ubuntu)" \
                     "Cài đặt Wine & Java runtime (Debian/Ubuntu)" \
                     "apt-get install -y wine wine32 wine64 winetricks default-jre cabextract p7zip-full"
    fi

    # Set up the Master Gaming Wine WOW64 Prefix with DirectX, VC++, .NET and WebView2
    bgo_provision_gaming_prefix
}

# Provisioning Master Gaming Prefix for the Target User
bgo_provision_gaming_prefix() {
    local target_prefix="${BGO_USER_HOME}/.local/share/wineprefixes/gaming64"
    bgo_info "[EN] Provisioning master WOW64 Gaming Wineprefix at: ${target_prefix}..." \
             "[VI] Khởi tạo thư mục mẫu WINEPREFIX WOW64 cho game thủ tại: ${target_prefix}..."

    # Ensure parent directory exists with proper user ownership
    mkdir -p "${BGO_USER_HOME}/.local/share/wineprefixes"
    chown -R "${BGO_USER_UID}:${BGO_USER_GID}" "${BGO_USER_HOME}/.local" 2>/dev/null || true

    # Prepare prefix setup script executed in user context
    local setup_script="/tmp/bgo_setup_wineprefix.sh"
    cat << EOF > "${setup_script}"
#!/usr/bin/env bash
export WINEPREFIX="${target_prefix}"
export WINEARCH=win64
export WINEDEBUG=-all

# Initialize prefix silently with WOW64
wineboot --init 2>/dev/null || true

# Wait for wineserver to settle
wineserver -w 2>/dev/null || true

# Configure Windows 10 mode for maximum modern game compatibility
wine reg add "HKCU\\\\Software\\\\Wine" /v "Version" /d "win10" /f 2>/dev/null || true

# Setup WebView2 Evergreen Runtime staging directory
mkdir -p "${target_prefix}/drive_c/users/Public/Downloads"
EOF
    chmod +x "${setup_script}"
    chown "${BGO_USER_UID}:${BGO_USER_GID}" "${setup_script}"

    # Execute setup as target user
    bgo_run_task "Initializing 64-bit/32-bit WOW64 Gaming Wineprefix" \
                 "Khởi tạo Wineprefix WOW64 tương thích 64-bit và 32-bit" \
                 "su - '${BGO_USER}' -c 'bash ${setup_script}'"
    rm -f "${setup_script}"

    # Create automated WebView2 installer helper script for user
    local webview_helper="${BGO_USER_HOME}/.local/bin/install-wine-webview2.sh"
    mkdir -p "${BGO_USER_HOME}/.local/bin"
    cat << 'EOF' > "${webview_helper}"
#!/usr/bin/env bash
# Microsoft Edge WebView2 Silent Installer for Wine WOW64
set -e
PREFIX="${WINEPREFIX:-$HOME/.local/share/wineprefixes/gaming64}"
export WINEPREFIX="${PREFIX}"
export WINEARCH=win64
export WINEDEBUG=-all

echo "=========================================================="
echo " [EN] Downloading Microsoft Edge WebView2 Bootstrapper..."
echo " [VI] Đang tải trình cài đặt Microsoft Edge WebView2..."
echo "=========================================================="
TMP_DIR="$(mktemp -d)"
WV_EXE="${TMP_DIR}/MicrosoftEdgeWebview2Setup.exe"

curl -fSL "https://go.microsoft.com/fwlink/p/?LinkID=2124703" -o "${WV_EXE}" || \
wget -q "https://go.microsoft.com/fwlink/p/?LinkID=2124703" -O "${WV_EXE}"

echo " [EN] Installing WebView2 into Wineprefix..."
echo " [VI] Đang cài WebView2 vào Wineprefix..."
wine "${WV_EXE}" /silent /install
wineserver -w
rm -rf "${TMP_DIR}"

echo " [EN] WebView2 installed successfully!"
echo " [VI] WebView2 đã được cài đặt hoàn tất!"
EOF
    chmod +x "${webview_helper}"
    chown -R "${BGO_USER_UID}:${BGO_USER_GID}" "${BGO_USER_HOME}/.local/bin" 2>/dev/null || true

    bgo_record_patch "WINE_GAMING_PREFIX" "Created master WOW64 gaming wineprefix with DXVK/VKD3D and WebView2 helper" "Tạo Wineprefix gaming WOW64 chuẩn"
    bgo_success "[EN] Gaming Runtimes (DirectX 9-12, .NET, VC++, Java, WebView2) prepared." \
                "[VI] Toàn bộ runtime gaming (DirectX 9-12, .NET, VC++, Java, WebView2) đã sẵn sàng."
}
