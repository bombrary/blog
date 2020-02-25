---
title: "二項分布の期待値を2種類の方法で求める"
date: 2020-02-19T07:44:43+09:00
draft: true
math: true
tags: ["確率", "二項分布"]
categories: ["数学", "確率", "期待値"]
---

## 二項分布とは

$k = 0,1,\ldots n$として、

$$
P(X = k) =
\left(\begin{matrix}
n \\\\ k
\end{matrix}\right)
p^k (1-p)^{n-k}
$$

で与えられる離散確率分布。高校数学でいう「反復試行の確率」。つまり、確率$p$で成功する試行を$n$回行ったとき、$k$回成功する確率を表す。

## 期待値

{{< math-def "定義(離散型確率分布の期待値)" >}}
確率変数$X$の期待値$E[X]$を次のように定義する。

$$
E[X] =
\sum_{x} x P(X = x)
$$
{{< /math-def >}}

つまり、$E[X]$とは$X$のとりうる値についての加重平均。

## 期待値の求め方(1): 二項定理

$$
k\left(\begin{matrix} n \\\\ k \end{matrix}\right)
= n\left(\begin{matrix} n - 1 \\\\ k - 1 \end{matrix}\right)
$$

に注意する。これは二項分布の定義から簡単に計算できる。これから、


{{< math-disp >}}
\begin{aligned}
E[X]
&= \sum_{k = 0}^{n} k \left(\begin{matrix} n \\ k \end{matrix}\right)p^k (1-p)^{n-k}\\
&= \sum_{k = 1}^{n} k \left(\begin{matrix} n \\ k \end{matrix}\right)p^k (1-p)^{n-k} \ \sf{ \footnotesize (k = 0の項を出すが、計算結果は0)}\\
&= \sum_{k = 1}^{n} n \left(\begin{matrix} n - 1 \\ k - 1\end{matrix}\right)p^k (1-p)^{n-k} \ \sf{ \footnotesize (上の注意より)}\\
&= \sum_{k = 0}^{n} n \left(\begin{matrix} n - 1 \\ k\end{matrix}\right)p^{k+1} (1-p)^{n-k-1} \ \sf{ \footnotesize (kをずらす)}\\
&= np\sum_{k = 0}^{n} \left(\begin{matrix} n - 1 \\ k\end{matrix}\right)p^{k} (1-p)^{n-k-1} \ \sf{ \footnotesize (二項定理の形をつくる)}\\
&= np \left\{ p + (1 - p) \right\}^{n-1}\\
&= np
\end{aligned}
{{< /math-disp >}}

## 期待値の求め方(2): 積率母関数

そもそも積率母関数とは何かというと、

{{< math-def "定義(積率母関数)" >}}
確率変数を$X$としたとき、$\phi(t) = E[e^{Xt}]$を積率母関数という。このとき、$X$が離散確率変数ならば、

{{< math-disp >}}
\begin{aligned}
E[e^{Xt}]
&= \sum_{x} e^{xt} P(e^{Xt} = e^{xt}) \\
&= \sum_{x} e^{xt} P(X = x)
\end{aligned}
{{< /math-disp >}}

{{< /math-def >}}

とある。何が嬉しいのかというと、これを微分して$t = 0$とすれば期待値が求められる。つまり、

{{< math-disp >}}
\begin{aligned}
\phi(t)'
&= \frac{dE[e^{Xt}]}{dt}\\
&= \sum_{x} xe^{xt} P(X = x)\\
\end{aligned}
{{< /math-disp >}}

として$t = 0$とすれば、

{{< math-disp >}}
\begin{aligned}
\phi(0)'
&= \sum_{x} xe^{x\cdot 0} P(X = x)\\
&= \sum_{x} x P(X = x)\\
&= E[X]
\end{aligned}
{{< /math-disp >}}

が得られるからである。一般に、$\phi^{(n)}(0) = E[X^n]$が成り立つ。証明には$e^{Xt}$のマクローリン展開と期待値の線形性を用いる。

余談だが、これをなぜ「積率母関数」と呼ぶのかよく分かっていない。「モーメント母関数」と表現している場合もある。物理におけるモーメントの式から来ているっぽい？

$\phi$を求め、それを微分して$t = 0$とすれば、期待値が求められる。これを二項分布でやってみる。

{{< math-disp >}}
\begin{aligned}
\phi(t)
&= \sum_{k = 0}^{n} e^{kt} P(X = k) \\
&= \sum_{k = 0}^{n} e^{kt} \left(\begin{matrix} n \\ k \end{matrix}\right)p^k (1-p)^{n-k}\\
&= \sum_{k = 0}^{n} \left(\begin{matrix} n \\ k \end{matrix}\right)(e^tp)^k (1-p)^{n-k}\\
&= \left\{ e^tp + (1-p) \right\}^n\\
&= \left( e^tp - p + 1 \right)^n\\

\phi(t)'
&= np\left( e^tp - p + 1 \right)^n\\

\phi(0)'
&= np
\end{aligned}
{{< /math-disp >}}

ということで$E[X] = np$が求められた。
