---
title: "線形回帰メモ 正則化"
date: 2021-07-07T23:58:24+09:00
draft: true
tags: []
categories: []
math: true
toc: true
---

正則化自体は線形回帰に限らないことに注意。

## 問題設定

$\bm{y} = (y^{(1)}, y^{(2)}, \ldots, y^{(N)})^T,\ \bm{x}_i = (1, x_1^{(i)}, x_2^{(i)}, \ldots, x_D^{(i)})^T$
とおく。$(\bm{x}_i, y_i),\ i = 1, 2, \ldots, N$ がデータとして与えられている。このとき、入力と出力の間に

$$
\begin{aligned}
y
&= h_{\bm{w}}(\bm{x})\\\\ 
&:= w_0 + w_1x_1 + w_2x_2 + \cdots + w_Dx_D\\\\ 
&= \bm{w}^T\bm{x}
\end{aligned}
$$

が成り立つと仮定し、これに適する$\bm{w}$を見つけたい。


## (正則化前の)コスト関数

ここで「適する」とは具体的に何なのかというと、ここでは予測とデータとの二乗誤差の和

$$
J(\bm{w}) = \frac{1}{2} \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})^2
$$

が最小となる $\bm{w}$ を求める。この $J$ をここではコスト関数と呼ぶ。
係数 $1/2$ は微分した時に出てくる $2$ を消し去るための便宜的なものであり、つける必然はない。


## L1正則化とL2正則化

コスト関数に $\bm{w}_i$ のL1ノルム(の1乗)の項を付けることをL1正則化という。

$$
J_1(\bm{w}) = J(\bm{w}) + \lambda \\|\bm{w}\\|_1
$$

ただし、$\lambda$ は適当な定数。

同様に，コスト関数に $\bm{w}_i$ のL2ノルムの2乗の項を付けることをL2正則化という。

$$
J_2(\bm{w}) = J(\bm{w}) + \frac{\lambda}{2} \\|\bm{w}\\|_2^2
$$

ただし、$\lambda$ は適当な定数。$\lambda$ に $1/2$ をつける理由は微分し易くするためのもの。

一般に，コスト関数に $\bm{w}_i$ のLpノルムのp乗の項を付けることをLp正則化という。

## Ridge回帰

$J(\bm{w})$ にL2正則化を施したものは以下の通り。

$$
J_2(\bm{w}) = \frac{1}{2} \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})^2 + \frac{\lambda}{2} \\|\bm{w}\\|_2^2
$$

### 勾配

L2正則化の場合は単純に微分できる。まず $w_j$ で微分すると、$\\| \bm{w} \\|\_2^2 = \sum_{j=1}^{D}w_j^2$ であることに注意して、

$$
\frac{\partial J_2}{\partial w_j}
= \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})x_{ij} + \lambda w_j
$$

となる。 これより勾配が計算できる。
$J$ の部分のベクトル表現については、[線形回帰の勾配法のときの計算]({{< ref "posts/regression-gradient-descent#勾配の計算" >}})と同様にして、

$$
\frac{\partial J_2}{\partial \bm{w}} = X^T(X\bm{w} - \bm{y}) + \lambda \bm{w}
$$

ただし、

$$
X = \begin{pmatrix}
x_{10} & x_{11} & \cdots & x_{1D}\\\\ 
x_{20} & x_{21} & \cdots & x_{2D}\\\\ 
\vdots & \vdots & \ddots & \vdots\\\\ 
x_{N0} & x_{N1} & \cdots & x_{ND}
\end{pmatrix}
$$


## Lasso回帰

L1正則化

$J(\bm{w})$ にL2正則化を施したものを改めて $J(\bm{w})$ とおく。

$$
J_1(\bm{w}) = \frac{1}{2} \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})^2 + \lambda \\|\bm{w}\\|_1
$$

### 勾配

$w_j$ で微分すると、$\\| \bm{w} \\|\_1 = \sum_{j=1}^{D} |w_j|$ であることに注意して、

$$
\frac{\partial J_1}{\partial w_j}
= \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})x_{ij} + \lambda \frac{\partial |w_j|}{\partial w_j}
$$

### 1変数以外は固定した場合の最小値

$J_1(\bm{w})$ について、 $w_d$ だけを動かすことを考え、$J_1$ が最小になる $w_d$ を求める。 "$J_1$ の $w_d$ に関する勾配 = 0" を解くことを目指す。

見やすさのため、以下の記号を定義する。

- $\bm{w}_{-d}$ : ベクトル $\bm{w}$ から第 $d$ 成分を取り除いたベクトル。
- $\bm{x}_{n, -d}$ : ベクトル $\bm{x}_n$ から第 $d$ 成分を取り除いたベクトル。
- $\bm{x}\_{:, d} = (x_{1d}, x_{2d}, \ldots, x_{Nd})^T$: 行列 $X$ の第 $d$ 列を取り出したベクトル。
- $X\_{:, -d}$ : 行列 $X$ から第 $d$ 列を取り除いた行列。
- $\bm{r}\_{-d} = \bm{y} - X\_{:, -d}\bm{w}_{-d}$ : データの $d$ 番目の特徴を考慮しない場合の誤差

$$
\begin{aligned}
\frac{\partial J_1}{\partial w_d}
&= \sum_{n=1}^{N} (\bm{w}^T\bm{x}_n - y^{(n)})x_{nd} + \lambda \frac{\partial |w_d|}{\partial w_d}\\\\ 
&= \sum_{n=1}^{N} (\bm{w}_{-d}^T\bm{x}_{n,-d} + w_dx_{nd} - y^{(n)})x_{nd} + \lambda \frac{\partial |w_d|}{\partial w_d}\\\\ 
&= \sum_{n=1}^{N} (\bm{w}_{-d}^T\bm{x}_{n,-d} - y^{(n)})x_{nd} + w_d\sum_{n=1}^{N} x_{nd}^2 + \lambda \frac{\partial |w_d|}{\partial w_d}\\\\ 
&= -x_{:, d}^T \bm{r}\_{-d} + w_d\\| \bm{x}_{:, d} \||_2^2 + \lambda \frac{\partial |w_d|}{\partial w_d}\\\\ 
&= -c_d + w_da_d + \lambda \frac{\partial |w_d|}{\partial w_d}
\end{aligned}
$$

ここで、再び見やすさのため、$c_d = x_{:, d}^T \bm{r}\_{-d},\ a_d = \\| \bm{x}_{:, d} \||_2^2$とおいた。

さて、"勾配 = 0" を解いて局所最小値を求めたいが、最後の項が $w_d = 0$ で微分不可能。
そこで、劣勾配の概念を利用する。$|w_d|$ の劣勾配は以下の通り。

$$
\frac{\partial |w_d|}{\partial w_d} = 
\begin{cases}
\{ -1 \} & (w_d < 0)\\\\ 
[ -1, 1] & (w_d = 0)\\\\ 
\{ 1 \} & (w_d > 0)
\end{cases}
$$

$J_1$ の劣勾配は、勾配と区別せず $\frac{\partial J_1}{\partial w_d}$ と書くことにする。。$w_d = 0$ のときは $w_da_d = 0$ になることに注意すると、
劣勾配は以下のようになる。

$$
\frac{\partial J_1}{\partial w_d} =
\begin{cases}
\\{ -c_d + w_da_d - \lambda \\} & (w_d < 0)\\\\ 
[ -c_d-\lambda, -c_d + \lambda ] & (w_d = 0)\\\\ 
\\{ -c_d + w_da_d + \lambda \\} & (w_d > 0)\\\\ 
\end{cases}
$$

代わりに "0 $\in$ 劣勾配" を満たす $\bm{w}$ を求める。やや天下り的ではあるが、$c_d$ の値で場合分けする。

$c_d < -\lambda$ のとき、$\hat{\bm{w}} = \frac{c_d + \lambda}{a_d}$ とおけば、$\hat{\bm{w}} < 0$。
よって、上式の1行目に代入できて、$\frac{\partial J_1}{\partial w_d} = \\{ 0 \\}$。

$c_d > \lambda$ のとき、$\hat{\bm{w}} = \frac{c_d - \lambda}{a_d}$ とおけば、$\hat{\bm{w}} > 0$。
よって、上式の3行目に代入できて、$\frac{\partial J_1}{\partial w_d} = \\{ 0 \\}$。

$-\lambda \le c_d \le \lambda$ のとき、$-c_d-\lambda \le 0 \le -c_d+\lambda$ すなわち $0 \in [-c_d-\lambda, -c_d+\lambda]$。
そこで、$\hat{\bm{w}} = 0$ とすれば、上式の2行目より $0 \in \frac{\partial J_1}{\partial w_d}$。

まとめると、"0 $\in$ 劣勾配" を満たす $\bm{w}$ は以下のようになる。

$$
\hat{\bm{w}} =
\begin{cases}
\frac{c_d + \lambda}{a_d} & (c_d < -\lambda)\\\\ 
0 & (-\lambda \le c_d \le \lambda)\\\\ 
\frac{c_d - \lambda}{a_d} & (c_d > \lambda)\\\\ 
\end{cases}
$$

一般に、ソフト閾値作用素 (soft thresholding operator)というものがある。それは以下のように定義される。

$$
S(\theta, \lambda) =
\begin{cases}
\theta + \lambda & (\theta < -\lambda)\\\\ 
0 & (-\lambda \le \theta \le \lambda)\\\\ 
\theta - \lambda & (\theta > \lambda)\\\\ 
\end{cases}
$$

これを用いて、$\hat{\bm{w}} = S(\frac{c_d}{a_d}, \frac{\lambda}{a_d})$ と書ける。


### 座標降下法

各ステップで以下の手順を行う。

$d = 1, 2, \ldots, D$ について、$\bm{w} \leftarrow \argmin_{w_d} J_1(\bm{w})$ 

つまり、色々な $d$ で、$w_d$ についての最小化問題を解くことを繰り返す。

$\argmin_{w_d} J_1(\bm{w})$ は「$w_d$ だけ動かした場合に、$J_1$ が最小となる $w_d$」のことである。これは前に求めた $\hat{\bm{w}}$ のことであったから、
手順は、

$d = 1, 2, \ldots, D$ について、
1. $a_d = \\| \bm{x}_{:, d} \\|_2^2$ を計算。
1. $c_d = x_{:, d}^T \bm{r}\_{-d}$ を計算。
2. $\bm{w} \leftarrow S(\frac{c_d}{a_d}, \frac{\lambda}{a_d})$。

と読み替えられる。


## Juliaによる実装

$a_d$ については、単純に`X[:, d]`のノルムを計算すれば良い。$c_d$については、

$$
\begin{aligned}
   x_{:, d}^T\bm{r}_{-d}
 &= \sum_{n=1}^{N} x_{nd}(y^{(n)} - \bm{w}_{-d}^T\bm{x}_{n,-d})\\\\ 
 &= \sum_{n=1}^{N} x_{nd}(y^{(n)} - \bm{w}^T\bm{x}_n + w_dx_{nd})\\\\ 
 &= \sum_{n=1}^{N} x_{nd}(y^{(n)} - \bm{w}^T\bm{x}_n) + w_d\sum_{n=1}^Nx_{nd}^2\\\\ 
 &= x_{:, d}^T(\bm{y} - X\bm{w}) + w_da_d
\end{aligned}
$$

と式変形すれば、

```jula
X[:, d]^T(y - X * w) - w[d] * a
```

と計算できる。


