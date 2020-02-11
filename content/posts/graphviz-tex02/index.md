---
title: "GraphvizでTeXの数式を表示する(2) - PDFにしたい場合"
date: 2020-02-11T21:57:47+09:00
tags: ["Graphviz", "TeX", "dot2tex"]
categories: ["Graphviz", "TeX", "グラフ"]
---

TeXのレポートに貼り付けたいが、TeXではSVG形式は扱えないのでPDFにしたくなった。やってみたら思ったより面倒だったので備忘録として残す。

### dotファイルの用意

前回と同じにする。ファイル名は`graph.dot`とする。

```dot
digraph {
  graph [ rankdir="LR" ];
  node [ shape="circle", fixedsize=true, height=0.6 ];
  Q0 [texlbl="$q_0$"];
  Q1 [texlbl="$q_1$"];
  Q2 [texlbl="$q_2$"];
  Q3 [texlbl="$q_3$"];
  Q4 [texlbl="$q_4$"];
  Q5 [texlbl="$q_5$"];
  Q6 [texlbl="$q_6$"];
  Q7 [texlbl="$q_7$"];
  Q8 [texlbl="$q_8$"];
  Q9 [texlbl="$q_9$"];
  Q10 [texlbl="$q_{10}$"];
  Q11 [texlbl="$q_{11}$"];
  Q12 [texlbl="$q_{12}$"];
  Q13 [texlbl="$q_{13}$"];
  Q0 -> Q1 [label=" ", texlbl="$\varepsilon$"];
  Q0 -> Q4 [label=" ", texlbl="$\varepsilon$"];
  Q0 -> Q7 [label=" ", texlbl="$\varepsilon$"];
  Q1 -> Q2 [label=" ", texlbl="$a$"];
  Q2 -> Q3 [label=" ", texlbl="$b$"];
  Q3 -> Q7 [label=" ", texlbl="$\varepsilon$"];
  Q4 -> Q5 [label=" ", texlbl="$b$"];
  Q5 -> Q6 [label=" ", texlbl="$b$"];
  Q6 -> Q7 [label=" ", texlbl="$\varepsilon$"];
  Q7 -> Q8 [label=" ", texlbl="$a$"];
  Q7 -> Q0 [label=" ", texlbl="$\varepsilon$"];
  Q8 -> Q9 [label=" ", texlbl="$\varepsilon$"];
  Q8 -> Q11 [label=" ", texlbl="$\varepsilon$"];
  Q9 -> Q10 [label=" ", texlbl="$b$"];
  Q10 -> Q13 [label=" ", texlbl="$\varepsilon$"];
  Q11 -> Q12 [label=" ", texlbl="$c$"];
  Q12 -> Q13 [label=" ", texlbl="$\varepsilon$"];
}
```

## dot &rarr; tex

<pre class="cui">
$ dot2tex graph.dot > graph.tex
</pre>

## tex &rarr; pdf

### 駄目なパターン

<pre class="cui">
$ platex graph.tex
$ dvipdf graph.dvi
</pre>

これをやると、一部が画面からはみ出したグラフが作成されてしまう。

### 調査

`graph.tex`のプリアンブルを見てみる。

{{< highlight tex >}}
\documentclass{standalone}
\usepackage[x11names, svgnames, rgb]{xcolor}
\usepackage[utf8]{inputenc}
\usepackage{tikz}
\usetikzlibrary{snakes,arrows,shapes}
\usepackage{amsmath}

\begin{document}
  \pagestyle{empty}

  \enlargethispage{100cm}
  ...
{{< /highlight >}}

`documentclass`が`article`になっている。この設定だと、pdfのサイズがA4になる。enlargethispageでサイズを広げているようだが、なぜかうまくいっていないようだ。

`article`を`standalone`に変えてみる。`standalone`のときは`enlargethispage`が使えないようなので、削除する。

{{< highlight tex >}}
\documentclass{standalone}
\usepackage[x11names, svgnames, rgb]{xcolor}
\usepackage[utf8]{inputenc}
\usepackage{tikz}
\usetikzlibrary{snakes,arrows,shapes}
\usepackage{amsmath}

\begin{document}
  \pagestyle{empty}
  ...
{{< /highlight >}}

これでもう一度次のコマンドを打つと、綺麗なpdfが作成される。

<pre class="cui">
$ platex graph.tex
$ dvipdf graph.dvi
</pre>

### 自動化

いちいち`standalone`に変えて`enlargepagesize`を削除するのは面倒なので、シェルスクリプトにまとめる。

例えば以下の内容を`dot2pdf.sh`として保存する。

{{< highlight sh >}}
dot2tex $1.dot > $1.tex
cat $1.tex\
  | sed 's/\\documentclass{article}/\\documentclass{standalone}/'\
  | sed 's/\\enlargethispage.*//' \
  > $1.tex
platex $1.tex
dvipdf $1.dvi
{{< /highlight >}}

`graph.dot`と同じディレクトリに置いて、次のコマンドを実行すれば、dotからpdfが一気に作成される。

<pre class="cui">
$ sh dot2pdf.sh graph
</pre>
