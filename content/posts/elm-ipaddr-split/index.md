---
title: "Elmメモ - 文字列をIPアドレスに変換(1) splitを用いる方法"
date: 2020-01-05T11:27:01+09:00
draft: true
tags: ["Elm", "IPアドレス", "IPv4"]
categories: ["Elm"]
---

IPv4アドレスの文字列"192.168.1.1"をパースする方法を考える。IPAddrの内部表現は次のようにする。

{{< highlight elm >}}
type IPAddr = IPAddr Int Int Int Int
{{< /highlight >}}

思いつくのは次の2通り。

1. ピリオドでsplitして、整数値に変換する。
2. パーサを利用する。

いずれにしても結構面倒。この記事では前者だけやる。

## 準備

適当なディレクトリで次のコマンドを実行。

<pre class="cui">
$ elm init
$ elm install elm/parser
</pre>

`src/IPAddr.elm`を作り、内容を以下の通りにする。

{{< highlight elm >}}
module IPAddr exposing (..)

type IPAddr = IPAddr Int Int Int Int
{{< /highlight >}}

<pre class="cui">
$ elm repl
> import IPAddr exposing (..)
</pre>

## 方針

次の処理を行う関数を`fromString`として定義する。

1. 文字列を`.`でsplitする。
2. Listの要素数が4でなければ失敗。
3. Listの各要素に`String.toInt`を適用し、どれか一つでも失敗すれば全体としても失敗。
4. Listを`[a,b,c,d]`としたとき、`IPAddr a b c d`を返す。

## traverseの実装

3の処理は、次の関数として抽象化できる: リストの各要素にfを適用し、その結果すべてが`Just`を返したときだけ、全体の結果を返す。

{{< highlight elm >}}
traverse : (a -> Maybe b) -> List a -> Maybe List b
{{< /highlight >}}


### 原始的な実装

なるべく`foldr`とかを使わずに書こうとするとこんな感じになる。

{{< highlight elm >}}
traverse : (a -> Maybe b) -> List a -> Maybe (List b)
traverse f list =
  case list of
    [] ->
      Just []

    x::xs ->
      case traverse f xs of
        Nothing ->
          Nothing

        Just ys ->
          case f x of
            Nothing ->
              Nothing

            Just y ->
              Just (y::ys)
{{< /highlight >}}

case文を使ってネストが深くなってくると、Haskellみたいなパターンマッチが欲しくなってくる。

### Maybe.map2を利用した実装

上の実装で、Maybeを2回剥がして値を取り出し、それに対してリストの連結を行なっていることがわかる。実はこの処理を抽象化した関数`Maybe.map2`が実装されている。

どちらもJust値だったときのみ、その値を取り出して計算し、Justに包んで返す関数。

<pre class="cui">
> import Maybe
> Maybe.map2 (\a b -> a + b) (Just 1) (Just 2)
<span class="cyan">Just</span> <span class="magenta">3</span> <span class="dgray">: Maybe.Maybe number</span>
> Maybe.map2 (\a b -> a + b) Nothing (Just 2)
<span class="cyan">Nothing</span> <span class="dgray">: Maybe.Maybe number</span>
> Maybe.map2 (\a b -> a + b) (Just 1) Nothing
<span class="cyan">Nothing</span> <span class="dgray">: Maybe.Maybe number</span>
> Maybe.map2 (\a b -> a + b) Nothing Nothing
<span class="cyan">Nothing</span> <span class="dgray">: Maybe.Maybe number</span>
</pre>

これを利用して書き直すと以下のようになる。

{{< highlight elm >}}
traverse : (a -> Maybe b) -> List a -> Maybe (List b)
traverse f list =
  case list of
    [] ->
      Just []

    x::xs ->
      Maybe.map2 (::) (f x) (traverse f xs)
{{< /highlight >}}

これはなかなか感動的。

### Maybe.map2 + foldrを利用した実装

上の定義を見ているとfoldrでもっと簡単に書けそうだと気づく。なので書く。

{{< highlight elm >}}
traverse : (a -> Maybe b) -> List a -> Maybe (List b)
traverse f list =
  List.foldr (\x acc -> Maybe.map2 (::) (f x) acc) (Just []) list
{{< /highlight >}}

### 補足

**これは実は車輪の再発明**で、同じ関数が[elm-community/Maybe.Extra](https://package.elm-lang.org/packages/elm-community/maybe-extra/latest/Maybe-Extra)で定義されている。

実はElmにもHoogleみたいに、型名から関数を検索するサービスがある。実際、「こんな型の関数ないかな」と思って[Elm Search](https://klaftertief.github.io/elm-search/)で検索したら出てきた。

## fromStringの実装

ようやく本題に入る。といってもtraverseさえできればあとは簡単。

まずは、文字列を整数値に変換し、さらに[0,255]に収まっているかどうかをチェックする関数`parseByte`を定義する。`Maybe.andThen`は以下のように、`Maybe`値に対してさらに条件をかけて、不正なものを落とすために使われる。

{{< highlight elm >}}
parseByte : String -> Maybe Int
parseByte string =
  String.toInt string
  |> Maybe.andThen toByteInt

toByteInt : Int -> Maybe Int
toByteInt n =
  if 0 <= n && n <= 255 then
    Just n
  else
    Nothing
{{< /highlight >}}

これを元に`fromString`を実装する。

{{< highlight elm >}}
fromString : String -> Maybe IPAddr
fromString string =
  let list = string
             |> String.split "."
             |> traverse parseByte
  in
    case list of
      Just [a,b,c,d] ->
        Just (IPAddr a b c d)

      _ ->
        Nothing
{{< /highlight >}}

<pre class="cui">
> IPAddr.fromString "192.168.1.1"
<span class="cyan">Just</span> (<span class="cyan">IPAddr</span> <span class="magenta">192 168 1 1</span>)
    <span class="dgray">: Maybe IPAddr.IPAddr</span>
> IPAddr.fromString "192.168.1"
<span class="cyan">Nothing</span> <span class="dgray">: Maybe IPAddr.IPAddr</span>
> IPAddr.fromString "192.168.1.1.1"
<span class="cyan">Nothing</span> <span class="dgray">: Maybe IPAddr.IPAddr</span>
> IPAddr.fromString "192.168.1.255"
<span class="cyan">Just</span> (<span class="cyan">IPAddr</span> <span class="magenta">192 168 1 255</span>)
    <span class="dgray">: Maybe IPAddr.IPAddr</span>
> IPAddr.fromString "192.168.1.256"
<span class="cyan">Nothing</span> <span class="dgray">: Maybe IPAddr.IPAddr</span>
</pre>
