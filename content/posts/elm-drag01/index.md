---
title: "Elmメモ ドラッグ移動の実現(1)"
date: 2020-02-25T19:15:00+09:00
tags: ["Elm", "elm-svg"]
categories: ["Elm"]
---

ElmでSVGの要素をドラッグ移動したいと思った。ドラッグ操作を実現するパッケージに[elm-draggable](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest/)がある。今回は勉強として、それに頼らず実装することを試みる。elm-draggableを用いた方法については次回やる。

## 初期状態

詳細は省略するが、Elmプロジェクトを作成して`elm/svg`と`elm/json`をインストールしておく。

`src/Main.elm`は以下のようにしておく。`elm reactor`で動くことを確認する。

{{< highlight elm >}}
module Main exposing (..)

import Browser
import Browser.Events as BE
import Html exposing (..)
import Html.Attributes exposing (..)
import Json.Decode as JD
import Svg as S exposing (Svg)
import Svg.Attributes as SA
import Svg.Events as SE


main =
    Browser.element
        { init = init
        , update = update
        , view = view
        , subscriptions = subscriptions
        }


type alias Model =
    {}


type Msg
    = Dummy


init : () -> ( Model, Cmd Msg )
init _ =
    ( {}, Cmd.none )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


view : Model -> Html Msg
view model =
    div [] []


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
{{< /highlight >}}


## 目標

- SVGの領域に円が複数存在する
- 円をドラッグ移動できるようにしたい。
- 円のドラッグ中はその色を橙色にし、それ以外のときは白にする

## 方針

ドラッグ処理については次の処理で実現することになる。

- ドラッグ開始は`Svg.Events.onMouseDown`を`ciecle`要素に付ける
- ドラッグ中は`Svg.Events.onMouseMove`を`svg`要素に付ける
- ドラッグ終了は`Browser.Events.onMouseUp`を`subscription`で登録する

いくつかの方針が考えられ、かつ慎重に考えなければならないことは、次の3点。

- 円をどんな形で扱うか:  特に、色の情報を円に持たせるか否か
- 円の集合をどんな形で扱うか:  円が`Circle`だとして、`List Circle`にするか、`Set Circle`にするか。もしくは何か`Id`を持たせて、`Dict Id Circle`にするか、など
- ドラッグ中の円をどんな形で扱うか:  `Model`にドラッグ中の`Circle`を直接持たせるか、それとも`Circle`の`Id`を持たせるか、など。

### 今回の方針

結局何がベストなのかはよく分からないのだが、とりあえず今回は次のようにやってみる。

- 円は ( id, x座標, y座標, 半径 ) の情報を持つ。idは`Int`として扱う。
- 円の集合は`List Circle`として持つ。また、円の`id`は一意であって欲しいので、「次付与する`id`」も情報として持たせることにする。これをまとめて`Circles`と呼ぶことにする。
- ドラッグされている状態の`Circle`をの`id`を`Model`内に持たせる。具体的には、`hold : Maybe Id`としてレコードに持たせる。

### 3点目についての補足

`Model`に`Circle`を直接持たせる場合、ドラッグ中の`Circle`と`Circles`に含まれている`Circle`とのデータの同期を取る必要がある。同期を取るのは面倒なので、次のようにやる方が良い。

- ドラッグ中の`Circle`と他の`Circle`を別々に管理する
- ドラッグ開始時、`Circles`からドラッグ中の`Circle`を一旦削除して、ドラッグ終了後に再び戻す。
- 描画するときは、ドラッグ中の`Circle`と他の`Circle`を統合する

個人的にはこの処理を書くのが少し面倒に感じたので、`Model`にはドラッグ中の`Circle`の`Id`だけ持たせておいて、それを使って`Circles`内の`Circle`を操作する方針を選んだ。

ただし、`Circle`を持たせることが活きてくる状況として、「ドラッグ中に何か特別な情報を`Circle`に持たせる場合」が考えられる。例えば、ドラッグ中の円に対して、「ドラッグ開始時の座標が何だったか」「他の円との距離」を持たせる場合が考えられる。このような場合は、ドラッグ中の円とドラッグしていない円とで分けてデータを管理したほうが良さそう。

#### 追記(2020/02/26)

[elm-draggableのサンプルの1つ](https://github.com/zaboco/elm-draggable/blob/master/examples/MultipleTargetsExample.elm)に、上記と似た実装があった。ただし、ここではドラッグ中の要素`movingBox`を`Model`ではなく要素の集合`BoxGroup`内に持たせている。座標を更新したいときは`movingBox`を変更すればよいだけ。この方針も悪くない、と思った。


## Circle/Circles の定義

`src/Circle.elm`を作成し、そちらで`Circle`と`Circles`を定義する。

{{< highlight elm >}}
module Circle exposing (..)

type alias Id = Int

type alias Circle =
    { id : Id
    , x : Float
    , y : Float
    , r : Float
    }


type alias Circles =
    { all : List Circle
    , nextId : Id
    }
{{< /highlight >}}

### ユーティリティ関数の定義

`Circles`の内部表現を気にせずに扱えるように、いくつかのユーティリティ関数を定義しておく。`add`関数は円を追加したいときに呼び出す関数だが、今回は利用しない。

{{< highlight elm >}}
empty : Circles
empty =
    { all = []
    , nextId = 0
    }


type alias CircleNoId =
    { x : Float
    , y : Float
    , r : Float
    }


fromList : List CircleNoId -> Circles
fromList list =
    { all = List.indexedMap (\i c -> { id = i, x = c.x, y = c.y, r = c.r }) list
    , nextId = List.length list
    }


toList : Circles -> List Circle
toList circles =
    circles.all

add : CircleNoId -> Circles -> Circles
add c circles =
    let
        circle =
            { id = circles.nextId
            , x = c.x
            , y = c.y
            , r = c.r
            }
    in
    { circles
        | all = circle :: circles.all
        , nextId = circles.nextId + 1
    }

update : Id -> (Circle -> Circle) -> Circles -> Circles
update id f circles =
    let
        new =
            List.foldr
                (\c acc ->
                    if c.id == id then
                        f c :: acc

                    else
                        c :: acc
                )
                []
                circles.all
    in
    { circles | all = new }
{{< /highlight >}}


## 円の描画

`src/Main.elm`に戻る。次の`import`文を追加。

{{< highlight elm >}}
import Circle as C exposing (Circle, CircleNoId, Circles, Id)
{{< /highlight >}}


### Modelの変更

`Model`に`Circles`を追加しておく。`circles`としていくつかの初期データを投入しておく。

{{< highlight elm >}}
type alias Model =
    { circles : Circles
    }

...

init : () -> ( Model, Cmd Msg )
init _ =
    ( { circles =
            C.fromList
                [ CircleNoId 10 10 10
                , CircleNoId 20 100 20
                , CircleNoId 250 250 30
                ]
      }
    , Cmd.none
    )
{{< /highlight >}}

### Viewの変更

SVG描画の処理は`viewSvg`に任せる。

{{< highlight elm >}}
view : Model -> Html Msg
view model =
    div []
        [ viewSvg model
        ]


viewSvg : Model -> Svg Msg
viewSvg model =
    S.svg
        [ style "border" "1px solid #000"
        , style "width" "500px"
        , style "height" "500px"
        ]
        [ viewCircles model
        ]
{{< /highlight >}}

`Circle(s)`の描画を`viewCircle(s)`に任せる。

{{< highlight elm >}}
viewCircles : Model -> Svg Msg
viewCircles model =
    S.g []
        (List.map (viewCircle model) (C.toList model.circles))


viewCircle : Model -> Circle -> Svg Msg
viewCircle model circle =
    S.g
        [ SA.transform (translate circle.x circle.y)
        ]
        [ S.circle
            [ SA.r (String.fromFloat circle.r)
            , SA.fill "#fff"
            , SA.stroke "#000"
            ]
            []
        ]


translate : Float -> Float -> String
translate x y =
    "translate(" ++ String.fromFloat x ++ "," ++ String.fromFloat y ++ ")"
{{< /highlight >}}

ここで、`viewCircle`、`viewCircles`は`Model`を引数にとるようにした。一般に、`view`と同じく要素の描画を担う関数に関しては、`Model`を引数にとった方が、後々の修正や変更が楽になると思われる。なぜなら、`Model`こそが要素描画のための全ての情報を持っているからである。「今はCircleの情報をもとに描画してたけど、それだけじゃなくてXXの情報も必要になった」などの変更に、比較的簡単に対応できる。

ここまで実装すると、実行結果は以下のようになる。

{{< figure src="./sc01.png" width="50%" >}}

## 円をクリック中の色変化

### holdの定義

ドラッグ状態にある円を`hold`として`Model`に持たせる。

{{< highlight elm >}}
type alias Model =
    { circles : Circles
    , hold : Maybe Id
    }

...

init : () -> ( Model, Cmd Msg )
init _ =
    ( { circles = ...
      , hold = Nothing
      }
    , Cmd.none
    )
{{< /highlight >}}


### ドラッグ開始イベントの定義

circle要素に対してマウスが押下されたときに、`CircleHeld id`という`Msg`を送る。`CircleHeld`を受け取ったとき、`hold`に円のデータを入れる。

{{< highlight elm >}}
type Msg
    = CircleHeld Id

...

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        CircleHeld id ->
            ( { model | hold = Just id }
            , Cmd.none
            )

...

viewCircle : Model -> Circle -> Svg Msg
viewCircle model circle =
    S.g
        [ ...
        ]
        [ S.circle
            [ ...
            , SE.onMouseDown (CircleHeld circle.id)
            ]
            []
        ]
{{< /highlight >}}

### ドラッグ中の色の変更

`fillCircle`関数が担う。これは、ドラッグ中の円のときだけ橙色のカラーコードを返す。

{{< highlight elm >}}
viewCircle : Model -> Circle -> Svg Msg
viewCircle model circle =
    S.g
        [ ...
        ]
        [ S.circle
            [ ...
            , SA.fill (fillCircle model circle)
            ...
            ]
            []
        ]


fillCircle : Model -> Circle -> String
fillCircle model circle =
    case model.hold of
        Nothing ->
            "#fff"

        Just id ->
            if circle.id == id then
                "#f80"

            else
                "#fff"
{{< /highlight >}}


### ドラッグ終了イベントの定義

マウスが離されたときに、`CircleReleased`というメッセージを送る。特定のDOM要素に依存しないイベントを監視する場合は、`subscription`を用いる。

{{< highlight elm >}}
type Msg
    = CircleHeld Id
    | CircleReleased

...


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ...

        CircleReleased ->
            ( { model | hold = Nothing }
            , Cmd.none
            )

...

subscriptions : Model -> Sub Msg
subscriptions model =
    subHold model


subHold : Model -> Sub Msg
subHold model =
    case model.hold of
        Nothing ->
            Sub.none

        Just _ ->
            BE.onMouseUp (JD.succeed CircleReleased)
{{< /highlight >}}

`Browser.Event.onMouseUp`を用いた。`Browser.Event`で提供される関数の多くは、引数に`Json.Decode.Decoder msg`をとる。これは何をDecodeするのかというと、JSのEventオブジェクトをDecodeする。今回はEventから何も取得する必要はないので、`Json.Decode.succeed`を用いる。

実行結果は以下のようになる。

{{< figure src="./sc02.gif" >}}

## マウス位置の取得

さて円のドラッグ移動とは、より詳しくいうと「円をクリックしている間にマウスを移動すると、円がそれに追従する」機能だ。これを実現するためには、マウスの位置ではなく「マウスがどれだけ動いたか」という情報も欲しい。マウスの位置は(Mouse)Eventオブジェクトの`offsetX`と`offsetY`で取得できる。マウスの移動量は、1つ前に発火したイベントの`x` `y`の位置の差分として計算する。

補足。マウスの移動量については`movementX`と`movementY`が使えそうかなと思ったが、ドラッグ位置がずれた。[movementXの説明](https://developer.mozilla.org/en-US/docs/Web/API/MouseEvent/movementX)的にはずれなさそうなのだが。よくわからない。

### Modelの定義

`mouse : MousePosition`を定義する。「マウスがどれだけ動いたか」の情報は`dx: Float`と`dy: Float`で持たせる。

{{< highlight elm >}}
type alias Model =
    { circles : Circles
    , hold : Maybe Circle
    , mouse : MousePosition
    }


type alias MousePosition =
    { x : Float
    , y : Float
    , dx : Float
    , dy : Float
    }

...

init : () -> ( Model, Cmd Msg )
init _ =
    ( { ...
      , mouse = MousePosition 0 0 0 0
      }
    , Cmd.none
    )
{{< /highlight >}}

### マウス移動のイベント

SVG領域内の左上を原点として座標を取得したいので、SVGに対して`mousemove`イベントを登録したい。しかし`Svg.Event.onMouseMove`みたいな関数は用意されていないので、自作する。`Svg.Event.on`関数を使う。これも`Browser.Event.onMouseUp`のときと同様引数に`Json.Decode.Decoder msg`をとり、JSのEventをDecodeする。

{{< highlight elm >}}
type Msg
    = ...
    | MouseMoved Float Float

...

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ...

        MouseMoved x y ->
            let
                newMouse =
                    { x = x
                    , y = y
                    , dx = x - model.mouse.x
                    , dy = y - model.mouse.y
                    }
            in
            ( { model
                | mouse = newMouse
              }
            , Cmd.none
            )

...

viewSvg : Model -> Svg Msg
viewSvg model =
    S.svg
        [...
        , onMouseMove MouseMoved
        ]
        [ ...
        ]


onMouseMove : (Float -> Float -> msg) -> S.Attribute msg
onMouseMove msg =
    SE.on "mousemove"
        (JD.map2 msg
            (JD.field "offsetX" JD.float)
            (JD.field "offsetY" JD.float)
        )
{{< /highlight >}}

試しにマウス座標を出力してみる。

{{< highlight elm >}}
view : Model -> Html Msg
view model =
    div []
        [ ...
        , viewMousePosition model
        ]


viewMousePosition : Model -> Html Msg
viewMousePosition model =
    div []
        [ p []
            [ text (textMousePosition model.mouse) ]
        , p []
            [ text (textMouseMovement model.mouse) ]
        ]


textMousePosition : MousePosition -> String
textMousePosition mouse =
    "(" ++ String.fromFloat mouse.x ++ "," ++ String.fromFloat mouse.y ++ ")"


textMouseMovement : MousePosition -> String
textMouseMovement mouse =
    "(" ++ String.fromFloat mouse.dx ++ "," ++ String.fromFloat mouse.dy ++ ")"
{{< /highlight >}}

試しにマウスを動かしてみると、下にその座標と移動量が表示される。

{{< figure src="./sc03.png" width="50%" >}}

## 円を動かす

`MouseMoved`を受け取ったときに、`Circle`の座標を更新すればよい。

{{< highlight elm >}}

update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ...
        MouseMoved x y ->
            let
              ...
            in
            ( { model
                | mouse = newMouse
                , circles = updateCircles model newMouse
              }
            , Cmd.none
            )


updateCircles : Model -> MousePosition -> Circles
updateCircles model mouse =
    case model.hold of
        Nothing ->
            model.circles

        Just id ->
            C.update id
                (\c ->
                    { c
                        | x = c.x + mouse.dx
                        , y = c.y + mouse.dy
                    }
                )
                model.circles
{{< /highlight >}}

良い感じで動いている。

{{< figure src="./sc04.gif" width="40%" >}}
