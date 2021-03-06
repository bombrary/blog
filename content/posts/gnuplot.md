---
title: "gnuplotの使い方メモ"
date: 2019-11-26T10:59:56+09:00
tags: ["gnuplot", "グラフ"]
categories: ["Visualization", "gnuplot"]
layout: default
---

備忘録に。

## インストール

Macの場合はbrewでインストールできる。

{{< highlight text >}}
$ brew install gnuplot
{{< /highlight >}}

`gnuplot`コマンドで起動。

## ファイルをプロットする

例えば`data.txt`が以下のようになっているとする。

{{< highlight txt >}}
#x #y1 #y2
0 1 2
1 2 1
2 0 2
3 1 1
{{< /highlight >}}

これを描画する。

`using X:Y`で、X番目の列を横軸、Y番目の列を縦軸にする。

`w lp`とは"with linespoints"の略。つまり線と点を描画する。`w l`だと"with line"、`w lp lt 3 lw 2`だと"with linepoints linetype 3 linewidth 2"という意味。いろいろある。

{{< highlight txt >}}
$ set xlabel "X axis"
$ set ylabel "Y axis"
$ plot "data.txt" using 1:2 w pl
{{< /highlight >}}

## 軸の範囲指定

例えばx軸を[0,3000]の範囲に制限して描画したいなら、次のコマンドを打つ。

{{< highlight txt >}}
$ set xrange [0:3000]
{{< /highlight >}}

こんな感じで、gnuplotは`set 属性名 値`で様々な設定をする印象がある。

## グラフの重ね書き

### replotを使う方法

{{< highlight txt >}}
$ plot "data.txt" using 1:2 w pl
$ replot "data.txt" using 1:3 w pl
{{< /highlight >}}

### カンマで区切る方法

{{< highlight txt >}}
$ plot "data.txt" using 1:2 w pl, "data.txt" using 1:3 w pl
{{< /highlight >}}

## png形式で出力

Macでは`set terminal qt`だったが、Linuxだと`set terminal x11`みたい。現在のterminalの確認方法については後述。

{{< highlight txt >}}
$ set terminal png
$ set output "output.png"
...(グラフを描画するためのコマンドを入力)
$ set terminal qt
$ set output
{{< /highlight >}}

### グラフを重ねる場合

`replot`を用いる場合は、`replot`のたびに`set output "output.png"`を呼び出す必要がある。これはgnuplotの仕様らしい。

カンマで区切る場合は問題なくできる。

## (おまけ) terminalの確認と一覧

Macだと`set terminal x11`でエラーを起こした。`x11`は存在しないらしい。そもそもデフォルトのterminalは何か。次のコマンドで調べられる。

{{< highlight txt >}}
$ show terminal
{{< /highlight >}}

gnuplotが何のterminalを持っているかは、次のコマンドで調べられる。

{{< highlight txt >}}
$ set terminal
{{< /highlight >}}

## スクリプトを書く

gnuplotを起動していちいちコマンドを打つのは面倒なので、あらかじめスクリプトでまとめておく。例えば以下のような感じ。拡張子はなんでも良さそうだが、とりあえず`test.plt`とする。バックスラッシュ + 改行でつなげると一つのコマンドとして認識される。

{{< highlight plt >}}
set terminal png
set output "output.png"
set xlabel "X axis"
set ylabel "Y axis"
plot "data.txt" using 1:2 w lp, \
  "data.txt" using 1:3 w lp, \
  "data.txt" using 1:4 w lp
set terminal qt
set output
{{< /highlight >}}
