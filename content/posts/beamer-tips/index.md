---
title: "Beamer備忘録"
date: 2021-01-31T16:45:10+09:00
draft: true
tags: ["Beamer", "Presentation"]
categories: ["LaTeX"]
toc: true
---

個人的Beamerの備忘録．

もっと良い方法があるかもしれないが，とりあえずスライドの見栄え的にはOK．

## 文章を揃える

`align`環境だとやりづらい場合に．

`tabular`環境を利用する．ただデフォルトだとカラム間の余白が広すぎるので，`\tabcolsep`で調節する．

```tex
{\tabcolsep=1mm
  \begin{tabular}{lcl}
    $t \in [0, 9999]$      & ： & $\bm{\theta} = (1, 1, 0)$\\
    $t \in [10000, 19999]$ & ： & $\bm{\theta} = (2, 1, 0)$
  \end{tabular}
}
```

## 数式を小さくする

`scalebox`または`resizebox`を利用する．

```tex
\scalebox{0.775}{$ (\gamma, \alpha, K, N, M) = (0.999, 10^{-5}, 1000, 10, 100)$}
```

## 字下げする

`minipage`と`hspace`を組み合わせる．

```tex
何か文章
\hspace{1em}
\begin{minipage}{0.9\hsize}
  何か文章にひっつく文章
\end{minipage}
```

## 2カラム

`columns`と`column`を利用．

```tex
\begin{columns}
  \begin{column}{0.45\hsize}
    何か文章
  \begin{column}
  \begin{column}{0.45\hsize}
    何か画像
  \end{column}
\end{columns}
```

## 上下余白の微調整

`\vspace`を利用する．負数を指定すると余白を狭められる．

```tex
  \begin{block}{ブロック1}
  何か文章1
  \end{block}
  \vspace{-1em}
  \begin{block}{ブロック2}
  何か文章2
  \end{block}
```

## 目次の調整

本編は`\section{section1}`，`\section{section2}`，`\section{section3}`，補助資料は`\section{補助資料}`とする．
次のようにすると，最後の目次だけ補助資料を表示する．

```tex
\section{section1}
\begin{frame}
 \frametitle{目次}
 \tableofcontents[currentsection, sections={<1-3>}]
\end{frame}

% 何かスライド

\section{section2}
\begin{frame}
 \frametitle{目次}
 \tableofcontents[currentsection, sections={<1-3>}]
\end{frame}

% 何かスライド

\section{section3}
\begin{frame}
 \frametitle{目次}
 \tableofcontents[currentsection, sections={<1-3>}]
\end{frame}

% 何かスライド

\section{補助資料}
\begin{frame}
  \frametitle{目次}
  \tableofcontents[sections=<4>, subsectionstyle=show]
\end{frame}

\subsection{補助資料1}
% 何かスライド
\subsection{補助資料2}
% 何かスライド
\subsection{補助資料3}
% 何かスライド
```

## blockの余白調整

`\addtobeamertemplate`を利用する．

```tex
\addtobeamertemplate{block begin}{}{\vspace{0.25pt}}
\addtobeamertemplate{block example begin}{}{\vspace{0.25pt}}
\addtobeamertemplate{block alerted begin}{}{\vspace{0.25pt}}
```

## 任意の位置に何かを配置する

`textpos`パッケージの`textblock`環境を利用する．例えば`tcolorbox`とかと組み合わせて枠線を表現できる．

```tex
\begin{textblock}{6.25}(9.5,2)
  \begin{tcolorbox}[
    left=1.5mm, right=0mm,
    colback=black!2, coltext=mdarkteal, colframe=mdarkteal,
    boxrule=0.75pt
  ]
  何か文章
  \end{tcolorbox}
\end{textblock}
```
