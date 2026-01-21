import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // Widget properties
    preferredRepresentation: fullRepresentation
    toolTipMainText: "LG TV Remote"
    toolTipSubText: tvConnected ? "Connected to " + tvName : "Not Connected"

    // TV connection state (stored in plasmoid config)
    property string tvName: Plasmoid.configuration.tvName || ""
    property string tvIp: Plasmoid.configuration.tvIp || ""
    property bool useSsl: Plasmoid.configuration.useSsl !== undefined ? Plasmoid.configuration.useSsl : true
    property bool tvConnected: tvName !== "" && tvIp !== ""
    property string statusMessage: tvConnected ? "Ready" : "Not connected"

    // Path to bundled Python scripts
    readonly property string scriptPath: Qt.resolvedUrl("../code/lgtv_remote.py").toString().replace("file://", "")
    readonly property string daemonPath: Qt.resolvedUrl("../code/lgtv_daemon.py").toString().replace("file://", "")
    
    // Track if daemon is connected to TV
    property bool daemonConnected: false

    // Executable DataSource for running commands
    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            var exitCode = data["exit code"]

            // Parse JSON response
            var result = null
            try {
                result = JSON.parse(stdout)
            } catch (e) {}

            // Handle daemon status check
            if (source.indexOf("status") !== -1) {
                if (result && result.running) {
                    daemonConnected = result.connected || false
                    if (!daemonConnected && tvConnected) {
                        // Daemon running but not connected - connect it
                        connectDaemon()
                    }
                } else {
                    // Daemon not running - start it
                    startDaemon()
                }
                executable.disconnectSource(source)
                return
            }
            
            // Handle daemon start
            if (source.indexOf("start") !== -1) {
                // Give daemon time to start, then connect
                daemonStartTimer.start()
                executable.disconnectSource(source)
                return
            }
            
            // Handle connect response
            if (source.indexOf("connect") !== -1) {
                if (result && result.success) {
                    daemonConnected = true
                    statusMessage = "Connected"
                } else {
                    daemonConnected = false
                    statusMessage = "Connection failed"
                }
                statusTimer.restart()
                executable.disconnectSource(source)
                return
            }

            // Handle regular command response
            if (result && result.success) {
                statusMessage = "OK"
            } else if (result && result.error) {
                statusMessage = "Error"
                // If daemon reports not connected, try reconnecting
                if (result.error.indexOf("Not connected") !== -1) {
                    daemonConnected = false
                }
            }

            statusTimer.restart()
            executable.disconnectSource(source)
        }

        function exec(cmd) {
            executable.connectSource(cmd)
        }
    }
    
    // Timer to wait for daemon to start
    Timer {
        id: daemonStartTimer
        interval: 500
        onTriggered: connectDaemon()
    }
    
    // Check daemon status periodically
    Timer {
        id: daemonCheckTimer
        interval: 30000  // Check every 30 seconds
        running: true
        repeat: true
        onTriggered: checkDaemon()
    }
    
    function startDaemon() {
        executable.exec("python3 '" + daemonPath + "' start")
    }
    
    function checkDaemon() {
        executable.exec("python3 '" + daemonPath + "' status")
    }
    
    function connectDaemon() {
        if (tvName && tvIp) {
            var sslFlag = useSsl ? "" : " --no-ssl"
            executable.exec("python3 '" + daemonPath + "' connect '" + tvName + "' " + tvIp + sslFlag)
        }
    }
    
    Component.onCompleted: {
        // Start daemon check on widget load
        checkDaemon()
    }

    Timer {
        id: statusTimer
        interval: 1500
        onTriggered: {
            statusMessage = tvConnected ? "Ready" : "Not connected"
        }
    }

    // Send command to TV via daemon (fast) or fallback to direct script (slow)
    function sendCommand(command, args) {
        if (!tvConnected) {
            statusMessage = "Not connected"
            return
        }

        var argsStr = args ? args.join(",") : ""
        
        if (daemonConnected) {
            // Fast path: use daemon
            executable.exec("python3 '" + daemonPath + "' send " + command + " '" + argsStr + "'")
        } else {
            // Slow path: direct script (also tries to start daemon)
            var sslFlag = useSsl ? "" : " --no-ssl"
            executable.exec("python3 '" + scriptPath + "' send '" + tvName + "' " + command + " '" + argsStr + "'" + sslFlag)
            // Try to start daemon for next time
            checkDaemon()
        }
    }

    function scanForTVs() {
        statusMessage = "Listing saved TVs..."
        executable.exec("python3 '" + scriptPath + "' list")
    }

    function authenticateTV() {
        if (tvIp === "" || tvName === "") {
            statusMessage = "Please enter TV name and IP"
            return
        }

        statusMessage = "Authenticating... Accept on TV screen"
        var sslFlag = useSsl ? "" : " --no-ssl"
        var cmd = "python3 '" + scriptPath + "' auth " + tvIp + " '" + tvName + "'" + sslFlag
        executable.exec(cmd)
        
        // After auth, restart daemon to pick up new key
        daemonConnected = false
    }

    function saveSettings() {
        Plasmoid.configuration.tvName = tvName
        Plasmoid.configuration.tvIp = tvIp
        Plasmoid.configuration.useSsl = useSsl
    }

    // Keyboard shortcuts
    Keys.onPressed: function(event) {
        if (!tvConnected) return

        var hasShift = event.modifiers & Qt.ShiftModifier

        switch(event.key) {
            case Qt.Key_Up:
                sendCommand("sendButton", ["UP"])
                event.accepted = true
                break
            case Qt.Key_Down:
                sendCommand("sendButton", ["DOWN"])
                event.accepted = true
                break
            case Qt.Key_Left:
                sendCommand("sendButton", ["LEFT"])
                event.accepted = true
                break
            case Qt.Key_Right:
                sendCommand("sendButton", ["RIGHT"])
                event.accepted = true
                break
            case Qt.Key_Return:
            case Qt.Key_Enter:
                sendCommand("sendButton", ["ENTER"])
                event.accepted = true
                break
            case Qt.Key_Backspace:
            case Qt.Key_Escape:
                sendCommand("sendButton", ["BACK"])
                event.accepted = true
                break
            case Qt.Key_Equal:
            case Qt.Key_Plus:
                if (hasShift) {
                    sendCommand("mute", ["false"])  // Shift+= unmutes
                } else {
                    sendCommand("volumeUp")
                }
                event.accepted = true
                break
            case Qt.Key_Minus:
            case Qt.Key_Underscore:
                if (hasShift) {
                    sendCommand("mute", ["true"])  // Shift+- mutes
                } else {
                    sendCommand("volumeDown")
                }
                event.accepted = true
                break
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 28
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 32

        focus: true
        Keys.forwardTo: [root]

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            // Header
            RowLayout {
                Layout.fillWidth: true

                Kirigami.Heading {
                    text: "LG TV Remote"
                    level: 2
                }

                Item { Layout.fillWidth: true }

                PlasmaComponents.Label {
                    text: root.statusMessage
                    color: root.tvConnected ? Kirigami.Theme.positiveTextColor : Kirigami.Theme.negativeTextColor
                }
            }

            // Connection section
            Kirigami.Separator { Layout.fillWidth: true }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "Connection"
                    font.bold: true
                }

                RowLayout {
                    PlasmaComponents.Label {
                        text: "TV Name:"
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                    }
                    PlasmaComponents.TextField {
                        id: tvNameField
                        Layout.fillWidth: true
                        text: root.tvName
                        placeholderText: "e.g., LivingRoomTV"
                        onTextChanged: {
                            root.tvName = text
                            root.saveSettings()
                        }
                    }
                }

                RowLayout {
                    PlasmaComponents.Label {
                        text: "TV IP:"
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 5
                    }
                    PlasmaComponents.TextField {
                        id: tvIpField
                        Layout.fillWidth: true
                        text: root.tvIp
                        placeholderText: "192.168.1.100"
                        onTextChanged: {
                            root.tvIp = text
                            root.saveSettings()
                        }
                    }
                }

                RowLayout {
                    PlasmaComponents.CheckBox {
                        id: sslCheckbox
                        text: "Use SSL"
                        checked: root.useSsl
                        onCheckedChanged: {
                            root.useSsl = checked
                            root.saveSettings()
                        }
                    }
                    Item { Layout.fillWidth: true }
                    PlasmaComponents.Button {
                        text: "Scan"
                        icon.name: "view-refresh"
                        onClicked: root.scanForTVs()
                    }
                    PlasmaComponents.Button {
                        text: "Auth"
                        icon.name: "dialog-password"
                        enabled: root.tvName !== "" && root.tvIp !== ""
                        onClicked: root.authenticateTV()
                    }
                }
            }

            // Directional pad
            Kirigami.Separator { Layout.fillWidth: true }

            ColumnLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    text: "Navigation"
                    font.bold: true
                }

                GridLayout {
                    Layout.alignment: Qt.AlignHCenter
                    columns: 3
                    rowSpacing: Kirigami.Units.smallSpacing
                    columnSpacing: Kirigami.Units.smallSpacing

                    Item { width: 50; height: 50 }
                    PlasmaComponents.Button {
                        icon.name: "arrow-up"
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        onClicked: root.sendCommand("sendButton", ["UP"])
                    }
                    Item { width: 50; height: 50 }

                    PlasmaComponents.Button {
                        icon.name: "arrow-left"
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        onClicked: root.sendCommand("sendButton", ["LEFT"])
                    }
                    PlasmaComponents.Button {
                        text: "OK"
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        onClicked: root.sendCommand("sendButton", ["ENTER"])
                    }
                    PlasmaComponents.Button {
                        icon.name: "arrow-right"
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        onClicked: root.sendCommand("sendButton", ["RIGHT"])
                    }

                    Item { width: 50; height: 50 }
                    PlasmaComponents.Button {
                        icon.name: "arrow-down"
                        Layout.preferredWidth: 50
                        Layout.preferredHeight: 50
                        onClicked: root.sendCommand("sendButton", ["DOWN"])
                    }
                    Item { width: 50; height: 50 }
                }
            }

            // Volume controls
            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Button {
                    text: "Vol -"
                    icon.name: "audio-volume-low"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("volumeDown")
                }

                PlasmaComponents.Button {
                    icon.name: "audio-volume-muted"
                    Layout.preferredWidth: 50
                    onClicked: root.sendCommand("mute", ["true"])
                    PlasmaComponents.ToolTip { text: "Mute (Shift+-)" }
                }

                PlasmaComponents.Button {
                    icon.name: "audio-volume-high"
                    Layout.preferredWidth: 50
                    onClicked: root.sendCommand("mute", ["false"])
                    PlasmaComponents.ToolTip { text: "Unmute (Shift+=)" }
                }

                PlasmaComponents.Button {
                    text: "Vol +"
                    icon.name: "audio-volume-high"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("volumeUp")
                }
            }

            // Quick actions
            Kirigami.Separator { Layout.fillWidth: true }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                rowSpacing: Kirigami.Units.smallSpacing
                columnSpacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Button {
                    text: "Power On"
                    icon.name: "system-shutdown"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("on")
                }
                PlasmaComponents.Button {
                    text: "Power Off"
                    icon.name: "system-shutdown"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("off")
                }
                PlasmaComponents.Button {
                    text: "Home"
                    icon.name: "go-home"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("sendButton", ["HOME"])
                }
                PlasmaComponents.Button {
                    text: "Back"
                    icon.name: "go-previous"
                    Layout.fillWidth: true
                    onClicked: root.sendCommand("sendButton", ["BACK"])
                }
            }

            Item { Layout.fillHeight: true }

            // Help text
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: "Keys: Arrows, Enter, +/-, Shift+=Unmute, Shift+-=Mute"
                wrapMode: Text.WordWrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
            }
        }
    }

    compactRepresentation: Kirigami.Icon {
        source: "video-television"
        active: compactMouse.containsMouse

        MouseArea {
            id: compactMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.expanded = !root.expanded
        }
    }
}
