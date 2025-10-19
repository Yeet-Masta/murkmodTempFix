#!/bin/bash

# image_patcher.sh
# written based on the original by coolelectronics and r58, modified heavily for murkmod
# R125 compatibility added

CURRENT_MAJOR=6
CURRENT_MINOR=1
CURRENT_VERSION=2

ascii_info() {
    echo -e "                      __                      .___\n  _____  __ _________|  | __ _____   ____   __| _/\n /     \|  |  \_  __ \  |/ //     \ /  _ \ / __ | \n|  Y Y  \  |  /|  | \/    <|  Y Y  (  <_> ) /_/ | \n|__|_|  /____/ |__|  |__|_ \__|_|  /\____/\____ | \n      \/                  \/     \/            \/\n"
    echo "        The fakemurk plugin manager - v$CURRENT_MAJOR.$CURRENT_MINOR.$CURRENT_VERSION"
}

nullify_bin() {
    cat <<-EOF >$1
#!/bin/bash
exit
EOF
    chmod 777 $1
}

. /usr/share/misc/chromeos-common.sh || :

traps() {
    set -e
    trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
    trap 'echo "\"${last_command}\" command failed with exit code $?. THIS IS A BUG, REPORT IT HERE https://github.com/MercuryWorkshop/fakemurk"' EXIT
}

leave() {
    trap - EXIT
    echo "exiting successfully"
    exit
}

sed_escape() {
    echo -n "$1" | while read -n1 ch; do
        if [[ "$ch" == "" ]]; then
            echo -n "\n"
        fi
        echo -n "\\x$(printf %x \'"$ch")"
    done
}

move_bin() {
    if test -f "$1"; then
        mv "$1" "$1.old"
    fi
}

disable_autoupdates() {
    sed -i "$ROOT/etc/lsb-release" -e "s/CHROMEOS_AUSERVER=.*/CHROMEOS_AUSERVER=$(sed_escape "https://updates.gooole.com/update")/"
    move_bin "$ROOT/usr/sbin/chromeos-firmwareupdate"
    nullify_bin "$ROOT/usr/sbin/chromeos-firmwareupdate"
    rm -rf "$ROOT/opt/google/cr50/firmware/" || :
}

SCRIPT_DIR=$(dirname "$0")
configure_binaries(){
  if [ -f /sbin/ssd_util.sh ]; then
    SSD_UTIL=/sbin/ssd_util.sh
  elif [ -f /usr/share/vboot/bin/ssd_util.sh ]; then
    SSD_UTIL=/usr/share/vboot/bin/ssd_util.sh
  elif [ -f "${SCRIPT_DIR}/lib/ssd_util.sh" ]; then
    SSD_UTIL="${SCRIPT_DIR}/lib/ssd_util.sh"
  else
    echo "ERROR: Cannot find the required ssd_util script. Please make sure you're executing this script inside the directory it resides in"
    exit 1
  fi
}

# R125 FIX: Add version-specific patches
patch_r125_specific() {
    local ROOT="$1"
    local milestone="$2"
    
    echo "=== Applying R125+ Compatibility Patches ==="
    
    # 1. Fix systemd-logind interaction
    echo "Installing systemd-logind compatibility layer..."
    mkdir -p "$ROOT/etc/systemd/system/systemd-logind.service.d"
    cat > "$ROOT/etc/systemd/system/systemd-logind.service.d/10-murkmod.conf" <<'EOF'
[Service]
# Wait for murkmod startup to complete before managing VTs
ExecStartPre=/bin/bash -c 'timeout 30 sh -c "while [ -f /run/murkmod-critical-startup ]; do sleep 0.5; done" || true'
Restart=on-failure
RestartSec=5
EOF

    # 2. Create VT unlock service
    echo "Creating VT unlock service..."
    cat > "$ROOT/etc/systemd/system/murkmod-vt-unlock.service" <<'EOF'
[Unit]
Description=Murkmod VT Unlock After Startup
After=chromeos_startup.service
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'for vt in tty2 tty3 tty4 tty5 tty6; do [ -c /dev/$vt ] && chmod 620 /dev/$vt 2>/dev/null || true; done'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    chmod 644 "$ROOT/etc/systemd/system/murkmod-vt-unlock.service"
    
    # 3. Enable the service
    if [ -x "$ROOT/bin/systemctl" ] || [ -x "$ROOT/usr/bin/systemctl" ]; then
        mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
        ln -sf /etc/systemd/system/murkmod-vt-unlock.service \
            "$ROOT/etc/systemd/system/multi-user.target.wants/murkmod-vt-unlock.service" 2>/dev/null || true
    fi
    
    # 4. Fix Terminal app for R125+ (vsh-based)
    if [ -f "$ROOT/usr/bin/vsh" ]; then
        echo "Patching vsh for R125+ Terminal app..."
        move_bin "$ROOT/usr/bin/vsh"
        
        cat > "$ROOT/usr/bin/vsh" <<'VSHEOF'
#!/bin/bash
# Murkmod vsh wrapper for R125+

# Check if Terminal app is launching us
if [[ "$*" == *"--"* ]] || [ -z "$*" ]; then
    # Redirect to mush instead
    exec /usr/bin/crosh
else
    # Other use of vsh - call original
    if [ -x /usr/bin/vsh.old ]; then
        exec /usr/bin/vsh.old "$@"
    else
        # Fallback to crosh
        exec /usr/bin/crosh
    fi
fi
VSHEOF
        chmod 755 "$ROOT/usr/bin/vsh"
        echo "vsh patched successfully"
    else
        echo "vsh not found - Terminal app may use different method on this version"
    fi
    
    # 5. Add fallback for chrome://terminal
    if [ -d "$ROOT/opt/google/chrome" ]; then
        echo "Adding Terminal app fallback..."
        # The Terminal PWA might be in different locations depending on version
        # We'll create a marker file that daemon.sh can check
        touch "$ROOT/var/murkmod_r125_terminal_needs_fix"
    fi
    
    # 6. Create diagnostic script
    cat > "$ROOT/usr/local/bin/murkmod-diagnose" <<'DIAGEOF'
#!/bin/bash
echo "=== Murkmod R125+ Diagnostic ==="
echo "ChromeOS Version: $(cat /etc/lsb-release | grep CHROMEOS_RELEASE_CHROME_MILESTONE | cut -d= -f2)"
echo ""
echo "=== systemd-logind status ==="
systemctl status systemd-logind.service --no-pager 2>&1 | head -20
echo ""
echo "=== VT permissions ==="
ls -la /dev/tty[0-9]* 2>/dev/null
echo ""
echo "=== Murkmod startup status ==="
[ -f /var/run/murkmod-startup-complete ] && echo "✓ Startup complete" || echo "✗ Startup not complete"
[ -f /run/murkmod-critical-startup ] && echo "✗ IN CRITICAL STARTUP (VT2 UNSAFE)" || echo "✓ Not in critical startup"
echo ""
echo "=== Terminal/crosh binaries ==="
ls -la /usr/bin/crosh* /usr/bin/vsh* 2>/dev/null
echo ""
echo "=== Recent journal errors ==="
journalctl -b --no-pager 2>/dev/null | grep -i "tty\|logind\|console\|panic" | tail -30
DIAGEOF
    chmod 755 "$ROOT/usr/local/bin/murkmod-diagnose"
    
    echo "=== R125+ Compatibility Patches Applied ==="
}

patch_root() {
    echo "Staging populator..."
    >$ROOT/population_required
    >$ROOT/reco_patched
    echo "Murkmod-ing root..."
    echo "Disabling autoupdates..."
    disable_autoupdates
    
    local milestone=$(lsbval CHROMEOS_RELEASE_CHROME_MILESTONE $ROOT/etc/lsb-release)
    echo "Detected ChromeOS milestone: R$milestone"
    
    # R125 FIX: Check if version is too new
    if [ "$milestone" -gt "122" ]; then
        echo "⚠️  WARNING: ChromeOS R$milestone detected!"
        echo "⚠️  Murkmod was only tested up to R118."
        echo "⚠️  R$milestone has significant changes that required compatibility patches."
        echo "⚠️  Applying R125-specific patches..."
        
        # Apply R125 patches
        patch_r125_specific "$ROOT" "$milestone"
    fi
    
    echo "Installing startup scripts..."
    move_bin "$ROOT/sbin/chromeos_startup.sh"
    if [ "$milestone" -gt "116" ]; then
        echo "Detected v116 or higher, using new chromeos_startup"
        move_bin "$ROOT/sbin/chromeos_startup"
        install "chromeos_startup.sh" $ROOT/sbin/chromeos_startup
        chmod 755 $ROOT/sbin/chromeos_startup
        touch $ROOT/new-startup
    else
        move_bin "$ROOT/sbin/chromeos_startup.sh"
        install "chromeos_startup.sh" $ROOT/sbin/chromeos_startup.sh
        chmod 755 $ROOT/sbin/chromeos_startup.sh
    fi
    
    if [ "$milestone" -gt "78" ]; then
        echo "Detected v78 or higher, patching chromeos-boot-alert to prevent blocking devmode virtually"
        move_bin "$ROOT/sbin/chromeos-boot-alert"
        install "chromeos-boot-alert" $ROOT/sbin/chromeos-boot-alert
        chmod 755 $ROOT/sbin/chromeos-boot-alert
    fi
    
    echo "Installing murkmod components..."
    install "daemon.sh" $ROOT/sbin/murkmod-daemon.sh
    move_bin "$ROOT/usr/bin/crosh"
    install "mush.sh" $ROOT/usr/bin/crosh
    echo "Installing startup services..."
    install "pre-startup.conf" $ROOT/etc/init/pre-startup.conf
    install "cr50-update.conf" $ROOT/etc/init/cr50-update.conf
    echo "Installing other utilities..."
    install "ssd_util.sh" $ROOT/usr/share/vboot/bin/ssd_util.sh
    install "image_patcher.sh" $ROOT/sbin/image_patcher.sh
    install "crossystem_boot_populator.sh" $ROOT/sbin/crossystem_boot_populator.sh
    mkdir -p "$ROOT/etc/opt/chrome/policies/managed"
    install "pollen.json" $ROOT/etc/opt/chrome/policies/managed/policy.json
    echo "Chmod-ing everything..."
    chmod 777 $ROOT/sbin/murkmod-daemon.sh $ROOT/usr/bin/crosh $ROOT/usr/share/vboot/bin/ssd_util.sh $ROOT/sbin/image_patcher.sh $ROOT/etc/opt/chrome/policies/managed/policy.json $ROOT/sbin/crossystem_boot_populator.sh
    
    # R125 FIX: Additional permissions for R125+
    if [ "$milestone" -gt "122" ]; then
        chmod 755 "$ROOT/usr/local/bin/murkmod-diagnose" 2>/dev/null || true
    fi
    
    echo "Done."
}

lsbval() {
  local key="$1"
  local lsbfile="${2:-/etc/lsb-release}"

  if ! echo "${key}" | grep -Eq '^[a-zA-Z0-9_]+$'; then
    return 1
  fi

  sed -E -n -e \
    "/^[[:space:]]*${key}[[:space:]]*=/{
      s:^[^=]+=[[:space:]]*::
      s:[[:space:]]+$::
      p
    }" "${lsbfile}"
}

get_asset() {
    curl -s -f "https://api.github.com/repos/xXMariahScaryXx/murkmodTempFix/contents/$1" | jq -r ".content" | base64 -d
}

install() {
    TMP=$(mktemp)
    get_asset "$1" >"$TMP"
    if [ "$?" == "1" ] || ! grep -q '[^[:space:]]' "$TMP"; then
        echo "Failed to install $1 to $2"
        rm -f "$TMP"
        exit
    fi
    cat "$TMP" >"$2"
    rm -f "$TMP"
}

main() {
  traps
  ascii_info
  configure_binaries
  echo $SSD_UTIL

  if [ -z $1 ] || [ ! -f $1 ]; then
    echo "\"$1\" isn't a real file, dipshit! You need to pass the path to the recovery image. Optional args: <path to custom bootsplash: path to a png> <unfuck stateful: int 0 or 1>"
    exit
  fi
  if [ -z $2 ]; then
    echo "Not using a custom bootsplash."
    local bootsplash="0"
  elif [ "$2" == "cros" ]; then
    echo "Using cros bootsplash."
    local bootsplash="cros"
  elif [ ! -f $2 ]; then
    echo "File $2 not found for custom bootsplash"
    local bootsplash="0"
  else
    echo "Using custom bootsplash $2"
    local bootsplash=$2
  fi
  if [ -z $3 ]; then
    local unfuckstateful="1"
  else 
    local unfuckstateful=$3
  fi

  if [ "$unfuckstateful" == "1" ]; then
    echo "Will unfuck stateful partition upon boot."  
  fi

  local bin=$1
  
  echo "Creating loop device..."
  local loop=$(losetup -f | tail -1)
  if [[ -z "$loop" ]]; then
    echo "No free loop device. Exiting..."
    exit 1
  else
    echo $loop
  fi
  echo "Setting up loop with $loop and $bin"
  losetup -P "$loop" "$bin"

  echo "Disabling kernel verity..."
  $SSD_UTIL --debug --remove_rootfs_verification -i ${loop} --partitions 4
  echo "Enabling RW mount..."
  $SSD_UTIL --debug --remove_rootfs_verification --no_resign_kernel -i ${loop} --partitions 2

  sync
  
  echo "Mounting target..."
  mkdir /tmp/mnt || :
  mount "${loop}p3" /tmp/mnt

  ROOT=/tmp/mnt
  patch_root

  if [ "$bootsplash" != "cros" ]; then
    if [ "$bootsplash" != "0" ]; then
      echo "Adding custom bootsplash..."
      for i in $(seq -f "%02g" 0 30); do
        rm $ROOT/usr/share/chromeos-assets/images_100_percent/boot_splash_frame${i}.png
      done
      cp $bootsplash $ROOT/usr/share/chromeos-assets/images_100_percent/boot_splash_frame00.png
    else
      echo "Adding murkmod bootsplash..."
      install "chromeos-bootsplash-v2.png" /tmp/bootsplash.png
      for i in $(seq -f "%02g" 0 30); do
        rm $ROOT/usr/share/chromeos-assets/images_100_percent/boot_splash_frame${i}.png
      done
      cp /tmp/bootsplash.png $ROOT/usr/share/chromeos-assets/images_100_percent/boot_splash_frame00.png
      rm /tmp/bootsplash.png
    fi
  fi

  if [ "$unfuckstateful" == "0" ]; then
    touch $ROOT/stateful_unfucked
    chmod 777 $ROOT/stateful_unfucked
  fi

  sleep 2
  sync
  echo "Done. Have fun."

  umount "$ROOT"
  sync
  losetup -D "$loop"
  sync
  sleep 2
  rm -rf /tmp/mnt
  leave
}

if [ "$0" = "$BASH_SOURCE" ]; then
    stty sane
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit
    fi
    main "$@"
fi
