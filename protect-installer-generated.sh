#!/usr/bin/env bash
# =============================================================================
#  Pterodactyl Protect Installer — v2.0.0
#  Pemakaian : sudo bash protect-installer.sh [opsi]      (lihat --help)
# =============================================================================
set -Eeuo pipefail
export DEBIAN_FRONTEND=noninteractive

VERSION="2.0.0"

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  IDENTITAS ANDA — ISI DUA BARIS INI                                       ║
# ║  (atau jalankan dengan: PROTECT_AUTHOR_NAME="..." PROTECT_AUTHOR_HANDLE=) ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
AUTHOR_NAME="${PROTECT_AUTHOR_NAME:-HenNex8}"
AUTHOR_HANDLE="${PROTECT_AUTHOR_HANDLE:-@HenNex8}"

# Label tampilan: jika nama sama dengan username, tampilkan sekali saja
if [[ "${AUTHOR_HANDLE#@}" == "$AUTHOR_NAME" ]]; then
    AUTHOR_LABEL="$AUTHOR_HANDLE"
else
    AUTHOR_LABEL="$AUTHOR_NAME ($AUTHOR_HANDLE)"
fi

# Branding lama di dalam file proteksi yang otomatis diganti ke identitas Anda.
# Format "lama|baru". Urutan penting: yang terpanjang harus di atas.
OLD_BRANDS=(
    "@WiL Official|${AUTHOR_HANDLE}"
    "WiL Official|${AUTHOR_NAME}"
    "@WiL|${AUTHOR_HANDLE}"
)

# ------------------------------- KONFIGURASI ---------------------------------
PROTEK_URL="${PROTECT_URL:-https://github.com/mwildanhidayat/installer-pterodactyl/raw/refs/heads/main/proteksi/Protect-panel.zip}"
EXPECTED_SHA="${PROTECT_SHA256:-}"
PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
STATE_DIR="/var/lib/pterodactyl-protect"
LOG_FILE="/var/log/pterodactyl-protect.log"
LOCK_FILE="/var/lock/pterodactyl-protect.lock"
BACKUP_KEEP=5   # jumlah backup terakhir yang disimpan

# Pemetaan "nama file di zip|path tujuan di panel"
FILE_MAP=(
    "TwoFactorController.php|app/Http/Controllers/Api/Client/TwoFactorController.php"
    "ServerTransferController.php|app/Http/Controllers/Admin/Servers/ServerTransferController.php"
    "ServersController.php|app/Http/Controllers/Admin/ServersController.php"
    "ReinstallServerService.php|app/Services/Servers/ReinstallServerService.php"
    "NodeController.php|app/Http/Controllers/Admin/Nodes/NodeController.php"
    "NestController.php|app/Http/Controllers/Admin/Nests/NestController.php"
    "ServerDeletionService.php|app/Services/Servers/ServerDeletionService.php"
    "MountController.php|app/Http/Controllers/Admin/MountController.php"
    "StartupModificationService.php|app/Services/Servers/StartupModificationService.php"
    "LocationController.php|app/Http/Controllers/Admin/LocationController.php"
    "IndexController.php|app/Http/Controllers/Admin/Settings/IndexController.php"
    "DetailsModificationService.php|app/Services/Servers/DetailsModificationService.php"
    "ClientServerController.php|app/Http/Controllers/Api/Client/Servers/ServerController.php"
    "BuildModificationService.php|app/Services/Servers/BuildModificationService.php"
    "ApiController.php|app/Http/Controllers/Admin/ApiController.php"
    "ApiKeyController.php|app/Http/Controllers/Api/Client/ApiKeyController.php"
    "DatabaseManagementService.php|app/Services/Databases/DatabaseManagementService.php"
    "FileController.php|app/Http/Controllers/Api/Client/Servers/FileController.php"
    "UserController.php|app/Http/Controllers/Admin/UserController.php"
    "DatabaseController.php|app/Http/Controllers/Admin/DatabaseController.php"
    "ServerController.php|app/Http/Controllers/Admin/Servers/ServerController.php"
    "EggController.php|app/Http/Controllers/Admin/Nests/EggController.php"
    "MailController.php|app/Http/Controllers/Admin/Settings/MailController.php"
    "AdvancedController.php|app/Http/Controllers/Admin/Settings/AdvancedController.php"
)

# ------------------------------- WARNA & LOG ---------------------------------
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; NC=$'\033[0m'

_log() { printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
info() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; _log "INFO  $*"; }
ok()   { printf '%s%s%s\n' "$GREEN"  "$*" "$NC"; _log "OK    $*"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; _log "WARN  $*"; }
err()  { printf '%s%s%s\n' "$RED"    "$*" "$NC" >&2; _log "ERROR $*"; }
die()  { err "❌ $*"; exit 1; }

# ------------------------------- STATE GLOBAL --------------------------------
MODE="install"; DRY_RUN=0; ASSUME_YES=0; FULL_BACKUP=0
NO_RESTART=0; NO_REBRAND=0; LOCAL_ZIP=""; ROLLBACK_DIR=""
TEMP_DIR=""; EXTRACT_DIR=""; ZIP_FILE=""; ZIP_SHA=""
BACKUP_DIR=""; WEB_USER=""; WEB_GROUP=""; PHP_MM=""; PANEL_VER=""
INSTALL_STARTED=0; INSTALL_DONE=0; MAINT_ON=0
COPIED=0; FAILED=0; MISSING=0
RES_SRC=(); RES_DEST=()
PATCH_SIDEBAR=""; PATCH_API=""; PATCH_SESSION_API=""

usage() {
cat <<EOF
Pterodactyl Protect Installer v${VERSION} — ${AUTHOR_LABEL}

Pemakaian: sudo bash $0 [opsi]

  -n, --dry-run          Simulasi: unduh, verifikasi & lint saja, panel TIDAK diubah
  -y, --yes              Lewati konfirmasi (untuk otomatisasi)
      --zip FILE         Pakai file zip lokal, tidak mengunduh
      --url URL          URL paket proteksi (default: lihat di dalam script)
      --sha256 HASH      Wajib cocok dengan hash zip (sangat disarankan)
      --panel-dir DIR    Lokasi panel (default: /var/www/pterodactyl)
      --full-backup      Tambah backup penuh folder panel (${PANEL_DIR}.bak.*)
      --no-restart       Jangan reload php-fpm / web server
      --no-rebrand       Jangan ganti teks branding di dalam file proteksi
      --rollback [DIR]   Kembalikan dari backup (default: backup terakhir)
      --list-backups     Tampilkan daftar backup
  -h, --help             Bantuan ini

Variabel env: PROTECT_AUTHOR_NAME, PROTECT_AUTHOR_HANDLE, PROTECT_URL,
              PROTECT_SHA256, PANEL_DIR
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--dry-run)   DRY_RUN=1 ;;
            -y|--yes)       ASSUME_YES=1 ;;
            --zip)          LOCAL_ZIP="${2:?--zip membutuhkan path file}"; shift ;;
            --url)          PROTEK_URL="${2:?--url membutuhkan URL}"; shift ;;
            --sha256)       EXPECTED_SHA="${2:?--sha256 membutuhkan hash}"; shift ;;
            --panel-dir)    PANEL_DIR="${2:?--panel-dir membutuhkan path}"; shift ;;
            --full-backup)  FULL_BACKUP=1 ;;
            --no-restart)   NO_RESTART=1 ;;
            --no-rebrand)   NO_REBRAND=1 ;;
            --list-backups) MODE="list" ;;
            --rollback)
                MODE="rollback"
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then ROLLBACK_DIR="$2"; shift; fi
                ;;
            -h|--help)      usage; exit 0 ;;
            *)              die "Opsi tidak dikenal: $1 (coba --help)" ;;
        esac
        shift
    done
}

banner() {
    printf '%s===========================================%s\n' "$BLUE" "$NC"
    printf '%s🚀 Pterodactyl Protect Installer v%s%s\n' "$GREEN" "$VERSION" "$NC"
    printf '%s© Protect By %s%s\n' "$YELLOW" "$AUTHOR_LABEL" "$NC"
    if (( DRY_RUN )); then printf '%s🧪 MODE DRY-RUN — panel tidak akan diubah%s\n' "$YELLOW" "$NC"; fi
    printf '%s===========================================%s\n' "$BLUE" "$NC"
}

# --------------------------------- UTILITAS ----------------------------------
sed_escape_pat()  { printf '%s' "$1" | sed -e 's/[][\/.*^$|]/\\&/g'; }
sed_escape_repl() { printf '%s' "$1" | sed -e 's/[\/&|\\]/\\&/g'; }

confirm() {
    if (( ASSUME_YES )); then return 0; fi
    if [[ ! -t 0 ]]; then die "Mode non-interaktif: tambahkan --yes untuk melanjutkan."; fi
    local ans
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

as_web() {
    if [[ "$(id -un)" == "$WEB_USER" ]]; then "$@"
    elif command -v runuser >/dev/null 2>&1; then runuser -u "$WEB_USER" -- "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo -u "$WEB_USER" -- "$@"
    else die "runuser/sudo tidak tersedia untuk menjalankan perintah sebagai $WEB_USER"
    fi
}

pt_artisan() { ( cd "$PANEL_DIR" && as_web php artisan "$@" ); }

validate_identity() {
    local re='^[A-Za-z0-9 ._@-]+$'
    if [[ "$AUTHOR_NAME" == "NAMA_ANDA" || "$AUTHOR_HANDLE" == "@username_anda" ]]; then
        if (( DRY_RUN )); then
            warn "⚠ AUTHOR_NAME / AUTHOR_HANDLE masih placeholder (diabaikan saat dry-run)"
        else
            die "Isi AUTHOR_NAME dan AUTHOR_HANDLE di bagian atas script dulu."
        fi
    fi
    [[ "$AUTHOR_NAME"   =~ $re ]] || die "AUTHOR_NAME hanya boleh huruf, angka, spasi, titik, _, @, -"
    [[ "$AUTHOR_HANDLE" =~ $re ]] || die "AUTHOR_HANDLE hanya boleh huruf, angka, spasi, titik, _, @, -"
}

acquire_lock() {
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE"
        flock -n 9 || die "Instalasi lain sedang berjalan (lock: $LOCK_FILE)"
    else
        warn "⚠ flock tidak ada — lewati penguncian"
    fi
}

# ---------------------------- DETEKSI & PREFLIGHT ----------------------------
detect_env() {
    [[ -d "$PANEL_DIR" && -f "$PANEL_DIR/artisan" ]] \
        || die "Pterodactyl tidak ditemukan di $PANEL_DIR (tidak ada file artisan)"
    command -v php >/dev/null 2>&1 || die "PHP tidak ditemukan"

    WEB_USER="$(stat -c '%U' "$PANEL_DIR/artisan")"
    if [[ "$WEB_USER" == "root" ]] || ! id -u "$WEB_USER" >/dev/null 2>&1; then
        WEB_USER=""
        local u
        for u in www-data nginx apache; do
            if id -u "$u" >/dev/null 2>&1; then WEB_USER="$u"; break; fi
        done
        [[ -n "$WEB_USER" ]] || die "User web server tidak terdeteksi (www-data/nginx/apache)"
    fi
    WEB_GROUP="$(id -gn "$WEB_USER")"
    PHP_MM="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
    PANEL_VER="$(grep -oE "'version' => '[^']+'" "$PANEL_DIR/config/app.php" 2>/dev/null | head -n1 | cut -d"'" -f4 || true)"
}

ensure_deps() {
    info "🔍 Memeriksa dependencies..."
    local c
    local -a missing=()
    for c in curl unzip; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    for c in sha256sum tar stat find sed awk; do
        command -v "$c" >/dev/null 2>&1 || die "Perintah wajib tidak ada: $c"
    done

    if (( ${#missing[@]} > 0 )); then
        if (( DRY_RUN )); then
            warn "⚠ [dry-run] akan menginstall: ${missing[*]}"
        elif command -v apt-get >/dev/null 2>&1; then
            info "📦 Menginstall: ${missing[*]}"
            apt-get update -qq && apt-get install -y -qq "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y -q "${missing[@]}"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y -q "${missing[@]}"
        else
            die "Install manual dulu: ${missing[*]}"
        fi
    fi

    local avail_kb
    avail_kb="$(df -Pk /var/lib | awk 'NR==2{print $4}')"
    if (( avail_kb < 204800 )); then die "Ruang disk kurang (butuh minimal 200MB di /var/lib)"; fi
    ok "✅ Dependencies & disk OK"
}

# ------------------------------ PAKET PROTEKSI -------------------------------
fetch_package() {
    ZIP_FILE="$TEMP_DIR/Protect-panel.zip"
    if [[ -n "$LOCAL_ZIP" ]]; then
        [[ -f "$LOCAL_ZIP" ]] || die "File zip lokal tidak ditemukan: $LOCAL_ZIP"
        cp "$LOCAL_ZIP" "$ZIP_FILE"
        ok "📦 Memakai zip lokal: $LOCAL_ZIP"
    else
        info "📥 Mengunduh paket proteksi..."
        curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 180 \
             --progress-bar -o "$ZIP_FILE" "$PROTEK_URL" \
            || die "Gagal mengunduh. Cek URL/koneksi: $PROTEK_URL"
        ok "✅ Download berhasil"
    fi

    [[ "$(stat -c%s "$ZIP_FILE")" -ge 1000 ]] || die "File zip korup atau terlalu kecil"
    unzip -tq "$ZIP_FILE" >/dev/null 2>&1 || die "File zip rusak (gagal uji integritas)"

    local listing
    listing="$(unzip -Z1 "$ZIP_FILE")"
    if grep -Eq '(^/|(^|/)\.\.(/|$))' <<<"$listing"; then
        die "Zip berisi path berbahaya (absolute / '..') — dibatalkan"
    fi

    ZIP_SHA="$(sha256sum "$ZIP_FILE" | awk '{print $1}')"
    if [[ -n "$EXPECTED_SHA" ]]; then
        if [[ "${ZIP_SHA,,}" != "${EXPECTED_SHA,,}" ]]; then
            err "SHA256 diharapkan : $EXPECTED_SHA"
            err "SHA256 sebenarnya : $ZIP_SHA"
            die "Hash zip tidak cocok — isi paket berubah, instalasi dihentikan"
        fi
        ok "🔒 SHA256 cocok: $ZIP_SHA"
    else
        warn "⚠ SHA256 zip: $ZIP_SHA"
        warn "  Tidak ada --sha256, isi paket tidak bisa diverifikasi. Simpan hash di atas"
        warn "  lalu pakai --sha256 pada instalasi berikutnya."
    fi
}

find_in_pkg() {
    find "$EXTRACT_DIR" -type f -name "$1" -not -path '*/__MACOSX/*' -print -quit
}

extract_package() {
    EXTRACT_DIR="$TEMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"
    unzip -oq "$ZIP_FILE" -d "$EXTRACT_DIR" || die "Gagal mengekstrak zip"
    ok "✅ Ekstrak berhasil"
}

apply_branding() {
    if (( NO_REBRAND )); then info "⏭  Rebrand dilewati (--no-rebrand)"; return 0; fi
    local pair old new eo en f hits=0
    local -a pkg_files=()
    mapfile -t pkg_files < <(find "$EXTRACT_DIR" -type f -name '*.php' -not -path '*/__MACOSX/*')
    for pair in "${OLD_BRANDS[@]}"; do
        old="${pair%%|*}"; new="${pair#*|}"
        eo="$(sed_escape_pat "$old")"; en="$(sed_escape_repl "$new")"
        for f in "${pkg_files[@]}"; do
            if grep -qF -- "$old" "$f"; then
                sed -i "s|${eo}|${en}|g" "$f"
                hits=$((hits + 1))
            fi
        done
    done
    ok "🏷️  Branding diganti ke ${AUTHOR_LABEL} — ${hits} penggantian"
}

resolve_files() {
    local pair name dest path
    RES_SRC=(); RES_DEST=(); MISSING=0
    for pair in "${FILE_MAP[@]}"; do
        name="${pair%%|*}"; dest="${pair#*|}"
        path="$(find_in_pkg "$name")"
        if [[ -n "$path" ]]; then
            RES_SRC+=("$path"); RES_DEST+=("$dest")
        else
            warn "⚠ $name tidak ada di dalam paket"
            MISSING=$((MISSING + 1))
        fi
    done
    (( ${#RES_SRC[@]} > 0 )) || die "Tidak ada satupun file proteksi yang cocok di dalam paket"
    PATCH_SIDEBAR="$(find_in_pkg admin.blade.php)"
    PATCH_API="$(find_in_pkg fix_api_view.php)"
    PATCH_SESSION_API="$(find_in_pkg install_api_session_protection.php)"
}

lint_package() {
    info "🧪 Lint sintaks PHP sebelum menyentuh panel..."
    local f bad=0
    local -a all=("${RES_SRC[@]}")
    if [[ -n "$PATCH_SIDEBAR" ]]; then all+=("$PATCH_SIDEBAR"); fi
    if [[ -n "$PATCH_API" ]];     then all+=("$PATCH_API"); fi
    if [[ -n "$PATCH_SESSION_API" ]]; then all+=("$PATCH_SESSION_API"); fi
    for f in "${all[@]}"; do
        if ! php -l "$f" >/dev/null 2>&1; then
            err "✗ Syntax error: ${f#"$EXTRACT_DIR"/}"
            bad=$((bad + 1))
        fi
    done
    (( bad == 0 )) || die "$bad file PHP gagal lint — dibatalkan, panel belum diubah."
    ok "✅ ${#all[@]} file PHP lolos lint"
}

show_plan() {
    printf '\n%s📋 Rencana instalasi%s\n' "$YELLOW" "$NC"
    echo "  Panel          : $PANEL_DIR ${PANEL_VER:+(versi $PANEL_VER)}"
    echo "  User web       : $WEB_USER:$WEB_GROUP   |   PHP $PHP_MM"
    echo "  Identitas      : $AUTHOR_LABEL"
    echo "  File proteksi  : ${#RES_SRC[@]} akan ditimpa, $MISSING tidak ada di paket"
    echo "  Patcher sidebar: $([[ -n "$PATCH_SIDEBAR" ]] && echo ada || echo "tidak ada")"
    echo "  Patcher API    : $([[ -n "$PATCH_API" ]] && echo ada || echo "tidak ada")"
    echo "  Patcher API session: $([[ -n "$PATCH_SESSION_API" ]] && echo ada || echo "tidak ada")"
    echo "  SHA256 paket   : $ZIP_SHA"
    echo "  Backup ke      : $STATE_DIR/backups/<timestamp>"
    echo
}

# ---------------------------- BACKUP & ROLLBACK ------------------------------
backup_file() {
    local rel="$1" target="$PANEL_DIR/$1"
    if [[ -f "$target" ]]; then
        mkdir -p "$BACKUP_DIR/files/$(dirname "$rel")"
        cp -a "$target" "$BACKUP_DIR/files/$rel"
        echo "MOD|$rel" >> "$BACKUP_DIR/manifest.txt"
    else
        echo "NEW|$rel" >> "$BACKUP_DIR/manifest.txt"
    fi
}

make_backup_dir() {
    local ts; ts="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$STATE_DIR/backups/$ts"
    install -d -m 0700 "$BACKUP_DIR" "$BACKUP_DIR/files"
    : > "$BACKUP_DIR/manifest.txt"
    {
        echo "date=$(date '+%F %T')"
        echo "author=$AUTHOR_LABEL"
        echo "panel=$PANEL_DIR"
        echo "panel_version=$PANEL_VER"
        echo "zip_sha256=$ZIP_SHA"
        echo "url=${LOCAL_ZIP:-$PROTEK_URL}"
    } > "$BACKUP_DIR/info.txt"

    if [[ -d "$PANEL_DIR/resources/views" ]]; then
        tar -czf "$BACKUP_DIR/views.tar.gz" -C "$PANEL_DIR" resources/views
    fi

    if (( FULL_BACKUP )); then
        local full="${PANEL_DIR}.bak.${ts}"
        info "📦 Backup penuh ke $full (bisa lama)..."
        cp -a "$PANEL_DIR" "$full" || die "Backup penuh gagal"
        echo "full_backup=$full" >> "$BACKUP_DIR/info.txt"
        ok "✅ Backup penuh: $full"
    fi
    ok "💾 Backup per-file: $BACKUP_DIR"
}

restore_backup() {
    local dir="$1" kind rel errors=0
    [[ -f "$dir/manifest.txt" ]] || { err "Manifest tidak ditemukan di $dir"; return 1; }

    while IFS='|' read -r kind rel; do
        [[ -n "$rel" ]] || continue
        if [[ "$rel" == /* || "$rel" == *..* ]]; then err "Path mencurigakan di manifest: $rel"; errors=$((errors + 1)); continue; fi
        case "$kind" in
            MOD) cp -a "$dir/files/$rel" "$PANEL_DIR/$rel" || errors=$((errors + 1)) ;;
            NEW) rm -f "$PANEL_DIR/$rel" || errors=$((errors + 1)) ;;
        esac
    done < "$dir/manifest.txt"

    if [[ -f "$dir/views.tar.gz" ]]; then
        tar -xzf "$dir/views.tar.gz" -C "$PANEL_DIR" || errors=$((errors + 1))
    fi
    pt_artisan optimize:clear >/dev/null 2>&1 || true
    pt_artisan config:cache   >/dev/null 2>&1 || true
    pt_artisan view:cache     >/dev/null 2>&1 || true
    (( errors == 0 ))
}

prune_backups() {
    local -a old=()
    mapfile -t old < <(ls -1dt "$STATE_DIR"/backups/*/ 2>/dev/null | tail -n +$((BACKUP_KEEP + 1)) || true)
    if (( ${#old[@]} > 0 )); then
        local d
        for d in "${old[@]}"; do
            if [[ "$d" == "$STATE_DIR"/backups/* ]]; then rm -rf "$d"; fi
        done
        info "🧹 Backup lama dipangkas (simpan $BACKUP_KEEP terakhir)"
    fi
}

list_backups() {
    local -a dirs=()
    mapfile -t dirs < <(ls -1dt "$STATE_DIR"/backups/*/ 2>/dev/null || true)
    if (( ${#dirs[@]} == 0 )); then info "Belum ada backup di $STATE_DIR/backups"; return 0; fi
    info "📁 Daftar backup (terbaru di atas):"
    local d
    for d in "${dirs[@]}"; do
        printf '  • %s   %s\n' "${d%/}" "$(grep -m1 '^date=' "$d/info.txt" 2>/dev/null || true)"
    done
}

do_rollback() {
    detect_env
    local dir="${ROLLBACK_DIR:-$STATE_DIR/latest}"
    [[ -e "$dir" ]] || die "Backup tidak ditemukan: $dir"
    dir="$(readlink -f "$dir")"
    info "⏪ Rollback dari: $dir"
    confirm "Kembalikan file panel dari backup ini?" || die "Dibatalkan oleh pengguna."
    restore_backup "$dir" || die "Rollback selesai dengan error — cek log: $LOG_FILE"
    reload_services
    ok "✅ Rollback selesai."
}

# -------------------------------- INSTALASI ----------------------------------
install_files() {
    info "📂 Menginstal ${#RES_SRC[@]} file proteksi..."
    local i n=0 total=${#RES_SRC[@]} rel
    for i in "${!RES_SRC[@]}"; do
        n=$((n + 1)); rel="${RES_DEST[$i]}"
        backup_file "$rel"
        if install -D -m 0644 -o "$WEB_USER" -g "$WEB_GROUP" "${RES_SRC[$i]}" "$PANEL_DIR/$rel"; then
            COPIED=$((COPIED + 1))
            printf '%s✓%s [%d/%d] %s → %s\n' "$GREEN" "$NC" "$n" "$total" "$(basename "${RES_SRC[$i]}")" "$rel"
        else
            FAILED=$((FAILED + 1))
            printf '%s✗%s [%d/%d] Gagal: %s\n' "$RED" "$NC" "$n" "$total" "$rel"
        fi
    done
    (( FAILED == 0 )) || die "$FAILED file gagal disalin"
}

run_patcher() {
    local label="$1" src="$2" name dst
    name="$(basename "$src")"; dst="$PANEL_DIR/$name"
    install -m 0644 -o "$WEB_USER" -g "$WEB_GROUP" "$src" "$dst"
    if ( cd "$PANEL_DIR" && as_web php "$name" ); then
        rm -f "$dst"
        ok "✅ $label berhasil"
    else
        rm -f "$dst"
        return 1
    fi
}

reload_services() {
    if (( NO_RESTART )); then info "⏭  Reload service dilewati (--no-restart)"; return 0; fi
    if ! command -v systemctl >/dev/null 2>&1; then warn "⚠ systemctl tidak ada — reload manual"; return 0; fi
    local svc
    for svc in "php${PHP_MM}-fpm" php-fpm "php${PHP_MM//./}-php-fpm" nginx apache2 httpd; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            if systemctl reload "$svc" 2>/dev/null; then ok "🔄 reload $svc"
            else warn "⚠ gagal reload $svc — restart manual"; fi
        fi
    done
}

on_exit() {
    local code=$?
    trap - EXIT ERR INT TERM
    set +e
    if [[ $INSTALL_STARTED -eq 1 && $INSTALL_DONE -eq 0 && $code -ne 0 ]]; then
        err "⏪ Terjadi kegagalan — mengembalikan file dari backup otomatis..."
        if restore_backup "$BACKUP_DIR"; then ok "✅ Panel dikembalikan ke kondisi semula"
        else err "Rollback otomatis gagal! Pulihkan manual: bash $0 --rollback"; fi
    fi
    if [[ $MAINT_ON -eq 1 ]]; then pt_artisan up >/dev/null 2>&1; fi
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then rm -rf "$TEMP_DIR"; fi
    exit "$code"
}

do_install() {
    validate_identity
    acquire_lock
    detect_env
    ensure_deps

    TEMP_DIR="$(mktemp -d /tmp/pterodactyl-protect.XXXXXX)"
    fetch_package
    extract_package
    apply_branding
    resolve_files
    lint_package
    show_plan

    if (( DRY_RUN )); then
        ok "🧪 Dry-run selesai: paket valid, tidak ada perubahan pada panel."
        return 0
    fi
    confirm "Lanjutkan instalasi?" || die "Dibatalkan oleh pengguna."

    install -d -m 0755 "$STATE_DIR/backups"
    make_backup_dir
    INSTALL_STARTED=1

    # Maintenance mode (kecuali panel sudah dalam maintenance)
    if [[ ! -f "$PANEL_DIR/storage/framework/down" ]]; then
        if pt_artisan down --retry=60 >/dev/null 2>&1; then MAINT_ON=1; info "🚧 Panel masuk maintenance mode sementara"; fi
    fi

    install_files

    if [[ -n "$PATCH_SIDEBAR" ]]; then
        info "🛡️  Mengaplikasikan proteksi sidebar..."
        run_patcher "Proteksi sidebar (hanya Admin ID 1)" "$PATCH_SIDEBAR" || die "Patcher sidebar gagal"
    else
        warn "⚠ admin.blade.php tidak ada di paket — sidebar tidak diproteksi"
    fi

    if [[ -n "$PATCH_API" ]]; then
        info "🔧 Memperbaiki tampilan API Key..."
        run_patcher "Filter API Key per user" "$PATCH_API" || die "Patcher API view gagal"
    else
        warn "⚠ fix_api_view.php tidak ada di paket — dilewati"
    fi

    if [[ -n "$PATCH_SESSION_API" ]]; then
        info "🔐 Memasang Owner Key session untuk Application API..."
        if ( PANEL_DIR="$PANEL_DIR" php "$PATCH_SESSION_API" ); then
            chown "$WEB_USER:$WEB_GROUP" "$PANEL_DIR/app/Http/Middleware/ApiSessionAuthorization.php" "$PANEL_DIR/app/Http/Controllers/Admin/ApiOwnerAuthorizationController.php" "$PANEL_DIR/resources/views/admin/api/owner-authorization.blade.php"
            ok "✅ Owner Key session API berhasil dipasang"
        else
            die "Patcher Owner Key session gagal"
        fi
    else
        warn "⚠ install_api_session_protection.php tidak ada di paket — API session tidak diproteksi"
    fi

    info "⚡ Mengoptimasi panel..."
    pt_artisan optimize:clear >/dev/null 2>&1 || warn "⚠ optimize:clear gagal, lanjut"
    if pt_artisan config:cache >/dev/null 2>&1; then ok "✓ config:cache"; else warn "⚠ config:cache gagal"; fi
    if pt_artisan route:cache  >/dev/null 2>&1; then ok "✓ route:cache";  else warn "⚠ route:cache gagal"; pt_artisan route:clear >/dev/null 2>&1 || true; fi
    if pt_artisan view:cache   >/dev/null 2>&1; then ok "✓ view:cache";   else warn "⚠ view:cache gagal"; fi

    info "🩺 Health check (aplikasi harus bisa boot)..."
    pt_artisan route:list >/dev/null 2>&1 || die "Panel gagal boot setelah instalasi"
    ok "✅ Health check lolos"

    INSTALL_DONE=1
    if [[ $MAINT_ON -eq 1 ]]; then
        if pt_artisan up >/dev/null 2>&1; then MAINT_ON=0; ok "🟢 Panel kembali online"; fi
    fi

    ln -sfn "$BACKUP_DIR" "$STATE_DIR/latest"
    prune_backups
    reload_services
    print_summary
}

print_summary() {
    printf '%s===========================================%s\n' "$BLUE" "$NC"
    printf '%s✅ INSTALASI SELESAI!%s\n\n' "$GREEN" "$NC"
    printf '%s📊 Ringkasan:%s\n' "$YELLOW" "$NC"
    echo "• File berhasil di-copy : $COPIED"
    echo "• File gagal            : $FAILED"
    echo "• File tidak ada di zip : $MISSING"
    echo "• Backup                : $BACKUP_DIR"
    echo "• SHA256 paket          : $ZIP_SHA"
    echo "• Log                   : $LOG_FILE"
    echo
    printf '%s🛡️  Fitur yang diproteksi (hanya Admin ID 1):%s\n' "$YELLOW" "$NC"
    echo "• Nodes (view, edit, delete, create) - /admin/nodes/*"
    echo "• Nests, Locations"
    echo "• Databases, Settings, API, Mounts"
    echo "• Semua aksi admin pada server orang lain (transfer, delete, reinstall, dll.)"
    echo "• Egg Management (/admin/nests/egg/*)"
    echo "• Mail Settings (/admin/settings/mail)"
    echo "• Advanced Settings (/admin/settings/advanced)"
    echo "• Application API: Owner Key session (/admin/api-owner/authorization)"
    echo
    printf '%s↩️  Ada masalah? Kembalikan dengan:%s\n' "$YELLOW" "$NC"
    echo "sudo bash $0 --rollback"
    printf '%s===========================================%s\n' "$BLUE" "$NC"
    printf '%sTerima kasih telah menggunakan ©Protect By %s%s\n' "$GREEN" "$AUTHOR_LABEL" "$NC"
}

# ----------------------------------- MAIN ------------------------------------
main() {
    parse_args "$@"
    trap 'err "Error di baris ${LINENO}: ${BASH_COMMAND}"' ERR
    trap 'exit 130' INT TERM
    trap on_exit EXIT

    banner
    [[ $EUID -eq 0 ]] || die "Script ini harus dijalankan sebagai root (sudo)"

    case "$MODE" in
        list)     list_backups ;;
        rollback) do_rollback ;;
        install)  do_install ;;
    esac
}

main "$@"