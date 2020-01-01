---
title: "Elmメモ - ランダムな位置に円を描画する"
date: 2020-01-01T21:03:50+09:00
tags: ["Elm", "elm/random"]
categories: ["Elm"]
---

乱数の練習に。

## 準備

プロジェクト用のディレクトリを適当に作り、そこで以下のコマンドを実行。

<pre class="cui">
$ elm init
</pre>

必要なモジュールを入れる。

<pre class="cui">
$ elm install elm/svg
$ elm install elm/random
</pre>

`Main.elm`を作成し、最低限の文を定義しておく。

{{< highlight elm >}}
module Main exposing (..)

import Browser
import Svg exposing (..)
import Svg.Attributes as SA exposing (..)
import Svg.Events as SE exposing (..)
import Random
{{< /highlight >}}

## 円の描画

こんな感じの円を描画する。

<svg width="100px" height="100px">
  <g transform="translate(50, 50)">
    <circle r="10" fill="white" stroke="black" />
    <text text-anchor="middle" dominant-baseline="central">1</text>
  </g>
</svg>

SVGでは次のように書く。

{{< highlight svg >}}
<svg width="100px" height="100px">
  <g transform="translate(50, 50)">
    <circle r="10" fill="white" stroke="black" />
    <text text-anchor="middle" dominant-baseline="central">1</text>
  </g>
</svg>
{{< /highlight >}}

円の情報で必要なのは次の4つ:

- x座標
- y座標
- 半径
- text要素の文字列

そこで円は次のように定義する。

{{< highlight elm >}}
type alias Circle =
  { r: Float
  , x: Float
  , y: Float
  , text: String
  }
{{< /highlight >}}

Elmでは宣言的にSVGやHTMLを書けるので、SVGの文法とほとんど似た構造でかける。直感的で嬉しい。

{{< highlight elm >}}
viewCircle : Circle -> Svg Msg
viewCircle { r, x, y, text } =
  Svg.g
    [ SA.transform <| translateAttr x y
    ]
    [ Svg.circle
        [ SA.r (String.fromFloat r)
        , SA.fill "white"
        , SA.stroke "black"
        ]
        []
    , Svg.text_
        [ SA.textAnchor "middle"
        , SA.dominantBaseline "central"
        ]
        [ Svg.text text
        ]
    ]

translateAttr : Float -> Float -> String
translateAttr x y =
  "translate("
  ++ String.fromFloat x
  ++ ","
  ++ String.fromFloat y
  ++ ")"
{{< /highlight >}}

他は定型通りに書く。

{{< highlight elm >}}
main = Browser.element
  { init = init
  , update = update
  , view = view
  , subscriptions = subscriptions
  }


type alias Model =
  { circles : List Circle
  }


init : () -> (Model, Cmd Msg)
init _ =
  ({ circles = 
      [ Circle 10 10 10 "1"
      , Circle 10 20 20 "2"
      , Circle 10 30 20 "3"
      , Circle 10 40 20 "4"
      , Circle 10 20 60 "5"
      , Circle 10 90 20 "6"
      ]
   }
  , Cmd.none
  )


type Msg
  = Dummy

update : Msg -> Model -> (Model, Cmd Msg)
update _ model = (model, Cmd.none)


subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none


view : Model -> Svg Msg
view { circles } =
  svg
    [ SA.style "border: 1px solid #000; margin: 10px;"
    , width "600px"
    , height "600px"
    ]
    (List.map viewCircle circles)
{{< /highlight >}}

{{< figure src="./sc01.png" width="30%" >}}

### (補足) レコード

`Circle`の定義はレコードだから、次のように定義するべきだろう。

{{< highlight elm >}}
{ r = 10
, x = 100
, y = 20
, text = "1"
}
{{< /highlight >}}

しかし型エイリアスとしてレコードが定義された場合、次のように`Circle`を定義することも可能。

{{< highlight elm >}}
Circle 10 100 20 "1"
{{< /highlight >}}

Haskellのフィールドラベルに近いものを感じる。

## 乱数を試す

Elmでほとんで乱数を使ったことがないので、色々試す。

{{< highlight elm >}}
init : () -> (Model, Cmd Msg)
init _ =
  ({ circles = []
   }
  , Random.generate GetRandomNumber (Random.int 1 6)
  )

type Msg
  = GetRandomNumber Int

update : Msg -> Model -> (Model, Cmd Msg)
update msg model = 
  case msg of 
    GetRandomNumber n -> 
      let _ = Debug.log "Random" n
      in
        (model, Cmd.none)

{{< /highlight >}}

ブラウザのデバッグコンソールを開くと、以下の文が出力される。

```
Random: [1-6のどれか]
```

### Random.generate

乱数を作るcommandを返す。第2引数には乱数生成器を指定する。ここでは`Random.int 1 6`としている。これは、`[1,6]`の`Int`型の乱数を作る生成器。乱数は第1引数のMsg型変数で受け取る。

様々な形の乱数生成器を作るための関数が用意されている。その一部については次で扱う。

### (補足) Debug.log

いわゆるprintデバッグをするために使われる関数。

{{< highlight elm >}}
-- JSにおけるconsole.log(`Label: ${value}`)と同義
Debug.log "Label" value
{{< /highlight >}}

Elmの仕様上、手続き的に書けないので、次のようにletをうまく利用して書く。

{{< highlight elm >}}
{- Elmでは
   Debug.log "Random" n
   return (model, Cmd.none)
   のように書けない。
-}
let _ = Debug.log "Random" n
in
  (model, Cmd.none)
{{< /highlight >}}

## リストの乱数生成器

{{< highlight elm >}}
randomList : Int -> Random.Generator (List Int)
randomList n =
  Random.list n <| Random.int 1 6

init : () -> (Model, Cmd Msg)
init _ =
  ({ circles = []
   }
  , Random.generate GetRandomNumbers (randomList 10)
  )

type Msg
  = GetRandomNumbers (List Int)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model = 
  case msg of 
    GetRandomNumbers list -> 
      let _ = Debug.log "Random" list
      in
        (model, Cmd.none)
{{< /highlight >}}

ブラウザのデバッグコンソールを開くと、以下の文が出力される。

```
Random: [1-6の乱数リスト]
```

### Random.list

乱数のリストを作るための乱数生成器を返す。第1引数にリストの長さ、第2引数に乱数生成器を指定する。

## Circleの乱数

`Circle`において、x、y座標だけがランダムであるような乱数を作る。

{{< highlight elm >}}
randomCircleLackedText : Random.Generator (String -> Circle)
randomCircleLackedText =
  let rf = Random.float 0 600
  in
    Random.map2 (\x y -> Circle 10 x y) rf rf
  

randomCircles : Int -> Random.Generator (List Circle)
randomCircles n =
  let randomCirclesGenerator = Random.list n <| randomCircleLackedText
  in
    Random.map
      (List.indexedMap (\i c -> c (String.fromInt i)))
      randomCirclesGenerator


init : () -> (Model, Cmd Msg)
init _ =
  ({ circles = []
   }
  , Random.generate GetRandomCircles (randomCircles 10)
  )

type Msg
  = GetRandomCircles (List Circle)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model = 
  case msg of 
    GetRandomCircles circles -> 
      ({ model | circles = circles }, Cmd.none)
{{< /highlight >}}

{{< figure src="./sc02.png" width="50%" >}}

### Random.map2

2つの乱数生成器に何かしらの処理を施して、新たな乱数生成器を作る関数。

以下では、`[0,600]`の`Float`乱数を2つ使って、それを`Circle`のx、yとしたものを作るようにしている。

ただし、textについてはまだ設定できないので、引数は3つにとどめておく。すると、乱数として作られるのは`Circle`ではなく厳密には`String -> Circle`となることに注意。データコンストラクタは関数みたいなものだから、このようにカリー化ができる。

{{< highlight elm >}}
randomCircleLackedText : Random.Generator (String -> Circle)
randomCircleLackedText =
  let rf = Random.float 0 600
  in
    Random.map2 (\x y -> Circle 10 x y) rf rf
{{< /highlight >}}

### Random.map

1つの乱数生成器に何かしらの処理を施して、新たな乱数生成器を作る関数。

以下では、randomCircleLackedTextで作られた乱数にtextを付加している。ここではリストの添字をtextとしている。

{{< highlight elm >}}
randomCircles : Int -> Random.Generator (List Circle)
randomCircles n =
  let randomCirclesGenerator = Random.list n <| randomCircleLackedText
  in
    Random.map
      (List.indexedMap (\i c -> c (String.fromInt i)))
      randomCirclesGenerator
{{< /highlight >}}

少し話がそれるが、`map`系の関数は概ね次のように処理されると認識している。

1.  `M X`の`M`を取り外す &rarr; `X`になる。
2.  `X`に関数を適用 &rarr; `Y`となる。
3.  `Y`に`M`を取り付ける &rarr; `M Y`になる。

今回の`Random.map`の場合は次のように処理される。

1. `Random.Generator (List (String -> Circle))`の`Random.Generator`を取り外す &rarr; `List (String -> Circle)`になる。
2. `List (String -> Circle)`に関数を適用 &rarr; `List Circle`になる。
3. `List Circle`に`Random.Generator`を取り付ける &rarr; `Random.Generator (List Circle)`になる。

ただし上の振る舞いが`map`すべてではない。例えば`Maybe.map`は上の動きに微妙に当てまらない。

## 感想

使い始めのときは「わざわざcommandにして乱数を作るの面倒だな」と思っていたが、実際にはcommandに関するコードをあまり書くことはない。乱数生成においてコードの大半を占めるのは乱数生成器作りで、こちらの理解にかなり時間がかかった。一度慣れてしまうと、結構柔軟に様々な型の乱数が作れて便利だな、と思った。

## 参考

- [Elm初心者でもできるprintデバッグ - Qiita](https://qiita.com/miyamo_madoka/items/a5321411ef6c2d3408da)
- [Elmの乱数を使いこなす - Qiita](https://qiita.com/Keck/items/106c3d14e2b078acdc59)
