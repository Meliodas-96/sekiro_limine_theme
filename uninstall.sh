#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_PATH=""
if [[ "${EUID}" -ne 0 && "${1:-}" != "-h" && "${1:-}" != "--help" ]]; then
  command -v sudo >/dev/null 2>&1 || { printf 'Error: ejecuta como root o instala sudo.\n' >&2; exit 1; }
  exec sudo -- "$0" "$@"
fi

while (($#)); do
  case "$1" in
    --config) (($# >= 2)) || { printf 'Falta la ruta después de --config.\n' >&2; exit 1; }; CONFIG_PATH="$2"; shift 2 ;;
    -h|--help) printf 'Uso: sudo ./uninstall.sh [--config /ruta/a/limine.conf]\n'; exit 0 ;;
    *) printf 'Opción desconocida: %s\n' "$1" >&2; exit 1 ;;
  esac
done

if [[ -z "$CONFIG_PATH" ]]; then
  for candidate in /boot/limine.conf /boot/limine/limine.conf /boot/efi/EFI/limine/limine.conf /boot/efi/EFI/BOOT/limine.conf /efi/EFI/limine/limine.conf /efi/EFI/BOOT/limine.conf; do
    if [[ -f "$candidate" ]]; then CONFIG_PATH="$candidate"; break; fi
  done
fi
[[ -n "$CONFIG_PATH" && -f "$CONFIG_PATH" ]] || { printf 'No se encontró limine.conf. Usa --config.\n' >&2; exit 1; }

if ! command -v findmnt >/dev/null 2>&1; then printf 'No se encontró findmnt.\n' >&2; exit 1; fi
BOOT_ROOT="$(findmnt -no TARGET -T "$CONFIG_PATH")"
[[ -n "$BOOT_ROOT" ]] || { printf 'No se pudo determinar el volumen de arranque.\n' >&2; exit 1; }
THEME_DIR="${BOOT_ROOT}/themes/Sekiro"
STATE_PATH="${THEME_DIR}/.sekiro-install-state"
BACKUP_PATH=""
if [[ -f "$STATE_PATH" ]]; then
  # The state file binds this uninstall to the backup created by the installer.
  # Do not guess from unrelated files in /boot.
  BACKUP_PATH="$(sed -n 's/^BACKUP_PATH=//p' "$STATE_PATH")"
fi
[[ -n "$BACKUP_PATH" ]] || { printf 'No se encontró un backup para %s. No se hará ningún cambio.\n' "$CONFIG_PATH" >&2; exit 1; }
[[ -f "$BACKUP_PATH" ]] || { printf 'El backup indicado no existe: %s\n' "$BACKUP_PATH" >&2; exit 1; }

printf 'Configuración: %s\nBackup: %s\nRecursos: %s\n' "$CONFIG_PATH" "$BACKUP_PATH" "$THEME_DIR"
read -r -p '¿Restaurar el backup y eliminar el tema? [s/N] ' answer
[[ "$answer" =~ ^[sS][iI]?$ ]] || { printf 'Desinstalación cancelada.\n'; exit 0; }

cp -- "$BACKUP_PATH" "$CONFIG_PATH"
background="$(sed -n 's/^BACKGROUND=//p' "$STATE_PATH")"
[[ -n "$background" && "$background" != */* && "$background" != *..* ]] || { printf 'Estado del tema inválido.\n' >&2; exit 1; }
rm -f -- "$THEME_DIR/$background" "$STATE_PATH"
rmdir -- "$THEME_DIR" 2>/dev/null || true
printf 'Tema Sekiro eliminado y configuración restaurada.\n'
