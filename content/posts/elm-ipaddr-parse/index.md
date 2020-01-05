---
title: "Elmメモ - 文字列をIPアドレスに変換(2) Parserを用いる方法"
date: 2020-01-05T14:29:15+09:00
tags: ["Elm", "elm-parser", "Parser", "IPアドレス", "IPv4"]
categories: ["Elm"]
---

## 準備

前回の`src/IPAddr.elm`を全て消し、内容を以下の通りにする。

{{< highlight elm >}}
module IPAddr exposing (..)

import Parser

type IPAddr = IPAddr Int Int Int Int
{{< /highlight >}}

<pre class="cui">
$ elm repl
> import Parser exposing (..)
> import IPAddr exposing (..)
</pre>

## Parserの基本

以下の2つのステップに分かれる。

1. Parserを作る
2. Parserを実行する - `Parser.run`を用いる

ライブラリでは、標準で用意されているParserと、それらを組み合わせて新たなParserを作るための関数が用意されている。

<pre class="cui">
> run int "123"
<span class="cyan">Ok</span> <span class="magenta">123</span> <span class="dgray">: Result (List Parser.DeadEnd) Int</span>
> run int "123abc"
<span class="cyan">Ok</span> <span class="magenta">123</span> <span class="dgray">: Result (List Parser.DeadEnd) Int</span>
> run int "abc123abc"
<span class="cyan">Err</span> [{ col = <span class="magenta">1</span>, problem = <span class="cyan">ExpectingInt</span>, row = <span class="magenta">1</span> }]
    <span class="dgray">: Result (List Parser.DeadEnd) Int</span>
</pre>

### succeed

何もパースせず、決まった結果だけを返すパーサー。

<pre class="cui">
> run (succeed "Hello") "123abcde"
<span class="cyan">Ok</span> <span class="yellow">"Hello"</span> <span class="dgray">: Result (List Parser.DeadEnd) String</span>
</pre>

パーサーを組み合わせるときの基本になる。

### |.と|=

- `|.`演算子は、右辺のParserの結果を無視した新しいParserを返す。
- `|=`演算子は、右辺のParserの結果を左辺のParserの値に適用した新しいParserを返す。

何を言っているのかわかりづらいと思うので例を示す。

{{< highlight elm >}}
add : Int -> Int -> Int
add a b =
  a + b

parser : Parser Int
parser =
  succeed add
    |= int
    |. spaces
    |= int
{{< /highlight >}}

<pre class="cui">
> run parser "1 2"
<span class="cyan">Ok</span> <span class="magenta">3</class> <span class="dgray">: Result (List DeadEnd) Int</span>
</pre>

以下の型は`Parser (Int -> Int -> Int)`である。

{{< highlight elm >}}
succeed add
{{< /highlight >}}

左辺の`Parser (Int -> Int -> Int)`の値に右辺の`Parser Int`の値`Int`を適用すると、結果の型は`Parser (Int -> Int)`となる。

{{< highlight elm >}}
succeed add
    |= int 
{{< /highlight >}}

`|. spaces`によって、スペースはパースの結果に影響しない。結果の型は`Parser (Int -> Int)`のまま。

{{< highlight elm >}}
succeed add
    |= int 
    |. spaces
{{< /highlight >}}

左辺の`Parser (Int -> Int)`の値に右辺の`Parser Int`の値`Int`を適用すると、結果の型は`Parser Int`となる。
{{< highlight elm >}}
succeed add
    |= int 
    |. spaces
    |= int 
{{< /highlight >}}

カスタム型やレコードも関数みたいなものなので、次のようにしてパース結果を各フィールドに入れることができる。

{{< highlight elm >}}
type TwoInt = TwoInt Int Int

parser : Parser TwoInt
parser =
  succeed TwoInt
    |= int
    |. spaces
    |= int
{{< /highlight >}}

<pre class="cui">
> run parser "1 2"
<span class="cyan">Ok</span> (<span class="cyan">TwoInt</span> <span class="magenta">1</span> <span class="magenta">2</span>)
</pre>

## fromString作成(失敗例)

ということで次のように定義すればIPアドレスがパースできそうである。

{{< highlight elm >}}
fromString : String -> Maybe IPAddr
fromString string =
  case run ipParser string of
    Ok addr ->
      Just addr

    Err _ ->
      Nothing


ipParser : Parser IPAddr
ipParser =
  succeed IPAddr
    |= int
    |. symbol "."
    |= int
    |. symbol "."
    |= int
    |. symbol "."
    |= int
    |. end
{{< /highlight >}}

ところが、これはうまくいかない。

<pre class="cui">
> fromString "192.168.1.1"
<span class="cyan">Nothing</span> <span class="dgray">: Maybe IPAddr</span>
> run ipParser "192.168.1.1"
<span class="cyan">Err</span> [{ col = <span class="magenta">1</span>, problem = <span class="cyan">ExpectingInt</span>, row = <span class="magenta">1</span> }]
    <span class="dgray">: Result (List DeadEnd) IPAddr</span>
</pre>

これは、ピリオドのせいでIntではなくFloatと認識されてしまったことが原因。実際、ピリオドではなく他の文字で代用するとうまく動く。

## Chompers

「elm parser period」でググったら、[まったく同じ悩みを持っている人がいた](https://discourse.elm-lang.org/t/how-to-use-elm-parser-to-parse-ints-followed-by-a-period-like-in-ip-addresses/2829)。そこを参考にしつつ自分でコードを書く。

結局、標準搭載の`int`は使わずに、数字を一文字ずつ読み取っていく戦略をとる。そのために、[elm/parserのChompers](https://package.elm-lang.org/packages/elm/parser/latest/Parser#chompers)の関数群の力を借りる。

### chompWhile

ある条件を満たしている間読み進めるだけのパーサを作成する。「数字が現れている間読み続ける」パーサは以下のように定義できる。

{{< highlight elm >}}
digit : Parser ()
digit =
  chompWhile Char.isDigit
{{< /highlight >}}

### getChompedString

chompWhileで読み進めた値をString値として取得するParserを作る。上の関数は次のように書き直せる。

{{< highlight elm >}}
digit : Parser String
digit =
  getChompedString
  <| chompWhile Char.isDigit
{{< /highlight >}}

### andThen

digitで得られた値はString型なので、これをInt型に変換した新しいParserが欲しい。ついでに、値が[0,255]に収まっているかどうかもチェックして、不正ならエラーを吐くようにしたい。これは`Parser.andThen`関数で実現できる。パースによって得られた値に対して、条件をチェックしたり、値を変換したりするために利用される。単に値を変換するだけなら、`Parser.map`を利用しても良い。

{{< highlight elm >}}
byte : Parser Int
byte =
  digit
  |> Parser.andThen parseByte

parseByte : String -> Parser Int
parseByte string =
  let x = String.toInt string
          |> Maybe.andThen checkByte
  in
    case x of
      Just n ->
        succeed n

      Nothing ->
        problem "Parse Error"


checkByte : Int -> Maybe Int
checkByte x =
  if 0 <= x && x <= 255 then
    Just x

  else
    Nothing
{{< /highlight >}}

## fromStringの実装

作った`byte`を使う。以下のようにする。

{{< highlight elm >}}
fromString : String -> Maybe IPAddr
fromString string =
  case run ipParser string of
    Ok addr ->
      Just addr

    Err _ ->
      Nothing


ipParser : Parser IPAddr
ipParser =
  succeed IPAddr
    |= byte
    |. symbol "."
    |= byte
    |. symbol "."
    |= byte
    |. symbol "."
    |= byte
    |. end
{{< /highlight >}}

出力結果は前回の記事と同じなので省略。
