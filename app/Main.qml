import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtCore

ApplicationWindow {
    id: win

    readonly property color cBg: "#0b0b0d"
    readonly property color cSide: "#121215"
    readonly property color cPanel: "#141417"
    readonly property color cHead: "#1e1e22"
    readonly property color cLine: "#2c2c31"
    readonly property color cText: "#e8e8ea"
    readonly property color cDim: "#77777d"
    readonly property color cRed: "#e3173e"
    readonly property color cRedDark: "#6e0b1f"

    readonly property var v: ddc.values
    property int page: 0

    // Picture modes are app-side presets: LG's own modes sit behind undocumented codes.
    readonly property var modes: [
        { name: "FPS", icon: "crosshairs", values: { "14": 0x05, "10": 80, "12": 75, "87": 70 } },
        { name: "RTS/RPG", icon: "games-config-tiles", values: { "14": 0x05, "10": 70, "12": 70, "87": 55 } },
        { name: "Racing", icon: "flag", values: { "14": 0x08, "10": 85, "12": 70, "87": 60 } },
        { name: "Cinema", icon: "video-television", values: { "14": 0x03, "10": 50, "12": 80, "87": 40 } },
        { name: "Reader", icon: "accessories-text-editor", values: { "14": 0x03, "10": 35, "12": 60, "87": 50 } },
        { name: "Night", icon: "weather-clear-night", values: { "14": 0x03, "10": 10, "12": 50, "87": 50 } },
        { name: "User", icon: "user", values: { "14": 0x0b, "10": 50, "12": 50, "87": 50, "16": 50, "18": 50, "1A": 50 } }
    ]
    readonly property var temps: [[0x03, "4000K"], [0x05, "6500K"], [0x08, "9300K"], [0x0b, "Custom (R/G/B)"]]
    readonly property var inputs: [[0x0f, "DisplayPort 1", "video-display"], [0x10, "DisplayPort 2", "video-display"],
        [0x11, "HDMI 1", "video-television"], [0x12, "HDMI 2", "video-television"]]

    function saved() {
        try { return JSON.parse(settings.presets) } catch (e) { return {} }
    }
    function modeValues(i) {
        return saved()[i] ?? modes[i].values
    }
    function selectMode(i) {
        settings.mode = i
        ddc.apply(modeValues(i))
    }
    function saveMode() {
        const s = saved()
        s[settings.mode] = { "14": v["14"], "10": v["10"], "12": v["12"], "87": v["87"], "16": v["16"], "18": v["18"], "1A": v["1A"] }
        settings.presets = JSON.stringify(s)
        toast.show(modes[settings.mode].name + " mode saved")
    }
    function resetMode() {
        const s = saved()
        delete s[settings.mode]
        settings.presets = JSON.stringify(s)
        ddc.apply(modes[settings.mode].values)
        toast.show(modes[settings.mode].name + " mode reset")
    }

    width: 1100
    height: 700
    minimumWidth: 1000
    minimumHeight: 660
    visible: true
    title: "MonCenter"
    color: cBg
    font.pixelSize: 13

    Settings {
        id: settings
        property int mode: 6
        property string presets: "{}"
    }

    // ---------- building blocks ----------

    component Corners: Item {
        id: corners
        property color tint: "#9a9aa0"
        property int len: 8
        Rectangle { x: 0; y: corners.height - 1; width: corners.len; height: 1; color: corners.tint }
        Rectangle { x: 0; y: corners.height - corners.len; width: 1; height: corners.len; color: corners.tint }
        Rectangle { x: corners.width - corners.len; y: corners.height - 1; width: corners.len; height: 1; color: corners.tint }
        Rectangle { x: corners.width - 1; y: corners.height - corners.len; width: 1; height: corners.len; color: corners.tint }
    }

    component Panel: Rectangle {
        id: panel
        property string title
        default property alias content: body.data
        color: win.cPanel
        border.color: "#222226"
        implicitHeight: head.height + body.implicitHeight + 48

        Rectangle {
            id: head
            width: parent.width
            height: 44
            color: win.cHead
            Label {
                x: 22
                anchors.verticalCenter: parent.verticalCenter
                text: panel.title
                color: win.cText
                font { pixelSize: 15; bold: true }
            }
        }
        ColumnLayout {
            id: body
            anchors { top: head.bottom; left: parent.left; right: parent.right; margins: 24 }
            spacing: 22
        }
        Corners { anchors.fill: parent }
    }

    component RogSlider: RowLayout {
        id: rs
        property string label
        property string code
        property bool active: true
        spacing: 18
        opacity: active ? 1 : 0.4

        Label { text: rs.label; color: win.cText; Layout.preferredWidth: 100 }
        Slider {
            id: s
            Layout.fillWidth: true
            from: 0; to: 100; stepSize: 1
            enabled: rs.active
            onMoved: ddc.set(rs.code, Math.round(value))
            // Follow the monitor, except while dragging.
            Binding on value {
                value: win.v[rs.code] ?? 0
                when: !s.pressed
                restoreMode: Binding.RestoreNone
            }
            background: Item {
                x: s.leftPadding
                y: s.topPadding + s.availableHeight / 2 - height / 2
                width: s.availableWidth
                height: 3
                Rectangle { anchors.fill: parent; color: "#4a4a50" }
                Item {
                    width: s.visualPosition * parent.width
                    height: parent.height
                    clip: true
                    Rectangle {
                        width: s.availableWidth
                        height: parent.height
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: "#17c9c9" }
                            GradientStop { position: 0.55; color: "#6d4dff" }
                            GradientStop { position: 1; color: "#e23bd2" }
                        }
                    }
                }
            }
            handle: Rectangle {
                x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
                y: s.topPadding + s.availableHeight / 2 - height / 2
                width: 9; height: 15; radius: 1
                color: s.pressed ? "white" : s.hovered ? "#e6e6ea" : "#b9b9be"
                border.color: "#1a1a1d"
            }
        }
        Label {
            text: Math.round(s.value)
            color: win.cText
            Layout.preferredWidth: 30
            horizontalAlignment: Text.AlignRight
        }
    }

    component RogButton: Rectangle {
        id: btn
        property string text
        property bool primary: false
        signal clicked
        implicitWidth: primary ? 110 : 84
        implicitHeight: primary ? 30 : 24
        color: ma.pressed ? win.cRedDark : ma.containsMouse ? "#2a1015" : "#161619"
        border.color: ma.containsMouse ? win.cRed : "#c4c4c9"
        Behavior on color { ColorAnimation { duration: 120 } }
        Label { anchors.centerIn: parent; text: btn.text; color: win.cText; font.pixelSize: 12 }
        MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: btn.clicked() }
    }

    component Tile: Item {
        id: tile
        property string text
        property string icon
        property bool selected
        signal clicked
        implicitWidth: 96
        implicitHeight: 86

        Rectangle {
            anchors.fill: parent
            color: ma2.containsMouse ? "#1d1d21" : "#141417"
            border.color: tile.selected ? win.cRed : "#3a3a40"
            Behavior on border.color { ColorAnimation { duration: 150 } }
        }
        Rectangle {
            anchors { fill: parent; margins: 1 }
            opacity: tile.selected ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            gradient: Gradient {
                GradientStop { position: 0; color: "#4d0a19" }
                GradientStop { position: 1; color: "#1a0509" }
            }
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 10
            ThemeIcon {
                Layout.alignment: Qt.AlignHCenter
                icon.name: tile.icon
                icon.color: tile.selected ? win.cRed : "#d8d8dc"
                size: 30
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                text: tile.text.toUpperCase()
                color: win.cText
                font.pixelSize: 11
            }
        }
        Corners { anchors.fill: parent; len: 6; tint: tile.selected ? win.cRed : "#8a8a90" }
        MouseArea { id: ma2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: tile.clicked() }
    }

    component RogCombo: ComboBox {
        id: cb
        property string code
        property var options: []
        model: options.map(o => o[1])
        onActivated: i => ddc.set(code, options[i][0])
        Binding on currentIndex {
            value: cb.options.findIndex(o => o[0] === win.v[cb.code])
            restoreMode: Binding.RestoreNone
        }
        implicitHeight: 28
        background: Rectangle { color: "#0f0f11"; border.color: cb.hovered ? win.cRed : "#d0d0d4" }
        contentItem: Label {
            leftPadding: 10
            text: cb.currentIndex < 0 ? "—" : cb.displayText
            color: win.cText
            verticalAlignment: Text.AlignVCenter
        }
        indicator: Label {
            x: cb.width - width - 10
            anchors.verticalCenter: parent.verticalCenter
            text: "▼"; font.pixelSize: 9; color: win.cText
        }
        popup.background: Rectangle { color: "#18181b"; border.color: "#3a3a40" }
        delegate: ItemDelegate {
            required property string modelData
            required property int index
            width: cb.width
            highlighted: cb.highlightedIndex === index
            contentItem: Label { text: modelData; color: win.cText }
            background: Rectangle { color: highlighted ? win.cRedDark : "transparent" }
        }
    }

    component RogSwitch: Rectangle {
        id: sw
        property bool on
        signal toggled
        implicitWidth: 56; implicitHeight: 20
        color: on ? win.cRedDark : "#202024"
        border.color: on ? win.cRed : "#55555b"
        Behavior on color { ColorAnimation { duration: 120 } }
        Rectangle {
            x: sw.on ? sw.width - width - 3 : 3
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 14
            color: sw.on ? "white" : "#8a8a90"
            Behavior on x { NumberAnimation { duration: 120 } }
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            x: sw.on ? 8 : sw.width - width - 8
            text: sw.on ? "ON" : "OFF"
            color: win.cText; font.pixelSize: 10
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.toggled() }
    }

    component NavItem: Item {
        id: nav
        property string text
        property string icon
        property int index
        readonly property bool current: win.page === index
        Layout.fillWidth: true
        implicitHeight: 40
        Rectangle {
            anchors.fill: parent
            visible: nav.current
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#b0122f" }
                GradientStop { position: 1; color: "#6a0b1d" }
            }
        }
        Rectangle { anchors.fill: parent; color: "white"; opacity: navMa.containsMouse && !nav.current ? 0.05 : 0 }
        RowLayout {
            anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 28 }
            spacing: 16
            ThemeIcon { icon.name: nav.icon; icon.color: win.cText }
            Label { text: nav.text; color: win.cText }
        }
        MouseArea { id: navMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.page = nav.index }
    }

    // A theme icon tinted to one color; Button's icon is the stock Qt way to get that.
    component ThemeIcon: Button {
        property int size: 18
        icon.width: size
        icon.height: size
        display: AbstractButton.IconOnly
        padding: 0
        background: null
        focusPolicy: Qt.NoFocus
    }

    component Heading: Label {
        color: win.cText
        font { pixelSize: 15; bold: true }
    }

    // ---------- layout ----------

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // Sidebar
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 230
            color: win.cSide

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 30
                spacing: 0

                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: "MONCENTER"
                    color: win.cText
                    font { pixelSize: 25; bold: true; italic: true; letterSpacing: 2 }
                }
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Rectangle { width: 18; height: 3; color: win.cRed; rotation: -20 }
                    Label { text: "Monitor Control"; color: win.cText; font { pixelSize: 12; bold: true } }
                    Rectangle { width: 18; height: 3; color: win.cRed; rotation: -20 }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.margins: 16
                    Layout.topMargin: 26
                    Layout.bottomMargin: 26
                    height: 30
                    color: "#1d1d21"
                    border.color: win.cLine
                    Label {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        text: "1. " + (ddc.model || "No monitor")
                        color: win.cText; font.pixelSize: 12
                    }
                    Rectangle {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 8; height: 8; radius: 4
                        color: ddc.error ? win.cRed : "#2ecc71"
                    }
                }

                NavItem { text: "Picture"; icon: "color-management"; index: 0 }
                NavItem { text: "Input & Audio"; icon: "audio-card"; index: 1 }
                NavItem { text: "Device Info"; icon: "help-about"; index: 2 }

                Item { Layout.fillHeight: true }

                Rectangle { Layout.fillWidth: true; Layout.margins: 16; height: 1; color: win.cLine }
                NavItem {
                    Layout.bottomMargin: 20
                    text: ddc.busy ? "Talking to monitor…" : "Re-read monitor"
                    icon: "view-refresh"
                    index: -1
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: ddc.refresh() }
                }
            }
        }

        // Content
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Red light streaks, bottom right.
            Repeater {
                model: [[0.62, 5, 0.55], [0.70, 2, 0.35], [0.80, 8, 0.25], [0.88, 3, 0.45], [0.95, 1, 0.6]]
                Rectangle {
                    required property var modelData
                    x: parent.width * modelData[0]
                    y: parent.height * 0.35
                    width: modelData[1]
                    height: parent.height
                    rotation: 55
                    opacity: modelData[2]
                    gradient: Gradient {
                        GradientStop { position: 0; color: "transparent" }
                        GradientStop { position: 0.5; color: win.cRed }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }

            StackLayout {
                anchors { fill: parent; margins: 32; topMargin: 28 }
                currentIndex: win.page

                // ---- Picture ----
                ColumnLayout {
                    spacing: 14
                    Label { text: "Picture Modes"; color: win.cText; font { pixelSize: 24; bold: true } }
                    Heading { text: "Select Mode"; Layout.topMargin: 10 }
                    RowLayout {
                        spacing: 10
                        Repeater {
                            model: win.modes
                            Tile {
                                required property var modelData
                                required property int index
                                text: modelData.name
                                icon: modelData.icon
                                selected: settings.mode === index
                                onClicked: win.selectMode(index)
                            }
                        }
                    }
                    RowLayout {
                        Layout.topMargin: 10
                        Heading { text: win.modes[settings.mode].name + " mode settings"; Layout.fillWidth: true }
                        RogButton { text: "Reset"; onClicked: win.resetMode() }
                        RogButton { text: "Save"; Layout.leftMargin: 10; onClicked: win.saveMode() }
                    }
                    RowLayout {
                        spacing: 12
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Panel {
                            title: "Image"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            RogSlider { label: "Brightness"; code: "10" }
                            RogSlider { label: "Contrast"; code: "12" }
                            RogSlider { label: "Sharpness"; code: "87" }
                        }
                        Panel {
                            title: "Color"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            RowLayout {
                                spacing: 18
                                Label { text: "Color Temp."; color: win.cText; Layout.preferredWidth: 100 }
                                RogCombo { code: "14"; options: win.temps; Layout.fillWidth: true }
                            }
                            RogSlider { label: "R"; code: "16"; active: win.v["14"] === 0x0b }
                            RogSlider { label: "G"; code: "18"; active: win.v["14"] === 0x0b }
                            RogSlider { label: "B"; code: "1A"; active: win.v["14"] === 0x0b }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ---- Input & Audio ----
                ColumnLayout {
                    spacing: 14
                    Label { text: "Input & Audio"; color: win.cText; font { pixelSize: 24; bold: true } }
                    Heading { text: "Input Source"; Layout.topMargin: 10 }
                    RowLayout {
                        spacing: 10
                        Repeater {
                            model: win.inputs
                            Tile {
                                required property var modelData
                                implicitWidth: 120
                                text: modelData[1]
                                icon: modelData[2]
                                selected: win.v["60"] === modelData[0]
                                onClicked: ddc.set("60", modelData[0])
                            }
                        }
                    }
                    Label {
                        text: "Switching to an input with nothing connected blanks this screen. Use the monitor's joystick to come back."
                        color: win.cDim; font.pixelSize: 12
                    }
                    Panel {
                        title: "Audio"
                        Layout.topMargin: 14
                        Layout.preferredWidth: 520
                        RogSlider { label: "Volume"; code: "62" }
                        RowLayout {
                            spacing: 18
                            Label { text: "Mute"; color: win.cText; Layout.preferredWidth: 100 }
                            // VCP 8D: 1 = muted, 2 = unmuted
                            RogSwitch { on: win.v["8D"] === 1; onToggled: ddc.set("8D", on ? 2 : 1) }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ---- Device Info ----
                ColumnLayout {
                    spacing: 14
                    Label { text: "Device Info"; color: win.cText; font { pixelSize: 24; bold: true } }
                    Panel {
                        title: ddc.model || "Monitor"
                        Layout.topMargin: 10
                        Layout.preferredWidth: 520
                        GridLayout {
                            columns: 2
                            columnSpacing: 40
                            rowSpacing: 14
                            Repeater {
                                model: [
                                    "Serial", ddc.serial,
                                    "Firmware", win.v["C9"] ?? "—",
                                    "Refresh rate", win.v["AE"] ? (win.v["AE"] / 100).toFixed(2) + " Hz" : "—",
                                    "Usage time", win.v["C0"] !== undefined ? win.v["C0"] + " h" : "—",
                                    "Control", "DDC/CI via ddcutil"
                                ]
                                Label {
                                    required property string modelData
                                    required property int index
                                    text: modelData
                                    color: index % 2 ? win.cText : win.cDim
                                }
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // Error bar
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: ddc.error ? 34 : 0
                visible: height > 0
                color: win.cRedDark
                Behavior on height { NumberAnimation { duration: 150 } }
                Label {
                    anchors { fill: parent; leftMargin: 32 }
                    verticalAlignment: Text.AlignVCenter
                    text: ddc.error
                    elide: Text.ElideRight
                    color: win.cText
                }
            }

            // Toast
            Rectangle {
                id: toast
                function show(msg) { toastLabel.text = msg; opacity = 1; toastTimer.restart() }
                anchors { right: parent.right; bottom: parent.bottom; margins: 32 }
                width: toastLabel.implicitWidth + 32
                height: 34
                opacity: 0
                color: "#1d1d21"
                border.color: win.cRed
                Behavior on opacity { NumberAnimation { duration: 200 } }
                Label { id: toastLabel; anchors.centerIn: parent; color: win.cText }
                Timer { id: toastTimer; interval: 1800; onTriggered: toast.opacity = 0 }
            }
        }
    }
}
