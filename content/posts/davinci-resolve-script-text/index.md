---
title: "DaVinci Resolve 字幕をテキストファイルからスクリプトで追加する"
date: 2025-10-13T11:30:00+09:00
tags: []
categories: ["Python", "DaVinci Resolve"]
---

## 前置き

DaVinci Resolveで動画編集する際に、字幕の入力が面倒だった。字幕を1かたまり作成する時に以下の作業が必要になる。
1. Text+オブジェクトを配置
1. 文字を設定
1. フォントを設定
1. サイズを設定
1. タイムライン上の位置、長さの設定

最後の項目は自動化が難しいが、他は自動化できないか調べたら、どうやらスクリプト機能で実現できるようだったので調べた。以下はその備忘録。

## 使用環境

* Windows 11
* DaVinci Resolve 20.2.1
* Python 3.13.7

## 参考資料


一次資料はここみたい。
* Windowsの場合: `C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting\README.txt`
* Macの場合: `/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/README.md`

LuaかPythonで書けるらしい。Luaであればインタプリタの導入は必要ないし、試しにLuaで書こうと思ったが、Luaの場合いまいちモジュール名がREADMEには書かれておらず不明瞭な点と、Pythonのほうが書き慣れているということでPythonを選択する。

またText+に関してはFusionの機能であり、Fusion関連であれば詳細なドキュメントがある。

[Fusion8 Scripting Guide](https://documents.blackmagicdesign.com/UserManuals/Fusion8_Scripting_Guide.pdf)

## Pythonの導入

自分のWindows環境にはこの時点でPythonが入っていなかったため、Pythonを入れる。

https://www.python.org/ からインストーラをDLして来ればよい。

READMEには以下の変数を設定しろと書いてある。内容的にPythonのモジュールパス関連の設定のようだ。
```sh
RESOLVE_SCRIPT_API="%PROGRAMDATA%\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting"
RESOLVE_SCRIPT_LIB="C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"
PYTHONPATH="%PYTHONPATH%;%RESOLVE_SCRIPT_API%\Modules\"
```

GUIの場合はシステム環境変数の設定画面から環境変数を設定すればよいが、PowerShellの場合は以下のコマンドでシステム環境変数を追加できる（管理者権限で実行すること）。

```ps1
$env:RESOLVE_SCRIPT_API="$env:PROGRAMDATA\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting"
$env:RESOLVE_SCRIPT_LIB="C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"
$env:PYTHONPATH="$env:PYTHONPATH;$env:RESOLVE_SCRIPT_API\Modules\"

[Environment]::SetEnvironmentVariable("RESOLVE_SCRIPT_API", "$env:RESOLVE_SCRIPT_API", 'Machine')
[Environment]::SetEnvironmentVariable("RESOLVE_SCRIPT_LIB", "$env:RESOLVE_SCRIPT_LIB", 'Machine')
[Environment]::SetEnvironmentVariable("PYTHONPATH", "$env:PYTHONPATH", 'Machine')
```

これでDaVinci Resolveのコンソールから、関連モジュールがimportできるようになる。

下記redditによると、DaVinciのコンソールからならimport文は不要らしい。
https://www.reddit.com/r/davinciresolve/comments/1frb4lj/save_me_please_from_this_modulenotfound_error/?tl=ja

## コンソール画面を開く

Workspace → Console を押す。

{{< figure src="./console-open.png" >}}

## プロジェクトの取得

Py3のタブを押し、スクリプトを入力していく。

現在開いているプロジェクトのオブジェクトを取得する。

```python
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()
```

以下のように出力されていれば問題ない。

{{< figure src="./console-project.png" >}}

## タイムラインの追加

タイムラインを作成してメディアプールに追加する。

```python
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()

mediapool = project.GetMediaPool()
timeline = mediapool.CreateEmptyTimeline("Timeline1")
```

{{< figure src="./create-timeline.png" >}}

## 現在のタイムラインの取得

`project.GetCurrentTimeline()` で取得可能。

```python
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()

timeline = project.GetCurrentTimeline()
```

## EditページにText+を追加する

試しにテキストを追加してみる。以下の処理を実行する。
1. 現在のTimelineを取得
1. Timelineに `Text+` を作成し挿入 → TimelineItem オブジェクトが帰ってくる
1. TimelineItem からFusion Compositionを取得（ `GetFusionCompByIndex(1)` ） → Composition オブジェクトが返ってくる
1. Composition オブジェクトからFusionノードのリストを取得（ `GetToolList()` ）
1. リストの1番目から `Text+` ノードを取得
1. ノードのプロパティを設定する

```python
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()

timeline = project.GetCurrentTimeline()

newtext = timeline.InsertFusionTitleIntoTimeline("Text+")
tool_list = newtext.GetFusionCompByIndex(1).GetToolList()
text_plus = tool_list[1]

text_plus.StyledText = 'Hello'
text_plus.Red1 = 1.0
text_plus.Green1 = 1.0
text_plus.Blue1 = 1.0
```

{{< figure src="./create-textplus.png" >}}

## Fusionノードのプロパティの調べ方

ノードが持つプロパティ名はGUIのインスペクタから調べられる。変えたいパラメータ名の上にマウスをかざすと、画面左下にプロパティ名が表示される。

{{< figure src="./create-inspect-property.png" >}}

よく使いそうなのは以下。
```python
text_plus.StyledText = "Hello"            # テキスト
text_plus.Font = "Yu Mincho"              # フォントファミリー
text_plus.Style = "Regular"               # フォントスタイル
text_plus.Size = 0.05                     # サイズ
text_plus.Red1 = 1.0                      # 赤
text_plus.Green1 = 1.0                    # 緑
text_plus.Blue1 = 1.0                     # 青
text_plus.HorizontalJustificationLeft = 1 # 左寄せを有効にする
text_plus.Center = (0.024, 0.035)         # 位置
```

すでに設定済みのプロパティ値を調べたい場合、単に `print(text_plus.StyledText)` のように取得しても、Inputというオブジェクトが帰ってくるだけで値を取得できない。
```console
Py3> print(text_plus.StyledText)
Input (0x0x131a7cf00) [App: 'Resolve' on 127.0.0.1, UUID: 1e7120a5-1391-4830-a2df-b7b18200bd7e]
```

値を出力したい場合以下のようにする（[Fusion8 Scripting Guide](https://documents.blackmagicdesign.com/UserManuals/Fusion8_Scripting_Guide.pdf) P.35 Inputs and Outputs参照）。
* `tool.prop名[frame]` で、frame目のプロパティの値を取得できる
    * フレームに依存しない値を取得したいなら、frameに `TIME_UNDEFINED` を指定する
* `tool.GetInput(prop名, frame)` でも同じ形で取得が可能
```python
print(text_plus.StyledText[resolve.TIME_UNDEFINED])
print(text_plus.GetInput("StyledText", resolve.TIME_UNDEFINED))
```

## テキストファイルから文字を取得してテキストを挿入する

ここまでDaVinci Resolve固有のライブラリの操作方法がわかれば、あとは普通にテキストファイルを読み込んで自動挿入することができる。

例えば以下のようなテキストファイルを用意する。ファイル `C:\Users\bombrary\Desktop\neko.txt` として保存されているものとする（エンコーディングはUTF-8）。
```txt
わがはいは猫である。名前はまだ無い。
どこで生れたかとんと見当けんとうがつかぬ。
何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。
吾輩はここで始めて人間というものを見た。
しかもあとで聞くとそれは書生という人間中で一番獰悪どうあくな種族であったそうだ。
この書生というのは時々我々を捕つかまえて煮にて食うという話である。
しかしその当時は何という考もなかったから別段恐しいとも思わなかった。
ただ彼の掌てのひらに載せられてスーと持ち上げられた時何だかフワフワした感じがあったばかりである。
掌の上で少し落ちついて書生の顔を見たのがいわゆる人間というものの見始みはじめであろう。
```

```python
import time

project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()

timeline = project.GetCurrentTimeline()

with open("C:\\Users\\bombrary\\Desktop\\neko.txt", "r", encoding="utf-8") as f:
    for line in f:
        styled_text = line.strip()
        print(styled_text)

        newtext = timeline.InsertFusionTitleIntoTimeline("Text+")
        tool_list = newtext.GetFusionCompByIndex(1).GetToolList()
        text_plus = tool_list[1]
        text_plus.StyledText = styled_text
        text_plus.Font = "Yu Gothic"
        text_plus.Style = "Regular"
        text_plus.Size = 0.05
        text_plus.Red1 = 1.0
        text_plus.Green1 = 1.0
        text_plus.Blue1 = 1.0

        time.sleep(0.5)
```

{{< figure src="./automation-insert-text.png" >}}

## すでに作成済みのテキストを取得・修正

`timeline.GetItemListInTrack(trackType, trackIndex)` を使う。
* `trackType` はオーディオトラックかビデオトラックかのいずれかの指定で、 `audio` か `video` のいずれか
* `trackIndex` は何番目のトラックかの指定

これを使えば、すでに作成済みの要素を一括修正できる。以下は、1番目のトラックのItemを列挙し、そのテキストカラーを修正する例。

```python
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()

timeline = project.GetCurrentTimeline()

items = timeline.GetItemListInTrack('video', 1)
for item in items:
    tool_list = item.GetFusionCompByIndex(1).GetToolList()
    text_plus = tool_list[1]
    text = text_plus.StyledText[resolve.TIME_UNDEFINED]
    print(f"modify {item.GetName()}: {text}")

    text_plus.Red1 = 0.5
    text_plus.Green1 = 0.5
    text_plus.Blue1 = 0.5

    time.sleep(1.0)
```

```console
Py3> for item in items:
    tool_list = item.GetFusionCompByIndex(1).GetToolList()
    text_plus = tool_list[1]
    text = text_plus.StyledText[resolve.TIME_UNDEFINED]
    print(f"modify {item.GetName()}: {text}")

    text_plus.Size = 0.05
    text_plus.Red1 = 0.5
    text_plus.Green1 = 0.5
    text_plus.Blue1 = 0.5

    time.sleep(1.0)
modify Text+: わがはいは猫である。名前はまだ無い。
modify Text+: どこで生れたかとんと見当けんとうがつかぬ。
modify Text+: 何でも薄暗いじめじめした所でニャーニャー泣いていた事だけは記憶している。
modify Text+: 吾輩はここで始めて人間というものを見た。
modify Text+: しかもあとで聞くとそれは書生という人間中で一番獰悪どうあくな種族であったそうだ。
modify Text+: この書生というのは時々我々を捕つかまえて煮にて食うという話である。
modify Text+: しかしその当時は何という考もなかったから別段恐しいとも思わなかった。
modify Text+: ただ彼の掌てのひらに載せられてスーと持ち上げられた時何だかフワフワした感じがあったばかりである。
modify Text+: 掌の上で少し落ちついて書生の顔を見たのがいわゆる人間というものの見始みはじめであろう。
```

## まとめ

DaVinci ResolveとPythonを使って、テキストを自動挿入する方法を作った。ある程度は単純作業が簡略化できてうれしい。
