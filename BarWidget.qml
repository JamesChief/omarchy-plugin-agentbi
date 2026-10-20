import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Your own site's agent-readiness score, in the bar: AgentBI icon, a dot
// coloured by band, and the score. Hovering opens the panel — that panel is
// the widget, the number in the bar is only its headline.
//
// Which site it measures comes from ~/.config/agentbi/widget.conf (url, name,
// lang). The only request it makes is one GET to agentbi.tech for that URL.
BarWidget {
  id: root
  moduleName: "agentbi"

  property string siteUrl: ""
  property string siteName: ""
  property string lang: "en"

  // The hover panel is a passive overlay on purpose — it cannot take keyboard
  // focus, so editing happens in the same card switched to click mode, which
  // does grab it.
  property bool editing: false
  property string formUrl: ""
  property string formName: ""
  property string formLang: "en"

  // empty | loading | ok | error
  property string status: "empty"
  property int score: -1
  property string checkedUrl: ""
  property string errText: ""
  property string checkedAt: ""
  property bool fromCache: false
  property var detail: ({})

  readonly property string confPath: Quickshell.env("HOME") + "/.config/agentbi/widget.conf"

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property color fgDim: Qt.darker(root.fg, 1.35)
  readonly property string mono: root.bar ? root.bar.fontFamily : Style.font.family

  // Same bands the site colours the score by (web/index.html scoreClass).
  readonly property color band: root.score >= 80 ? "#1a7f4b"
                              : root.score >= 50 ? "#b8860b" : "#b03030"
  readonly property color dotColor: root.status === "ok" ? root.band : "#8a8a8a"

  readonly property var rows: [
    { label: "Agents",       value: root.detail.fetch || "" },
    { label: "Product data", value: root.detail.structured || "" },
    { label: "UCP",          value: root.detail.ucp || "" },
    { label: "llms.txt",     value: root.detail.llms || "" },
    { label: "robots.txt",   value: root.detail.robots || "" }
  ]

  // ---- config
  FileView {
    path: root.confPath
    watchChanges: true
    printErrors: false
    onLoaded: root.applyConf(text())
    onFileChanged: reload()
    onLoadFailed: root.applyConf("")
  }

  function applyConf(raw) {
    var lines = String(raw || "").split("\n")
    var url = "", name = "", lang = "en"
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (line === "" || line.charAt(0) === "#") continue
      var eq = line.indexOf("=")
      if (eq < 0) continue
      var key = line.slice(0, eq).trim().toLowerCase()
      var val = line.slice(eq + 1).trim()
      if (key === "url") url = val
      else if (key === "name") name = val
      else if (key === "lang") lang = val === "zh" ? "zh" : "en"
    }
    root.siteUrl = url
    root.siteName = name || url
    root.lang = lang
    root.refresh()
  }

  // ---- scan
  function refresh() {
    if (!root.siteUrl) {
      root.status = "empty"
      return
    }
    root.status = "loading"
    // The config load and the periodic timer both fire at startup; debounced so
    // the second call cannot kill the first request mid-flight (a killed curl
    // answers with an empty body, which reads as a failed scan).
    startTimer.restart()
  }

  function startEditing() {
    root.formUrl = root.siteUrl
    root.formName = root.siteName
    root.formLang = root.lang
    root.editing = true
    Qt.callLater(function () { urlField.forceActiveFocus() })
  }

  function saveEditing() {
    var url = String(root.formUrl || "").trim().replace(/\s+/g, " ")
    var name = String(root.formName || "").trim().replace(/\s+/g, " ")
    root.formUrl = url
    root.formName = name
    root.editing = false
    writeProc.running = true
  }

  // Values travel as argv, never interpolated into the script: a URL is
  // arbitrary text and this writes a file.
  Process {
    id: writeProc
    command: ["sh", "-c",
             "mkdir -p \"$(dirname \"$4\")\" && printf 'url = %s\\nname = %s\\nlang = %s\\n' \"$1\" \"$2\" \"$3\" > \"$4\"",
             "sh", root.formUrl, root.formName, root.formLang, root.confPath]
  }

  Timer {
    id: startTimer
    interval: 250
    onTriggered: if (!checkProc.running) checkProc.running = true
  }

  // No -f: a rate-limited or failed scan still answers with JSON that says why,
  // and that reason belongs in the panel.
  Process {
    id: checkProc
    command: ["curl", "-sS", "--max-time", "25",
             "https://agentbi.tech/api/check?url="
             + encodeURIComponent(root.siteUrl) + "&lang=" + root.lang]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ingest(String(text || ""))
    }
  }

  function ingest(raw) {
    var body = String(raw || "").trim()
    root.checkedAt = Qt.formatTime(new Date(), "HH:mm")
    if (!body) {
      root.status = "error"
      root.errText = "no answer from agentbi.tech"
      return
    }
    var j = null
    try { j = JSON.parse(body) } catch (e) {
      root.status = "error"
      root.errText = "unreadable answer"
      return
    }
    if (j && j.error) {
      root.status = "error"
      root.errText = String(j.error)
      return
    }
    var r = j ? j.result : null
    if (!r || r.score === undefined) {
      root.status = "error"
      root.errText = r && r.error ? String(r.error) : "no result"
      return
    }
    root.fromCache = j.cached === true
    root.score = r.score
    root.detail = r.detail || ({})
    root.checkedUrl = r.checked_url || r.url || root.siteUrl
    root.status = "ok"
  }

  // A check of your own site can change whenever you deploy; half an hour
  // matches the server's cache window.
  Timer {
    interval: 1800000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "agentbi"
    function refresh(): void { root.broadcast("refresh") }
  }

  // ---- bar mark
  implicitWidth: content.implicitWidth + Style.space(14)
  implicitHeight: root.barSize

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    Image {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(15)
      height: Style.space(15)
      source: Qt.resolvedUrl("icon.svg")
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(7)
      height: Style.space(7)
      radius: width / 2
      color: root.dotColor
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: !root.vertical
      textFormat: Text.PlainText
      text: root.status === "ok" ? String(root.score) : "—"
      color: root.fg
      font.family: root.mono
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    cursorShape: Qt.PointingHandCursor
    onEntered: root.hoverBtn = true
    onExited: root.hoverBtn = false
    onClicked: function (mouse) {
      if (mouse.button === Qt.MiddleButton) root.refresh()
      else openProc.running = true
    }
  }

  Process {
    id: openProc
    command: ["xdg-open", "https://agentbi.tech/"]
  }

  // ---- hover panel
  property bool hoverBtn: false
  property bool panelOpen: false
  readonly property bool hoverOpen: root.hoverBtn || popup.containsMouse

  onHoverOpenChanged: {
    if (root.hoverOpen) {
      closeTimer.stop()
      openTimer.restart()
    } else {
      openTimer.stop()
      closeTimer.restart()
    }
  }

  // Short enough not to fire while the cursor is only passing over the bar,
  // long enough to cross the gap between the mark and the panel.
  Timer {
    id: openTimer
    interval: 180
    onTriggered: if (root.hoverOpen) root.panelOpen = true
  }

  Timer {
    id: closeTimer
    interval: 240
    onTriggered: if (!root.hoverOpen) root.panelOpen = false
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    // Hover shows the result; editing switches the same card to click mode so
    // it takes keyboard focus and stays put while you type.
    triggerMode: root.editing ? "click" : "hover"
    open: root.editing || root.panelOpen
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(col.implicitHeight)

    Column {
      id: col
      anchors.fill: parent
      spacing: Style.space(5)

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.siteName || "AgentBI"
        color: root.fg
        font.family: root.mono
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: root.siteUrl || ("no site configured — " + root.confPath)
        color: root.fgDim
        font.family: root.mono
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }

      Row {
        visible: root.status === "ok"
        spacing: Style.space(4)
        bottomPadding: Style.space(2)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: String(root.score)
          color: root.band
          font.family: root.mono
          font.pixelSize: Style.font.displayLarge
          font.bold: true
        }

        Text {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(4)
          textFormat: Text.PlainText
          text: "/100"
          color: root.fgDim
          font.family: root.mono
          font.pixelSize: Style.font.bodySmall
        }
      }

      Repeater {
        model: root.rows

        Text {
          required property var modelData
          width: parent.width
          visible: modelData.value !== ""
          textFormat: Text.PlainText
          text: modelData.label + " · " + modelData.value
          color: root.fg
          font.family: root.mono
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }

      Text {
        width: parent.width
        visible: root.status === "loading"
        textFormat: Text.PlainText
        text: "scanning…"
        color: root.fgDim
        font.family: root.mono
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        width: parent.width
        visible: root.status === "error"
        textFormat: Text.PlainText
        text: root.errText
        color: Color.urgent
        font.family: root.mono
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.status === "empty"
        textFormat: Text.PlainText
        text: "url = https://your-store.com\nname = My Store\nlang = en"
        color: root.fgDim
        font.family: root.mono
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Text {
        width: parent.width
        visible: root.status === "ok" && !root.editing
        topPadding: Style.space(3)
        textFormat: Text.PlainText
        text: root.checkedAt + (root.fromCache ? " · cached" : " · fresh")
        color: root.fgDim
        font.family: root.mono
        font.pixelSize: Style.font.bodySmall
      }

      Row {
        visible: !root.editing
        topPadding: Style.space(2)
        spacing: Style.space(4)

        Button {
          text: "Edit site"
          onClicked: root.startEditing()
        }
      }

      Column {
        width: parent.width
        visible: root.editing
        spacing: Style.space(4)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Site URL"
          color: root.fgDim
          font.family: root.mono
          font.pixelSize: Style.font.bodySmall
        }

        TextField {
          id: urlField
          width: parent.width
          text: root.formUrl
          placeholderText: "https://your-store.com"
          onTextChanged: root.formUrl = text
          onAccepted: root.saveEditing()
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "Name shown in the panel"
          color: root.fgDim
          font.family: root.mono
          font.pixelSize: Style.font.bodySmall
        }

        TextField {
          id: nameField
          width: parent.width
          text: root.formName
          placeholderText: "My Store"
          onTextChanged: root.formName = text
          onAccepted: root.saveEditing()
        }

        Row {
          spacing: Style.space(4)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Language"
            color: root.fgDim
            font.family: root.mono
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            text: "en"
            active: root.formLang === "en"
            onClicked: root.formLang = "en"
          }

          Button {
            text: "zh"
            active: root.formLang === "zh"
            onClicked: root.formLang = "zh"
          }
        }

        Row {
          spacing: Style.space(4)

          Button {
            text: "Save"
            onClicked: root.saveEditing()
          }

          Button {
            text: "Cancel"
            onClicked: root.editing = false
          }
        }
      }
    }
  }
}
