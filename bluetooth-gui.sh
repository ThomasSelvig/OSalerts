#!/bin/bash

# Function to check if bluetooth is powered on
check_bluetooth_power() {
    powered=$(bluetoothctl show | grep "Powered:" | cut -d " " -f 2)
    if [ "$powered" != "yes" ]; then
        zenity --question --title="Bluetooth Power" --text="Bluetooth is powered off. Turn it on?" --width=300
        if [ $? -eq 0 ]; then
            bluetoothctl power on
        else
            exit 1
        fi
    fi
}

# Function to scan and list devices
scan_devices() {
    # Show scanning progress
    (
        bluetoothctl scan on &
        scan_pid=$!
        for i in {1..5}; do
            echo "$i"
            echo "# Scanning for devices... ($i/5 seconds)"
            sleep 1
        done
        kill $scan_pid
    ) | zenity --progress \
        --title="Scanning" \
        --text="Starting scan..." \
        --percentage=0 \
        --auto-close \
        --auto-kill

    # Get list of devices
    devices=$(bluetoothctl devices | awk '{$1=""; print substr($0,2)}')

    # Create device list for zenity
    echo "$devices" | awk '{print $1 "|" $2}'
}

# Function to get device trust status
get_trust_status() {
    local mac=$1
    trusted=$(bluetoothctl info $mac | grep "Trusted: " | cut -d " " -f 2)
    echo $trusted
}

# Function to manage device trust
manage_trust() {
    devices=$(bluetoothctl devices | awk '{$1=""; print substr($0,2)}')
    if [ -z "$devices" ]; then
        zenity --error --title="No Devices" --text="No paired devices found" --width=300
        return
    fi

    # Create a list with trust status
    device_list=""
    while IFS= read -r device; do
        mac=$(echo $device | awk '{print $1}')
        name=$(echo $device | cut -d' ' -f2-)
        trust_status=$(get_trust_status $mac)
        device_list+="$mac|$name|$trust_status\n"
    done <<< "$devices"

    selected=$(echo -e "$device_list" | zenity --list \
        --title="Manage Device Trust" \
        --width=500 --height=300 \
        --column="MAC" --column="Name" --column="Trusted" \
        --text="Select a device to change trust status:")

    if [ -n "$selected" ]; then
        mac=$(echo $selected | cut -d'|' -f1)
        current_trust=$(get_trust_status $mac)

        if [ "$current_trust" = "yes" ]; then
            bluetoothctl untrust $mac
            zenity --info --text="Device untrusted" --width=300
        else
            bluetoothctl trust $mac
            zenity --info --text="Device trusted" --width=300
        fi
    fi
}

# Main menu
while true; do
    check_bluetooth_power

    action=$(zenity --list \
        --title="Bluetooth Manager" \
        --width=400 --height=350 \
        --column="Action" \
        "Scan for Devices" \
        "Connect to Device" \
        "Disconnect Device" \
        "Manage Trust" \
        "Remove Paired Device" \
        "Exit")

    case "$action" in
        "Scan for Devices")
            devices=$(scan_devices)
            if [ -n "$devices" ]; then
                zenity --info --title="Available Devices" --text="$devices" --width=300
            else
                zenity --error --title="No Devices" --text="No devices found" --width=300
            fi
            ;;

        "Connect to Device")
            devices=$(bluetoothctl devices | awk '{$1=""; print substr($0,2)}')
            selected=$(echo "$devices" | zenity --list \
                --title="Select Device" \
                --column="MAC" --column="Name" \
                --width=400 --height=300)

            if [ -n "$selected" ]; then
                mac=$(echo $selected | cut -d'|' -f1)
                (
                    echo "# Attempting to connect..."
                    bluetoothctl connect $mac
                ) | zenity --progress \
                    --title="Connecting" \
                    --text="Connecting to device..." \
                    --pulsate \
                    --auto-close \
                    --auto-kill

                # Check if connection was successful
                if bluetoothctl info $mac | grep -q "Connected: yes"; then
                    zenity --info --text="Connected successfully" --width=300
                else
                    zenity --error --text="Connection failed" --width=300
                fi
            fi
            ;;

        "Disconnect Device")
            connected=$(bluetoothctl info | grep "Device" | cut -d " " -f 2)
            if [ -n "$connected" ]; then
                bluetoothctl disconnect $connected
                zenity --info --text="Device disconnected" --width=300
            else
                zenity --error --text="No device connected" --width=300
            fi
            ;;

        "Manage Trust")
            manage_trust
            ;;

        "Remove Paired Device")
            devices=$(bluetoothctl devices | awk '{$1=""; print substr($0,2)}')
            selected=$(echo "$devices" | zenity --list \
                --title="Select Device to Remove" \
                --column="MAC" --column="Name" \
                --width=400 --height=300)

            if [ -n "$selected" ]; then
                mac=$(echo $selected | cut -d'|' -f1)
                bluetoothctl remove $mac
                zenity --info --text="Device removed" --width=300
            fi
            ;;

        "Exit")
            exit 0
            ;;

        *)
            exit 0
            ;;
    esac
done
