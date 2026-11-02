#!/usr/bin/env bash
# Print battery levels of connected Bluetooth devices, including both halves
# of ZMK splits (needs CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y).
#
#   $ scripts/battery.sh
#   Fuji44: left 79%, right 85%
set -euo pipefail

BATTERY_LEVEL=00002a19-0000-1000-8000-00805f9b34fb
USER_DESCRIPTION=00002901-0000-1000-8000-00805f9b34fb

prop() { busctl get-property org.bluez "$1" "$2" "$3" 2>/dev/null | cut -d' ' -f2- | tr -d '"'; }
read_byte() { busctl call org.bluez "$1" org.bluez.GattCharacteristic1 ReadValue 'a{sv}' 0 2>/dev/null | cut -d' ' -f3; }

paths=$(busctl tree org.bluez --list 2>/dev/null)

for dev in $(grep -E '^/org/bluez/hci[0-9]+/dev_[0-9A-F_]+$' <<<"$paths"); do
    [[ $(prop "$dev" org.bluez.Device1 Connected) == true ]] || continue
    levels=()
    for chr in $(grep -E "^$dev/service[0-9a-f]+/char[0-9a-f]+$" <<<"$paths"); do
        [[ $(prop "$chr" org.bluez.GattCharacteristic1 UUID) == "$BATTERY_LEVEL" ]] || continue
        level=$(read_byte "$chr") && [[ -n $level ]] || continue
        # ZMK labels proxied peripheral batteries with a user description;
        # the central's (left half's) own battery has none.
        side=left
        for desc in $(grep -E "^$chr/desc[0-9a-f]+$" <<<"$paths"); do
            [[ $(prop "$desc" org.bluez.GattDescriptor1 UUID) == "$USER_DESCRIPTION" ]] && side=right
        done
        levels+=("$side $level%")
    done
    ((${#levels[@]})) || continue
    name=$(prop "$dev" org.bluez.Device1 Alias)
    if ((${#levels[@]} == 1)); then
        echo "$name: ${levels[0]#* }"
    else
        echo "$name: $(IFS=,; sed 's/,/, /g' <<<"${levels[*]}")"
    fi
done
