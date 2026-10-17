import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// 状态栏上的每日普查头条：今天有多少站真的部署了 UCP。
// 数据源是 /summary.json（几百字节），不是 245KB 的 batch.json —— 为了在状态栏
// 显示一个分数去拉全量原始数据太浪费。数据是公开且可复核的，见 /batch.json。
BarWidget {
  id: root
  moduleName: "agentbi"

  property string label: ""
  property string detail: "AgentBI: today's census not loaded yet"

  function refresh() {
    fetchProc.running = false
    fetchProc.running = true
  }

  Process {
    id: fetchProc
    command: ["curl", "-fsS", "--max-time", "8", "https://agentbi.tech/summary.json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (!raw) return
        var d
        try { d = JSON.parse(raw) } catch (e) { return }
        if (!d || d.sites === undefined) return
        root.label = d.ucp_row2 + "/" + d.sites
        root.detail = d.day + " · " + d.evaluable + "/" + d.sites + " reachable · avg "
          + d.avg_score + (d.ctrl_blocks ? " · " + d.ctrl_blocks + " block non-browser clients" : "")
      }
    }
  }

  // 普查一天跑一次（03:30 +0800），半小时刷一次足够，别去敲别人的服务器。
  Timer {
    interval: 1800000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label === "" ? "—" : root.label
    tooltipText: root.detail

    onPressed: function (b) {
      if (b === Qt.MiddleButton) root.refresh()
      else openProc.running = true
    }
  }

  Process {
    id: openProc
    command: ["xdg-open", "https://agentbi.tech/leaderboard"]
  }
}
