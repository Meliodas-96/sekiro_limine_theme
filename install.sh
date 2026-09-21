#!/usr/bin/env bash
set -Eeuo pipefail

THEME_NAME="Sekiro"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/${THEME_NAME}"
BEGIN_MARKER="# BEGIN SEKIRO LIMINE THEME"
END_MARKER="# END SEKIRO LIMINE THEME"
CONFIG_PATH=""
RESOLUTION=""
ASSUME_YES=false
CONFIG_CANDIDATES=(
  /boot/limine.conf
  /boot/limine/limine.conf
  /boot/efi/EFI/limine/limine.conf
  /boot/efi/EFI/BOOT/limine.conf
  /efi/EFI/limine/limine.conf
  /efi/EFI/BOOT/limine.conf
)

if [[ "${EUID}" -ne 0 && "${1:-}" != "-h" && "${1:-}" != "--help" ]]; then
  command -v sudo >/dev/null 2>&1 || { printf 'Error: ejecuta como root o instala sudo.\n' >&2; exit 1; }
  exec sudo -- "$0" "$@"
fi

info() { printf '\033[1;36m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
error() { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die() { error "$*"; exit 1; }

usage() {
  cat <<'EOF'
Uso: sudo ./install.sh [opciones]

Opciones:
  --config RUTA       Usar una ruta concreta a limine.conf
  --resolution MODO   Elegir una resolución, por ejemplo 1920x1080
  --yes               No pedir confirmación final
  -h, --help          Mostrar esta ayuda
EOF
}

while (($#)); do
  case "$1" in
    --config) (($# >= 2)) || die "Falta la ruta después de --config"; CONFIG_PATH="$2"; shift 2 ;;
    --resolution) (($# >= 2)) || die "Falta la resolución después de --resolution"; RESOLUTION="$2"; shift 2 ;;
    --yes) ASSUME_YES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Opción desconocida: $1" ;;
  esac
done

cat <<'EOF'

  SSSSS  EEEEE  K  K  III  RRRR   OOO
  S      E      K K    I   R   R O   O
  SSSSS  EEEE   KK     I   RRRR  O   O
      S  E      K K    I   R R   O   O
  SSSSS  EEEEE  K  K  III  R  RR  OOO

             LIMINE THEME INSTALLER
EOF

select_config() {
  local candidate choice
  if [[ -n "$CONFIG_PATH" ]]; then
    [[ -f "$CONFIG_PATH" ]] || die "No existe la configuración: $CONFIG_PATH"
    return
  fi
  local found=()
  for candidate in "${CONFIG_CANDIDATES[@]}"; do
    [[ -f "$candidate" ]] && found+=("$candidate")
  done
  if ((${#found[@]} == 0)); then
    die "No se encontró limine.conf. Usa --config /ruta/a/limine.conf."
  elif ((${#found[@]} == 1)); then
    CONFIG_PATH="${found[0]}"
  else
    printf 'Se encontraron varias configuraciones de Limine:\n'
    local i
    for i in "${!found[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${found[$i]}"; done
    read -r -p 'Elige una [1]: ' choice
    choice="${choice:-1}"
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#found[@]}" ]] || die 'Selección inválida.'
    CONFIG_PATH="${found[$((choice - 1))]}"
  fi
}

select_resolution() {
  local options=() choice
  [[ -f "${SOURCE_DIR}/sekiro_1920x1080.png" ]] && options+=("1920x1080")
  [[ -f "${SOURCE_DIR}/sekiro_2560x1440.png" ]] && options+=("2560x1440")
  ((${#options[@]} > 0)) || die "No se encontraron fondos compatibles en ${SOURCE_DIR}."
  if [[ -n "$RESOLUTION" ]]; then
    local option
    for option in "${options[@]}"; do [[ "$option" == "$RESOLUTION" ]] && return; done
    die "Resolución no disponible: $RESOLUTION"
  elif ((${#options[@]} == 1)); then
    RESOLUTION="${options[0]}"
  else
    printf '\nFondos disponibles:\n'
    local i
    for i in "${!options[@]}"; do printf '  %d) %s\n' "$((i + 1))" "${options[$i]}"; done
    read -r -p 'Elige una [1]: ' choice
    choice="${choice:-1}"
    [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#options[@]}" ]] || die 'Selección inválida.'
    RESOLUTION="${options[$((choice - 1))]}"
  fi
}

remove_theme_block() {
  local file="$1" tmp
  tmp="$(mktemp)"
  awk -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
    $0 == begin { skip=1; next }
    $0 == end { skip=0; next }
    !skip { print }
  ' "$file" > "$tmp"
  cat "$tmp" > "$file"
  rm -f "$tmp"
}

select_config
select_resolution
command -v findmnt >/dev/null 2>&1 || die 'No se encontró findmnt; no se puede localizar el volumen de arranque de forma segura.'
BOOT_ROOT="$(findmnt -no TARGET -T "$CONFIG_PATH")"
[[ -n "$BOOT_ROOT" && -d "$BOOT_ROOT" ]] || die "No se pudo determinar el volumen de arranque para $CONFIG_PATH."
THEME_DIR="${BOOT_ROOT}/themes/${THEME_NAME}"
BACKUP_PATH="${CONFIG_PATH}.backup-$(date +%Y%m%d-%H%M%S)"
STATE_PATH="${THEME_DIR}/.sekiro-install-state"
BACKGROUND="sekiro_${RESOLUTION}.png"
INSTALL_ID="$(date +%Y%m%d-%H%M%S)-$$"

cat <<EOF

Configuración:  ${CONFIG_PATH}
Volumen boot:   ${BOOT_ROOT}
Backup:         ${BACKUP_PATH}
Tema:           ${THEME_DIR}
Fondo:          ${BACKGROUND}

EOF
if [[ "$ASSUME_YES" != true ]]; then
  read -r -p '¿Continuar con la instalación? [s/N] ' answer
  [[ "$answer" =~ ^[sS][iI]?$ ]] || { info 'Instalación cancelada.'; exit 0; }
fi

while [[ -e "$BACKUP_PATH" ]]; do
  BACKUP_PATH="${CONFIG_PATH}.backup-${INSTALL_ID}"
  INSTALL_ID="${INSTALL_ID}-1"
done
cp -- "$CONFIG_PATH" "$BACKUP_PATH"
rollback() {
  error 'La instalación falló; restaurando el backup de limine.conf.'
  cp -a -- "$BACKUP_PATH" "$CONFIG_PATH"
  exit 1
}
trap rollback ERR

mkdir -p -- "$THEME_DIR"
# EFI/FAT volumes do not support preserving Unix ownership. A plain copy is
# intentional here; the bootloader only needs to read the image.
cp -- "${SOURCE_DIR}/${BACKGROUND}" "$THEME_DIR/${BACKGROUND}"

remove_theme_block "$CONFIG_PATH"
tmp_config="$(mktemp "${CONFIG_PATH}.tmp.XXXXXX")"
cat > "$tmp_config" <<EOF
${BEGIN_MARKER}
# Generated by sekiro_grub_theme. Do not edit this block manually.
graphics: yes
interface_resolution: ${RESOLUTION}
wallpaper: boot():/themes/${THEME_NAME}/${BACKGROUND}
wallpaper_style: stretched
interface_branding: Sekiro
interface_branding_colour: b14046
interface_help_colour: b14046
interface_help_colour_bright: f0a0a0
term_background: 80000000
term_foreground: ffffff
term_background_bright: 40000000
term_foreground_bright: ffffff
term_margin: 64
term_margin_gradient: 8
term_palette: 120b0b;8f1d2c;5f6b3a;b8863b;3e4b6b;7d3152;557a78;d8c9b0
term_palette_bright: 4d4141;d94b5b;93a85b;e0b85c;6477a8;bd5e8a;7da9a2;fff4dc
${END_MARKER}

EOF
cat "$CONFIG_PATH" >> "$tmp_config"
chmod --reference="$CONFIG_PATH" "$tmp_config" 2>/dev/null || true
mv -f -- "$tmp_config" "$CONFIG_PATH"
rm -f "$tmp_config"
printf '%s\n' "CONFIG_PATH=$CONFIG_PATH" "BACKUP_PATH=$BACKUP_PATH" "BOOT_ROOT=$BOOT_ROOT" "THEME_DIR=$THEME_DIR" "BACKGROUND=$BACKGROUND" > "$STATE_PATH"

trap - ERR
[[ -f "${THEME_DIR}/${BACKGROUND}" ]] || die 'No se pudo verificar el fondo instalado.'
grep -Fq "$BEGIN_MARKER" "$CONFIG_PATH" || die 'No se pudo verificar el bloque de configuración.'
success 'Tema instalado correctamente.'
printf '\nRollback manual:\n  sudo cp -- %q %q\n' "$BACKUP_PATH" "$CONFIG_PATH"
printf 'Desinstalación:\n  sudo ./uninstall.sh --config %q\n' "$CONFIG_PATH"
