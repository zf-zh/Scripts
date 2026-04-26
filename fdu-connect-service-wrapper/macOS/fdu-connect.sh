#!/usr/bin/env bash

# Check for root permissions
if [ "$(whoami)" != "root" ]
then
    echo "$0: Permission denied, please try again with \"sudo\"" >&2
    exit 1
fi


# Define variables
## Default
DAEMON_NAME_DEFAULT="com.github.fdu-connect-daemon-helper"
DAEMON_PATH_DEFAULT="/Users/jz2025/.config/fdu-connect/com.github.fdu-connect-daemon-helper.plist"
CONFIG_PATH_DEFAULT="/Users/jz2025/.config/fdu-connect/config-fdu-connect.toml"
EXEC_PATH_DEFAULT="/Users/jz2025/.config/fdu-connect/fdu-connect"

## Specified
DAEMON_NAME="com.github.fdu-connect-daemon-helper"
DAEMON_PATH="/Library/LaunchDaemons/com.github.fdu-connect-daemon-helper.plist"
CONFIG_PATH="$CONFIG_PATH_DEFAULT"
EXEC_PATH="$EXEC_PATH_DEFAULT"
EXEC_ARGS=""

## Types
DAEMON_TYPE=0   # 0: main, 1: helper
CONFIG_TYPE=0   # 0: default config, 1: custom config, 2: args
EXEC_TYPE=0     # 0: default executable, 1: custom executable
OPERATION_TYPE="$1"


# Function to display help message
help() {
    echo "fdu-connect daemon helper:"
    echo "Usage:"
    echo -e "  start [options]\n    \tStart the daemon"
    echo -e "  stop\n    \tStop the daemon"
    echo -e "  restart\n    \tRestart the daemon"
    echo -e "  status\n    \tCheck the status of the daemon"
    echo -e "  help\n    \tDisplay this help message. For more details about fdu-connect, use -h or --help"
    echo ""
    echo "Additional options for \"start\" command:"
    echo -e "  -a, --args string\n    \tSpecify the arguments for the executable (ignored if -c/--config is used)"
    echo -e "  -c, --config string\n    \tSpecify the configuration file path (default \"$CONFIG_PATH_DEFAULT\")"
    echo -e "  -e, --exec string\n    \tSpecify the executable file path (default \"$EXEC_PATH_DEFAULT\")"
    echo ""
    echo "Other options:"
    echo -e "  -\n    \tRead from standard input"
    echo -e "  -h, --help\n    \tDisplay help message of fdu-connect"
    echo ""
    return 0
}


# Parse additional options for "start" command
shift
ARG_NUMBER=$#
if [ "$OPERATION_TYPE" = "start" ]
then
    while [ $# -gt 0 ]
    do
        case "$1" in
            -a | --args)
                DAEMON_TYPE=1
                # Check for multiple argument sources
                if [ $CONFIG_TYPE -eq 2 ]
                then
                    echo "$0 start: Multiple argument sources specified" >&2
                    help
                    exit 1
                fi
                # Check if config file is specified
                if [ $CONFIG_TYPE -ne 1 ]
                then
                    CONFIG_TYPE=2
                fi
                # Read arguments
                if [[ "$2" =~ ^[[:space:]]*$ ]]
                then
                    echo "Arguments must be specified" >&2
                    exit 1
                elif [ "$2" = "-" ]
                then
                    EXEC_ARGS="$(cat /dev/stdin)"
                else
                    EXEC_ARGS="$2"
                fi
                ;;
            -c | --config)
                DAEMON_TYPE=1
                # Check for multiple config sources
                if [ $CONFIG_TYPE -eq 1 ]
                then
                    echo "$0 start: Multiple config sources specified" >&2
                    help
                    exit 1
                fi
                CONFIG_TYPE=1
                # Read config path
                if [[ "$2" =~ ^[[:space:]]*$ ]]
                then
                    CONFIG_PATH=$CONFIG_PATH_DEFAULT
                elif [ "$2" = "-" ]
                then
                    CONFIG_PATH="$(cat /dev/stdin)"
                else
                    CONFIG_PATH="$2"
                fi
                ;;
            -e | --exec)
                DAEMON_TYPE=1
                # Check for multiple executable sources
                if [ $EXEC_TYPE -eq 1 ]
                then
                    echo "$0 start: Multiple executable sources specified" >&2
                    help
                    exit 1
                fi
                EXEC_TYPE=1
                # Read executable path
                if [[ "$2" =~ ^[[:space:]]*$ ]]
                then
                    EXEC_PATH=$EXEC_PATH_DEFAULT
                elif [ "$2" = "-" ]
                then
                    EXEC_PATH="$(cat /dev/stdin)"
                else
                    EXEC_PATH="$2"
                fi
                ;;
            *)
                echo "$0 start: Unknown option \"$1\"" >&2
                help
                exit 1
                ;;
        esac
        if ! shift 2
        then
            shift
        fi
    done
fi


# Functions for daemon management
## Function to check the arguments
check_arguments() {
    if [ $ARG_NUMBER -ne 0 ]
    then
        echo "$0 $OPERATION_TYPE: Unexpected arguments" >&2
        help
        return 1
    fi
    return 0
}

## Function to generate plist file
generate_plist() {
    if [ $DAEMON_TYPE -eq 1 ]
    then
        # Generate customized plist
        cat <<EOF > "$DAEMON_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key>
        <string>${DAEMON_NAME}</string>
        <key>RunAtLoad</key>
        <false/>
        <key>KeepAlive</key>
        <dict>
            <key>Crashed</key>
            <true/>
        </dict>
        <key>ProgramArguments</key>
        <array>
            <string>${EXEC_PATH}</string>
EOF
        if [ $CONFIG_TYPE -eq 2 ]
        then
            for arg in $EXEC_ARGS
            do
                echo "            <string>${arg}</string>" >> "$DAEMON_PATH"
            done
        else
            echo "            <string>--config</string>" >> "$DAEMON_PATH"
            echo "            <string>${CONFIG_PATH}</string>" >> "$DAEMON_PATH"
        fi
        cat <<EOF >> "$DAEMON_PATH"
        </array>
    </dict>
</plist>
EOF
        if [ $? -ne 0 ]
        then
            echo "$0: Failed to create plist file \"$DAEMON_PATH\"" >&2
            return 1
        fi
    else
        # Use default plist
        cp "$DAEMON_PATH_DEFAULT" "$DAEMON_PATH"
        if [ $? -ne 0 ]
        then
            echo "$0: Failed to copy default plist file \"$DAEMON_PATH_DEFAULT\" to \"$DAEMON_PATH\"" >&2
            return 1
        fi
    fi
    return 0
}

## Function to start the daemon
start_daemon() {
    # Check if the daemon is running
    if launchctl list | grep -q "$DAEMON_NAME"
    then
        echo "$0: Daemon is already running" >&2
        return 1
    fi
    # Generate the plist file
    generate_plist
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to generate plist file" >&2
        return 1
    fi
    # Load the daemon
    launchctl load "$DAEMON_PATH"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to load \"$DAEMON_PATH\"" >&2
        return 1
    fi
    # Start the daemon
    launchctl start "$DAEMON_NAME"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to start \"$DAEMON_NAME\"" >&2
        return 1
    fi
    return 0
}

## Function to stop the daemon
stop_daemon() {
    # Check the arguments
    if ! check_arguments
    then
        return 1
    fi
    # Check if the daemon is running
    if ! launchctl list | grep -q "$DAEMON_NAME"
    then
        echo "$0: Daemon is not running" >&2
        return 1
    fi
    # Stop the daemon
    launchctl stop "$DAEMON_NAME"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to stop \"$DAEMON_NAME\"" >&2
        return 1
    fi
    # Unload the daemon
    launchctl unload "$DAEMON_PATH"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to unload \"$DAEMON_PATH\"" >&2
        return 1
    fi
    # Remove the daemon plist file
    rm "$DAEMON_PATH"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to remove \"$DAEMON_PATH\", please remove it manually" >&2
        return 1
    fi
    return 0
}

## Function to restart the daemon
restart_daemon() {
    # Check the arguments
    if ! check_arguments
    then
        return 1
    fi
    # Check if the daemon is running
    if ! launchctl list | grep -q "$DAEMON_NAME"
    then
        echo "$0: Daemon is not running, starting it instead"
        start_daemon
        return $?
    fi
    # Stop the daemon
    launchctl stop "$DAEMON_NAME"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to stop \"$DAEMON_NAME\"" >&2
        return 1
    fi
    # Wait for a moment to ensure the daemon has stopped
    sleep 1
    # Start the daemon
    launchctl start "$DAEMON_NAME"
    if [ $? -ne 0 ]
    then
        echo "$0: Failed to start \"$DAEMON_NAME\"" >&2
        return 1
    fi
    return 0
}

## Function to check the status of the daemon
status_daemon() {
    # Check the arguments
    if ! check_arguments
    then
        return 1
    fi
    # Check if the daemon is running
    if ! launchctl list | grep -q "$DAEMON_NAME"
    then
        echo "fdu-connect is not running"
        return 3
    fi
    echo "fdu-connect is running"
    launchctl list | grep "PID\tStatus\tLabel"
    launchctl list | grep "$DAEMON_NAME"
    return 0
}


# Phrase the first argument and call corresponding functions
case $OPERATION_TYPE in
    "" | help)
        help
        exit $?
        ;;
    -h | --help)
        help
        "$EXEC_PATH" -h
        exit $?
        ;;
    start)
        start_daemon
        exit $?
        ;;
    stop)
        stop_daemon
        exit $?
        ;;
    restart)
        restart_daemon
        exit $?
        ;;
    status)
        status_daemon
        exit $?
        ;;
    *)
        echo -e "$0: Unknown argument \"$OPERATION_TYPE\"\n" >&2
        help
        exit 1
        ;;
esac

