# MaxCLI interaction design

## Product boundary

參考 Agent Sessions 的 local-first 與統一 agent 概念，但 MaxCLI 的主流程是「同時執行與調度」，不是索引歷史紀錄。MVP 因此把資源集中在 PTY 相容性、密集 session 導航及背景狀態，不先做 token 計費、transcript database 或雲端同步。

## Information architecture

```text
┌ compact sidebar ─────┬──────────────── active workspace ────────────────┐
│ Running / Attention  │ Focus: one large interactive terminal            │
│ Search + agent filter│                         or                        │
│ 1  pinned API        │ Grid: 2–3 columns of live terminal panes         │
│ 2  web review    ●   │                                                  │
│ 3  tests             │ pane header = state + agent + repo + stop/start  │
│ … up to dozens       │                                                  │
│ + New     •••        │                                                  │
└──────────────────────┴──────────────────────────────────────────────────┘
```

Sidebar 順序刻意不隨最近使用跳動，確保 `⌘1`…`⌘9` 能形成穩定肌肉記憶；`⌘K` 快速切換器才使用 MRU 排序。Pinned 項目在上方，未釘選項目依建立時間排列。

## Session lifecycle

```text
create / restart → launching → running ─┬→ stopped (manual or exit 0)
                                       ├→ attention (bell/background exit)
                                       └→ failed (non-zero exit)
```

`AppModel` 保存可序列化的 `WorkspaceSession`，`TerminalRuntime` 則持有不可序列化的 `LocalProcessTerminalView`。因此 SwiftUI 重新排版或 Focus/Grid 切換只搬動 view，不擁有或重建 child process。重啟會換 runtime generation，舊 PTY 延遲送達的 termination event 不會覆蓋新程序狀態。

應用程式重開時只恢復 session 設定並標為 Stopped。沒有 tmux 或 daemon 時，宣稱已接回舊 PID 會是不可靠的；未來若要跨 app launch 保活，應另做明確的 background broker，而不是偷偷改變這項語意。

## Scaling to 10–20 sessions

- UI：Grid 使用 lazy layout，離開畫面的 terminal view 可卸下，但 runtime 仍持有 PTY。
- 導航：數字熱鍵處理固定前九個；MRU 搜尋處理剩餘 session。
- 注意力：不因每次輸出就打擾，只在 bell、背景退出及非零 exit 改變 attention 狀態。
- 安全：關閉仍在執行的 session 會先確認；Stop All 是明確選單操作。
- 可恢復性：命令、路徑、參數與 pin 設定使用 UserDefaults JSON 保存。

## Next steps beyond MVP

- 可拖曳排序與 project group。
- per-session unread output counter，而不只 bell/exit。
- tmux 或 XPC broker，讓 app 重啟後重新 attach。
- agent session ID 偵測與 `resume` 指令。
- CPU、記憶體、token/quota 指標及 macOS notification。
