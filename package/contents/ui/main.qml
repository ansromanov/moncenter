import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // shortcut: talks to ddcutil's default (first) display only; add --display N per monitor if a second one appears.
    readonly property string readCmd: "ddcutil detect --terse && ddcutil getvcp 10 12 87 14 16 18 1A 60 62 8D --terse"

    property var vcp: ({})
    property var pending: ({})
    property string model: ""
    property string error: ""
    property bool running: false

    Plasmoid.icon: "video-display"
    toolTipMainText: model || i18n("Monitor")
    toolTipSubText: vcp["10"] === undefined ? "" : i18n("Brightness %1% · Contrast %2%", vcp["10"], vcp["12"])

    onExpandedChanged: if (expanded) refresh()
    Component.onCompleted: refresh()

    function run(cmd) {
        running = true
        exec.connectSource(cmd)
    }

    function refresh() {
        if (!running) run(readCmd)
    }

    function set(code, value) {
        vcp = Object.assign({}, vcp, { [code]: value })
        pending = Object.assign({}, pending, { [code]: value })
        writeTimer.restart()
    }

    function flush() {
        if (running) {
            writeTimer.restart()
            return
        }
        const args = Object.keys(pending).map(k => k + " " + pending[k]).join(" ")
        pending = {}
        if (args) run("ddcutil setvcp " + args)
    }

    function parse(out) {
        const v = {}
        for (const line of out.split("\n")) {
            const m = line.match(/^VCP (\w\w) (C|SNC) x?(\w+)/)
            if (m) v[m[1].toUpperCase()] = m[2] === "C" ? parseInt(m[3]) : parseInt(m[3], 16)
            const mon = line.match(/Monitor:\s+\w+:([^:]+)/)
            if (mon) model = mon[1]
        }
        // Keep edits that haven't reached the monitor yet.
        vcp = Object.assign(v, pending)
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            root.running = false
            if (data["exit code"] !== 0) {
                root.error = (data.stderr || data.stdout).trim() || i18n("ddcutil failed")
                return
            }
            root.error = ""
            if (source === root.readCmd) root.parse(data.stdout)
        }
    }

    Timer {
        id: writeTimer
        interval: 150
        onTriggered: root.flush()
    }

    component Card: Rectangle {
        id: card
        default property alias content: col.data
        property string title

        Layout.fillWidth: true
        implicitHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.cornerRadius * 2
        color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.08)

        ColumnLayout {
            id: col
            anchors { fill: parent; margins: Kirigami.Units.largeSpacing }
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Heading {
                text: card.title
                level: 5
                opacity: 0.6
            }
        }
    }

    component Choices: Flow {
        id: choices
        property string code
        property var options: []

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: choices.options
            PC3.Button {
                required property var modelData
                text: modelData[1]
                checkable: true
                checked: root.vcp[choices.code] === modelData[0]
                onClicked: root.set(choices.code, modelData[0])
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: content.implicitHeight + header.implicitHeight + Kirigami.Units.largeSpacing * 2

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                Kirigami.Icon {
                    source: "video-display"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                }
                Kirigami.Heading {
                    text: root.model || i18n("Monitor")
                    level: 3
                    Layout.fillWidth: true
                }
                PC3.BusyIndicator {
                    running: root.running
                    visible: running
                    implicitWidth: Kirigami.Units.iconSizes.small
                    implicitHeight: Kirigami.Units.iconSizes.small
                }
                PC3.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refresh()
                    PC3.ToolTip.text: i18n("Re-read from monitor")
                    PC3.ToolTip.visible: hovered
                }
            }
        }

        PlasmaExtras.PlaceholderMessage {
            anchors.centerIn: parent
            width: parent.width - Kirigami.Units.gridUnit * 2
            visible: root.error !== "" && root.vcp["10"] === undefined
            iconName: "dialog-warning"
            text: i18n("Can't reach the monitor")
            explanation: root.error
        }

        ColumnLayout {
            id: content
            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: Kirigami.Units.largeSpacing
            visible: root.vcp["10"] !== undefined

            Card {
                title: i18n("Picture")
                VcpSlider {
                    label: i18n("Brightness"); icon: "brightness-high"
                    value: root.vcp["10"] ?? 0
                    fromColor: "#1a1a1a"; toColor: "#ffd54f"
                    onMoved: v => root.set("10", v)
                }
                VcpSlider {
                    label: i18n("Contrast"); icon: "contrast"
                    value: root.vcp["12"] ?? 0
                    fromColor: "#7a7a7a"; toColor: "#f5f5f5"
                    onMoved: v => root.set("12", v)
                }
                VcpSlider {
                    label: i18n("Sharpness"); icon: "draw-triangle"
                    value: root.vcp["87"] ?? 0
                    fromColor: "#3d5afe"; toColor: "#00e5ff"
                    onMoved: v => root.set("87", v)
                }
            }

            Card {
                title: i18n("Color")
                Choices {
                    code: "14"
                    options: [[0x03, "4000K"], [0x05, "6500K"], [0x08, "9300K"], [0x0b, i18n("Custom")]]
                }
                VcpSlider {
                    label: i18n("Red"); icon: "color-picker"
                    value: root.vcp["16"] ?? 0
                    fromColor: "#200000"; toColor: "#ff4d4d"
                    onMoved: v => root.set("16", v)
                }
                VcpSlider {
                    label: i18n("Green"); icon: "color-picker"
                    value: root.vcp["18"] ?? 0
                    fromColor: "#002000"; toColor: "#4dff88"
                    onMoved: v => root.set("18", v)
                }
                VcpSlider {
                    label: i18n("Blue"); icon: "color-picker"
                    value: root.vcp["1A"] ?? 0
                    fromColor: "#000020"; toColor: "#4d8dff"
                    onMoved: v => root.set("1A", v)
                }
            }

            Card {
                title: i18n("Input")
                Choices {
                    code: "60"
                    options: [[0x0f, "DisplayPort 1"], [0x10, "DisplayPort 2"], [0x11, "HDMI 1"], [0x12, "HDMI 2"]]
                }
            }

            Card {
                title: i18n("Audio")
                RowLayout {
                    VcpSlider {
                        Layout.fillWidth: true
                        label: i18n("Volume"); icon: "audio-volume-high"
                        value: root.vcp["62"] ?? 0
                        fromColor: "#4a148c"; toColor: "#e040fb"
                        onMoved: v => root.set("62", v)
                    }
                    PC3.ToolButton {
                        // VCP 8D: 1 = muted, 2 = unmuted
                        icon.name: root.vcp["8D"] === 1 ? "audio-volume-muted" : "audio-volume-high"
                        checkable: true
                        checked: root.vcp["8D"] === 1
                        onClicked: root.set("8D", checked ? 1 : 2)
                    }
                }
            }
        }
    }
}
