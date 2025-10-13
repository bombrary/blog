---
title: "DaVinci Resolve 字幕をテキストファイルからスクリプトで追加する"
date: 2025-10-13T11:30:00+09:00
tags: []
draft: true
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


`C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting\README.txt` が一次資料らしいのでそれを読んでいく。 

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
mediapool = project.GetMediaPool()
timeline = mediapool.CreateEmptyTimeline("Timeline1")
```

{{< figure src="./create-timeline.png" >}}

## EditページにText+を追加する

試しにテキストを追加してみる。以下の処理を実行する。
1. 現在のTimelineを取得
1. Timelineに `Text+` を作成し挿入 → TimelineItem オブジェクトが帰ってくる
1. TimelineItem からFusion Compositionを取得（ `GetFusionCompByIndex(1)` ） → Composition オブジェクトが返ってくる
1. Composition オブジェクトからFusionノードのリストを取得（ `GetToolList()` ）
1. リストの1番目から `Text+` ノードを取得
1. ノードのプロパティを設定する

```python
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

ちなみに、ノードが持つプロパティ名はGUIのインスペクタから調べられる。変えたいパラメータ名の上にマウスをかざすと、画面左下にプロパティ名が表示される。

{{< figure src="./create-inspect-property.png" >}}

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

## まとめ

DaVinci ResolveとPythonを使って、テキストを自動挿入する方法を作った。ある程度は単純作業が簡略化できてうれしい。
