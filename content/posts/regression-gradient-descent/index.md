---
title: "線形回帰メモ 勾配法"
date: 2021-06-20T13:58:47+09:00
draft: true
tags: ["線形回帰", "勾配法"]
categories: ["機械学習", "Julia"]
math: true
toc: true
---


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

が成り立つと仮定し、これに適する$\bm{w}$を見つけたい。「適する」とは具体的に何なのかというと、ここでは予測とデータとの二乗誤差の和

$$
J(\bm{w}) = \frac{1}{2} \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})^2
$$

が最小となる $\bm{w}$ を求める。この $J$ については呼び名がいくつかあるが、ここではコスト関数と呼ぶ。
係数 $1/2$ は微分した時に出てくる $2$ を消し去るための便宜的なものであり、つける必然はない。





各ステップで勾配を計算する。勾配と逆向きに進んでいけば、(局所)最小値に近づくことが期待される。

## コスト関数の勾配

$w_j$に関する偏微分を計算すると、

$$
\frac{\partial J(\bm{w})}{\partial w_j}
= \sum_{i=1}^{N} (h_{\bm{w}}(\bm{x}_i) - y^{(i)})x_j^{(i)},\ j = 0, 1, \ldots, D
$$

だたし、$x_0 = 1$ とした。


## Juliaによる実装

まず、前回同様データを生成する関数を作る。

```julia
function generate_data(w :: Vec, N :: Int64)
  D = length(w)
  @assert D > 1

  d = Normal()
  X = hcat(ones(N), rand(N, D - 1))
  y = X * w + 0.1*rand(d, N)

  X, y
end
```

勾配法は次のように作る。終了条件は、勾配のノルムが十分小さくなったときとする。

```julia
function gradient_descent(X::Mat, y::Vec, w0::Vec; alpha::Float64 = 0.01, eps::Float64 = 1e-8, max_step=1e5)
  @assert size(X, 1) == length(y)
  N = length(y)
  D = size(X, 2)

  ws = [w0]
  for _ in 1:max_step
    w = ws[end]
    a = X * w - y

    dJ = transpose(X) * a
    norm(dJ) < eps && break

    w = w - alpha * dJ
    push!(ws, w)
  end
  hcat(ws...)
end
```

実際に使ってみる。コスト関数の地形図も描画してみる。

```julia
function main()
  Random.seed!(2021)


  # データの作成とプロット
  X, y = generate_data([1.0, 2.0], 50)
  p1 = scatter(X[:, 2], y)


  # wの推定
  ws = gradient_descent(X, y, [0.5, 1.5])
  w = ws[:, end]
  println("result: ", w)


  # 推定したwを元に直線を描画
  plot_x = range(minimum(X[:, 2]), maximum(X[:, 2]), length=100)
  plot_y = map(x -> w[1] + w[2]*x, plot_x)
  plot!(p1, plot_x, plot_y)

  
  # コスト関数の地形を描画
  J0 = generate_J(X, y)
  J(w0, w1) = J0([w0, w1])

  w0 = range(0.5, 1.5, length=100)
  w1 = range(1.5, 2.5, length=100)
  p2 = contour(w0, w1, J)


  # 色々なwを勾配法の初期値とし、その動きをみる
  for w_init in [[0.5, 1.5], [0.6, 2.4], [1.4, 2.4]]
    ws = gradient_descent(X, y, w_init)
    plot!(p2, ws[1, :], ws[2, :])
  end

  # データのプロットとコスト関数の地形を並べて表示
  plot(p1, p2, layout=(1, 2), size=(1200, 400))
end

# main関数を実行
main()
```

