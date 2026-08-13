# MaxCLI

MaxCLI 是一個以 SwiftUI 製作的 macOS AI CLI 控制台。它把 Codex、Claude Code、Gemini CLI 等互動式工具放進真正的 PTY 終端，重點不是瀏覽舊對話，而是讓你同時操作十幾個正在工作的 agent，仍然找得到、切得快、看得懂哪一個需要注意。

## 目前功能

- 每個 session 有獨立 PTY、工作目錄、CLI 與啟動參數；切換畫面不會停止程序。
- Focus 模式專心操作一個終端；Grid 模式同時監看多個終端。
- 緊湊 sidebar 顯示 Running、Attention、Total，支援搜尋、agent 篩選、釘選與右鍵操作。
- `⌘1`…`⌘9` 固定快速切換前九個 session，`⌘K` 依最近使用順序搜尋全部 session。
- 可複製 session，在同一 repo 快速開第二或第三個 agent。
- 程序結束、失敗或送出 terminal bell 時會顯示狀態；背景 session 會標成 Needs attention。
- 關閉後保存 session 設定；下次啟動可逐一或一次重新啟動，但不假裝能接回已不存在的程序。
- 純本機運作，不上傳 terminal 內容。

內建啟動設定：Codex、Claude Code、Gemini CLI、Cursor Agent、GitHub Copilot CLI、OpenCode、Grok、一般 Shell，以及任意自訂命令。

## 開發與執行

需求：macOS 14+、Xcode 16+。

```sh
swift build
swift test
swift run MaxCLI
```

也可以直接用 Xcode 開啟 `Package.swift`。專案使用 [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 提供 VT100/Xterm 與本機 pseudo-terminal 支援。

建立可雙擊的 ad-hoc signed app：

```sh
make app
open build/MaxCLI.app
```

MaxCLI 不啟用 App Sandbox，因為 child process 必須能存取你指定的 repository、登入 shell 的 CLI 與開發工具。正式散佈前仍應設定自己的 Developer ID、notarization 與更新流程。

## 鍵盤操作

| 快捷鍵 | 動作 |
| --- | --- |
| `⌘N` | 新增 session |
| `⌘K` | 快速搜尋並切換 |
| `⌘1`…`⌘9` | 切到 sidebar 前九個 session |
| `⌘[` / `⌘]` | 上一個 / 下一個 session |
| `⌘D` | 複製目前 session |
| `⌘⇧R` | 重啟目前 session |
| `⌘⇧.` | 停止目前 session |
| `⌘⇧G` | Focus / Grid 切換 |

## 十幾個 session 的建議用法

1. 用 repository 與任務命名，例如 `api · review`、`web · tests`，不要只叫 `Claude 1`。
2. 長期主線釘選在最上方；前九個位置會保持穩定，適合建立肌肉記憶。
3. 平時用 Focus，等待 agent 時切 Grid；橘色/紅色邊框只處理需要注意的 session。
4. 同一個 repo 要平行處理時先 Duplicate，再更換名稱或 CLI；每個 session 仍是獨立程序。

更完整的互動與架構取捨在 [docs/DESIGN.md](docs/DESIGN.md)。
