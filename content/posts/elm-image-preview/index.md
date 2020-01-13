---
title: "Elmメモ - 画像のプレビュー機能を作る"
date: 2020-01-13T11:00:50+09:00
tags: ["Elm", "elm-file", "css", "html"]
categories: ["Elm"]
---

Elmを利用して、画像を選択してそれを表示するアプリを作る。

## ファイル読み込みの方法

`Select.file`関数を利用する。これはファイル選択用のエクスプローラを開くための`Cmd Msg`を作成してくれる。選択したファイルは`Msg`に載せられる。

適切なMIMEタイプを指定すると、エクスプローラ上にてそのタイプのファイルしか選択できなくなる。例えば、`text/plain`を選択しておけば、拡張子`.txt`のファイルしか選択できなくなる。

{{< highlight elm >}}
Select.file "MIMEタイプのリスト" "Msg"
{{< /highlight >}}

## 画像ファイルへの変換

こうして得られたファイルは`File`と呼ばれる型で保持される。

もしファイルを文字列として扱いたいなら、`File.toString`を利用する。

もし画像として扱いたいなら、`File.toUrl`を利用する。これは画像をBase64符号化した文字列を作る。これを`img`タグの`src`属性に指定すれば、画像が表示される。

## 画像を選択し、それを表示するアプリの作成

### 準備

プロジェクトを作成して、`elm/file`をインストール。

<pre class="cui">
$ elm init
$ elm install elm/file
</pre>

`src/Main.elm`の雛形を作る。

{{< highlight elm >}}
module Main exposing (..)

import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import File exposing (File)
import File.Select as Select
import Task

main =
  Browser.element
    { init = init
    , update = update
    , view = view
    , subscriptions = subscriptions
    }

type alias Model =
  {
  }

init : () -> (Model, Cmd Msg)
init _ =
  ( {
    }
  , Cmd.none
  )

type Msg
  = Msg

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  ( model
  , Cmd.none
  )

view : Model -> Html Msg
view model =
  div []
    [
    ]

subscriptions : Model -> Sub Msg
subscriptions model =
  Sub.none
{{< /highlight >}}

htmlファイルを自分で作りたいので、makeのときはjsファイルを単独で生成させる。

<pre class="cui">
$ elm make src/Main.elm --output=main.js
</pre>

`index.html`を作成し、次のようにする。

{{< highlight html >}}
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <link rel="stylesheet" href="style.css">
  </head>
  <body>
    <div id="elm"></div>
    <script src="main.js"></script>
    <script>
      const app = Elm.Main.init({
        node: document.getElementById('elm')
      })
    </script>
  </body>
</html>
{{< /highlight >}}

`style.css`も作っておく。

{{< highlight css >}}
@charset 'utf-8';
{{< /highlight >}}

これでelm reactorで見ると、真っ白なページが表示されているはず。

### model定義

以降はしばらく`src/Main.elm`で作業する。

必要なのは画像のURLだから、それ用のレコードを用意する。画像が読み込まれていない時点では存在しないため、型は`Maybe`にする。

{{< highlight elm >}}
type alias Model =
  { url : Maybe String
  }
{{< /highlight >}}

それに応じて`init`も編集。

{{< highlight elm >}}
init : () -> (Model, Cmd Msg)
init _ =
  ( { url = Nothing
    }
  , Cmd.none
  )
{{< /highlight >}}

### view定義

ボタンが押されたら、`ImageRequested`メッセージを送るようにする。

もし`model.url`が存在すれば、`src`属性にそれを指定して画像を表示する。

{{< highlight elm >}}
view : Model -> Html Msg
view model =
  div []
    [ button
        [ onClick ImageRequested
        ]
        [ text "Select Image"
        ]
    , viewImage model
    ]

viewImage : Model -> Html Msg
viewImage model =
  case model.url of
    Nothing ->
      p []
        [ text "No image" ]

    Just url ->
      img
        [ src url
        ]
        []
{{< /highlight >}}

### update定義

先ほど書いた`ImageRequested`に加え、ファイルが取得できたときに送られるメッセージ`ImageSelected`とファイルをurlに変換した時に送られるメッセージ`ImageLoaded`を定義する。

{{< highlight elm >}}
type Msg
  = ImageRequested
  | ImageSelected File
  | ImageLoaded String
{{< /highlight >}}

- `ImageRequested`が送られてきたとき: `Select.file`でエクスプローラを開く。選択し終わると`ImageSelected`メッセージが送られる。
- `ImageSelected`が送られてきたとき: `File.toUrl`でURLに変換する。これはTask型なので、`Task.perform`で`Cmd Msg`を作成する。変換が終わると`ImageLoaded`メッセージが送られる。
-  `ImageLoaded`が送られてきたとき: urlを入れたmodelを返す。

{{< highlight elm >}}
update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ImageRequested ->
      ( model
      , Select.file ["image/png"] ImageSelected
      )

    ImageSelected file ->
      ( model
      , Task.perform ImageLoaded (File.toUrl file)
      )

    ImageLoaded url ->
      ( { model | url = Just url }
      , Cmd.none
      )
{{< /highlight >}}

ボタン"Select"を押して画像を選択すると、次のように画像が右に表示される。

{{< figure src="sc01.png" width="70%" >}}

## 取り消しボタンの追加

&times;ボタンを追加して、それをクリックすると画像の表示が消えるようにする。

&times;ボタンはa要素で表現し、記号はCSSで表現することにする。a要素は画像の右上に重なるように配置したいため、CSSで`position: absolute`を指定することになる。などいろいろ考えた結果、以下のように要素を構成する。

{{< highlight elm >}}
viewImage : Model -> Html Msg
viewImage model =
    ...
    Just url ->
      div
        [ class "image-wrapper"
        ]
        [ div 
            [ class "image-container"
            ]
            [ a
                [ class "del-btn"
                , onClick DeleteClicked
                ]
                []
            , img
                [ src url
                ]
                []
            ]
        ]
{{< /highlight >}}

`Msg`に`DeleteClicked`を追加し、`update`関数にも追加をする。

{{< highlight elm >}}
type Msg
  = ...
    ...
  | DeleteClicked



update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    ...

    DeleteClicked ->
      ( { model | url = Nothing }
      , Cmd.none
      )
{{< /highlight >}}

### style.cssの編集

これでmakeした後にアプリを動かしても、a要素のサイズが0なのでボタンは現れない。これをCSSで調整する。

まずは画像とa要素をひとまとめにした領域`.image-container`を`inline-block`にすることで、画像のサイズぴったりに全体のサイズを調整する。a要素の位置を絶対座標にしたいので、`position: relative`を指定する。

{{< highlight css >}}
.image-container {
  display: inline-block;
  position: relative;
}
{{< /highlight >}}

a要素の領域は20px &times; 20pxにする。背景はグレーとし、丸みを帯びさせる。位置は右上にする。色は少し透明にしておく。マウスを乗せた時のカーソルの設定をする。

{{< highlight css >}}
.del-btn {
  width: 30px;
  height: 30px;
  border-radius: 10px;
  background-color: gray;
  position: absolute;
  top: 0;
  right: 0;
  opacity: 0.7;
  cursor: pointer;
}
{{< /highlight >}}

バツ印は擬似要素の枠線で指定する。枠線が領域中央になるように移動し、45度傾ける。枠の色は白にする。

{{< highlight css >}}
.del-btn::before {
  content: "";
  width: 20px;
  height: 1px;
  border-top: 2px solid white;
  position: absolute;
  top: 15px;
  left: 5px;
  transform: rotate(45deg);
}

.del-btn::after {
  content: "";
  width: 20px;
  height: 1px;
  border-top: 2px solid white;
  position: absolute;
  top: 15px;
  left: 5px;
  transform: rotate(-45deg);
}
{{< /highlight >}}

いい感じ。

{{< figure src="sc02.png" width="60%" >}}

## 参考

[File - file 1.0.5](https://package.elm-lang.org/packages/elm/file/latest/File)
