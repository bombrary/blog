---
title: "Elmメモ ドラッグ移動の実現(2) - elm-draggableの利用"
date: 2020-02-27T12:39:44+09:00
tags: ["Elm", "elm-svg", "elm-draggable"]
categories: ["Elm"]
---

[前回]({{< ref "posts/elm-drag01" >}})は`Browsert`や`Svg`などの標準的なパッケージを利用してドラッグ機能を実現した。今回は[elm-draggable](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest)というパッケージを使ってドラッグ機能を実現してみる。


## 準備

Elmのプロジェクトを作成して、`src/Main.elm`と`src/Circle.elm`を作成。

### Circle.elm

前回と同じなのでコードだけ載せる。

{{< highlight elm >}}
module Circle exposing (..)


type alias Id =
    Int


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


fromList : List CircleNoId -> Circles
fromList list =
    { all = List.indexedMap (\i c -> { id = i, x = c.x, y = c.y, r = c.r }) list
    , nextId = List.length list
    }


toList : Circles -> List Circle
toList circles =
    circles.all


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

### Main.elm

`Circles`を描画するところまで書く。

{{< highlight elm >}}
module Main exposing (..)

import Browser
import Circle as C exposing (Circle, CircleNoId, Circles, Id)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
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
    { circles : Circles
    }


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


type Msg
    = Dummy


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    ( model, Cmd.none )


view : Model -> Html Msg
view model =
    div []
        [ viewSvg model
        ]


viewSvg : Model -> Svg Msg
viewSvg model =
    S.svg
        [ style "width" "500px"
        , style "height" "500px"
        , style "border" "1px solid #000"
        ]
        [ viewCircles model
        ]


viewCircles : Model -> Svg Msg
viewCircles model =
    S.g []
        (List.map (viewCircle model) (C.toList model.circles))


viewCircle : Model -> Circle -> Svg Msg
viewCircle model circle =
    S.g [ SA.transform (translate circle.x circle.y) ]
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


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none
{{< /highlight >}}

### elm-draggableのインストール

<pre class="cui">
$ elm install zaboco/elm-draggable
</pre>

`src/Main.elm`にて、`Draggable`と`Draggable.Events`をimportする。

{{< highlight elm >}}
import Draggable as D
import Draggable.Events as DE
{{< /highlight >}}

## elm-draggableの仕組み

[Usage](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest#usage)を読むと、次のような仕組みでドラッグを管理しているとわかる。

- ドラッグの状態は、`Model`内に`drag: Draggable.DragState a`として管理する。`a`に入るのは、ドラッグ中の要素の識別子の型。
- ドラッグは`Draggable.mouseTrigger`をドラッグしたい要素に指定することで可能になる。
- ドラッグ状態の変化は`subscription`で`Draggable.subscriptions`を指定することで待ち受ける。
- `Draggable.update`で、`Model`内の`drag`を更新する。
- ドラッグ量、ドラッグ開始、ドラック終了などの細かい情報をどんな`Msg`として受けとるのかについては、`Draggable.customConfig`で指定する。`Draggable.update`の引数に乗せることによって、`Msg`を発生させているっぽい。

## Modelの追加

`drag`を追加する。ついでにドラッグ中の`Circle`の`id`を`hold`として持たせておく。`drag`は`Draggable.init`で初期化しなければいけないようなのでその通りにする。

{{< highlight elm >}}
type alias Model =
    { ...
    , hold : Maybe Id
    , drag : D.State Id
    }


init : () -> ( Model, Cmd Msg )
init _ =
    ( { ...
      , hold = Nothing
      , drag = D.init
      }
    , Cmd.none
    )
{{< /highlight >}}

## ドラッグイベントの指定

`Draggable.mouseTrigger`を`circle`要素に指定する。第1引数には、ドラッグの対象となる要素の識別子を指定する。今回は`Circle`の`Id`を指定する。

{{< highlight elm >}}
type Msg
    = DragMsg (D.Msg Id)

...

viewCircle : Model -> Circle -> Svg Msg
viewCircle model circle =
    S.g [ ... ]
        [ S.circle
            [ ...
            , D.mouseTrigger circle.id DragMsg
            ]
            []
        ]
{{< /highlight >}}


ドキュメントに明言はされていないが、おそらく`mouseTrigger`はマウスが押下されたときに起こるイベント。ドラッグ中は`Draggable.subscriptions`で監視する。

{{< highlight elm >}}
subscriptions : Model -> Sub Msg
subscriptions model =
    D.subscriptions DragMsg model.drag
{{< /highlight >}}

## ドラッグイベントを受け取る

`Model`が持つ`drag`はドラッグ状態(ドラッグ開始/中/終了など)を持っている。ただし、この状態を直接のぞくことはできない。ドラッグ状態は`Msg`として取得する。具体的には、以下のようにする。

まず、どんな状態が欲しいのかを`Msg`として定義する。`D.Delta`とはマウスの移動量を表す型で、`(Float, Float)`のエイリアス。

{{< highlight elm >}}
type Msg
    = DragMsg (D.Msg Id)
    | OnDragStart Id
    | OnDragBy D.Delta
    | OnDragEnd
{{< /highlight >}}

どの`Msg`にどの状態を対応させるのかを、`D.customConfig`に定義する。`Draggable.Event.onDragStart`はドラッグ開始を意味する。`Draggable.Event.onDragBy`はドラッグ中を意味する。`Draggable.Event.onDragStart`はドラッグ終了を意味する。それぞれの状態がどんな情報を持っているのかについては[ドキュメント](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest/Draggable-Events)を読むと分かる。

{{< highlight elm >}}
dragConfig : D.Config Id Msg
dragConfig =
    D.customConfig
        [ DE.onDragStart OnDragStart
        , DE.onDragBy OnDragBy
        , DE.onDragEnd OnDragEnd
        ]
{{< /highlight >}}

`DragMsg`を受け取ったとき、`Draggable.upate`を用いて`drag`を更新する。この際に、上で定義した`dragConfig`を利用する。恐らくこのときに、`OnDragStart Id`、`OnDragBy D.Delta`、`OnDragEnd`のいずれかを発生させるようなコマンドが作られる。

{{< highlight elm >}}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        DragMsg dragMsg ->
            D.update dragConfig dragMsg model
{{< /highlight >}}

そこで、各ドラッグ状態に対応した`Msg`について、`Model`の更新処理を書く。

{{< highlight elm >}}
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ...

        OnDragStart id ->
            ( { model | hold = Just id }
            , Cmd.none
            )

        OnDragBy ( dx, dy ) ->
            ( { model
                | circles = updateCircles model dx dy
              }
            , Cmd.none
            )

        OnDragEnd ->
            ( { model | hold = Nothing }
            , Cmd.none
            )


updateCircles : Model -> Float -> Float -> Circles
updateCircles model dx dy =
    case model.hold of
        Nothing ->
            model.circles

        Just id ->
            C.update id
                (\c -> { c | x = c.x + dx, y = c.y + dy })
                model.circles
{{< /highlight >}}

これで円をドラッグして移動できるようになった。「ドラッグ中は円の色を変える」処理については、前回とまったく同じなので省略。


## 補足: Msgを発行するコマンド

`OnDragStart`や`OnDragBy`はどこから発行されているのか、については[Usage](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest/#usage)の最初の段落で述べられている。


どうやら、任意の`Msg`を作るコマンドは、`Task`を用いて作ることができるようだ。例えば以下のようにすると、`Foo`を発行するコマンドを作成することができる。

{{< highlight elm >}}
Task.perform identity (Task.succeed Foo)
{{< /highlight >}}

`Task.succeed Foo`で、常に`Foo`という値を返す`Task`を作成する。`Task.perform`は、第2引数の`Task`を実行して、その結果を第1引数に適用して`Msg`を発行する。`identity`は恒等関数なので、結局`Foo`そのものを`Msg`として発行する。

この手法については[Elm-CommunityのFAQ](http://faq.elm-community.org/#how-do-i-generate-a-new-message-as-a-command)にも載っている。しかしそこにも書かれているが、わざわざコマンドを作成して非同期処理にするよりも、単に`update`を再帰呼び出しすれば十分なことが多い。

つまり、

{{< highlight elm >}}
update : Msg -> Model -> Cmd Msg
update msg model =
    Foo ->
      ...

    Bar ->
      (model
      , Task.perform identity (Task.succeed Foo)
      )
{{< /highlight >}}

とするより、

{{< highlight elm >}}
update : Msg -> Model -> Cmd Msg
update msg model =
    Foo ->
      ...

    Bar ->
      update Foo model
{{< /highlight >}}

とすれば十分なことが多い。

ただ前者を用いた良いケースもあるようで、FAQでは、

<blockquote>
The former option may be attractive when recursive calls to update could cause an infinite loop, or for authors of reusable components interested in creating a clean encapsulation of their library’s internal behavior.

意訳: 前者の選択肢は、updateを再帰呼び出しすると無限ループを引き起こしたり、また再利用可能なコンポーネントの作者が、ライブラリの内部状態をきれいにカプセル化することに関心がある場合に魅力的かもしれない。
</blockquote>

とある。

## 参考

- [elm-draggable](https://package.elm-lang.org/packages/zaboco/elm-draggable/latest/)
- [Task](https://package.elm-lang.org/packages/elm/core/latest/Task)
