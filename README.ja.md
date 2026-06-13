# nvim-claude-plugin

[Claude Code](https://claude.ai/code) CLIをNeovimに統合するプラグインです。

## 機能

- **複数セッション** — 作業ディレクトリごとに独立したClaude Codeセッションを同時に起動できます
- **右カラム固定パネル** — Claudeウィンドウは常に画面右全体を占有し、他のウィンドウを開いても崩れません
- **入力バッファ** — markdownハイライト付きのNeovimバッファで複数行のプロンプトを書いて、キー一つで送信できます
- **テンプレートピッカー** — Telescopeでプロンプトテンプレートを一覧表示・プレビューして呼び出せます
- **lualineへのステータス表示** — モデル名とトークン使用量（入力 / 出力 / キャッシュ）を常時グローバルステータスラインに表示します
- **winbarのセッションタブ** — Claudeウィンドウのwinbarにセッションごとのディレクトリ名をタブ表示します

## 必要環境

- Neovim 0.10以上
- [Claude Code CLI](https://claude.ai/code)（`~/.npm-global/bin/claude` にインストール済み）
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim)（ステータスライン表示を使う場合）

## インストール

### lazy.nvim（ローカル）

```lua
{
  dir = vim.fn.expand("~/nvim-claude-plugin"),
  name = "claude_nvim",
  config = function()
    require("claude_nvim").setup()
  end,
}
```

### lualine連携

lualineの設定にステータスコンポーネントを追加します：

```lua
require("lualine").setup({
  options = { globalstatus = true },
  sections = {
    lualine_x = {
      { function() return require("claude_nvim").status_line() end },
      -- ... 他のコンポーネント
    },
  },
})
```

## 使い方

### コマンド

| コマンド | 説明 |
|---|---|
| `:Claude` | Claudeパネルの表示・非表示を切り替え（初回はディレクトリ選択） |
| `:ClaudeNew` | 新しいセッションを開始（ディレクトリを選択） |
| `:ClaudeInput` | 入力バッファを開く |
| `:ClaudeTemplate` | テンプレートピッカーを開く |

### キーマップ

| キー | モード | 説明 |
|---|---|---|
| `<M-n>` | ノーマル / ターミナル | 新しいセッション |
| `<M-i>` | ノーマル / ターミナル | 入力バッファを開く |
| `<leader>t` | ノーマル | テンプレートピッカー |
| `<C-t>` | ターミナル | テンプレートピッカー |
| `<C-j>` | ノーマル（入力バッファ内） | プロンプトをClaudeに送信 |
| `q` | ノーマル（入力バッファ内） | 送信せずに入力バッファを閉じる |
| `<M-Right>` | ターミナル | 次のセッションへ切り替え |
| `<M-Left>` | ターミナル | 前のセッションへ切り替え |
| `<C-h>` | ターミナル | 左ウィンドウへフォーカス移動 |
| `i` | ノーマル（Claudeウィンドウ内） | ターミナルモードに入る |

### テンプレート

`~/.claude/templates/` にmarkdownファイルを置くと、テンプレートピッカーに表示されます。

```
~/.claude/templates/
├── explain_code.md
├── code_review.md
├── fix_bug.md
└── write_tests.md
```

## 設定

```lua
require("claude_nvim").setup({
  new_key      = "<M-n>",     -- 新しいセッションのキーマップ
  input_key    = "<M-i>",     -- 入力バッファのキーマップ
  template_key = "<leader>t", -- テンプレートピッカーのキーマップ
})
```

## ライセンス

MIT
