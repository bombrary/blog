---
title: "DaVinci Resolve 字幕をテキストファイルからスクリプトで追加する"
date: 2023-06-20T18:38:00+09:00
tags: []
draft: true
categories: ["Python", "DaVinci Resolve"]
---

## 使用環境

* Windows 11
* DaVinci Resolve 20.2.1
* Python 3.13.7

## 参考資料

`C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting\README.txt` が一次資料らしいのでそれを読んでいく。 

LuaかPythonで書けるらしい。試しにLuaで書こうと思ったが、Luaの場合いまいちモジュール名がREADMEには書かれておらず不明瞭な点と、Pythonのほうが書きなれているということでPythonを選択する。


## Pythonの導入

自分のWindows環境にはこの時点でPythonが入っていなかったため、Pythonを入れる。

https://www.python.org/ からインストーラをDLして来ればよい。

READMEには以下の変数を設定しろと書いてある。内容的にPythonのモジュールパス関連の設定のようだ。
```sh
RESOLVE_SCRIPT_API="%PROGRAMDATA%\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting"
RESOLVE_SCRIPT_LIB="C:\Program Files\Blackmagic Design\DaVinci Resolve\fusionscript.dll"
PYTHONPATH="%PYTHONPATH%;%RESOLVE_SCRIPT_API%\Modules\"
```

PowerShellの場合は以下のコマンドでシステム環境変数を追加できる。

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


## プロジェクトの取得

現在開いているプロジェクトのオブジェクトを取得する。

```python3
project_manager = resolve.GetProjectManager()
project = project_manager.GetCurrentProject()
```

## タイムラインの追加

タイムラインを作成してメディアプールに追加する。

```python3
mediapool = project.GetMediaPool()
timeline = mediapool.CreateEmptyTimeline("Timeline1")
```

## EditページにText+を追加する


```python3
timeline = project.GetCurrentTimeline()
newtext = timeline.InsertFusionTitleIntoTimeline("Text+")
tool_list = newtext.GetFusionCompByIndex(1).GetToolList()
text_plus = tool_list[1]

text_plus.StyledText = 'Hello'
text_plus.Red1 = 1.0
text_plus.Green1 = 0.0
text_plus.Blue1 = 0.0
```
