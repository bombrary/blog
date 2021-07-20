---
title: "モンテカルロ法による積分"
date: 2021-07-14T07:38:58+09:00
draft: true
tags: []
categories: []
math: true
toc: true
---


## 一般論


$$
\begin{aligned}
\int_{\Omega} f(x) dx
&= \int_{\Omega} \frac{f(x)}{p(x)}p(x)dx\\\\ 
&= \mathbb{E}\left[\frac{f(x)}{p(x)}\right]
\end{aligned}
$$

ここで、$p$ は確率密度関数。上の $\mathbb{E}$ が期待値であるためには、

$$
\int_{\Omega} p(x) dx = 1
$$

である必要がある。

大数の法則より、確率分布 $p$ に従う 標本 $x_n\ (n = 1, 2, \ldots, N)$ に対して、$N$ が十分大きければ、

$$
\mathbb{E}\left[\frac{f(x)}{p(x)}\right]
\simeq \frac{1}{N} \sum_{n=1}^{N} \frac{f(x_n)}{p(x_n)}
$$

となるから、結局、

$$
\begin{aligned}
\int_{\Omega} f(x) dx \simeq \frac{1}{N} \sum_{n=1}^{N} \frac{f(x_n)}{p(x_n)}
\end{aligned}
$$

と近似できる。


## 1変数の定積分

$p$ は $[a, b]$ 上の一様分布に従うとする。$x \in [a, b]$ について $p(x) = \frac{1}{b - a}$ であるから、

$$
\begin{aligned}
\int_{a}^{b} f(x) dx \simeq \frac{b - a}{N} \sum_{n=1}^{N} f(x_n)
\end{aligned}
$$

## 領域上の重積分

領域 $\Omega$ の体積を $V$ とする。
$p$ は $\Omega$ 上の一様分布に従うとする。$x \in \Omega$ について $p(x) = \frac{1}{V}$ であるから、

$$
\begin{aligned}
\int_{\Omega} f(x) dx \simeq \frac{V}{N} \sum_{n=1}^{N} f(x_n)
\end{aligned}
$$
