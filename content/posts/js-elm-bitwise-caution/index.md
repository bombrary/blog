---
title: "JavaScript/Elm ビット演算のときにはまったこと"
date: 2019-12-31T09:34:25+09:00
tags: ["JavaScript", "Elm", "ビット演算"]
categories: ["JavaScript", "Elm"]
---

## 結論

- JavaScriptにおいて、`>>>`以外のビット演算は32ビット符号付き整数値として扱われる。  
  &rarr; 例えば`&|^~`の計算前に、オペランドに型変換が起こる([ソース](https://developer.mozilla.org/ja/docs/Web/JavaScript/Reference/Operators/Bitwise_Operators#Bitwise_logical_operators))。
  - JSにおいて数字は`Number`という型しかないが、ビット演算のときだけ32ビット整数値に変換されるっぽい
- JavaScriptにおいて、`x >>> 0`を使うと符号なし整数になる。
- 負数を2で割り続けても、コンピュータにおける2進表現にはならない。
  - これはすごく当たり前だった
  - コンピュータにおける2進数表現にしたいなら，論理シフトを使うこと。
- ElmはJavaScriptに変換されるので、上の事実はすべてElmでも当てはまる。
  - 各種ビット演算は、JSの演算をそのまま使っているっぽい([ソース](https://github.com/elm/core/blob/1.0.4/src/Elm/Kernel/Bitwise.js))

## 検証コード

<pre class="cui">
$ elm init
</pre>

`src/MyBitwise.elm`を作成し、内容を以下のようにする。

{{< highlight elm >}}
module MyBitwise exposing (..)

import Bitwise

toBinaryString : Int -> String
toBinaryString x =
  let bit = Bitwise.and x 1
      rem = Bitwise.shiftRightZfBy 1 x
  in
  if rem > 0 then
    (toBinaryString rem) ++ (String.fromInt bit)
  else
    String.fromInt bit

{{< /highlight >}}

elm replを起動し、試す。まず必要なモジュールをimportする。

<pre class="cui">
$ elm repl
> import Bitwise
> import MyBitwise exposing (..)
</pre>

2<sup>32</sup>-1 = 4294967295を2進表示すると、1が32個並んだ数になる。32ビット整数の2の補数表現では、-1と4294967295は同じ表現方法になる。

<pre class="cui">
> toBinaryString 4294967295
<span class="yellow">"11111111111111111111111111111111"</span> <span class="dgray">: String</span>
> toBinaryString -1
<span class="yellow">"11111111111111111111111111111111"</span> <span class="dgray">: String</span>
</pre>

`Bitwise.and`の計算結果は符号付き整数値とみなされるので、以下では4294967295ではなく-1と出力される。

<pre class="cui">
> Bitwise.and 4294967295 4294967295
<span class="magenta">-1</span> <span class="dgray">: Int</span>
</pre>

ここで、`MyBitwise.elm`にて次の関数を定義する。ビットシフトの部分を2でのmodと割り算に置き換えただけ。

{{< highlight elm >}}
toBinaryStringWrong : Int -> String
toBinaryStringWrong x =
  let bit = modBy 2 x
      rem = x // 2
  in
  if rem > 0 then
    (toBinaryString rem) ++ (String.fromInt bit)
  else
    String.fromInt bit
{{< /highlight >}}

2つの関数の計算結果を比べてみると、`toBinaryStringWrong`の結果が1になってしまい、これはおかしい。

<pre class="cui">
> toBinaryString (Bitwise.and 4294967295 4294967295)
<span class="yellow">"11111111111111111111111111111111"</span> <span class="dgray">: String</span>
> toBinaryStringWrong (Bitwise.and 4294967295 4294967295)
<span class="yellow">"1"</span> <span class="dgray">: String</span>
</pre>

ちなみに符号なし整数に変換するには、次のようにする。

{{< highlight elm >}}
showAsUnsigned : Int -> Int
showAsUnsigned x =
  Bitwise.shiftRightZfBy 0 x
{{< /highlight >}}

<pre class="cui">
> showAsUnsigned -1
<span class="magenta">4294967295</span> <span class="dgray">: Int</span>
</pre>

## 考えるに至った背景

IPアドレスとサブネットマスクからネットワーク部を算出するプログラムを書いていたら、この状況に出くわした。

IPアドレスは次のように持っているものとする。

{{< highlight elm >}}
type IPAddr = IPAddr Int
type DotDecimalNotation = DDN Int Int Int Int

fromDDN : DotDecimalNotation -> IPAddr
fromDDN ddn =
  case ddn of
    DDN a b c d ->
      IPAddr (2^24*a + 2^16*b + 2^8*c + d)
{{< /highlight >}}

サブネットマスクからネットワーク部を算出する関数を定義する。

{{< highlight elm >}}
networkAddrBy : IPAddr -> IPAddr -> IPAddr
networkAddrBy subnet addr =
  case subnet of
    IPAddr s ->
      case addr of
        IPAddr a ->
          IPAddr (Bitwise.and s a)
{{< /highlight >}}

ここまではいいのだが、次のようにしてDDNに変換する関数を定義したところ、バグらせた。

{{< highlight elm >}}
toDDNHelp : Int -> (Int, Int)
toDDNHelp n =
  (modBy (2^8) n, n // (2^8))

toDDN : IPAddr -> DotDecimalNotation
toDDN addr =
  case addr of
    IPAddr n0 ->
      case toDDNHelp n0 of
        (d, n1) -> 
          case toDDNHelp n1 of
            (c, n2) -> 
              case toDDNHelp n2 of
                (b, n3) -> 
                  case toDDNHelp n3 of
                    (a, _) -> 
                      DDN a b c d
{{< /highlight >}}

以下で、`192.168.1.1`と`255.255.255.0`の論理和をとって`193.169.1.0`となるわけがないのでおかしい。

<pre class="cui">
> networkAddrBy (fromDDN (DDN 192 168 1 1)) (fromDDN (DDN 255 255 255 0))
<span class="cyan">IPAddr</span> <span class="magenta">-1062731520</span> <span class="dgray">: IPAddr</span>
> networkAddrBy (fromDDN (DDN 192 168 1 1)) (fromDDN (DDN 255 255 255 0)) |> toDDN
<span class="cyan">DDN</span> <span class="magenta">193 169 1 0</span>
    <span class="dgray">: DotDecimalNotation</span>
</pre>

これは`toDDNHelp`に問題があり、次のようにシフトを使って書き直すとうまくいく。

{{< highlight elm >}}
toDDNHelp : Int -> (Int, Int)
toDDNHelp n =
  (Bitwise.and (2^8-1) n
  ,Bitwise.shiftRightZfBy 8 n
  )
{{< /highlight >}}

<pre class="cui">
> networkAddrBy (fromDDN (DDN 192 168 1 1)) (fromDDN (DDN 255 255 255 0)) |> toDDN
<span class="cyan">DDN</span> <span class="magenta">192 168 1 0</span>
    <span class="dgray">: DotDecimalNotation</span>
</pre>

はじめElmの`Bitwise.and`がバグってるんじゃないかと思ってデバッグしていたら、どうやらJSの仕様だということが判明。

型変換の怖さを味わった良い機会だった。Elm側でIntの符号付きと符号なしの区別をうまくしてほしいな、と思った。
