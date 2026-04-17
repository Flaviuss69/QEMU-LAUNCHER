#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║              Q L A U N C H  v3.0                        ║
# ║         Universal QEMU/KVM Launcher                     ║
# ╚══════════════════════════════════════════════════════════╝

R='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
BRED='\033[91m'; BGRN='\033[92m'; BYEL='\033[93m'
BMAG='\033[95m'; BCYN='\033[96m'; BWHT='\033[97m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS="/usr/share/OVMF/OVMF_VARS_4M.fd"
DEF_RAM=4096
DEF_CPUS=6
DEF_VNC="127.0.0.1:0"

# ─── UI ──────────────────────────────────────────────────────
hr()     { echo -e "  ${DIM}${BCYN}────────────────────────────────────────────────────────────${R}"; }
ok()     { echo -e "  ${BGRN}✔${R}  $*"; }
warn()   { echo -e "  ${BYEL}⚠${R}  $*"; }
err()    { echo -e "  ${BRED}✘${R}  $*"; }
info()   { echo -e "  ${BCYN}·${R}  $*"; }
skip()   { echo -e "  ${DIM}  ↷  $* (indisponibil — sarit)${R}"; }

ask() {
    local _v="$1" _p="$2" _d="$3" _i
    echo -en "  ${BCYN}›${R} ${_p} ${DIM}[${_d}]${R}: "
    read -r _i </dev/tty
    printf -v "$_v" '%s' "${_i:-${_d}}"
}

yn() {
    local _a
    echo -en "  ${BYEL}?${R}  ${BOLD}$1${R} ${DIM}[y/N]${R}: "
    read -r _a </dev/tty
    [[ "${_a,,}" == "y" ]]
}

icon_for() {
    local n="${1,,}"
    case "$n" in
        *kali*)                    echo "💀" ;;
        *parrot*)                  echo "🦜" ;;
        *ubuntu*)                  echo "🟠" ;;
        *debian*)                  echo "🌀" ;;
        *fedora*)                  echo "🎩" ;;
        *arch*)                    echo "🏹" ;;
        *mint*)                    echo "🌿" ;;
        *manjaro*)                 echo "🍃" ;;
        *windows*|*win10*|*win11*) echo "🪟" ;;
        *freebsd*)                 echo "😈" ;;
        *tails*)                   echo "🧅" ;;
        *whonix*)                  echo "🧅" ;;
        *alpine*)                  echo "🏔️"  ;;
        *qubes*)                   echo "🔐" ;;
        *proxmox*)                 echo "🖥️"  ;;
        *centos*|*rhel*)           echo "🔴" ;;
        *opensuse*)                echo "🦎" ;;
        *.qcow2)                   echo "💾" ;;
        *.iso)                     echo "💿" ;;
        *)                         echo "🖥️"  ;;
    esac
}

filesize() {
    local s; s=$(stat -c%s "$1" 2>/dev/null || echo 0)
    if   (( s >= 1073741824 )); then printf "%.1fG" "$(echo "scale=1;$s/1073741824"|bc)"
    elif (( s >= 1048576    )); then printf "%dM"   $(( s / 1048576 ))
    else                              printf "%dK"   $(( s / 1024 ))
    fi
}

banner() {
    clear
    echo -e "${BCYN}"
    echo -e "  ██████╗ ██╗      █████╗ ██╗   ██╗███╗   ██╗ ██████╗██╗  ██╗"
    echo -e "  ██╔═══██╗██║     ██╔══██╗██║   ██║████╗  ██║██╔════╝██║  ██║"
    echo -e "  ██║   ██║██║     ███████║██║   ██║██╔██╗ ██║██║     ███████║"
    echo -e "  ██║▄▄ ██║██║     ██╔══██║██║   ██║██║╚██╗██║██║     ██╔══██║"
    echo -e "  ╚██████╔╝███████╗██║  ██║╚██████╔╝██║ ╚████║╚██████╗██║  ██║"
    echo -e "   ╚══▀▀═╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝${R}"
    echo ""
    echo -e "  ${DIM}${BCYN}Universal QEMU/KVM Launcher  •  v3.0  •  $(date '+%Y-%m-%d %H:%M')${R}"
    hr; echo ""
}

# ─── DETECTIE QEMU ───────────────────────────────────────────
# Cauta in PATH + locatii comune + orice ./*/qemu-system-x86_64
detect_qemu() {
    # 1. PATH standard
    if command -v qemu-system-x86_64 &>/dev/null; then
        command -v qemu-system-x86_64; return 0
    fi
    # 2. Locatii fixe comune
    for b in /usr/bin/qemu-system-x86_64 \
             /usr/local/bin/qemu-system-x86_64 \
             /opt/qemu/bin/qemu-system-x86_64; do
        [[ -x "$b" ]] && { echo "$b"; return 0; }
    done
    # 3. Build local — cauta recursiv in folderul scriptului (max 3 nivele)
    local found
    found="$(find "$SCRIPT_DIR" -maxdepth 3 -name "qemu-system-x86_64" -executable 2>/dev/null | head -1)"
    [[ -n "$found" ]] && { echo "$found"; return 0; }
    return 1
}

# ─── PROBE CAPABILITATI ──────────────────────────────────────
# Verifica daca un device/backend e compilat in binary
has_device() {
    "$QEMU_BIN" -device help 2>&1 | grep -q "^$1"
}

has_netdev() {
    "$QEMU_BIN" -netdev help 2>&1 | grep -q "^$1"
}

has_audiodev() {
    "$QEMU_BIN" -audiodev help 2>&1 | grep -q "^$1"
}

has_display() {
    "$QEMU_BIN" -display help 2>&1 | grep -qi "$1"
}

has_accel() {
    "$QEMU_BIN" -accel help 2>&1 | grep -q "^$1"
}

# ─── START ───────────────────────────────────────────────────
banner

# Gaseste QEMU
QEMU_BIN="$(detect_qemu)"
if [[ -z "$QEMU_BIN" ]]; then
    err "qemu-system-x86_64 nu a fost gasit nicaieri."
    info "Incearca: sudo apt install qemu-system-x86  sau  adauga build-ul in PATH"
    exit 1
fi
QEMU_VER="$("$QEMU_BIN" --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)"
ok "QEMU ${DIM}${QEMU_BIN}${R}  ${BCYN}v${QEMU_VER}${R}"

# KVM
KVM_ON=0
if [[ -r /dev/kvm ]]; then
    KVM_ON=1; ok "KVM disponibil"
elif [[ -e /dev/kvm ]]; then
    warn "KVM exista dar nu ai permisiuni — adauga-te in grupul 'kvm'"
else
    warn "KVM indisponibil — rulare in TCG (lent)"
fi

# UEFI
UEFI_OK=0
[[ -f "$OVMF_CODE" && -f "$OVMF_VARS" ]] && { UEFI_OK=1; ok "UEFI/OVMF gasit"; } \
    || warn "OVMF lipsa — doar BIOS legacy  ${DIM}(apt install ovmf)${R}"

# Probe devices compilate
CAP_VIRTIO_NET=0;  has_device "virtio-net-pci"   && CAP_VIRTIO_NET=1
CAP_E1000=0;       has_device "e1000"             && CAP_E1000=1
CAP_VNC=0;         has_display "vnc"              && CAP_VNC=1
CAP_QXL=0;         has_device "qxl-vga"          && CAP_QXL=1
CAP_VMWARE=0;      has_device "vmware-svga"       && CAP_VMWARE=1
CAP_VIRTIO_GPU=0;  has_device "virtio-gpu-pci"   && CAP_VIRTIO_GPU=1
CAP_USB_EHCI=0;    has_device "usb-ehci"         && CAP_USB_EHCI=1
CAP_USB_XHCI=0;    has_device "usb-xhci"         && CAP_USB_XHCI=1
CAP_USB_TABLET=0;  has_device "usb-tablet"       && CAP_USB_TABLET=1
CAP_BALLOON=0;     has_device "virtio-balloon-pci" && CAP_BALLOON=1
CAP_RNG=0;         has_device "virtio-rng-pci"   && CAP_RNG=1
CAP_SCSI=0;        has_device "virtio-scsi-pci"  && CAP_SCSI=1
CAP_9P=0;          has_device "virtio-9p-pci"    && CAP_9P=1

# Audio backends
CAP_AUDIO_PA=0;    has_audiodev "pa"             && CAP_AUDIO_PA=1
CAP_AUDIO_ALSA=0;  has_audiodev "alsa"           && CAP_AUDIO_ALSA=1
CAP_AUDIO_SDL=0;   has_audiodev "sdl"            && CAP_AUDIO_SDL=1
CAP_AC97=0;        has_device "AC97"             && CAP_AC97=1
CAP_HDA=0;         has_device "intel-hda"        && CAP_HDA=1

# Network
CAP_SLIRP=0;       has_netdev "user"             && CAP_SLIRP=1
CAP_TAP=0;         has_netdev "tap"              && CAP_TAP=1
CAP_BRIDGE=0;      has_netdev "bridge"           && CAP_BRIDGE=1

echo ""; hr

# ─── SCAN FISIERE ────────────────────────────────────────────
mapfile -t ALL_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 \( -iname "*.iso" -o -iname "*.qcow2" \) | sort)

if [[ ${#ALL_FILES[@]} -eq 0 ]]; then
    echo ""
    err "Niciun .iso sau .qcow2 gasit in: ${DIM}${SCRIPT_DIR}${R}"
    echo ""; exit 1
fi

echo ""
echo -e "  ${BOLD}${BWHT}  #    TIP        SIZE      NUME${R}"
hr

for i in "${!ALL_FILES[@]}"; do
    f="${ALL_FILES[$i]}"
    fname="$(basename "$f")"
    ext="${fname##*.}"; ext="${ext,,}"
    ico="$(icon_for "$fname")"
    sz="$(filesize "$f")"
    [[ "$ext" == "qcow2" ]] \
        && typ="${BMAG}[DISK]${R}" \
        || typ="${BCYN}[LIVE]${R}"
    printf "  ${BCYN}[${BYEL}%2d${BCYN}]${R}  %b  %s  ${DIM}%-8s${R}  ${BOLD}%s${R}\n" \
        "$((i+1))" "$typ" "$ico" "$sz" "$fname"
done

echo ""; hr; echo ""
echo -en "  ${BCYN}›${R} ${BOLD}Alege OS${R} ${DIM}[1-${#ALL_FILES[@]}]${R}: "
read -r CHOICE </dev/tty

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || (( CHOICE < 1 || CHOICE > ${#ALL_FILES[@]} )); then
    echo ""; err "Optiune invalida: '${CHOICE}'"; echo ""; exit 1
fi

SELECTED="${ALL_FILES[$((CHOICE-1))]}"
FNAME="$(basename "$SELECTED")"
EXT="${FNAME##*.}"; EXT="${EXT,,}"

# ─── CONFIGURATIE ────────────────────────────────────────────
banner
echo -e "  ${BCYN}▸${R}  ${BOLD}${FNAME}${R}  $(icon_for "$FNAME")"
echo ""; hr; echo ""
echo -e "  ${BOLD}${BWHT}CONFIGURATIE${R}  ${DIM}(Enter = pastreaza default)${R}"
echo ""

ask RAM  "RAM (MB)"    "$DEF_RAM"
ask CPUS "vCPU total"  "$DEF_CPUS"
CORES=$(( CPUS / 2 )); [[ $CORES -lt 1 ]] && CORES=1; THREADS=2

echo ""
echo -e "  ${DIM}── Display ──────────────────────────────────────────────────${R}"

# Alege VGA
VGA_DEVICE="std"
if (( CAP_QXL || CAP_VMWARE || CAP_VIRTIO_GPU )); then
    echo -e "  ${BCYN}Video disponibil:${R}"
    VGA_OPTS=("std")
    [[ $CAP_QXL       -eq 1 ]] && VGA_OPTS+=("qxl")
    [[ $CAP_VMWARE    -eq 1 ]] && VGA_OPTS+=("vmware")
    [[ $CAP_VIRTIO_GPU -eq 1 ]] && VGA_OPTS+=("virtio")
    for vi in "${!VGA_OPTS[@]}"; do
        printf "  ${BCYN}[${BYEL}%d${BCYN}]${R}  %s\n" "$((vi+1))" "${VGA_OPTS[$vi]}"
    done
    echo -en "  ${BCYN}›${R} VGA ${DIM}[1]${R}: "
    read -r VGA_PICK </dev/tty
    if [[ "$VGA_PICK" =~ ^[0-9]+$ ]] && (( VGA_PICK >= 1 && VGA_PICK <= ${#VGA_OPTS[@]} )); then
        VGA_DEVICE="${VGA_OPTS[$((VGA_PICK-1))]}"
    fi
fi
info "VGA: ${VGA_DEVICE}"

# VNC
USE_VNC=0
if [[ $CAP_VNC -eq 1 ]]; then
    ask VNC "VNC address" "$DEF_VNC"
    USE_VNC=1
else
    warn "VNC nu e disponibil in acest build — folosesc display SDL/GTK daca exista"
fi

echo ""
echo -e "  ${DIM}── Retea ─────────────────────────────────────────────────────${R}"

NET_MODE="none"
if   [[ $CAP_SLIRP   -eq 1 ]]; then NET_MODE="user"
elif [[ $CAP_TAP     -eq 1 ]]; then NET_MODE="tap"
elif [[ $CAP_BRIDGE  -eq 1 ]]; then NET_MODE="bridge"; fi

NET_DEV="virtio-net-pci"
[[ $CAP_VIRTIO_NET -eq 0 && $CAP_E1000 -eq 1 ]] && NET_DEV="e1000"

if [[ "$NET_MODE" == "none" && $CAP_VIRTIO_NET -eq 0 && $CAP_E1000 -eq 0 ]]; then
    skip "Retea (niciun backend/device disponibil)"
else
    info "Retea: ${NET_MODE} / ${NET_DEV}"
fi

echo ""
echo -e "  ${DIM}── UEFI / Boot ───────────────────────────────────────────────${R}"

USE_UEFI=0
if [[ $UEFI_OK -eq 1 ]]; then
    yn "UEFI/OVMF?" && USE_UEFI=1
else
    skip "UEFI"
fi

USE_SNAPSHOT=0
if [[ "$EXT" == "qcow2" ]]; then
    yn "Snapshot mode (fara scriere pe disk)?" && USE_SNAPSHOT=1
fi

echo ""
echo -e "  ${DIM}── Audio ─────────────────────────────────────────────────────${R}"

USE_AUDIO=0
AUDIO_BACKEND=""
AUDIO_DEVICE=""

if (( CAP_AUDIO_PA || CAP_AUDIO_ALSA || CAP_AUDIO_SDL )); then
    if   [[ $CAP_AUDIO_PA   -eq 1 ]]; then AUDIO_BACKEND="pa"
    elif [[ $CAP_AUDIO_ALSA -eq 1 ]]; then AUDIO_BACKEND="alsa"
    elif [[ $CAP_AUDIO_SDL  -eq 1 ]]; then AUDIO_BACKEND="sdl"; fi

    if   [[ $CAP_HDA  -eq 1 ]]; then AUDIO_DEVICE="intel-hda"
    elif [[ $CAP_AC97 -eq 1 ]]; then AUDIO_DEVICE="AC97"; fi

    if [[ -n "$AUDIO_DEVICE" ]]; then
        yn "Sunet (${AUDIO_BACKEND} + ${AUDIO_DEVICE})?" && USE_AUDIO=1
    else
        skip "Audio device (backend exista dar niciun device HDA/AC97)"
    fi
else
    skip "Audio (niciun backend compilat)"
fi

echo ""
echo -e "  ${DIM}── USB ────────────────────────────────────────────────────────${R}"

USE_USB=0
USB_CTRL=""
if   [[ $CAP_USB_XHCI -eq 1 ]]; then USB_CTRL="xhci"
elif [[ $CAP_USB_EHCI -eq 1 ]]; then USB_CTRL="ehci"; fi

if [[ -n "$USB_CTRL" && $CAP_USB_TABLET -eq 1 ]]; then
    yn "USB tablet (input VNC mai smooth) — controller ${USB_CTRL}?" && USE_USB=1
else
    skip "USB tablet"
fi

echo ""
echo -e "  ${DIM}── Extra ─────────────────────────────────────────────────────${R}"

USE_BALLOON=0
if [[ $CAP_BALLOON -eq 1 ]]; then
    yn "Memory balloon (elibereaza RAM dinamic)?" && USE_BALLOON=1
else
    skip "Memory balloon"
fi

USE_RNG=0
if [[ $CAP_RNG -eq 1 ]]; then
    yn "VirtIO RNG (entropy mai rapid in VM)?" && USE_RNG=1
else
    skip "VirtIO RNG"
fi

# ─── BUILD CMD ───────────────────────────────────────────────
CMD=("$QEMU_BIN")

# CPU / KVM
if [[ $KVM_ON -eq 1 ]]; then
    CMD+=(-enable-kvm -cpu "host,kvm=on")
else
    CMD+=(-cpu "qemu64")
fi
CMD+=(-smp "${CPUS},sockets=1,cores=${CORES},threads=${THREADS}" -m "$RAM")

# Drive
if [[ "$EXT" == "qcow2" ]]; then
    SNAP_OPT=""; [[ $USE_SNAPSHOT -eq 1 ]] && SNAP_OPT=",snapshot=on"
    CMD+=(-drive "file=${SELECTED},format=qcow2,if=virtio${SNAP_OPT}" -boot order=c)
else
    CMD+=(-cdrom "$SELECTED" -boot order=d)
fi

# UEFI
if [[ $USE_UEFI -eq 1 ]]; then
    CMD+=(-drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}")
    CMD+=(-drive "if=pflash,format=raw,file=${OVMF_VARS}")
fi

# Retea
if [[ "$NET_MODE" != "none" ]]; then
    CMD+=(-netdev "${NET_MODE},id=n1" -device "${NET_DEV},netdev=n1")
fi

# Display
CMD+=(-vga "$VGA_DEVICE")
if [[ $USE_VNC -eq 1 ]]; then
    CMD+=(-vnc "$VNC")
fi

# Audio
if [[ $USE_AUDIO -eq 1 ]]; then
    CMD+=(-audiodev "${AUDIO_BACKEND},id=snd0")
    if [[ "$AUDIO_DEVICE" == "intel-hda" ]]; then
        CMD+=(-device "intel-hda" -device "hda-duplex,audiodev=snd0")
    else
        CMD+=(-device "${AUDIO_DEVICE},audiodev=snd0")
    fi
fi

# USB
if [[ $USE_USB -eq 1 ]]; then
    CMD+=(-usb)
    if [[ "$USB_CTRL" == "xhci" ]]; then
        CMD+=(-device "nec-usb-xhci,id=xhci" -device "usb-tablet,bus=xhci.0")
    else
        CMD+=(-device "usb-ehci,id=ehci" -device "usb-tablet,bus=ehci.0")
    fi
fi

# Extra
[[ $USE_BALLOON -eq 1 ]] && CMD+=(-device virtio-balloon-pci)
[[ $USE_RNG     -eq 1 ]] && CMD+=(-device virtio-rng-pci)

# ─── SUMAR ───────────────────────────────────────────────────
echo ""; hr; echo ""
echo -e "  ${BOLD}${BWHT}SUMAR${R}"; echo ""
echo -e "  ${BCYN}OS      ${R}  $(icon_for "$FNAME")  ${BOLD}${FNAME}${R}"
echo -e "  ${BCYN}QEMU    ${R}  ${DIM}${QEMU_BIN}${R}  ${BCYN}v${QEMU_VER}${R}"
echo -e "  ${BCYN}RAM     ${R}  ${RAM} MB"
echo -e "  ${BCYN}vCPU    ${R}  ${CPUS}  (${CORES} cores × ${THREADS} threads)"
echo -e "  ${BCYN}KVM     ${R}  $([[ $KVM_ON       -eq 1 ]] && echo "${BGRN}ON${R}"  || echo "${BYEL}TCG${R}")"
echo -e "  ${BCYN}UEFI    ${R}  $([[ $USE_UEFI     -eq 1 ]] && echo "${BGRN}ON${R}"  || echo "${DIM}BIOS${R}")"
echo -e "  ${BCYN}VGA     ${R}  ${VGA_DEVICE}"
echo -e "  ${BCYN}VNC     ${R}  $([[ $USE_VNC      -eq 1 ]] && echo "${VNC}"         || echo "${DIM}OFF${R}")"
echo -e "  ${BCYN}Retea   ${R}  $([[ "$NET_MODE" != "none" ]] && echo "${NET_MODE}/${NET_DEV}" || echo "${DIM}OFF${R}")"
echo -e "  ${BCYN}Audio   ${R}  $([[ $USE_AUDIO    -eq 1 ]] && echo "${BGRN}${AUDIO_BACKEND}+${AUDIO_DEVICE}${R}" || echo "${DIM}OFF${R}")"
echo -e "  ${BCYN}USB     ${R}  $([[ $USE_USB      -eq 1 ]] && echo "${BGRN}${USB_CTRL}+tablet${R}" || echo "${DIM}OFF${R}")"
echo -e "  ${BCYN}Balloon ${R}  $([[ $USE_BALLOON  -eq 1 ]] && echo "${BGRN}ON${R}"  || echo "${DIM}OFF${R}")"
echo -e "  ${BCYN}RNG     ${R}  $([[ $USE_RNG      -eq 1 ]] && echo "${BGRN}ON${R}"  || echo "${DIM}OFF${R}")"
[[ "$EXT" == "qcow2" ]] && \
echo -e "  ${BCYN}SNAP    ${R}  $([[ $USE_SNAPSHOT -eq 1 ]] && echo "${BGRN}ON${R}"  || echo "${DIM}OFF${R}")"
echo ""
echo -e "  ${DIM}CMD: ${CMD[*]}${R}"
echo ""; hr; echo ""

yn "Lansezi?" || { echo -e "\n  ${DIM}Anulat.${R}\n"; exit 0; }

echo ""
echo -e "  ${BGRN}▶  Pornire ${BOLD}${FNAME}${R}${BGRN} ...${R}"
echo ""
sleep 0.3
exec "${CMD[@]}"
