import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: row

    property string label
    property string icon
    property int value: 0
    property color fromColor: "#202020"
    property color toColor: Kirigami.Theme.highlightColor

    signal moved(int value)

    spacing: Kirigami.Units.smallSpacing

    RowLayout {
        Kirigami.Icon {
            source: row.icon
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
        QQC2.Label {
            text: row.label
            Layout.fillWidth: true
        }
        QQC2.Label {
            text: Math.round(slider.value)
            font.bold: true
            opacity: 0.8
        }
    }

    QQC2.Slider {
        id: slider
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 1.2
        from: 0
        to: 100
        stepSize: 1
        onMoved: row.moved(Math.round(value))

        // Follow the monitor's value, except while the user is dragging.
        Binding on value {
            value: row.value
            when: !slider.pressed
            restoreMode: Binding.RestoreNone
        }

        background: Rectangle {
            x: slider.leftPadding
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: slider.availableWidth
            height: Kirigami.Units.smallSpacing * 2
            radius: height / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: row.fromColor }
                GradientStop { position: 1; color: row.toColor }
            }

            // Dim the unfilled part of the track.
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: parent.width * (1 - slider.visualPosition)
                radius: parent.radius
                color: Kirigami.Theme.backgroundColor
                opacity: 0.65
            }
        }

        handle: Rectangle {
            x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
            y: slider.topPadding + slider.availableHeight / 2 - height / 2
            width: Kirigami.Units.gridUnit
            height: width
            radius: width / 2
            color: "white"
            border.color: Qt.darker(row.toColor, 1.3)
            border.width: 2
            scale: slider.pressed ? 1.2 : slider.hovered ? 1.1 : 1

            Behavior on scale { NumberAnimation { duration: Kirigami.Units.shortDuration } }
        }
    }
}
