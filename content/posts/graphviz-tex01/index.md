---
title: "GraphvizでTeXの数式を表示する(1)"
date: 2020-01-26T14:00:25+09:00
tags: ["Graphviz", "TeX", "dot2tex"]
categories: ["Graphviz", "TeX", "グラフ"]
---

Graphvizはグラフを描画してくれる素晴らしいソフトなのだが、単体では数式を表示することができない。

## dot2tex

dot2texを利用すると、グラフのラベルに数式が使えるようになる。

次の手順でグラフを作る。

1. dot言語でグラフを書く
2. `dot2tex`でdotファイルをtexファイルに変換
3. texを使ってpdfなりsvgなりを作る。
   - pdfなら`platex + dvipdf`を使う(詳細は[別記事]({{< ref "/posts/graphviz-tex02/index.md" >}})にて)
   - svgなら`platex + dvisvgm`を使う。

いやGraphviz使ってないじゃないか、と思うかもしれない。しかし[Dependensies](https://dot2tex.readthedocs.io/en/latest/installation_guide.html#dependencies)にGraphvizが含まれているから、おそらくGraphvizの描画エンジンを利用してノードの位置を決定しているのだと思う。

## インストール

Python製のソフトウェアみたいで、pip経由でインストールする。

<pre class="cui">
$ pip3 install dot2tex
</pre>

## 利用の手順

### dot言語でグラフを書く

今回は次のようにする。ファイル名は適当に`graph.dot`とする。

```dot
digraph {
  graph [ rankdir="LR" ]
  node [ shape="circle", fixedsize=true, height=0.6 ]
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

`texlbl`とはdot2texが読むための属性。おそらくtex labelの略で、これがnodeまたはedgeのラベルとして、texファイルに直接展開される。そのため、数式を描きたいなら`$`で囲む。もしdotファイル上にlabel属性が定義されていたら、`texlbl`の内容に上書きされる。

edgeに対して`texlbl`を使いたいなら、ダミー用の`label`属性をつける必要がある。これをやらないとラベルが表示されないので注意([参考](https://dot2tex.readthedocs.io/en/latest/usage_guide.html#labels))。しかも、**ダミーに指定するlabelの内容は空文字では駄目で、空白でも良いから1文字以上の文字列を指定する必要がある。** これが分からなくて数十分はまっていた。

### texに変換

<pre class="cui">
$ dot2tex graph.dot > graph.tex
</pre>

### svgに変換

<pre class="cui">
$ platex graph.tex
$ dvisvgm graph.dvi
</pre>

他にも、一旦pdfに変換してから`pdftocairo`を使ってsvgに変換するのもあり。

出来上がった画像がこちら。

{{< figure src="./graph.svg" >}}

良い感じ。

## 参考

- [dot2tex](https://dot2tex.readthedocs.io/en/latest/)
- [Graphviz](https://www.graphviz.org)
