#!/bin/sh

# Installs sing-box-extended pinned to v1.13.12-extended-2.4.0,
# then applies moix89/podkop-xhttp-patch.

set -u

TAG="v1.13.12-extended-2.4.0"
VERSION="1.13.12-extended-2.4.0"
REPO="shtorm-7/sing-box-extended"
API_URL="https://api.github.com/repos/$REPO/releases/tags/$TAG"
PATCH_URL="https://raw.githubusercontent.com/moix89/podkop-xhttp-patch/main/install.sh"
DEST_FILE="/usr/bin/sing-box"
FACADE_FILE="/usr/lib/podkop/sing_box_config_facade.sh"
PODKOP_FILE="/usr/bin/podkop"
BACKUP_DIR="/root/podkop-sing-box-backup"

R="$(printf '\033[1;31m')"
G="$(printf '\033[1;32m')"
Y="$(printf '\033[1;33m')"
C="$(printf '\033[1;36m')"
N="$(printf '\033[0m')"

WORK_DIR=""
SERVICE_STOPPED="0"
SERVICE_NAME="sing-box"

log() { printf "%s[*]%s %s\n" "$C" "$N" "$1"; }
ok() { printf "%s[+]%s %s\n" "$G" "$N" "$1"; }
warn() { printf "%s[!]%s %s\n" "$Y" "$N" "$1" >&2; }
fail() {
  printf "%s[!] ОШИБКА:%s %s\n" "$R" "$N" "$1" >&2
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  [ "$SERVICE_STOPPED" = "1" ] && service "$SERVICE_NAME" start >/dev/null 2>&1
  exit 1
}

cleanup_on_signal() {
  printf "\n%s[!] Установка прервана.%s\n" "$R" "$N" >&2
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  [ "$SERVICE_STOPPED" = "1" ] && service "$SERVICE_NAME" start >/dev/null 2>&1
  exit 1
}
trap cleanup_on_signal INT TERM

if command -v curl >/dev/null 2>&1; then
  FETCH="curl -fsSL --insecure --connect-timeout 15"
  DOWNLOAD="curl -fsSL --insecure --connect-timeout 30 -o"
elif command -v wget >/dev/null 2>&1; then
  FETCH="wget -qO- --no-check-certificate --timeout=15"
  DOWNLOAD="wget -q --no-check-certificate --timeout=30 -O"
else
  fail "Не найден curl или wget."
fi

if [ -f "/opt/etc/init.d/podkop" ] || [ -f "/etc/init.d/podkop" ]; then
  SERVICE_NAME="podkop"
fi

restore_latest_file() {
  src_pattern="$1"
  dst="$2"
  latest="$(ls -t "$BACKUP_DIR"/$src_pattern 2>/dev/null | head -n 1)"
  [ -n "$latest" ] || return 1
  cp -af "$latest" "$dst" || return 1
  return 0
}

rollback() {
  [ -d "$BACKUP_DIR" ] || fail "Backup directory not found: $BACKUP_DIR"

  log "Rolling back files from $BACKUP_DIR."
  service "$SERVICE_NAME" stop >/dev/null 2>&1 || true

  if restore_latest_file "sing-box.before.*" "$DEST_FILE"; then
    chmod +x "$DEST_FILE" 2>/dev/null || true
    ok "Restored $DEST_FILE"
  else
    warn "No sing-box backup found."
  fi

  if [ -f "$FACADE_FILE" ]; then
    if restore_latest_file "sing_box_config_facade.sh.before.*" "$FACADE_FILE"; then
      ok "Restored $FACADE_FILE"
    else
      warn "No facade backup found."
    fi
  fi

  if [ -f "$PODKOP_FILE" ]; then
    if restore_latest_file "podkop.before.*" "$PODKOP_FILE"; then
      chmod +x "$PODKOP_FILE" 2>/dev/null || true
      ok "Restored $PODKOP_FILE"
    else
      warn "No podkop backup found."
    fi
  fi

  service "$SERVICE_NAME" start >/dev/null 2>&1 || true
  ok "Rollback finished."
  "$DEST_FILE" version 2>/dev/null || true
  exit 0
}

case "${1:-}" in
  --rollback)
    rollback
    ;;
  --help|-h)
    printf "Usage: sh %s [--rollback]\n" "$0"
    exit 0
    ;;
  "")
    ;;
  *)
    fail "Unknown argument: $1"
    ;;
esac

HOST_ARCH="$(uname -m)"
DISTRIB_ARCH=""

if [ -f "/etc/openwrt_release" ]; then
  # shellcheck disable=SC1091
  . /etc/openwrt_release
  DISTRIB_ARCH="${DISTRIB_ARCH:-}"

  case "$DISTRIB_ARCH" in
    *mipsel*|*mipsle*) HOST_ARCH="mipsel" ;;
    *mips64el*|*mips64le*) HOST_ARCH="mips64el" ;;
  esac
fi

case "$HOST_ARCH" in
  aarch64) ARCH_SUFFIX="arm64" ;;
  armv7*) ARCH_SUFFIX="armv7" ;;
  armv6*) ARCH_SUFFIX="armv6" ;;
  x86_64) ARCH_SUFFIX="amd64" ;;
  i386|i686) ARCH_SUFFIX="386" ;;
  mips) ARCH_SUFFIX="mips-softfloat" ;;
  mipsel|mipsle) ARCH_SUFFIX="mipsle-softfloat" ;;
  mips64) ARCH_SUFFIX="mips64" ;;
  mips64el|mips64le) ARCH_SUFFIX="mips64le" ;;
  riscv64) ARCH_SUFFIX="riscv64" ;;
  s390x) ARCH_SUFFIX="s390x" ;;
  *) fail "Архитектура $HOST_ARCH не поддерживается." ;;
esac

CURRENT_VER=""
if [ -x "$DEST_FILE" ]; then
  CURRENT_VER="$("$DEST_FILE" version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//')" || true
fi

log "Использую фиксированный релиз $TAG."
API_RESPONSE="$($FETCH "$API_URL" 2>/dev/null)" || true
[ -n "$API_RESPONSE" ] || fail "Не удалось получить релиз $TAG через GitHub API."

DOWNLOAD_URL=""
ARCHIVE_NAME=""

FILE_PATTERN="linux-${ARCH_SUFFIX}-musl\\.tar\\.gz"
DOWNLOAD_URL="$(echo "$API_RESPONSE" \
  | tr ',' '\n' \
  | grep "browser_download_url" \
  | grep "$FILE_PATTERN" \
  | head -n 1 \
  | awk -F '"' '{print $4}')"
ARCHIVE_NAME="sing-box-extended-$VERSION-linux-$ARCH_SUFFIX-musl.tar.gz"

if [ -z "$DOWNLOAD_URL" ]; then
  fail "Не найден musl tarball для '$HOST_ARCH' ($ARCH_SUFFIX / ${DISTRIB_ARCH:-н/д}) в $TAG."
fi

log "Найден musl tarball для $ARCH_SUFFIX. Пакетный менеджер opkg/apk не используется."

get_free_space_kb() {
  space="$(df -Pk "$1" 2>/dev/null | awk 'NR==2 {print $4}')"
  case "$space" in
    ''|*[!0-9]*) echo 0 ;;
    *) echo "$space" ;;
  esac
}

DEST_DIR="$(dirname "$DEST_FILE")"
DEST_FREE_KB="$(get_free_space_kb "$DEST_DIR")"
EXISTING_SIZE_KB="0"
if [ -f "$DEST_FILE" ]; then
  EXISTING_SIZE_KB="$(du -k "$DEST_FILE" 2>/dev/null | awk '{print $1}')"
  case "$EXISTING_SIZE_KB" in ''|*[!0-9]*) EXISTING_SIZE_KB="0" ;; esac
fi

REQ_TEMP_KB=40960
REQ_DEST_KB=25600
TOTAL_DEST_AVAILABLE=$((DEST_FREE_KB + EXISTING_SIZE_KB))
[ "$TOTAL_DEST_AVAILABLE" -ge "$REQ_DEST_KB" ] || fail "Недостаточно места в $DEST_DIR: нужно $((REQ_DEST_KB / 1024)) МБ."

HOME_DIR="${HOME:-/root}"
DIR_RAM="/tmp/sing-box-install"
DIR_DISK="$HOME_DIR/sing-box-install_tmp"
FREE_RAM_KB="$(awk '/MemFree/ {print $2}' /proc/meminfo 2>/dev/null)"
case "$FREE_RAM_KB" in ''|*[!0-9]*) FREE_RAM_KB="0" ;; esac

if [ "$FREE_RAM_KB" -gt 81920 ]; then
  PREF_DIR="$DIR_RAM"
  PREF_PARENT="/tmp"
  ALT_DIR="$DIR_DISK"
  ALT_PARENT="$HOME_DIR"
else
  PREF_DIR="$DIR_DISK"
  PREF_PARENT="$HOME_DIR"
  ALT_DIR="$DIR_RAM"
  ALT_PARENT="/tmp"
fi

if [ "$(get_free_space_kb "$PREF_PARENT")" -ge "$REQ_TEMP_KB" ]; then
  WORK_DIR="$PREF_DIR"
elif [ "$(get_free_space_kb "$ALT_PARENT")" -ge "$REQ_TEMP_KB" ]; then
  WORK_DIR="$ALT_DIR"
else
  fail "Недостаточно свободного места для временных файлов: нужно $((REQ_TEMP_KB / 1024)) МБ."
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR" || fail "Не удалось создать $WORK_DIR."
cd "$WORK_DIR" || fail "Не удалось перейти в $WORK_DIR."

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR" || fail "Не удалось создать $BACKUP_DIR."
if [ -e "$DEST_FILE" ]; then
  cp -a "$DEST_FILE" "$BACKUP_DIR/sing-box.before.$TS" || fail "Не удалось сохранить backup $DEST_FILE."
  ok "Backup saved: $BACKUP_DIR/sing-box.before.$TS"
else
  warn "$DEST_FILE not found before install; sing-box rollback backup skipped."
fi

log "Скачиваю $DOWNLOAD_URL"
$DOWNLOAD "$ARCHIVE_NAME" "$DOWNLOAD_URL" || fail "Не удалось скачать sing-box-extended."
[ -s "$ARCHIVE_NAME" ] || fail "Скачанный файл пустой."

SERVICE_STOPPED="1"
service "$SERVICE_NAME" stop >/dev/null 2>&1 || true
sleep 2
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true

tar -xzf "$ARCHIVE_NAME" || fail "Не удалось распаковать архив."
BINARY_PATH="$(find . -type f -name sing-box | head -n 1)"
[ -n "$BINARY_PATH" ] || fail "Бинарник sing-box не найден в архиве."
mv -f "$BINARY_PATH" "$DEST_FILE" || fail "Не удалось заменить $DEST_FILE."
chmod +x "$DEST_FILE"

NEW_VERSION="$("$DEST_FILE" version 2>/dev/null | head -n 1 | awk '{print $NF}' | sed 's/^v//')" || true
[ "$NEW_VERSION" = "$VERSION" ] || fail "После установки версия sing-box = '${NEW_VERSION:-н/д}', ожидалась '$VERSION'."

NAIVE_TEST_CONFIG="$WORK_DIR/naive-support-check.json"
cat > "$NAIVE_TEST_CONFIG" << 'NAIVE_TEST_EOF'
{
  "log": {
    "disabled": true
  },
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080
    }
  ],
  "outbounds": [
    {
      "type": "naive",
      "tag": "naive-test",
      "server": "example.com",
      "server_port": 443,
      "username": "user",
      "password": "pass",
      "tls": {
        "enabled": true,
        "server_name": "example.com"
      }
    }
  ],
  "route": {
    "rules": [
      {
        "inbound": [
          "mixed-in"
        ],
        "outbound": "naive-test"
      }
    ]
  }
}
NAIVE_TEST_EOF

log "Проверяю поддержку Naive outbound в установленном sing-box."
"$DEST_FILE" check -c "$NAIVE_TEST_CONFIG" >/dev/null 2>&1 || fail "Установленный sing-box не прошёл проверку Naive outbound. Naive не гарантирован, установка остановлена."
ok "Naive outbound поддерживается установленным sing-box."

cd /
rm -rf "$WORK_DIR"
WORK_DIR=""
SERVICE_STOPPED="0"
service "$SERVICE_NAME" start >/dev/null 2>&1 || true

ok "sing-box установлен: ${CURRENT_VER:-н/д} -> $NEW_VERSION"

PATCH_TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR" || fail "Не удалось создать $BACKUP_DIR."
if [ -f "$FACADE_FILE" ]; then
  cp -a "$FACADE_FILE" "$BACKUP_DIR/sing_box_config_facade.sh.before.$PATCH_TS" || fail "Не удалось сохранить backup $FACADE_FILE."
  ok "Backup saved: $BACKUP_DIR/sing_box_config_facade.sh.before.$PATCH_TS"
else
  warn "$FACADE_FILE not found before patch; facade rollback backup skipped."
fi
if [ -f "$PODKOP_FILE" ]; then
  cp -a "$PODKOP_FILE" "$BACKUP_DIR/podkop.before.$PATCH_TS" || fail "Не удалось сохранить backup $PODKOP_FILE."
  ok "Backup saved: $BACKUP_DIR/podkop.before.$PATCH_TS"
else
  warn "$PODKOP_FILE not found before patch; podkop rollback backup skipped."
fi

PATCH_FILE="/tmp/podkop-xhttp-patch.sh"
log "Скачиваю и запускаю podkop-xhttp-patch."
$DOWNLOAD "$PATCH_FILE" "$PATCH_URL" || fail "Не удалось скачать podkop-xhttp-patch."
sh "$PATCH_FILE" || fail "podkop-xhttp-patch завершился с ошибкой."
rm -f "$PATCH_FILE"

ok "Готово. Проверка:"
"$DEST_FILE" version || true
