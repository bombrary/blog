---
title: "GDBの使い方メモ"
date: 2019-12-11T12:22:42+09:00
draft: true
tags: []
categories: []
---

授業で利用したので，備忘録に．

## 前準備

{{< highlight txt >}}
$ gcc -g -O0 test.c -o test
{{< /highlight >}}

## 起動
{{< highlight txt >}}
$ gdb test
{{< /highlight >}}

## コマンド

### run前

| コマンド | 省略形 | 効果 |
| ---- | ---- | ---- |
| break *l* | b | l行目にブレークポイントを作成 |
| ---- | ---- | ---- |
| line *l* | l | l行目周辺のソースコード表示 |
| run *args* | | argsをコマンドライン引数にして実行 |


### running中
