---
title: "Elmで超簡易Todoリスト"
date: 2019-11-10T21:08:12+09:00
tag: ["Elm"]
categories: ["Elm", "Programming"]
---

Todoリストと言っても、フィールドに入力した内容が`li`要素として追加されるだけ。

Elm習いたてなので、何か無駄があるかも。

個人的になるほどと思った点は`List.map`を利用して`li`要素を生成するところで、これは要素を生成する関数が子要素の**リスト**を引数に取るから実現できる。


{{< highlight elm >}}
import Browser
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick, onInput)

main =
  Browser.sandbox { init = init, update = update, view = view }

--Model

type alias Todo =
  { description : String
  }

type alias Model =
  { todos : List Todo
  , input : Todo
  }

init : Model
init =
  { todos = []
  , input = Todo ""
  }

type Msg = Add | Change String

--Update

update : Msg -> Model -> Model
update msg model =
  case msg of
    Add ->
      { model | todos = model.input :: model.todos }
    Change str ->
      { model | input = Todo str }

-- View

view : Model -> Html Msg
view model = 
  div []
    [ input [ type_ "text", placeholder "What will you do?", onInput Change] []
    , button [ onClick Add ] [ text "Add" ]
    , ul [] (List.map viewLi model.todos)
    ]

viewLi : Todo -> Html Msg
viewLi todo =
  li [] [ text todo.description ]
{{< /highlight >}}
