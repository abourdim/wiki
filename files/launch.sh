#!/usr/bin/env bash
# launch.sh - a friendly helper to build and flash the ESP32-CAM robot.
#
#   ./launch.sh            show the menu
#   ./launch.sh <step>     run one step directly, for example: ./launch.sh compile
#
# Steps: check install wifi config compile usb ota logs open clean help
#
# Every command is printed (after a ▶) before it runs, so you can see
# exactly what the computer is doing.

set -u
cd "$(dirname "$0")" || exit 1

YAML="esp32_cam_robot.yaml"
NAME="esp32-cam-robot"
ESPHOME_VERSION="2026.7.3"
VENV="$HOME/esphome-venv"
ROBOT="${ROBOT_IP:-$NAME.local}"     # robot address, change it with ROBOT_IP=192.168.1.42

# ---------------------------------------------------------------- Colours
if [ -t 1 ]; then
  OFF=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'
  MAGENTA=$'\e[35m'; CYAN=$'\e[36m'; WHITE=$'\e[97m'
else
  OFF=""; BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
  MAGENTA=""; CYAN=""; WHITE=""
fi

ok()    { printf '%s  ✅ %s%s\n' "$GREEN$BOLD" "$*" "$OFF"; }
bad()   { printf '%s  ❌ %s%s\n' "$RED$BOLD" "$*" "$OFF"; }
warn()  { printf '%s  ⚠️  %s%s\n' "$YELLOW$BOLD" "$*" "$OFF"; }
info()  { printf '%s  👉 %s%s\n' "$CYAN" "$*" "$OFF"; }
title() { printf '\n%s%s %s %s\n\n' "$MAGENTA$BOLD" "━━━" "$*" "━━━$OFF"; }

# Print a command in bright colours, then run it.
show_cmd() {
  local s="" a
  for a in "$@"; do
    case "$a" in *" "*) s+=" \"$a\"" ;; *) s+=" $a" ;; esac
  done
  s="${s//$HOME/\~}"
  printf '%s  ▶%s%s\n' "$BOLD$YELLOW" "$WHITE$s" "$OFF"
}
run() {
  show_cmd "$@"
  "$@"
  local rc=$?
  if [ $rc -ne 0 ]; then bad "That command failed (code $rc)"; fi
  return $rc
}

ask_yes() {   # ask_yes "question" -> 0 for yes
  local a
  read -r -p "${BOLD}${BLUE}  ❓ $1 [y/N] ${OFF}" a
  [[ "$a" =~ ^[yYoO] ]]
}
pause() { read -r -p "${DIM}  Press Enter to go back to the menu...${OFF}" _; }

# ---------------------------------------------------------------- Helpers
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) WINDOWS=1 ;;
  *) WINDOWS=0 ;;
esac

PY=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1; then PY="$p"; break; fi
done

# Programs inside the ESPHome folder (venv): bin/ on Linux, Scripts/ on Windows
if [ "$WINDOWS" = 1 ]; then VBIN="$VENV/Scripts"; EXE=".exe"; else VBIN="$VENV/bin"; EXE=""; fi

find_esphome() {
  if   [ -x "$VBIN/esphome$EXE" ];         then ESPHOME="$VBIN/esphome$EXE"
  elif command -v esphome >/dev/null 2>&1; then ESPHOME="$(command -v esphome)"
  else ESPHOME=""
  fi
}
find_esphome

# On Windows, Git Bash sets MSYSTEM and puts it back into every program it
# starts ("env -u" can't remove it). ESP-IDF sees it and builds nothing, while
# ESPHome still says "Successfully compiled". So on Windows, esphome is started
# by a tiny Python step that deletes MSYSTEM first.
NOMSYS='import os, subprocess, sys; os.environ.pop("MSYSTEM", None); sys.exit(subprocess.call(sys.argv[1:]))'
esp_quiet() {   # esp_quiet <args>: run esphome <args>
  if [ "$WINDOWS" = 1 ]; then "$(esphome_python)" -c "$NOMSYS" "$ESPHOME" "$@"
  else "$ESPHOME" "$@"; fi
}
esp_run() {     # esp_run <args>: show "esphome <args>", then run it
  show_cmd esphome "$@"
  [ "$WINDOWS" = 1 ] && printf '%s     (Windows: started without MSYSTEM, so the build really happens)%s\n' "$DIM" "$OFF"
  esp_quiet "$@"
  local rc=$?
  if [ $rc -ne 0 ]; then bad "That command failed (code $rc)"; fi
  return $rc
}

# The Python that ESPHome runs on (it brings pyserial, used to list COM ports)
esphome_python() {
  if [ -x "$VBIN/python$EXE" ]; then echo "$VBIN/python$EXE"
  elif [ "$WINDOWS" = 1 ] && [ -x "$(dirname "$(dirname "$ESPHOME")")/python.exe" ]; then
    echo "$(dirname "$(dirname "$ESPHOME")")/python.exe"
  else echo "$PY"
  fi
}

need_esphome() {
  if [ -z "$ESPHOME" ]; then
    bad "ESPHome is not installed yet."
    info "Choose 2 (Install) first."
    return 1
  fi
}

need_secrets() {
  if [ ! -s secrets.yaml ]; then
    bad "No Wi-Fi settings yet (secrets.yaml is missing)."
    info "Choose 3 (Set Wi-Fi) first."
    return 1
  fi
}

firmware_file() {   # newest firmware .bin in the build folder
  find ".esphome/build/$NAME" \( -name "$NAME.bin" -o -name firmware.bin \) \
       -newer "$YAML" 2>/dev/null | head -n 1
}

usb_ports() {
  if [ "$WINDOWS" = 1 ]; then
    "$(esphome_python)" -m serial.tools.list_ports -q 2>/dev/null | awk '{print $1}'
  else
    ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
  fi
}

ask_robot() {
  local a
  read -r -p "${BOLD}${BLUE}  ❓ Robot address (shown on the OLED) [$ROBOT]: ${OFF}" a
  [ -n "$a" ] && ROBOT="$a"
}

# ---------------------------------------------------------------- Steps
do_check() {
  title "🔍 Check install"
  local problems=0 v

  if [ -n "$PY" ]; then ok "Python found: $($PY --version 2>&1)"
  else bad "Python 3 is missing"; problems=$((problems + 1)); fi

  if [ -d "$VENV" ]; then ok "ESPHome folder found: ${VENV/$HOME/\~}"
  else warn "No ESPHome folder at ${VENV/$HOME/\~} (Install makes it)"; fi

  if [ -n "$ESPHOME" ]; then
    show_cmd esphome version
    v="$(esp_quiet version 2>/dev/null | sed 's/.*: //')"
    if [ "$v" = "$ESPHOME_VERSION" ]; then ok "ESPHome $v (the right version)"
    else bad "ESPHome is $v, but this robot needs $ESPHOME_VERSION"; problems=$((problems + 1)); fi
  else
    bad "ESPHome is not installed"; problems=$((problems + 1))
  fi

  if [ "$WINDOWS" = 1 ]; then
    ok "Windows: esphome is started without MSYSTEM, so compiling works"
  elif id -nG | grep -qw dialout; then ok "You may use USB ports (dialout group)"
  else bad "You are not in the dialout group yet (Install can fix it)"; problems=$((problems + 1)); fi
  local ports; ports="$(usb_ports)"
  if [ -n "$ports" ]; then ok "USB port found: $(echo $ports)"
  else warn "No USB board plugged in (only needed for the first flash)"; fi

  if [ -s secrets.yaml ] && ! grep -q "your-ssid" secrets.yaml; then ok "Wi-Fi settings found"
  else bad "Wi-Fi settings missing (choose 3)"; problems=$((problems + 1)); fi

  echo
  if [ $problems -eq 0 ]; then ok "Everything is ready! 🎉"
  else warn "$problems thing(s) to fix"; fi
}

do_install() {
  title "📦 Install"
  if [ -z "$PY" ]; then
    bad "Python 3 is missing"
    if [ "$WINDOWS" = 1 ]; then info "Ask an adult to install Python from python.org (tick 'Add to PATH')"
    else info "Ask an adult to run: sudo apt install python3 python3-venv"; fi
    return 1
  fi
  if [ ! -x "$VBIN/python$EXE" ]; then
    run "$PY" -m venv "$VENV" || { [ "$WINDOWS" = 1 ] || info "Try: sudo apt install python3-venv"; return 1; }
  else
    ok "ESPHome folder already there"
  fi
  run "$VBIN/python$EXE" -m pip install --upgrade pip || return 1
  run "$VBIN/python$EXE" -m pip install "esphome==$ESPHOME_VERSION" || return 1
  find_esphome
  ok "ESPHome $ESPHOME_VERSION installed"

  if [ "$WINDOWS" = 0 ] && ! id -nG | grep -qw dialout; then
    echo
    info "To flash over USB you must be in the 'dialout' group. This needs the admin password."
    if ask_yes "Add $USER to dialout now?"; then
      run sudo usermod -aG dialout "$USER" && warn "Log out and log back in for this to work"
    fi
  fi
}

do_wifi() {
  title "📶 Set Wi-Fi"
  if [ -s secrets.yaml ] && ! ask_yes "Wi-Fi is already set. Change it?"; then return 0; fi
  info "The robot only works on 2.4 GHz Wi-Fi (not 5 GHz)."
  local ssid pass
  read -r -p "${BOLD}${BLUE}  📶 Wi-Fi name: ${OFF}" ssid
  read -r -s -p "${BOLD}${BLUE}  🔑 Wi-Fi password (hidden): ${OFF}" pass; echo
  if [ -z "$ssid" ]; then bad "The name can't be empty"; return 1; fi
  ssid="${ssid//\\/\\\\}"; ssid="${ssid//\"/\\\"}"
  pass="${pass//\\/\\\\}"; pass="${pass//\"/\\\"}"
  printf '%s  ▶%s write secrets.yaml (password hidden)%s\n' "$BOLD$YELLOW" "$WHITE" "$OFF"
  printf 'wifi_ssid: "%s"\nwifi_password: "%s"\n' "$ssid" "$pass" > secrets.yaml
  chmod 600 secrets.yaml 2>/dev/null
  ok "Wi-Fi saved"
}

do_config() {
  title "🧪 Check config"
  need_esphome || return 1
  need_secrets || return 1
  local log rc
  log="$(mktemp)"
  show_cmd esphome config "$YAML"
  esp_quiet config "$YAML" > "$log" 2>&1
  rc=$?
  if [ $rc -eq 0 ]; then
    ok "The config is valid"
  else
    sed -n '/Failed config/,$p' "$log"
    bad "The config has a mistake (see above)"
  fi
  rm -f "$log"
  return $rc
}

do_compile() {
  title "🛠️  Compile"
  need_esphome || return 1
  need_secrets || return 1
  info "The first time takes 5-15 minutes. Time for a snack 🍪"
  esp_run compile "$YAML" || return 1
  local bin; bin="$(firmware_file)"
  if [ -n "$bin" ]; then
    ok "Firmware ready: $bin ($(( $(wc -c < "$bin") / 1024 )) kB)"
  else
    bad "ESPHome said OK but made no firmware file"
    return 1
  fi
}

ensure_compiled() {
  if [ -n "$(firmware_file)" ]; then return 0; fi
  info "No fresh firmware yet, compiling first."
  do_compile
}

do_usb() {
  title "🔌 Flash over USB"
  need_esphome || return 1
  ensure_compiled || return 1

  echo
  printf '%s  Get the robot ready:%s\n' "$BOLD$WHITE" "$OFF"
  printf '%s   1. ⚡ Motor power switch OFF (wheels must not spin on the desk)%s\n' "$YELLOW" "$OFF"
  printf '%s   2. 🔗 Put the jumper on J6 (IO0 to GND)%s\n' "$YELLOW" "$OFF"
  printf '%s   3. 🔌 Plug the USB-serial adapter into J5, and USB-C for power%s\n' "$YELLOW" "$OFF"
  read -r -p "${DIM}  Press Enter when ready...${OFF}" _

  local ports port
  mapfile -t ports < <(usb_ports)
  if [ ${#ports[@]} -eq 0 ]; then
    bad "No USB board found"
    info "Check the cable (some cables only charge) and try again."
    return 1
  elif [ ${#ports[@]} -eq 1 ]; then
    port="${ports[0]}"
  else
    info "Several USB boards found:"
    select port in "${ports[@]}"; do [ -n "$port" ] && break; done
  fi
  ok "Using $port"
  esp_run upload "$YAML" --device "$port" || return 1
  ok "Flashed! 🎉"
  printf '%s   Now remove the J6 jumper and press reset.%s\n' "$YELLOW$BOLD" "$OFF"
  info "The OLED will show the robot's address in a few seconds."
}

do_ota() {
  title "📡 Update over Wi-Fi"
  need_esphome || return 1
  ensure_compiled || return 1
  ask_robot
  esp_run upload "$YAML" --device "$ROBOT" || return 1
  ok "Robot updated! 🎉"
}

do_logs() {
  title "📜 Watch logs"
  need_esphome || return 1
  ask_robot
  info "Press Ctrl+C to stop."
  esp_run logs "$YAML" --device "$ROBOT"
}

open_url() {
  if   [ "$WINDOWS" = 1 ];                  then run cmd.exe //c start "" "$1"
  elif command -v xdg-open >/dev/null 2>&1; then run xdg-open "$1"
  elif command -v open >/dev/null 2>&1;     then run open "$1"
  else info "Open this in your browser: $1"
  fi
}

do_open() {
  title "🌐 Open robot page"
  ask_robot
  open_url "http://$ROBOT/"
  open_url "http://$ROBOT:8080/"
  info "Buttons are on the first page, video on the second."
}

do_clean() {
  title "🧹 Clean"
  need_esphome || return 1
  if ask_yes "Delete the build files? (the next compile will be slow)"; then
    esp_run clean "$YAML" && ok "All clean ✨"
  fi
}

do_help() {
  printf 'Usage: %s [step]\n\n' "$0"
  printf 'Steps: check install wifi config compile usb ota logs open clean\n'
  printf 'Without a step, a menu is shown. Set ROBOT_IP to skip typing the address.\n'
}

# ---------------------------------------------------------------- Menu
banner() {
  local text="ESP32-CAM ROBOT" cols=("$RED" "$YELLOW" "$GREEN" "$CYAN" "$BLUE" "$MAGENTA") i out=""
  for (( i = 0; i < ${#text}; i++ )); do
    out+="${cols[i % 6]}${text:i:1}"
  done
  printf '\n  🤖  %s%s%s  🤖\n' "$BOLD" "$out" "$OFF"
  printf '%s  ESPHome %s · robot v2 + plugin v3%s\n' "$DIM" "$ESPHOME_VERSION" "$OFF"
}

menu() {
  while true; do
    banner
    printf '\n'
    printf '  %s 1%s  🔍 Check install\n'      "$CYAN$BOLD"    "$OFF"
    printf '  %s 2%s  📦 Install\n'            "$GREEN$BOLD"   "$OFF"
    printf '  %s 3%s  📶 Set Wi-Fi\n'          "$YELLOW$BOLD"  "$OFF"
    printf '  %s 4%s  🧪 Check config\n'       "$BLUE$BOLD"    "$OFF"
    printf '  %s 5%s  🛠️  Compile\n'           "$MAGENTA$BOLD" "$OFF"
    printf '  %s 6%s  🔌 Flash over USB\n'     "$RED$BOLD"     "$OFF"
    printf '  %s 7%s  📡 Update over Wi-Fi\n'  "$CYAN$BOLD"    "$OFF"
    printf '  %s 8%s  📜 Watch logs\n'         "$GREEN$BOLD"   "$OFF"
    printf '  %s 9%s  🌐 Open robot page\n'    "$YELLOW$BOLD"  "$OFF"
    printf '  %s10%s  🧹 Clean\n'              "$BLUE$BOLD"    "$OFF"
    printf '  %s 0%s  👋 Quit\n\n'             "$WHITE$BOLD"   "$OFF"
    local c
    read -r -p "${BOLD}  Pick a number: ${OFF}" c
    case "$c" in
      1) do_check ;;   2) do_install ;; 3) do_wifi ;;  4) do_config ;;
      5) do_compile ;; 6) do_usb ;;     7) do_ota ;;   8) do_logs ;;
      9) do_open ;;   10) do_clean ;;
      0|q|Q) printf '\n  👋 Bye! Have fun with your robot!\n\n'; exit 0 ;;
      *) bad "Pick a number from the list" ;;
    esac
    pause
  done
}

case "${1:-}" in
  "")      menu ;;
  check)   do_check ;;
  install) do_install ;;
  wifi)    do_wifi ;;
  config)  do_config ;;
  compile) do_compile ;;
  usb)     do_usb ;;
  ota)     do_ota ;;
  logs)    do_logs ;;
  open)    do_open ;;
  clean)   do_clean ;;
  help|-h|--help) do_help ;;
  *) bad "Unknown step: $1"; do_help; exit 1 ;;
esac
