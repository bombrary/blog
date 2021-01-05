---
title: "Purescriptメモ - 配列のシャッフルを様々な方法で実装する"
date: 2021-01-04T13:29:19+09:00
tags: ["Fisher-Yates Shuffle", "FFI", "ST", "Monad"]
toc: true
categories: ["PureScript"]
---

PureScriptで配列のシャッフルをしたい。型はこんな感じ。乱数は副作用を伴うため、返り値の型は`Effect`で包まれる。

```haskell
shuffle :: forall a. Array a -> Effect (Array a)
```

アルゴリズムは[Fisher-Yates ShuffleのModern Algorithmの項の2つ目](https://en.wikipedia.org/wiki/Fisher–Yates_shuffle#The_modern_algorithm)を利用する。これをさまざまな方法で作成したところ、Functor, Applicative, Monadなどに関連する事項だったり、`ST`モナドの使い方、FFIの使い方だったりが学べたので、備忘のために書く。

## 準備

適当なディレクトリでプロジェクトを作成する。今回使うパッケージをインストールする。

{{< cui >}}
$ spago init
$ spago install arrays
$ spago install random
$ spago install foldable-traversable
{{< /cui >}}

## 方法1: 素直(?)な書き方

ここでは、`src/Shuffle.purs`に記述する。

天下り的ではあるが、これから使う関数、型をimportしておく。

```haskell
module Shuffle where

import Prelude

import Effect (Effect)
import Data.Array (range, (!!), updateAt, length)
import Data.Traversable (for)
import Effect.Random (randomInt)
import Data.Maybe (maybe)
import Data.Foldable (foldr)
```

まずは、「どの添字ととの添字の値を交換するか」という情報をもったデータ`ExchangeIndex`と、それを作成する関数`exchangeIndicies`を作成する。

```haskell
type ExchangeIndex =
  { i :: Int
  , j :: Int
  }

exchangeIndicies :: Int -> Effect (Array ExchangeIndex)
exchangeIndicies n =
  for (range 0 (n - 2)) \i -> do
     j <- randomInt i (n - 1)
     pure { i, j }
```

次に、`ExchangeIndex`の情報を元に配列を交換する関数`exchange`を作成。配列の添字が不正だった場合(配列外参照を起こしそうなとき)は`!!`演算子が`Nothing`を返すため、一連の計算は`Maybe`に包まれる。今回は簡単のため、交換に失敗したら元の配列をそのまま返すような実装にする。

```haskell
exchange :: forall a. ExchangeIndex -> Array a -> Array a
exchange {i, j} xs = maybe xs identity do
  xi <- xs !! i
  xj <- xs !! j
  updateAt j xi =<< updateAt i xj xs
```


最後に、`shuffle`関数を作成。「どことどこを交換すべきか」という複数の情報の配列を`exchangeIndicies (length xs)`で作成する。それらを元に`xs`の要素を交換したい。このような、あるデータ`xs`に対してデータ列`exchangeIndicies (length xs)`を順々に適用していきたい場合は、`foldr`が有効である。

```haskell
shuffle :: forall a. Array a -> Effect (Array a)
shuffle xs = foldr exchange xs <$> exchangeIndicies (length xs)
```


`<$>`のところだけ補足しておく。もし`exchangeIndicies (length xs)`が`Array ExchangeIndex`を返すなら、単に

```haskell
shuffle :: forall a. Array a -> Effect (Array a)
shuffle xs = foldr exchange xs (exchangeIndicies (length xs))
```

とすれば良い。ところが、`exchangeIndicies (length xs)`は`Effect`に包まれた型なので、間に`<$>`を挟む必要がある。


## 方法2: StateTの利用

[Wikipediaに記載されているアルゴリズム](https://en.wikipedia.org/wiki/Fisher–Yates_shuffle#The_modern_algorithm)では手続き的に書かれている。関数型言語でも似たように書けないだろうか。「配列のある要素とある要素を交換する」という処理は、ある種配列の中身を変更しているように取れる。このような、配列の状態を変えるような計算には`State`モナドが利用できる。ただし今回のケースでは乱数の利用において`Effect`モナドが伴う。`Effect`と`State`を同じ`do`構文の中で利用するためには、`State`の代わりに`StateT`を利用する。

`StateT`を使うので、関連パッケージを入れる。

{{< cui >}}
$ spago install transformers
{{< /cui >}}

ここでは`src/Shuffle/State.purs`に書く。
天下り的ではあるが、これから使う関数をimportしておく。

```haskell
module Shuffle.State where

import Prelude

import Effect (Effect)
import Effect.Random (randomInt)
import Data.Maybe (maybe)
import Control.Monad.State (StateT, get, modify_, execStateT, lift)
import Data.Array (range, (!!), length, updateAt)
import Data.Traversable (for_)
```

方法1ではボトムアップに考えたが、ここではトップダウンに考える。
[Wikipediaに記載されているアルゴリズム](https://en.wikipedia.org/wiki/Fisher–Yates_shuffle#The_modern_algorithm)を引用すると次の通り。

```
for i from 0 to n−2 do
     j ← random integer such that i ≤ j < n
     exchange a[i] and a[j]
```

これを真似すると、PureScriptでは次のように書ける．一般に`StateT`モナドは`StateT s m b`の形で書けて、`s`は状態、`m`は`StateT`と組み合わせたいモナド、`b`は計算結果の型である。状態として扱いたいのは配列なので、`s`には`Array a`が入る。乱数の処理で副作用を扱いたいので，`m`には`Effect`が入る。今回は特に計算結果がないため、`b`には`Unit`を指定する。

`StateT`の`do`構文の中で`Effect`を伴う処理を書きたい場合は、以下のように`lift`関数を噛ませる。

`shuffleSt`では計算の手順を定義しただけであり、実際に計算を走らせるのは`shuffle`関数の`execStateT`である。`execStateT`は、一連の計算を行った後の状態を返す関数である。

```haskell
shuffleSt :: forall a. StateT (Array a) Effect Unit
shuffleSt = do
  n <- length <$> get
  for_ (range 0 (n-2)) \i -> do
    j <- lift $ randomInt i (n - 1)
    exchange i j -- これから実装する


shuffle :: forall a. Array a -> Effect (Array a)
shuffle xs = execStateT shuffleSt xs
```

`exchange`関数は`modify_`関数が組み合わさっているだけで、やってることは方法1とほとんど変わらない。

```haskell
exchange :: forall a m. Monad m => Int -> Int -> StateT (Array a) m Unit
exchange i j = do
  modify_ \xs ->
    maybe xs identity do
      xi <- xs !! i
      xj <- xs !! j
      updateAt i xj =<< updateAt j xi xs
```

### 補足: 大きすぎる配列で実行時エラーを起こす

REPLで`shuffle (range 0 10000)`を実行したところ、`RangeError: Maximum call stack size exceeded`を引き起こした。これは`shuffleSt`関数で使っている`for_`周りで起こっているらしく、ちゃんと確かめていないが恐らく以下の2点に問題がありそう。

- `for_` (及びそのflip版である`traverse_`) の実装
- `Effect a`は内部では`() => { ... }`というJSの関数として表されていること

これは、[Control.Safelyのfor\_関数](https://pursuit.purescript.org/packages/purescript-safely/4.0.0/docs/Control.Safely#v:for_)を利用することで解決できる。詳細は[purescript-safely](https://pursuit.purescript.org/packages/purescript-safely/4.0.0)を参照。

## 方法3: STとSTArrayの利用

`ST`モナドと`STArray`を使ってシャッフルを実装してみる。`ST`モナドは`State`モナドと似ているが、`ST`はmutableな計算が行えるという点で異なる。しかし`StateT`のようなモナド変換子の仕組みはないため、`Effect`と混ぜて書くことは(自分がやってみた限りだと)難しそうだ。そこで、`ST`の計算のなかで乱数の計算を行わないよう工夫する必要がある。具体的には、方法1と似た方法をとる。

余談。実は`ST`モナドについてあまりよくわかっていない状態である。`ST`周りを勉強したいなら、PureScriptではなくHaskellの文献を調べてみると良さそう。

ここでは`src/Shuffle/ST.purs`に書く。
天下り的ではあるが、これから使う関数をimportしておく。

```haskell
module Shuffle.ST where

import Prelude

import Control.Monad.ST (ST, foreach, run)
import Data.Array (range, length)
import Data.Array.ST (STArray, thaw, freeze, peek, poke)
import Data.Maybe (maybe)
import Data.Traversable (for)
import Effect (Effect)
import Effect.Random (randomInt)
```

方法1と同様に、`ExchangeIndex`と`exchangeIndicies`を作成。

```haskell
type ExchangeIndex =
  { i :: Int
  , j :: Int
  }

exchangeIndicies :: Int -> Effect (Array ExchangeIndex)
exchangeIndicies n =
  for (range 0 (n - 2)) \i -> do
     j <- randomInt i (n - 1)
     pure { i, j }
```

続いて、`STArray`の要素を交換する関数`exchangeST`を書く。ここの処理は`ST`だけでなく`Maybe`も出てくる。Applicativeスタイルを使うと多少綺麗に書ける。

`exchange`の`Array ExchangeInfo`版の関数`exchangeMany`も作る。

```haskell
exchange :: forall h a. ExchangeIndex -> STArray h a -> ST h Unit
exchange {i, j} stArr = do
  xiMay <- peek i stArr
  xjMay <- peek j stArr
  maybe
    (pure unit)
    identity
    (pokeVals <$> xiMay <*> xjMay)
  where
    pokeVals :: a -> a -> ST h Unit
    pokeVals xi xj = do
       void $ poke j xi stArr
       void $ poke i xj stArr


exchangeMany :: forall h a. Array ExchangeIndex -> STArray h a -> ST h Unit
exchangeMany indicies stArr =
  foreach indicies
    \idx -> exchange idx stArr
```

これを元に`shuffle`を作成する。`thaw`で`Array`を`STArray`に変換し、`freeze`で逆の変換を行う。実際に`ST`の計算を走らせるには`run`関数を用いる。

```haskell
shuffle' :: forall a. Array a -> Effect (Array a)
shuffle' xs = do
  indicies <- exchangeIndicies (length xs)
  pure $ run do
     stArr <- thaw xs
     exchangeMany indicies stArr
     freeze stArr
```

`withArray`関数を用いて次のようにも書ける。

```haskell
-- import Data.Array.ST (withArray)

shuffle :: forall a. Array a -> Effect (Array a)
shuffle xs = do
  indicies <- exchangeIndicies (length xs)
  pure $ run (withArray (exchangeMany indicies) xs)
```


### 補足

`run (..)`のところを`run $ ..`に変えても同じかと思い、次のように変えてみる。

```haskell
shuffle :: forall a. Array a -> Effect (Array a)
shuffle xs = do
  indicies <- exchangeIndicies (length xs)
  pure $ run $ withArray (exchangeMany indicies) xs
```

ところが、これはコンパイルエラーになる。

{{< cui >}}
Error found:
in module Shuffle.ST
at src/Shuffle/ST.purs:51:3 - 51:52 (line 51, column 3 - line 51, column 52)

  The type variable r has escaped its scope, appearing in the type

    ST r5 (Array a4) -> Array a4


in the expression apply run
in value declaration shuffle

See https://github.com/purescript/documentation/blob/master/errors/EscapedSkolem.md for more information,
or to contribute content related to this error.
{{< /cui >}}

`$`を使うとまずい、という話は、[EscapedSkolem ErrorのNotesの項目](https://github.com/purescript/documentation/blob/master/errors/EscapedSkolem.md#notes)に載っている(ページの内容が古いらしく、2021年1月現時点では`run`が`runST`と記載されていることに注意)。エラーがなぜ起こるのかについては、勉強不足のためよく分からない。

[こちら](https://gitlab.haskell.org/ghc/ghc/-/wikis/impredicative-polymorphism)で知ったのだが、どうやらGHC(Haskell)では`$`演算子だけ例外扱いしており、上のようなコードは動くようだ。同じことは[PureScriptのドキュメント](https://github.com/purescript/documentation/blob/master/language/Differences-from-Haskell.md#no-special-treatment-of-)でも言及している。

ちなみに、PureScriptではGHCでいう[BlockArguments](https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#extension-BlockArguments)拡張と同じ機能が有効であるため([ドキュメント参照](https://github.com/purescript/documentation/blob/master/language/Differences-from-Haskell.md#extensions))、`do`と`run`の間に`$`を入れなくても動く。むしろ入れてしまうと、上のエラーを引き起こす。

```haskell
run do
  ...  -- 何かの計算
```

## 方法4: FFIの利用

JavaScriptのコードをPureScriptで呼び出す方法。もはやPureScriptではないが、Fisher-Yates Shuffleの書きやすさでは1番だと思われる。

`src/Shuffle/FFI.purs`の内容は以下の通り。

```haskell
module Shuffle.FFI where

import Prelude
import Effect (Effect)

foreign import shuffle :: forall a. Array a -> Effect (Array a)
```

`src/Shuffle/FFI.js`の内容は以下の通り。`Effect e`の値は、`() => { .. }` のような、引数無しの関数であることに注意([purescript-effect](https://pursuit.purescript.org/packages/purescript-effect/2.0.1)の"Using Effects via the Foreign Function Interface"を参照)。

```js
exports.shuffle = (xs) => () => {
  const n = xs.length;
  for (let i = 0; i < n-1; i++) {
    const j = i + Math.floor( Math.random() * (n - i) );
    [xs[i], xs[j]] = [xs[j], xs[i]];
  }
  return xs;
}
```

上は`Math.random`で直接乱数を発生させたが、もし`Effect.Random`の`randomInt`関数を使いたいなら次のようにする。`randomInt`は`Effect`で包まれた値を返すため、`randomInt(a)(b)`ではなく`randomInt(a)(b)()`としないと値が得られないことに注意(`Effect e`の値は引数無しの関数であるため)。

```js
const { randomInt } = require('../Effect.Random');

exports.shuffle = (xs) => () => {
  const n = xs.length;
  for (let i = 0; i < n-1; i++) {
    const j = randomInt(i)(n-1)();
    [xs[i], xs[j]] = [xs[j], xs[i]];
  }
  return xs;
}
```

補足。1行目について、`require`の部分を`require('Effect.Random');`に変えると、REPLでは動くが`spago run`では`MODULE NOT FOUND`のエラーが発生する([参考](https://discourse.purescript.org/t/cannot-find-module-when-attempting-run-purescript-function-from-javascript/1242))。

## 計測

せっかくなので4つの方法を計測してみる。時刻を取得するためにpurescript-nowパッケージを導入。

{{< cui >}}
$ spago install now
{{< /cui >}}

`src/Main.purs`に記述していく。必要なものをimportしておく。

```haskell
module Main where
import Prelude

import Effect (Effect)
import Effect.Console (log)

import Shuffle as S
import Shuffle.State as SS
import Shuffle.ST as SST
import Shuffle.FFI as SF

import Effect.Now (nowTime)
import Data.Time (diff)
import Data.Time.Duration (Milliseconds(..))
import Data.Array (range, replicate)
import Data.Traversable (sequence)
import Data.Foldable (fold)
import Data.Int (toNumber)
import Data.Newtype (wrap, unwrap)
```

配列`xs`のシャッフル時間を計測する関数`measure`と、n回の平均を出す関数`measureN`を作成。

```haskell
measure :: forall a. Array a -> (Array a -> Effect (Array a)) -> Effect Milliseconds
measure xs shuffle = do
  ts <- nowTime
  _ <- shuffle xs
  te <- nowTime
  pure $ diff te ts


measureN :: forall a. Int -> Array a -> (Array a -> Effect (Array a)) -> Effect Milliseconds
measureN n xs shuffle = do
  ts <- sequence $ replicate n $ measure xs shuffle
  let total = fold ts
      ave = wrap $ unwrap total / toNumber n
  pure ave
```

計測結果を綺麗に出力するヘルパーを作成。

```haskell
logTime :: String -> Milliseconds -> Effect Unit
logTime label (Milliseconds t) =
  log $ label <> ": " <> show t <> " msec"
```

`main`関数はこんな感じにする。

```haskell
main :: Effect Unit
main = do
  let xs = range 0 1000
      n = 100
  logTime "1" =<< (measureN n xs S.shuffle)
  logTime "2" =<< (measureN n xs SS.shuffle)
  logTime "3" =<< (measureN n xs SST.shuffle)
  logTime "4" =<< (measureN n xs SF.shuffle)
```

REPLで実行してみる。

{{< cui >}}
> import Main
> main
1: 15.0 msec
2: 53.0 msec
3: 9.0 msec
4: 1.0 msec
unit
{{< /cui >}}

方法4(直接JSを書く)方法が一番早いのは予想通り。方法2(`StateT`の利用)が思ったより遅くて驚いた。
