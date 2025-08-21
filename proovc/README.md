# PoorVC — PowerShell だけで使える“ミニ版 Git”

> **ローカル専用 / インストール不要 / フォルダ・ファイル単位のコミット＆復元対応**

Windows 10 標準の PowerShell だけで `add → commit → log → diff → restore` の流れを再現する小さな VCS（バージョン管理）です。`poorvc.ps1` をプロジェクト直下に置いて使います。

---

## Features

- ✅ **Local only**（ネット不要・外部インストール不要）
- ✅ **Folder/File-level commits**（ステージ方式でピンポイント保存）
- ✅ **Selective restore**（特定ファイル/フォルダだけ復元）
- ✅ **Ignore rules**（`.pignore` による除外）
- ✅ **UTF-8** で日本語コミットメッセージに対応

※ ブランチ/マージ、削除の履歴保存は未対応（必要なら拡張可能）

---

## Quick Start

1.  実行ポリシー（一時的に許可・推奨）

        Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

2.  プロジェクト直下に移動

        cd C:\path\to\your\project

3.  スクリプトを読み込み（ドットソース）

        . .\poorvc.ps1

4.  初期化（`.pvcs` と `.pignore` を作成）

        pvc-init

5.  ステージ（git add 相当）

        pvc-add .\src\ .\README.md
        pvc-status

6.  コミット（git commit -m 相当）

        pvc-commit -m "feat: initial snapshot"

7.  ログ（git log 相当）

        pvc-log
        pvc-log -n 5

8.  差分（git diff 相当）

        pvc-diff -From HEAD~1 -To HEAD
        pvc-diff -From HEAD~1 -To HEAD -Path src\main.ps1

9.  復元（git restore/checkout 相当）

        pvc-restore -To HEAD~2            # 全体を2個前へ上書き（確認あり）
        pvc-restore -To HEAD~1 -Path src\ # フォルダだけ1個前へ
        pvc-restore -To HEAD~1 -Path main.js  # ファイルだけ戻す
        pvc-restore -To HEAD~1 -Force     # 確認なしで強制

---

## Install

1.  プロジェクトの **ルート** に `poorvc.ps1` を保存
2.  PowerShell でそのフォルダへ移動して **ドットソース** 読み込み

        . .\poorvc.ps1

※ 実行ポリシーでブロックされたら「Quick Start の 1」を実行（詳細は Troubleshooting）。

---

## Commands

| Command           | Purpose                                 | Usage example                                                |
| ----------------- | --------------------------------------- | ------------------------------------------------------------ |
| `pvc-init`        | 初期化（`.pvcs`/`.pignore` 生成）       | `pvc-init`                                                   |
| `pvc-add`         | ステージ（git add）                     | `pvc-add src\` / `pvc-add README.md` / `pvc-add *.ps1`       |
| `pvc-status`      | ステージ内容の確認                      | `pvc-status`                                                 |
| `pvc-commit -m`   | コミット（ZIP 作成・ログ追記）          | `pvc-commit -m "feat: add parser"`                           |
| `pvc-log`         | コミット履歴表示                        | `pvc-log` / `pvc-log -n 5`                                   |
| `pvc-diff`        | 差分（存在差＋ハッシュ／テキストは fc） | `pvc-diff -From HEAD~1 -To HEAD` / `-Path src\main.ps1`      |
| `pvc-restore`     | 復元（全体 or 指定 Path を上書き）      | `pvc-restore -To HEAD~2` / `pvc-restore -To HEAD -Path src\` |
| `pvc-ignore-edit` | `.pignore` を開いて編集                 | `pvc-ignore-edit`                                            |

---

## Ref（コミット参照）の書き方

- `HEAD` … 最新コミット
- `HEAD~1` … 1 つ前
- `HEAD~2` … 2 つ前
- `yyyyMMdd-HHmmss-rand` … `pvc-log` に出る実 ID

---

## Ignore Rules（`.pignore`）

- ルート直下の `.pignore` に **glob 記法** で記述（`**` 対応）
- 例:

        # folders
        bin/
        node_modules/
        **/obj/**

        # files
        *.tmp
        *.log

- `pvc-add` 実行時に適用（`.pvcs` 自体は常に除外）

---

## Restore（復元）Examples

- 全体を **2 個前** に戻す

        pvc-restore -To HEAD~2

- **フォルダ** を 2 個前に戻す

        pvc-restore -To HEAD~2 -Path src\

- **ファイル** を直前に戻す

        pvc-restore -To HEAD~1 -Path main.js

- 確認なしで強制

        pvc-restore -To HEAD~1 -Force

※ 復元は ZIP から **上書きコピー** します。ZIP に無いファイルは **削除されません**（不要ファイルは手動削除 or 拡張機能が必要）。

---

## Encoding（日本語の文字化け対策）

- 本ツールは **UTF-8** でログ/設定を読み書きします。コンソールも UTF-8 にすると安定。

        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding
        $OutputEncoding = [Console]::OutputEncoding
        chcp 65001

- `poorvc.ps1` は **UTF-8 (BOM なし)** で保存推奨

---

## Typical Workflows

A) ファイル単位の小さな修正

    . .\poorvc.ps1
    pvc-init

    pvc-add src\parser.ps1
    pvc-commit -m "fix: handle empty lines"

    pvc-log -n 3
    pvc-diff -From HEAD~1 -To HEAD -Path src\parser.ps1

B) ディレクトリ丸ごとスナップショット

    pvc-add src\
    pvc-commit -m "feat: add new module"
    pvc-restore -To HEAD~2 -Path src\

C) 事故復旧（全体を直前コミットへ）

    pvc-restore -To HEAD~1   # プロンプトで y

---

## How It Works

- **Commit**: ステージ済みの相対パスだけを **ZIP** で保存 → `.pvcs/commits/<commitId>.zip`
- **Log**: `.pvcs/log.csv`（UTF-8）に `time,commit,author,message,count` を追記
- **Index**: `.pvcs/index.txt` にステージされた相対パスを保持
- **Restore**: ZIP を展開し対象 Path を **上書きコピー**（削除はしない）
- **Diff**: 2 つの ZIP を展開 → 存在差＋ `Get-FileHash` で内容差 → テキストは `fc` で行差分表示

---

## Limitations

- No **branch/merge**（単一路線）
- No **delete history**（削除の反映はしない）
- Binary diff is **presence-only**（行単位の差分はテキストのみ）
- Large binaries は `.pignore` で除外推奨

---

## Troubleshooting

1.  実行ポリシーでブロック

         このシステムではスクリプトの実行が無効...

    対処（どちらか）  
     一時的（推奨）:

             Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

    恒久（自ユーザー）:

             Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

2.  変数直後の `:` でエラー（例: `${commitId}:`）

    `${var}` で囲む or `-f` 文字列整形を使用  
     例: `"Restored ${commitId}: $rel"` / `("Restored {0}: {1}" -f $commitId,$rel)`

3.  `.Count` が無い/PropertyNotFound

    `@(...)` で **配列化** して扱う（`Read-Index` の戻りやパイプ結果に注意）

4.  日本語が文字化け
    コンソールを UTF-8 化（上記 Encoding 参照）  
     `poorvc.ps1` を UTF-8 (BOM なし) で保存  
     `Import-Csv` / `Get-Content` / `Set-Content` / `Add-Content` は `-Encoding UTF8` 指定

---

## FAQ

- ステージをクリアしたい

        Set-Content .\.pvcs\index.txt -Value "" -Encoding UTF8

- “全部コミット”したい（毎回丸ごと ZIP）

  設計上可能。`pvc-add` を省略し、作業ツリー全体を対象にするモードを追加できます。

- 削除も履歴に入れたい

  各コミットに **マニフェスト**（ファイル一覧）を持たせ、復元時に「無いファイルを削除」する拡張で対応可能。

---

## License / Notes

- ローカル用途の簡易ツールです。重要データは別途バックアップ推奨。
- 改良要望（削除反映、完全巻き戻しモード、否定パターン `!keep.txt`、見やすい diff、詳細 status 等）は歓迎です。
