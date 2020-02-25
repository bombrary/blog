---
title: "置換(Permutaion)の勉強メモ(1)"
date: 2019-11-12T10:07:09+09:00
math: true
tags: ["置換", "Permutation", "数学"]
categories: ["数学", "代数学"]
---

置換について、線形代数の教科書に出てきたけど、授業ではあまり触れられなかったので自分で勉強してみる。以下はそのメモ。

## 置換の定義

<div class="math_def">
<h3>定義(置換)</h3>
$X_n$は$n$個の元を持つ集合とする。このとき、全単射写像 $\sigma: X_n \rightarrow X_n$ を$X_n$上の置換(Permutation)と呼ぶ。
</div>

言い換えると、$X_n$を適当に並べたとき、置換 $\sigma$ とはそれを並び替える方法を表したものである。

置換と聞くとReplacementがまず思い浮かぶけど、ここではPermutationなのね。

<div class="math_example">
<h3>例</h3>
$X_3 = {1,2,3}$ とする。このとき、 $X_n$ の元を並べて $(1,2,3)$ としよう。このとき、 $\sigma(1)=2,\sigma(2)=3,\sigma(3)=1$ とすれば、写像 $\sigma$ は $X_3$ 上の置換となる。このとき、 $(1,2,3)$ という列が $\sigma$ によって $(2,3,1)$ に並び替えられたように見える。
</div>

$X_n$の元はなんでも良いが、以後説明のため$X_n = \lbrace 1,2,\ldots,n \rbrace$とする。

置換は以下のように表示することがある：$\sigma(i) = p_i\ (i=1,\ldots,n)$について、

$$
\sigma = \begin{pmatrix}
   1 & 2 & \ldots & n \\\\ 
   p_1 & p_2 & \ldots & p_n
\end{pmatrix}
$$

先ほど置換とは $X_n$ を適当に並べたとき、置換 $\sigma$ とはそれを並び替えたもの、と表現した。実際、$\sigma$はただの写像なので、並び替えというより対応関係だけが大事である。上の表示方法はあくまで「上の段の元と下の段の元の対応関係」にだけ着目している。従って、上の段が$1,2,\ldots n$という並びになるとは限らない。

また、見やすさのため $\sigma(i)=i$ なる列は省略しても良いことにする。これを認めないといくつかの証明のときに書くのが大変。

## 写像と置換

写像における言葉である「合成写像」、「逆写像」、「恒等写像」を、置換においては次のように表現する。

<div class="math_def">
<h3>定義(積、恒等置換、逆置換)</h3>
<ul>
<li>$\sigma, \tau$ を置換とする。この時、その合成写像 $\sigma \circ \tau$ もまた置換である。この合成写像を積とみなし、$\sigma\tau$ と表す。</li>
<li>置換 $\sigma$ が任意の $i=1,\ldots,n$ について $\sigma(i)=i$ を満たすとき、$\sigma$ を恒等置換と呼び、$\mathrm{Id}_{X_n}$で表す。</li>
<li>置換 $\sigma$ の 逆写像 $\sigma^{-1}$ を逆置換と呼ぶ。$\sigma$の表示において、上の行と下の行を入れ替えると $\sigma^{-1}$ になることに注目。</li>
</ul>
</div>

ここで $\sigma^0=\mathrm{Id}_{X_n}$ と約束すると、$\sigma$の $n$ 回の積 $\sigma^n$ が指数法則を満たすことが分かる。さらに、 $(\sigma^{-1})^n = (\sigma^n)^{-1}$ を満たすことも分かる。

## 巡回置換

<div class="math_def">
<h3>定義(サイクル、互換)</h3>
<p>$X_n$の元のいくつかを取り出して$\{p_1, \ldots , p_m\}$ とおく。このとき、$\{p_i\}$ に含まれていない元 $p$ については$\sigma(p)=p$であり、また $\sigma(p_i)=p_{i+1}\ (i=1,\ldots,m-1),\sigma(p_m)=p_1$ が成り立つとき、$\sigma$ をサイクル(巡回置換)と呼び、$(p_1, \ldots , p_m)$ で表す。このとき $m$ をサイクルの長さと呼ぶ。</p>
<p>また、長さ2のサイクル $(i, j)$ を互換という。</p>
</div>

つまりサイクルとは、ある元は動かさず、それ以外の元については対応関係がループするような置換のこと。互換はいわゆるスワップのことで、これは馴染み深い。

サイクルについて、次の命題が成り立つ。

<div class="math_prop">
<h3>命題</h3>
<ol>
<li>$\sigma$がサイクルなら$\sigma^{-1}$もサイクルで、その長さは等しい。</li>
<li>任意の $m$ サイクルは $m-1$ 個の互換の積で表せる。</li>
</ol>
</div>

<div class="math_proof-prop">
<h3>証明</h3>
<ol>
<li>
<p>天下り的な感じがするが、$\sigma=(p_1, p_2, \ldots , p_m)$ のとき、 $\tau=(p_m, \ldots, p_2, p_1)$ が実は $\sigma$ の逆置換になっている。これは実際に書き下してみると明らかで、次のようになる。</p>
<p>2行目の変形では、$\sigma$の下行と$\tau$の上行が一致するように、$\tau$の順番を入れ替えている。</p>
$$
\begin{aligned}
\sigma\tau
&= \begin{pmatrix}
  p_1 & p_2 & \ldots & p_{m-1} & p_m \\
  p_2 & p_3 & \ldots & p_m & p_1
\end{pmatrix}
\begin{pmatrix}
  p_m & p_{m-1} & \ldots & p_2 & p_1 \\
  p_{m-1} & p_{m-2} & \ldots & p_1 & p_m
\end{pmatrix}\\
&= \begin{pmatrix}
  p_1 & p_2 & \ldots & p_{m-1} & p_m \\
  p_2 & p_3 & \ldots & p_m & p_1
\end{pmatrix}
\begin{pmatrix}
  p_2 & p_{3} & \ldots & p_{m} & p_1 \\
  p_1 & p_{2} & \ldots & p_{m-1} & p_m
\end{pmatrix}\\
&=
\begin{pmatrix}
  p_1 & p_1 & \ldots & p_{m-1} & p_m \\
  p_1 & p_2 & \ldots & p_{m-1} & p_m
\end{pmatrix}\\
&=
\mathrm{Id}_{X_n}
\end{aligned}
$$
$\tau\sigma=\mathrm{Id}_{X_n}$についても明らかに成り立つ。
</li>
<li>
<p>これも天下り的な感じがするが、$(p_1, p_2, \ldots , p_m) = (p_1, p_2)(p_2, p_3)\cdots(p_{m-1}, p_m)$となることが示せる。しかし単純に式変形するだけで意味を汲み取るのは難しそう。</p>
<p>そこで、そもそも互換の意味を考えてみると、$(p_i, p_j)$とは「$p_i$と$p_j$を交換する」と読める。従って、$(p_1, p_2)(p_2, p_3)\cdots(p_{m-1}, p_m)$とは「$p_1p_2\cdots p_m$という列の$p_m$と$p_{m-1}$を交換して、さらに$p_{m-1}$と$p_{m-2}$を交換して&hellip;」と分かる。実際に交換を繰り返してみると次のようになる。</p>
$$
\begin{aligned}
&p_1p_2p_3 \ldots p_{m-5} p_{m-4} p_{m-3} p_{m-2} p_{m-1}p_m\\
\xrightarrow{(p_{m-1}, p_m)}    & p_1p_2p_3 \ldots p_{m-5}p_{m-4}p_{m-3}p_{m-2}p_{m}p_{m-1}\\
\xrightarrow{(p_{m-2}, p_{m-1})}& p_1p_2p_3 \ldots p_{m-5}p_{m-4}p_{m-3}p_{m-1}p_{m}p_{m-2}\\
\xrightarrow{(p_{m-3}, p_{m-2})}& p_1p_2p_3 \ldots p_{m-5}p_{m-4}p_{m-2}p_{m-1}p_{m}p_{m-3}\\
\xrightarrow{(p_{m-4}, p_{m-3})}& p_1p_2p_3 \ldots p_{m-5}p_{m-3}p_{m-2}p_{m-1}p_{m}p_{m-4}\\
\xrightarrow{(p_{m-5}, p_{m-4})}& p_1p_2p_3 \ldots p_{m-4}p_{m-3}p_{m-2}p_{m-1}p_{m}p_{m-5}\\
&\cdots\\
\xrightarrow{(p_3, p_4)}& p_1p_2p_4 \ldots p_{m-4}p_{m-3}p_{m-2}p_{m-1}p_{m}p_3\\
\xrightarrow{(p_2, p_3)}& p_1p_3p_4 \ldots p_{m-4}p_{m-3}p_{m-2}p_{m-1}p_{m}p_2\\
\xrightarrow{(p_1, p_2)}& p_2p_3p_4 \ldots p_{m-4}p_{m-3}p_{m-2}p_{m-1}p_{m}p_1\\
\end{aligned}
$$
<p>よって、式の最初と最後から、次のようになる。</p>
$$
\begin{aligned}
&\begin{pmatrix}
p_1&p_2&p_3& \ldots& p_{m-5}& p_{m-4}& p_{m-3}& p_{m-2}& p_{m-1}&p_m\\
p_2&p_3&p_4& \ldots& p_{m-4}&p_{m-3}&p_{m-2}&p_{m-1}&p_{m}&p_1
\end{pmatrix}\\
&=(p_1, p_2, \ldots, p_m)
\end{aligned}
$$
</li>
</ol>
</div>

次に分離積を定義する。

<div class="math_def">
<h3>定義(分離積)</h3>
共通の文字を含まない何個か(1個でも可)のサイクルの積を分離積という。
</div>

<div class="math_example">
<h3>例</h3>
$(1,2,3)(4,5,6,7)$は分離積である。$(1,2,3)(1,4,5,6)$は分離積でない。
</div>

分離積の言葉を使って、次の命題を示す。

<div class="math_prop">
<h3>命題</h3>
<ol>
<li>サイクルの分離積は可換である。</li>
<li>任意の置換は分離積として表せる。</li>
<li>任意の置換は何個かの互換の積として表せる。</li>
</ol>
</div>
<div class="math_proof-prop">
<h3>証明</h3>
<ol>
<li>
<p>2つのサイクルの積として表された場合を考えれば十分である。$(p_1,p_2,\ldots , p_k)(q_1, q_2, \ldots , q_l)$を考える。$\{p_k\} \cap \{q_k\} = \emptyset$ であることに注意すると、</p>
$$
\begin{aligned}
&(p_1,p_2,\ldots , p_k)(q_1, q_2, \ldots , q_l)\\
=&
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k\\
p_2 & p_3 & \cdots & p_1
\end{pmatrix}
\begin{pmatrix}
q_1 & q_2 & \cdots & q_l\\
q_2 & q_3 & \cdots & q_1
\end{pmatrix}\\
=&
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k & q_1 & q_2 & \cdots q_l\\
p_2 & p_3 & \cdots & p_1 & q_1 & q_2 & \cdots q_l
\end{pmatrix}
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k & q_1 & q_2 & \cdots & q_l\\
p_1 & p_2 & \cdots & p_k & q_2 & q_3 & \cdots & q_1
\end{pmatrix}\\
=&
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k & q_1 & q_2 & \cdots & q_l\\
p_1 & p_2 & \cdots & p_k & q_2 & q_3 & \cdots & q_1
\end{pmatrix}
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k & q_1 & q_2 & \cdots q_l\\
p_2 & p_3 & \cdots & p_1 & q_1 & q_2 & \cdots q_l
\end{pmatrix}\\
=&
\begin{pmatrix}
q_1 & q_2 & \cdots & q_l\\
q_2 & q_3 & \cdots & q_1
\end{pmatrix}
\begin{pmatrix}
p_1 & p_2 & \cdots & p_k\\
p_2 & p_3 & \cdots & p_1
\end{pmatrix}\\
=&
(q_1, q_2, \ldots , q_l)(p_1,p_2,\ldots , p_k)\\
\end{aligned}
$$
</li>
<li><p>まず、$s\in X_n$から始めて$\sigma$を$m$回適用させてできた数列は$p_m = \sigma^m(s)$と表せる。このとき、 $p_1,p_2,\ldots , p_n, p_{n+1}$ には重複する元が必ず現れる。これは鳩ノ巣原理からいえる。その2元を $p_k=p_l=i\ (k \gt l)$ とおくと、 $p_{l-k} = s$ である。これは、</p>
<ul>
  <li>$\sigma^k(s) = p_k = i$</li>
  <li>$\sigma^k(p_{l-k}) = \sigma^k(\sigma^{l-k}(s)) = \sigma^l(s) = i$</li>
</ul>
<p>から $\sigma^k(p_{l-k}) = \sigma^k(s)$ であり、$\sigma^k$ の単射性からいえる。</p>
<p>以上から、数列 $p_m$ は $p_{l-k}$ から循環することが分かる。そこで、 $X_n$ のうち数列 $p_m$ に含まれていない元を $p'_m$ と置いて、</p>
$$
\begin{aligned}
\sigma
&=
\begin{pmatrix}
p_1 & p_2 & \cdots & p_{l-k} & p'_1 & p'_2 & \cdots p'_{n-l+k}\\
p_2 & p_3 & \cdots & p_1 & q_1 & q_2 & \cdots q_{n-l+k}
\end{pmatrix}\\
&=
\begin{pmatrix}
p_1 & p_2 & \cdots & p_{l-k}\\
p_2 & p_3 & \cdots & p_1
\end{pmatrix}
\begin{pmatrix}
p_1 & p_2 & \cdots p_{l-k} & p'_1 & p'_2 & \cdots p'_{n-l+k}\\
p_1 & p_2 & \cdots p_{l-k} & q_1 & q_2 & \cdots q_{n-l+k}
\end{pmatrix}\\
&=
(p_1, p_2, \ldots , p_{l-k})
\begin{pmatrix}
p'_1 & p'_2 & \cdots p'_{n-l+k}\\
q_1 & q_2 & \cdots q_{n-l+k}
\end{pmatrix}
\end{aligned}
$$
<p>と分解できる。$q_m = p_m$ となる $m$ が存在しないことは、2番目の式から明らかである。</p>
<p>同様にして、$p'_m$のある元を $s$ として循環する部分を探し、それを分離することを繰り返せば、置換を分離積に分解することができる</p>
<li>前命題と、「任意の $m$ サイクルは $m-1$ 個の互換の積で表せる」という命題から導かれる。</li>
</ol>
</div>

最終的に、「どんな並び替えも有限回のスワップでできる」という割と直感的な結論が導かれた。

とりあえずここまで。符号の話は気が向いたらやる。
