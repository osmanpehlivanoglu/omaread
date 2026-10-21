import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts
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
    property var searchMatches: []
    property int searchIndex: -1
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
    Shortcut { sequence: "Ctrl+N"; onActivated: reader.newWindow() }
    Shortcut { sequence: "Ctrl+E"; onActivated: reader.edit() }
    Shortcut { sequence: "Ctrl+P"; enabled: reader.hasFile; onActivated: reader.printDocument() }
    Shortcut { sequence: "Ctrl+R"; onActivated: reader.reload() }
    Shortcut { sequence: "Ctrl+F"; onActivated: openSearch() }
    Shortcut { sequence: "Ctrl+G"; enabled: searchBar.visible; onActivated: moveSearch(1) }
    Shortcut { sequence: "Ctrl+Shift+G"; enabled: searchBar.visible; onActivated: moveSearch(-1) }
    Shortcut { sequences: ["Ctrl+?", "F1"]; onActivated: shortcutsDialog.open() }
    Shortcut { sequence: "Escape"; enabled: searchBar.visible; onActivated: closeSearch() }
    Shortcut { sequences: ["Meta+F", "F11"]; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    Shortcut { sequence: "Ctrl++"; onActivated: win.zoom = Math.min(3, win.zoom * 1.1) }
    Shortcut { sequence: "Ctrl+="; onActivated: win.zoom = Math.min(3, win.zoom * 1.1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom = Math.max(0.5, win.zoom / 1.1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom = 1 }

    function openSearch() {
        searchBar.visible = true
        searchField.forceActiveFocus()
        searchField.selectAll()
    }

    function closeSearch() {
        searchBar.visible = false
        reader.highlightSearch("", -1)
        document.deselect()
        document.forceActiveFocus()
    }

    function updateSearch() {
        searchMatches = reader.findAllText(searchField.text)
        searchIndex = searchMatches.length > 0 ? 0 : -1
        showSearchMatch()
    }

    function showSearchMatch() {
        const match = searchIndex >= 0 ? searchMatches[searchIndex] : null
        reader.highlightSearch(searchBar.visible ? searchField.text : "", match ? match.start : -1)
        if (!match) {
            document.deselect()
            return
        }
        document.select(match.start, match.end)
        const location = document.positionToRectangle(match.start)
        page.contentY = Math.max(0, Math.min(page.contentHeight - page.height,
                         document.y + location.y - page.height / 3))
    }

    function moveSearch(direction) {
        if (searchMatches.length === 0) return
        searchIndex = (searchIndex + direction + searchMatches.length) % searchMatches.length
        showSearchMatch()
    }

    Connections {
        target: reader
        function onChanged() {
            if (searchBar.visible) Qt.callLater(updateSearch)
        }
    }

    Dialog {
        id: shortcutsDialog
        objectName: "shortcutsDialog"
        modal: true
        title: "Keyboard shortcuts"
        standardButtons: Dialog.Close
        anchors.centerIn: parent
        contentItem: Label {
            text: " Ctrl+O Open\n Ctrl+N New Window\n Ctrl+E Edit in Omawrite\n Ctrl+P Print\n Ctrl+F Find\n Enter / Shift+Enter Next / Previous Match\n Ctrl+G Next Match\n Ctrl+Shift+G Previous Match\n Escape Close Search\n Ctrl+R Reload\n Ctrl+= / Ctrl+- Zoom\n Ctrl+0 Reset Zoom\n F11 / Super+F Fullscreen\n Ctrl+? / F1 Shortcuts"
            lineHeight: 1.5
        }
    }

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
            objectName: "document"
            x: Math.round((page.width - width) / 2)
            y: Math.max(42, Math.round(win.height * 0.05))
            width: Math.min(Math.round(fontMetrics.averageCharacterWidth * 65),
                            Math.max(360, win.width - Math.round(fontMetrics.averageCharacterWidth * 20)))
            height: Math.max(page.height - y - 96, implicitHeight + 20)
            text: reader.content
            textFormat: TextEdit.MarkdownText
            baseUrl: reader.fileUrl
            readOnly: true
            persistentSelection: true
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

    Rectangle {
        id: searchBar
        objectName: "searchBar"
        visible: false
        z: 10
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 12
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        height: 56
        radius: 9
        color: reader.darkMode ? "#22221f" : "#fffef2"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 8
            spacing: 8

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                TextInput {
                    id: searchField
                    objectName: "searchField"
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    selectByMouse: true
                    clip: true
                    color: reader.darkMode ? "#aab9de" : "#62635f"
                    selectionColor: reader.selection
                    selectedTextColor: reader.foreground
                    font.family: "iA Writer Mono S"
                    font.pixelSize: 17
                    onTextChanged: win.updateSearch()
                    Keys.onPressed: function(event) {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            win.moveSearch((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
                            event.accepted = true
                        }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Find"
                    visible: searchField.text.length === 0
                    color: win.muted
                    font.family: "iA Writer Mono S"
                    font.pixelSize: 17
                }
            }
            Text {
                Layout.preferredWidth: 58
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: win.searchMatches.length ? (win.searchIndex + 1) + "/" + win.searchMatches.length : "0/0"
                color: reader.darkMode ? "#aab9de" : "#62635f"
                font.family: "iA Writer Mono S"
                font.pixelSize: 16
            }
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 34
                color: reader.darkMode ? "#6f6f62" : "#d5d56e"
            }
            Repeater {
                model: ["up", "down", "close"]
                delegate: Item {
                    required property string modelData
                    Layout.preferredWidth: 40
                    Layout.fillHeight: true
                    Canvas {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        property color iconColor: reader.darkMode ? "#aab9de" : "#62635f"
                        onIconColorChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = iconColor
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            ctx.beginPath()
                            if (modelData === "close") {
                                ctx.moveTo(4, 4); ctx.lineTo(16, 16)
                                ctx.moveTo(16, 4); ctx.lineTo(4, 16)
                            } else if (modelData === "up") {
                                ctx.moveTo(4, 12); ctx.lineTo(10, 6); ctx.lineTo(16, 12)
                            } else {
                                ctx.moveTo(4, 8); ctx.lineTo(10, 14); ctx.lineTo(16, 8)
                            }
                            ctx.stroke()
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData === "close") win.closeSearch()
                            else win.moveSearch(modelData === "up" ? -1 : 1)
                        }
                    }
                }
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
