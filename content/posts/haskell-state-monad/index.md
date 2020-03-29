---
title: "HaskellでStateモナドを自作する"
date: 2020-03-28T19:16:20+09:00
tags: ["Monad", "State"]
categories: ["Haskell"]
---

Stateモナドがわからない状態から、ギリギリ分かる状態になった。

## Stateモナドを学習した流れ

結局、具体例を通して学習した。個人的には、いきなりモナドの定義から学習するよりも、たくさんの例を見たり、実際に例を作ってみたりした方が覚えられた。抽象的な概念を理解するためには具体的な概念に触れるべきだ、ということを改めて認識した。

以下は、自分が行った学習の流れ。[Haskell IOモナド 超入門](https://qiita.com/7shi/items/d3d3492ddd90d47160f2#bind)は学習のうえで参考になった。とくに、`>>=`を漏斗の形に見立てる比喩のおかげで、モナドと関数の組み合わせのイメージがクリアになった。

1. Maybeモナド、Listモナドの使い方を理解する。
2. IOモナドの使い方を理解する。
3. いくつかのモナドについて、do構文を`>>=`に書き換えてみる。
4. Stateモナドの使い方を理解する。
5. Stateモナドを自作する。


この記事ではStateモナドを自作することをテーマとしているため、ある程度Stateモナドに慣れた人でないとわかりづらいかもしれない。

## Stateの定義

まずはStateを自作する。Stateは、`状態 -> (計算結果,次の状態)`という関数を内部に持っている。この関数のことを、この記事では「内部関数」「状態付き計算」などと表現する。

```hs
newtype State s a = State (s -> (a, s))
```

**これは本来のStateの定義とは異なることに注意**。本来は、StateはStateTを使って実装されている。上のように定義してしまうと、モナド変換子としての機能が利用できない。ただ、そこまで考えると面倒なので、今回はStateを単なる関数のラッパーとして定義した。

型引数の順番と内部関数が返すタプルの順番が逆なのが微妙に気持ち悪い。これはあくまで推測でしかないが、

- あくまで状態付きの計算なので、重要なのは計算の結果。なので返り値は`(a, s)`と計算結果を先に書いている。
- 型引数の順番が`s a`なのは、`Monad`にするときに不都合を生じないため。

なのだと思う。

### 余談

Stateモナドがよくわかっていない時は、Stateのことを「状態を持つ型」と勘違いしていた。正しくは、「状態付き**計算**を持つ型」。Stateは状態を持っているわけでなく、あくまで、「状態を引数にとり、計算結果と次の状態を返す関数」を持っている。なので、初期状態は内部関数の引数として、自分で投入する。

### runStateの定義

レコード構文を使って、`runState`を定義する。`runState`は、Stateから中身の関数を取り出す関数。

```hs
newtype State s a = State { runState :: s -> (a, s) }
```

### 試す

上の定義を踏まえて、次のようにプログラムを書いてみる。以下は、状態を`[Int]`とする状態付き計算。

`addX` `doubleAll` `sumUp`はそれぞれ、単純な内部関数を持つStateである。一方で、`calc0`はこれらの関数を組み合わせた、新たなStateであることに注目。**一連の状態付き計算を一つにまとめて、新たな状態付き計算を作っている**。

`calc0`において、初期状態を`s`、次の状態を`s0`、その次の状態を`s1`、&hellip;と置いている。計算結果を返すのは`sumUp`だけで、他の関数は単に状態を変更するだけ。なので計算結果は`()`となっている。

```hs
addX :: Int -> State [Int] ()
addX x = State $ \s -> ((), x:s)

doubleAll :: State [Int] ()
doubleAll = State $ \s -> ((), map (* 2) s)

sumUp :: State [Int] Int
sumUp = State $ \s -> (sum s, s)

calc0 :: State [Int] Int
calc0 = State $ \s ->
  let
    (_, s0) = runState (addX 1) s
    (_, s1) = runState (addX 2) s0
    (a2, s2) = runState sumUp s1
    (_, s3) = runState (addX a2) s2
    (_, s4) = runState doubleAll s3
  in
    runState sumUp s4

main = do
  print $ runState calc0 []
```

実行結果は以下のようになる。

{{< cui >}}
(12, [6,4,2])
{{< /cui >}}


## Monadのメソッド

[Control.Monad](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Monad.html)に定義が書いてある。

型クラスが、`Functor => Applicative => Monad`の順に定義されている。なので、Stateを`Monad`にするためには、同時に`Applicative`と`Functor`にしておかなければいけない。

以下は、最低限の定義だけ記している。

```hs
class Functor f where
  fmap :: (a -> b) -> f a -> f b
```

```hs
class Functor f => Applicative f where
  pure :: a -> f a
  (<*>) :: f (a -> b) -> f a -> f b
```

```hs
class Applicative m => Monad m where
  (>>=) :: m a -> (a -> m b) -> m b
```

`Functor`、`Applicative`、`Monad`のメソッドを見ると、`f a`や`m a`のように使われていることが分かる。つまり、これらは型引数を1つだけ取る型だと分かる。ところが、State型は型引数を2つ持つ。なので、`f`や`m`の部分には、2つある型引数を1つ埋めて、`State s`を入れる。具体的には、上のメソッドの型は次のように書ける。

```hs
  fmap :: (a -> b) -> State s a -> State s b

  pure :: a -> State s a
  (<*>) :: State s (a -> b) -> State s a -> State s b

  (>>=) :: State s a -> (a -> State s b) -> State s b
```

このように具体的に型を書いてみると、各関数でどんな処理を実装すれば良いのかがなんとなく分かるかも。また一応確認しておきたいのは、どれも「1つ以上のStateを引数にとって、新しいStateを返す」関数だということ。言い換えると、「1つ以上の状態付き計算を引数にとって、新しい状態付き計算を返す」関数。

## Functorのインスタンス化

- `fmap`: Stateの中身の関数は`状態`を引数にとり`(値,次の状態)`を返すが、`値`に対してさらに関数を適用する。

```hs
instance Functor (State s) where
  fmap f state = State $ \s ->
    let
      (a0, s0) = runState state s
    in
      (f a0, s0)
```


## Applicativeのインスタンス化

- `pure`: 引数をそのまま返す状態付き計算を返す。
- `<*>`: `(関数f, 次の状態)`を返す関数と`(値a, 次の次の状態)`を返す関数を引数にとり、`(f a, 次の次の状態)`を返す関数を返す。

```hs
instance Applicative (State s) where
  pure a = State $ \s -> (a, s)
  state0 <*> state1 = State $ \s ->
    let
      (f, s0) = runState state0 s
      (a1, s1) = runState state1 s0
    in
      (f a1, s1)
```


## Monadのインスタンス化

分かりやすさのために、少し冗長に書いている。

- `(>>=)`: bind演算子と呼ばれる。左辺で得られた計算結果を、右辺の状態付き計算に利用する。

```hs
instance Monad (State s) where
  state >>= f = State $ \s -> 
    let
      (a0, s0) = runState state s
      (a1, s1) = runState (f a0) s0
    in
      (a1, s1)
```

### calc0の書き直し

bind演算子を利用すると、calc0は次のように書けるようになる。かなりすっきりした。

```hs
calc0 :: State [Int] Int
calc0 =
  addX 1 >>= \_ ->
  addX 2 >>= \_ ->
  sumUp >>= \a2 ->
  addX a2 >>= \_ ->
  doubleAll >>= \_ ->
  sumUp
```

do構文で書くと次のようになる。さらにすっきりした。

```hs
calc0 :: State [Int] Int
calc0 = do
  addX 1
  addX 2
  a2 <- sumUp
  addX a2
  doubleAll
  sumUp
```

## getとputの定義

せっかくなので`get`と`put`を定義する。

- `get`: 状態を取り出す。単に`状態 -> (状態, 状態)`を内部関数にすればよい。
- `put`: 状態を更新する。単に`状態 -> ((), 新しい状態)`を内部関数にすればよい。

```hs
get :: State s s
get = State $ \s -> (s, s)

put :: s -> State s ()
put s = State $ \_ -> ((), s)
```

### addX,doubleAll,sumUpの書き直し

`get`と`put`を使うと、少し見やすくなる。

```hs
addX :: Int -> State [Int] ()
addX x = do
  xs <- get
  put $ x:xs

doubleAll :: State [Int] ()
doubleAll = do
  xs <- get
  put $ map (* 2) xs

sumUp :: State [Int] Int
sumUp = do
  xs <- get
  return $ sum xs
```

## (おまけ) Functor、Applicative、Monad則の確認


以下はひたすら各法則の証明をしている。非常に単調で長い。正直読んでわかるかどうか怪しいので、自分で頭を動かしながらやってみると良い。

<details>

<summary>確認</summary>

### Functor則を満たしていることの確認

Functor則とは次のような規則である。[Control.Monad](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Monad.html)からの抜粋。

```hs
1. fmap id  ==  id
2. fmap (f . g)  ==  fmap f . fmap g
```

`fmap`の定義がFunctor則に合っているか、一応証明しておく。上の`fmap`の定義に当てはめて証明する。

以下、同値変形の記号を`<=>`で表す。

`fmap`は次のように定義したことを思い出す。

```hs
  fmap f state = State $ \s ->
    let
      (a0, s0) = runState state s
    in
      (f a0, s0)
```

### 1.の証明

```hs
  state = State $ \s -> (a0, s0)
```

とおけば、

```hs
    fmap id
<=> \state -> State $ \s -> (id a0, s0)
<=> \state -> State $ \s -> (a0, s0)
<=> \state -> state
<=> id
```

### 2.の証明

```hs
  state = State $ \s -> (a0, s0)
```

とおけば、

```hs
    fmap g
<=> \state -> State $ \s -> (g a0, s0)
<=> \state -> state1 -- 次で使うためstate1とおく
```

```hs
    fmap f . fmap g
<=> \state -> (fmap f (fmap g state))
<=> \state -> (fmap f state1)
<=> \state -> State $ \s -> (f (g a0), s0)
<=> \state -> State $ \s -> ((f . g) a0 , s0)
<=> fmap (f . g)
```


### Applicative則を満たしていることの確認

[Control.Applicative](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Applicative.html#t:Applicative)からの抜粋。

```hs
-- identity
1. pure id <*> v = v
-- composition
2. pure (.) <*> u <*> v <*> w = u <*> (v <*> w)
-- homomorphism
3. pure f <*> pure x = pure (f x)
-- interchange
4. u <*> pure y = pure ($ y) <*> u
```

`pure`と`(<*>)`は次のように定義したことを思い出す。

```hs
  pure a = State $ \s -> (a, s)
  state0 <*> state1 = State $ \s ->
    let
      (f, s0) = runState state0 s
      (a1, s1) = runState state1 s0
    in
      (f a1, s1)
```

#### 証明における補足

`pure`の定義から、次のような性質があることを念頭に置く。状態を変えず、計算結果だけが`x`に変わる。

```hs
 runState (pure x) s == (x, s)
```

#### 1. の証明

```hs
 runState (pure id) s == (id, s)
```

であることに注意する。また、

```hs
 runState v s = (a0, s0)
```

とおくと、

```hs
    pure id <*> v
<=> State $ \s -> (id a0, s0)
<=> State $ \s -> (a0, s0)
<=> v
```

#### 2. の証明

左辺について、

```hs
 runState (pure (.)) s == ((.), s)
```

であることに注意する。また、

```hs
 runState u s = (f, s0)
 runState v s0 = (g, s1)
 runState w s1 = (a, s2)
```

とおくと、

```hs
    pure (.) <*> u
<=> State $ \s -> ((.) f, s0)
```


```hs
    pure (.) <*> u <*> v
<=> State $ \s -> ((.) f g, s1)
<=> State $ \s -> (f . g, s1)
```

```hs
    pure (.) <*> u <*> v <*> w
<=> State $ \s -> (f . g a, s2)
```

右辺について、

```hs
 runState (v <*> w) s0 == (g a, s2)
```

であることに注意すると、

```hs
    u <*> (v <*> w)
<=> (f (g a), s2)
<=> ((f . g) a, s2)
```

#### 3. の証明

```hs
 runState (pure f) s = (f, s)
 runState (pure x) s = (x, s)
```

より、

```hs
    pure f <*> pure x
<=> State $ \s-> (f x, s)
<=> pure (f x)
```

#### 4. の証明

左辺について、

```hs
 runState u s = (f, s0)
```

とおく。また、

```hs
 runState (pure y) s0 == (y, s0)
```

に注意して、

```hs
    u <*> pure y
<=> State $ \s -> (f y, s0)
```

右辺について、

```hs
 runState (pure ($ y)) s = ($ y, s)
```

に注意して、

```hs
    pure ($ y) <*> u
<=> State $ \s -> (($ y) f, s0)
<=> State $ \s -> (f y, s0) -- ∵ ($ y) f <=> f $ y <=> f y
```

### Monad則を満たしていることの確認


Monad則とは次のような規則である。[Control.Monad](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Monad.html)からの抜粋。

```hs
1. return a >>= k  =  k a
2. m >>= return  =  m
3. m >>= (\x -> k x >>= h)  =  (m >>= k) >>= h
```

`return = pure`として定義されているので、1. の確認は不要。

`(>>=)`は以下のように定義されていたことを思い出す。

```hs
  state >>= f = State $ \s -> 
      let
        (a0, s0) = runState state s
        (a1, s1) = runState (f a0) s0
      in
        (a1, s1)
```

また、`return`は`pure`と同じなので、以下の性質が成り立っていることを念頭に置く。

```hs
 runState (return x) s = (x, s)
```

#### 2. の証明

```hs
 runState m s = (a0, s0)
```

とおく。また、

```hs
 runState (return a0) s0 == (a0, s0)
```

に注意して、

```hs
{-
  (a0, s0) = runState m s
  (a0, s0) = runState (return a0) s0
-}
    m >>= return
<=> State $ \s -> (a0, s0)
<=> state
```

#### 3. の証明

```hs
 runState m s = (a0, s0)
 runState (k a0) s0 = (a1, s1)
 runState (h a1) s1 = (a2, s2)
```

とおく。

左辺について、

`(\x -> k x >>= h)`に値`a0`を適用したケースを考える。

```hs
{-
  (a1, s1) = runState (k a0) s0
  (a2, s2) = runState (h a1) s1
-}
    (\x -> k x >>= h) a0
<=> State $ \s0 -> (a2, s2)
```

よって、

```hs
{-
  (a0, s0) = runState m s
  (a2, s2) = runState ((\x -> k x >>= h) a0) s0
-}
    m >>= (\x -> k x >>= h)
<=> State $ \s -> (a2, s2)
```

右辺について、

```hs
{-
  (a0, s0) = runState m s
  (a1, s1) = runState (k a0) s0
-}
    m >>= k
<=> State $ \s -> (a1, s1)
```

```hs
{-
  (a1, s1) = runState (m >>= k) s
  (a2, s2) = runState (h a1) s1
-}
    (m >>= k) >>= h
<=> State $ \s -> (a2, s2)
```

</details>

## 参考

- [状態系モナド超入門](https://qiita.com/7shi/items/2e9bff5d88302de1a9e9): 具体例が豊富
- [Control.Monad](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Monad.html)
- [Control.Applicative](https://hackage.haskell.org/package/base-4.12.0.0/docs/Control-Applicative.html)
