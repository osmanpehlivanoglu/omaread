import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs as Dialogs
import QtQuick.Window

ApplicationWindow {
    id: win
    width: 1280
    height: 820
    minimumWidth: 720
    minimumHeight: 520
    visible: true
    title: reader.fileName + " - Omaread"
    color: reader.background
    Material.theme: reader.darkMode ? Material.Dark : Material.Light
    Material.accent: reader.accent
    property real zoom: 1
    readonly property int bodySize: Math.round(20 * zoom)
    readonly property color muted: reader.darkMode ? "#909191" : "#aeb1b5"

    FontMetrics {
        id: fontMetrics
        font.family: "iA Writer Mono S"
        font.pixelSize: win.bodySize
    }

    Dialogs.FileDialog {
        id: fileDialog
        title: "Open Markdown file"
        fileMode: Dialogs.FileDialog.OpenFile
        nameFilters: ["Markdown files (*.md *.markdown)", "Text files (*.txt)", "All files (*)"]
        onAccepted: reader.open(selectedFile)
    }

    Shortcut { sequence: "Ctrl+O"; onActivated: fileDialog.open() }
    Shortcut { sequence: "Ctrl+E"; onActivated: reader.edit() }
    Shortcut { sequence: "Ctrl+R"; onActivated: reader.reload() }
    Shortcut { sequences: ["Meta+F", "F11"]; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    Shortcut { sequence: "Ctrl++"; onActivated: win.zoom = Math.min(3, win.zoom * 1.1) }
    Shortcut { sequence: "Ctrl+="; onActivated: win.zoom = Math.min(3, win.zoom * 1.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom = Math.max(0.5, win.zoom / 1.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom = 1 }

    DropArea {
        anchors.fill: parent
        onDropped: function(drop) {
            if (drop.hasUrls && drop.urls.length > 0) reader.open(drop.urls[0])
        }
    }

    Flickable {
        id: page
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        clip: true
        contentWidth: width
        contentHeight: Math.max(height, document.y + document.implicitHeight + 220)
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            bottomPadding: 32
            bottomInset: 32
        }

        TextEdit {
            id: document
            x: Math.round((page.width - width) / 2)
            y: Math.max(42, Math.round(win.height * 0.05))
            width: Math.min(Math.round(fontMetrics.averageCharacterWidth * 65),
                            Math.max(360, win.width - Math.round(fontMetrics.averageCharacterWidth * 20)))
            height: Math.max(page.height - y - 96, implicitHeight + 20)
            text: reader.content
            textFormat: TextEdit.MarkdownText
            baseUrl: reader.fileUrl
            readOnly: true
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            color: reader.foreground
            selectionColor: reader.selection
            selectedTextColor: reader.foreground
            font.family: "iA Writer Mono S"
            font.pixelSize: win.bodySize
            renderType: Screen.devicePixelRatio % 1 === 0 ? TextEdit.NativeRendering : TextEdit.QtRendering
            onLinkActivated: function(link) { Qt.openUrlExternally(link) }
            Component.onCompleted: {
                reader.attachDocument(textDocument)
                Qt.callLater(function() { reader.styleDocument(win.bodySize) })
            }
        }
        Repeater {
            model: reader.markers
            delegate: Text {
                required property var modelData
                z: 100
                property rect textPosition: {
                    document.width
                    document.text
                    return document.positionToRectangle(modelData.position)
                }
                text: modelData.label
                x: document.x + textPosition.x - width - 4
                y: document.y + textPosition.y
                width: Math.max(3, text.length + 1) * fontMetrics.averageCharacterWidth
                height: textPosition.height
                horizontalAlignment: Text.AlignRight
                color: reader.darkMode ? "#4f525a" : "#aeb1b5"
                font.family: "iA Writer Mono S"
                font.pixelSize: win.bodySize
                Rectangle { anchors.fill: parent; color: reader.background; z: -1 }
            }
        }
    }

    onBodySizeChanged: Qt.callLater(function() { reader.styleDocument(win.bodySize) })

    Text {
        anchors.centerIn: parent
        visible: reader.content.length === 0 && reader.status.length === 0
        text: "Open a Markdown file  ·  Ctrl+O"
        color: win.muted
        font.family: "iA Writer Mono S"
        font.pixelSize: 14
    }

    Row {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 12
        anchors.bottomMargin: 10
        spacing: 12
        opacity: 0.55
        Item {
            width: 16
            height: 16
            ToolTip.visible: openArea.containsMouse
            ToolTip.text: "Open"
            Canvas {
                anchors.fill: parent
                onPaint: {
                    const context = getContext("2d")
                    context.clearRect(0, 0, width, height)
                    context.strokeStyle = win.muted
                    context.lineWidth = 1.4
                    context.lineCap = "round"
                    context.lineJoin = "round"
                    context.beginPath()
                    context.moveTo(2.5, 13)
                    context.lineTo(2.5, 3.5)
                    context.lineTo(6.5, 3.5)
                    context.lineTo(8.5, 5.5)
                    context.lineTo(13.5, 5.5)
                    context.lineTo(13.5, 13)
                    context.closePath()
                    context.stroke()
                }
            }
            MouseArea {
                id: openArea
                anchors.centerIn: parent
                width: 28
                height: 28
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: fileDialog.open()
            }
        }
        Text {
            text: "EDIT"
            visible: reader.hasFile
            color: win.muted
            font.family: "iA Writer Mono S"
            font.pixelSize: 11
            height: 16
            verticalAlignment: Text.AlignVCenter
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: reader.edit()
            }
        }
        Text {
            text: reader.status
            visible: text.length > 0
            color: win.muted
            font.family: "iA Writer Mono S"
            font.pixelSize: 11
            width: Math.min(360, win.width / 3)
            height: 16
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 12
        anchors.bottomMargin: 10
        text: reader.wordCount + (reader.wordCount === 1 ? " Word" : " Words")
        color: win.muted
        opacity: 0.75
        font.family: "iA Writer Mono S"
        font.pixelSize: 11
    }
}
