---
title: "PureScriptで作るBrainfuckインタプリタ 4/4 Halogenの利用"
date: 2021-07-09T23:15:00+09:00
tags: ["Halogen"]
categories: ["PureScript", "Brainfuck"]
toc: true
---

## Halogenの利用

続いて、GUIでBrainfuckを動かすことをやってみる。
GUIのフレームワークとして、ここでは[purescript-halogen](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2)を使ってみる。
Halogenについてはまだ勉強中で、この記事は解説記事というより勉強記録である(いままでの記事もそうではあるのだが)。

{{< cui >}}
% spago install halogen
{{< /cui >}}

### 雛形

`src/Main.purs`を以下のようにする。
ここのコードはほとんど[Halogen Guide](https://github.com/purescript-halogen/purescript-halogen/tree/master/docs/guide)と同様。
関数名的におそらく、`body`要素を取得して、その中で`component`を走らせるのだと思う。

```haskell
module Main where

import Prelude

import Effect (Effect)
import Halogen.Aff (awaitBody, runHalogenAff) as HA
import Halogen.VDom.Driver (runUI)
import Component (component)


main :: Effect Unit
main = HA.runHalogenAff do
  body <- HA.awaitBody
  runUI component unit body
```

`component`は`src/Component.purs`で定義する。とりあえず雛形を作成。

```haskell
module Component where

import Prelude

import Halogen as H
import Halogen.HTML as HH


data Action
  = Dummy


type State =
  {}


initialState :: forall input. input -> State
initialState _ =
  {}


component :: forall query input output m. H.Component query input output m
component =
  H.mkComponent
    { initialState
    , render
    , eval: H.mkEval $ H.defaultEval { handleAction = handleAction }
    }


render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.p_ [ HH.text "Hello" ]


handleAction :: forall output m. Action -> H.HalogenM State Action () output m Unit
handleAction =
  case _ of
    Dummy ->
      pure unit
```

[Halogen Guide 02](https://github.com/purescript-halogen/purescript-halogen/blob/master/docs/guide/02-Introducing-Components.md)の2段落目によると、Componentとは、
「入力を受け付けて、HTMLを生成するもの」のこと。さらにComponentは内部状態を持っている。そして何かイベントを定義することができ、それに応じて内部状態を変えたり、副作用を起こしたりできる。

Halogenにおいて、状態は *State*、イベントは *Action*、と呼ばれる。`render`でHTMLを生成することができる。`handleAction`で Action を補足し、何かしらの処理を行うことができる。
Elmとの比較でいうと、State が Model、Action が Msg、render が view、handleAction が update に当たる。

何やら各関数の型がごついので、これについて一応補足しておく。
型変数`query`、`output`に関しては、複数のコンポーネントを作った場合にそれら同士のやりとりで使うようだが、今回は必要ないため、型変数のままにしておく。
`H.ComponentHTML Action () m`の`()`についても同様に、複数コンポーネントを扱う場合に関わってくるものなので、今回は必要ない。
`input`は、コンポーネントの状態を初期化するときに指定する引数の型。これは入力エリア作成のときに利用する。
`m`はモナドで、`handleAction`で副作用を扱うときに必要となる。
後で`Aff`関係の処理を書きたいときに、`MonadAff m`の型クラス制約を追加する (実際は、[runUI](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2/docs/Halogen.VDom.Driver#v:runUI)のときに`m`は`Aff`に推論される)。


この時点で`bundle-app`してみる。

{{< cui >}}
% spago bundle-app -t dist/Main.js
{{< /cui >}}

`dist/`にて以下のhtmlファイルを作って開くと、`Hello`とだけ表示される。

```haskell
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
  </head>
  <body>
    <script src="Main.js"></script>
  </body>
</html>
```

## 仕様

1. プログラム入力エリアにプログラムを入力し、実行ボタンを押すとプログラムが実行される
2. 実行結果と実行後の`iptr`、`dptr`、`memory`を表示する。
3. 実行時に出力命令を踏んだときに、出力エリアに文字が表示される。
4. 実行時に入力命令を踏んだときに、入力エリアが出現。それまでプログラムは停止し、入力を確定すると再開する。

1と2は簡単。3は`Brainfuck.State.State`の内部状態をダンプする関数を実装すれば良いだけなので、難しくない。
4は[Halogen GuideのSubscriptionの項](https://github.com/purescript-halogen/purescript-halogen/blob/master/docs/guide/04-Lifecycles-Subscriptions.md#subscriptions)を読むとできる。

5が結構悩ましく、2つの方法が思いついた。

- `interpProgram`や`interpCommand`を使わず、`handleAction`の中で`Interp`を逐次評価する。すると入力処理は`Action`の中で自然に扱える。
- [avar](https://pursuit.purescript.org/packages/purescript-avar/4.0.0)を使い、BrainfuckインタプリタとComponent間でデータのやりとりをする。

後者が実装が楽なのでこれを用いる。

## プログラム入力エリアと実行結果エリアの作成

### Stateの追加

`src/Component.purs`に戻る。以下のインポート文を追加。

```haskell
import Brainfuck (run) as B
import Brainfuck.Interp.Stream (defaultStream) as BIS
import Brainfuck.Interp.Log (noLog) as BIL
import Brainfuck.State (State(..)) as BS
import Brainfuck.Interp (InterpResult) as BI
import Brainfuck.Program (fromString) as BP
import Data.Maybe (Maybe(..))
import Data.Either (Either(..))
import Effect.Aff.Class (class MonadAff)
import Effect.Class (liftEffect)
import Halogen.HTML.Events as HE
import Halogen.HTML.Properties as HP
```

状態を決める。

```haskell
type State =
  { program :: String
  , result :: Maybe (BI.InterpResult Unit)
  }


initialState :: forall input. input -> State
initialState _ =
  { program: ""
  , result: Nothing
  }
```

次の`Action`を定義する。

- `ChangeProgram`: プログラム入力エリアが変更された場合に起こる。
- `ExecuteProgram`: プログラム実行ボタンが押されたときに起こる。

```haskell
data Action
  = ChangeProgram String
  | ExecuteProgram
```

Viewは次のようにする。プログラム入力エリア、実行ボタン、実行結果を表示する。
入力が変化したとき、クリックされたときはそれぞれ`HE.onValueChange`、`HE.onClick`で補足できる。
関数の引数に、起こる`Action`を指定する。

```haskell
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div_
    [ programArea
    , case state.result of
        Just res ->
          interpResult res

        Nothing ->
          HH.div_ []
    ]


programArea :: forall w. HH.HTML w Action
programArea =
  HH.div_
    [ HH.textarea [ HE.onValueChange ChangeProgram ]
    , HH.button [ HE.onClick (\_ -> ExecuteProgram) ] [ HH.text "Execute" ]
    ]


interpResult :: forall w i. BI.InterpResult Unit -> HH.HTML w i
interpResult { result, state } =
  let { iptr, dptr, memory } = BS.dump state
      message =
        case result of
          Right _ ->
            "Succeed"

          Left err ->
            show err
  in
    HH.div_
      [ HH.div_ [ HH.text ("Result: " <> message) ]
      , HH.div_
          [ HH.ul_
              [ HH.li_ [ HH.text ("iptr: " <> show iptr) ]
              , HH.li_ [ HH.text ("dptr: " <> show dptr) ]
              , HH.li_ [ HH.text ("memory: " <> show memory) ]
              ]
          ]
      ]
```

`handleAction`を実装。`liftAff`を使う都合上、`MonadAff`の型クラス制約を加える。

```haskell
handleAction :: forall output m. MonadAff m => Action -> H.HalogenM State Action () output m Unit
handleAction =
  case _ of
    ChangeProgram program ->
      H.modify_ _ { program = program }

    ExecuteProgram -> do
      { program } <- H.get
      res <- liftEffect $ B.run BIS.defaultStream BIL.noLog (BP.fromString program)
      H.modify_ _ { result = Just res }
```

`component`にも`MonadAff`を加える。

```haskell
component :: forall query input output m. MonadAff m => H.Component query input output m
```

`bundle-app`すると以下のようにテキストエリアとボタンが出現し、テキストエリアにBrainfuckプログラムを入力してExecuteボタンを押すと、実行結果が下に出力される。
本当はCSSをいじって見栄えをよくしたいが、今回はやらない。

{{< figure src="img00.png" width="70%" >}}

### 実行中は実行ボタンが押せないようにする

Brainfuckプログラムが多重実行されるのを防ぐために、実行が終わるまでボタンが押せないようにする。

`State`に実行可能かどうかのフラグを追加する。

```haskell
type State =
  { -- 略
  , isExecutable :: Boolean
  }


initialState _ =
  { -- 略
  , isExecutable: true
  }
```

`isExecutable`を使ってボタンが押せるか押せないかを設定。

```haskell
render state =
  HH.div_
    [ programArea state.isExecutable -- 引数追加
      -- 略
    ]


-- 引数追加
programArea :: forall w. Boolean -> HH.HTML w Action
programArea isExecutable =
  HH.div_
    [ HH.textarea [ HE.onValueChange ChangeProgram ]
    , HH.button
        [ HE.onClick (\_ -> ExecuteProgram)
        , HP.enabled isExecutable -- 追加
        ]
        [ HH.text "Execute" ]
    ]
```

実行時に`isExecutable = false`にして、実行後に`isExecutable = true`にする。

```haskell
handleAction =
   -- 略
    ExecuteProgram -> do
      { program } <- H.get
      H.modify_ _ { result = Nothing, isExecutable = false }
      res <- liftEffect $ B.run BIS.defaultStream BIL.noLog (BP.fromString program)
      H.modify_ _ { result = Just res, isExecutable = true }
```

## 出力エリアの作成

[halogen-subscriptions](https://pursuit.purescript.org/packages/purescript-halogen-subscriptions/1.0.0)パッケージを利用する。

{{< cui >}}
% spago install halogen-subscriptions
{{< /cui >}}

halogen-subscriptionsを使うと、`component`の外部から`Action`を通知することができるようになる。これを用いて、以下の処理を実装する。

- `Branfuck.Stream.Stream`の`output`フィールドは、`Output Char`という`Action`を通知する。
- `Output Char`を通知すると、`component`は文字を出力する。


そのために、Halogen専用のStreamを作成する必要がある。問題はそのStreamをどこに置くかだが、これは2通り考えられる。

- Componentのinputとして与える。これは`Main.purs`の`runUI`の引数で与えられる。
- `State`のフィールドとして与え、その初期化は`handleAction`で行う。

後者の欠点はStreamが常に`Maybe`に包まれてしまうことだが、前者に比べると実装が簡単なので後者を採用する。

まず以下のインポート文を追加。

```haskell
import Brainfuck.Interp.Stream (Stream(..)) as BIS
import Data.String.CodeUnits (singleton) as CodeUnits
import Data.Traversable (for_)
import Effect.Aff (Aff)
import Effect.Aff.Class (liftAff)
import Halogen.Subscription as HS
```

`for_`関数を使いたいので、以下の関連パッケージをインストール。

{{< cui >}}
spago install foldable-traversable
{{< /cui >}}

### State、renderの追加

出力結果を`output`として、`State`に持たせる。`Stream`も`State`に持たせる。

```haskell
type State =
  { --- 略
  , streamMay :: Maybe (BIS.Stream Aff)
  , output :: String
  }


initialState _ =
  { --- 略
  , streamMay: Nothing
  , output: ""
  }
```

Viewにて、出力エリア`outputArea`を追加。

```haskell
render state =
  HH.div_
    [ programArea state.isExecutable
    , outputArea state.output -- 追加
    , case state.result of
        Just res ->
          interpResult res

        Nothing ->
          HH.div_ []
    ]

-- 追加
outputArea :: forall w i. String -> HH.HTML w i
outputArea output =
  HH.div_
    [ HH.p_ [ HH.text ("Output: " <> output ) ] ]
```

### Actionの追加

以下の2つの値を追加する。

- `Initialize`: `component`の初期化の際に起こる。
- `Output Char`: Branfuckの出力命令を踏んだときに起こる。

```haskell
data Action
  = Initialize -- 追加
  | ChangeProgram String
  | ExecuteProgram
  | Output Char -- 追加
```

`component`の初期化の処理を`Initialize`に任せるために、`H.defaultEval`の`initialize`フィールドを設定する。

```haskell
component =
  H.mkComponent
    { -- 略
    , eval: H.mkEval $ H.defaultEval
        { handleAction = handleAction
        , initialize = Just Initialize -- 追加
        }
    }
```

### Streamの作成

`handleAction`の`case`文に、`Initialize`を付け足す。

```haskell
handleAction =
  case _ of
    Initialize -> do
      { emitter, listener } <- liftEffect HS.create
      _ <- H.subscribe emitter
      H.modify_ _ { streamMay = Just $ createStream listener }

    -- 略


createStream :: HS.Listener Action -> BIS.Stream Aff
createStream listener = BIS.Stream { input, output }
  where
    input = pure 'N'

    output c =
      liftEffect $ HS.notify listener (Output c)
```

`Output c`を追加。`c`を`output`に付け足す処理を行う。

```haskell
handleAction =
  case _ of
    -- 略

    Output c ->
      H.modify_ (\s -> s { output = s.output <> (CodeUnits.singleton c) })
```

`HS.create`は`Emitter a`と`Listener a`を返す関数。`Emitter a`とはイベントの受信者であり、`Listener a`はイベントの送信者である。
ここでのイベントとは`a`型の値のことである。`String`でも`Int`でもなんでもありえるが、`H.subscribe`の都合上`Action`をイベントとする。

`H.subscribe emitter`を使うと、`emitter`で受け取った`Action`を`handleAction`に回すことができる。
`HS.notify listener x`を使うと、`listener`に紐づいた`emitter`に対して値`x`を送ることができる。


続いて、`ExecuteProgram`を修正。`stream`を使って`Brainfuck`プログラムを走らせる。`output`は実行の度に空に初期化しておく。

```haskell
handleAction =
  case _ of
    -- 略

    ExecuteProgram -> do
      { program, streamMay } <- H.get
      for_ streamMay \s -> do
          H.modify_ _ { output = "" , result = Nothing, isExecutable = false }
          res <- liftAff $ B.run s BIL.noLog (BP.fromString program)
          H.modify_ _ { result = Just res, isExecutable = true }
```

(**補足**) `for_`について。これは他言語のforループみたいに「与えられた配列一つ一つに対して何か処理をする」ような場合に用いられるが、
以下のように、「`Maybe`型の値が`Just`なら何か処理を行い、`Nothing`なら何もしない」ような場合にも使える。
`case`文を書かずに済むので、コードが若干見易くなる。


`bundle-app`してみると、Hello, Worldのプログラムが動くようになる。

{{< figure src="img01.png" width="70%" >}}

## 入力エリアの作成

[avar](https://pursuit.purescript.org/packages/purescript-avar/4.0.0)を利用する。

{{< cui >}}
% spago install avar
{{< /cui >}}

avarパッケージは`AVar a`を提供する。これは、`a`型の値が入る「非同期の変数(**a**synchronous **var**iable)」を表す。
「非同期の変数」と聞くとよく分からないが、ソケット通信におけるソケットのようなものだと理解すれば良さそう。
この`AVar a`を介してデータのやりとりを行う。

`AVar a`に対し[put](https://pursuit.purescript.org/packages/purescript-avar/4.0.0/docs/Effect.Aff.AVar#v:put)で値を入れることができ、
[take](https://pursuit.purescript.org/packages/purescript-avar/4.0.0/docs/Effect.Aff.AVar#v:take)で値を取り出すことができる。
大事なのは、`take`関数は変数に値が入るまで待機するという点である。よって、以下の動作を実現できる。

1. 入力命令`,`を踏むと、入力エリアが出現(これは`H.notify`を利用すれば可能)
2. `take`関数で`AVar Char`に値が入ってくるまで待つ
3. 入力エリアに文字を入力し、確定ボタンを押すと、`put`関数によって`AVar Char`に値が入る。
4. 待機中だった`take`関数が完了し、Brainfuckインタプリタの動作が再開する。


以下のインポート文を追加しておく。

```haskell
import Effect.Aff.AVar (AVar, put, take) as AVar
import Data.String.CodeUnits (take, toChar) as CodeUnits
```

### Stateの追加

以下のフィールドを追加。

- `avar`: Brainfuckインタプリタと入力エリアをつなぐ変数
- `input`: 入力エリアに入っている文字
- `isInputEnabled`: 入力エリアが表示されているかどうか

```haskell
type State =
  { -- 略
  , avar :: AVar.AVar Char
  , input :: String
  , isInputEnabled :: Boolean
  }
```

[empty](https://pursuit.purescript.org/packages/purescript-avar/4.0.0/docs/Effect.Aff.AVar#v:empty)を利用することで
空の`AVar Char`を作成することができるが、これは`Aff`に包まれて返ってきてしまう。
そこで、以下のように`initialState`の引数に`AVar Char`を指定する。

```haskell
initialState :: AVar.AVar Char -> State
initialState avar =
  { -- 略
  , avar
  , input: ""
  , isInputEnabled: false
  }
```

この引数はどこから与えられるのかというと、`src/Main.purs`の`runUI`で与えられる。

```haskell
import Effect.Aff.AVar (empty) as AVar --追加

main = HA.runHalogenAff do
  body <- HA.awaitBody
  avar <- AVar.empty -- 追加
  runUI component avar body -- 引数をunitからavarに変更。
```

`input`が`AVar Char`になったのに伴い、`src/Component.purs`の`component`の引数を変更。

```haskell
component :: forall query output m. MonadAff m => H.Component query (AVar.AVar Char) output m
```


### Actionの追加

3つの`Action`を追加

- `RequestInput`: Brainfuckインタプリタが`,`命令を踏んだときに起こる。
- `ChangeInput String`: 入力エリアにテキストを入力したときに起こる
- `ConfirmInput`: 入力確定ボタンが押されたときに起こる。

```haskell
data Action
  = -- 略
  | RequestInput
  | ChangeInput String
  | ConfirmInput
```

`handleAction`に追加。

```haskell
handleAction =
  -- 略

    RequestInput ->
      H.modify_ _ { isInputEnabled = true }

    ChangeInput input ->
      H.modify_ _ { input = input }

    ConfirmInput -> do
      { avar, input } <- H.get
      case CodeUnits.toChar $ CodeUnits.take 1 input of
        Just c -> do
          H.modify_ _ { input = "", isInputEnabled = false } -- (*1)
          liftAff $ AVar.put c avar -- (*2)

        Nothing ->
          pure unit
```

(**注意**)  `(*1)`と `(*2)`を逆にすると正常に動作しないことに注意。`,`が2回以上現れるプログラムで、入力エリアが1度しか現れない。
その理由は`isInputEnabled`が`false`になるタイミングと2回目の`RequestInput`が投げられるタイミングを考えると分かる。
BrainfuckとComponent間でのデータのやりとりはある種の通信と捉えられるが、通信を扱うときには処理を行うタイミングについてより慎重になる必要がありそう。

`stream`が`avar`を使えるように、`createStream`の引数を変更する。

```haskell
handleAction =
  case _ of
    Initialize -> do
      { emitter, listener } <- liftEffect HS.create
      _ <- H.subscribe emitter
      H.modify_ \s -> s { streamMay = Just $ createStream listener s.avar }

    -- 略


createStream :: HS.Listener Action -> AVar.AVar Char -> BIS.Stream Aff
createStream listener avar = BIS.Stream { input, output }
  where
    input = do
      liftEffect $ HS.notify listener RequestInput
      liftAff $ AVar.take avar

    output c =
      liftEffect $ HS.notify listener (Output c)
```

### renderの実装

入力エリアを実装する。

```haskell
render state =
  HH.div_
    [ programArea state.isExecutable
    -- 以下3行を追加
    , if state.isInputEnabled 
        then inputArea
        else HH.div_ []
    , outputArea state.output
    -- 略
    ]


-- 追加
inputArea :: forall w. HH.HTML w Action
inputArea =
  HH.div_
    [ HH.input
        [ HP.type_ HP.InputText
        , HE.onValueChange ChangeInput
        ]
    , HH.button
        [ HE.onClick (\_ -> ConfirmInput) ]
        [ HH.text "input" ]
    ]
```

3文字の入力を促して、アルファベットを1ずらして出力するBrainfuckプログラムを書いてみる。

{{< figure src="mov00.gif" width="70%" >}}

結果が`bcd`になってくれている。


## プログラムの実行中の様子を可視化する

Brainfuckインタプリタの動きを可視化するためには、ステップごとのプログラムの状態をComponentに出力してあげる必要がある。
これを実装するには前回実装した、`Brainfuck.Interp.Log`の`Log m`を使えば良い。具体的には、以下の手順を実装する。

1. Brainfuckインタプリタの各ステップで`Log m`の`onState`が呼ばれる。このとき`RequestLogState state`という`Action`が通知される。
2. `RequestLogState state`を`handleAction`で受け取り、`State`のフィールドとして格納される。
3. `render`で`state`を描画する。

以下のimport文を追加。

```haskell
import Brainfuck.Interp.Log (Log(..)) as BIL
import Brainfuck.Program (Program(..)) as BP
import Data.Array (mapWithIndex) as Array
import Effect.Aff (delay, Milliseconds(..))
```

### Stateの定義

 `Log m`を`State`のフィールドに持たせる。

```haskell
type State =
  { -- 略
  , logMay :: Maybe (BIL.Log Aff)
  , stateMay :: Maybe (BS.State)
  }


initialState :: AVar.AVar Char -> State
initialState avar =
  { -- 略
  , logMay: Nothing
  , stateMay: Nothing
  }
```

### Logの定義

Logを作成する関数`createLogState`を作る。これは`RequestLogState state`を通知する。

```haskell
createLog :: HS.Listener Action -> BIL.Log Aff
createLog listener = BIL.Log
    { onStart: pure unit
    , onState
    , onCmd: \_ -> pure unit
    , onEnd: pure unit
    }
  where
    onState state = do
      liftEffect $ HS.notify listener (RequestLogState state)
      liftAff $ delay (Milliseconds 100.0)
```


### Actionの定義

`RequestLogState`を追加。

```haskell
data Action
  = -- 略
  | RequestLogState BS.State
```

`handleAction`の`Initialize`の際に、`logMay`をセットする。

`RequestLogState`が起こると、`stateMay`に現在のプログラムの状態をセットする。

`ExecuteProgram`の`B.run`の引数にLogが指定できるよう修正。

```haskell
handleAction =
  case _ of
    Initialize -> do
      { emitter, listener } <- liftEffect HS.create
      _ <- H.subscribe emitter
      H.modify_ \s ->
        s { streamMay = Just $ createStream listener s.avar
          , logMay = Just $ createLog listener -- 追加
          }


    RequestLogState state -> do
       H.modify_ _ { stateMay = Just state }


    ExecuteProgram -> do
      { program, streamMay, logMay } <- H.get
      for_ streamMay \s ->
        for_ logMay \l -> do
          H.modify_ _ { output = "" , result = Nothing, isExecutable = false }
          res <- liftAff $ B.run s l (BP.fromString program)
          H.modify_ _ { result = Just res, isExecutable = true }
```

### Viewの定義

現在の状態を表示するエリアを作成。
インストラクションポインタの指す命令、メモリの指す命令には色をつけて表示する。
`memory`の表示については要素間の間隔が詰まっていて見づらいため、`margin-right`を指定している。


```haskell
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div_
    [ -- 略
    , case state.stateMay of
        Just s ->
          stateArea (BP.fromString state.program) s

        Nothing ->
          HH.div_ []
    , -- 略
    ]


stateArea :: forall w i. BP.Program -> BS.State -> HH.HTML w i
stateArea program (BS.State { iptr, dptr, memory }) =
  HH.div_
    [ programLogArea iptr program
    , memoryLogArea dptr memory
    ]


mapWithASpecialIndex :: forall a b. Int -> (a -> b) -> (a -> b) -> Array a -> Array b
mapWithASpecialIndex j fThen fElse =
  Array.mapWithIndex (\i x -> if i == j then fThen x else fElse x)


programLogArea :: forall w i. Int -> BP.Program -> HH.HTML w i
programLogArea iptr (BP.Program program) =
  HH.div_ $
    mapWithASpecialIndex iptr
      (\cmd -> HH.span [ HP.style "background-color: salmon;" ] [ HH.text $ show cmd ])
      (\cmd -> HH.span [ HP.style "background-color: white;" ] [ HH.text $ show cmd ])
      program


memoryLogArea :: forall w i. Int -> Array Int -> HH.HTML w i
memoryLogArea dptr memory =
  HH.div_ $
    mapWithASpecialIndex dptr
      (\dat -> HH.span [ HP.style "background-color: salmon; margin-right: 1em;" ] [ HH.text $ show dat ])
      (\dat -> HH.span [ HP.style "background-color: white; margin-right: 1em;" ] [ HH.text $ show dat ])
      memory
```


いい感じで可視化されている。

{{< figure src="mov01.gif" width="70%" >}}

## ソースコードとデモ

CSSやHTML要素の順番などを微調整したバージョンを
[GitHubのRepositry](https://github.com/bombrary/brainfuck-purescript)に上げた。
実際に動くものを[GitHub Pages](https://bombrary.github.io/brainfuck-purescript/)に上げた。


## 感想とまとめ

### Brainfuckの思い出

Brainfuckとの初めての出会いは[BrainfuckをJavaScriptを使って実装する動画](https://www.nicovideo.jp/watch/sm10384056)を見つけたところからだった。
当時プログラミングは学んでおらず、書いていることや喋っている意味はまったく分からなかった。分からないけど、なんか面白そう、とは思っていた。

その2、3年後くらいにC言語を学び、力試しとしてBrainfuckを作った。とはいえ単に文字列を1文字づつ見ていくだけだし、入出力はそれぞれ`printf`と`scanf`で行う簡単なものだった。

さらに年月は経ち、大学のJavaの授業でSwingを使ったGUIアプリ作成の課題があったのだが、電卓にBrainfuckを組み込んだ。
オブジェクト指向に入門したのがこのときで、Brainfuckインタプリタをクラスとして分離して汎用性を持たせようとした記憶がある。
入力命令は面倒だと考え実装しなかった。

そして今回、PureScriptでBrainfuckを作った。

### まとめ

PureScriptでBrainfuckインタプリタを作成した。インタプリタの骨組みを作り、それがCUI、GUI両方で使えることを示した。
インタプリタの動作の様子を可視化する仕組みも実装した。

Brainfuckなんて、抽象化を気にせずC言語で書くと、以下のように60行に満たない。

```c
#include <stdio.h>

#define S_SIZE 1100
#define D_SIZE 31000

int main(void) {
  char S[S_SIZE];
  int data[D_SIZE] = { 0 };
  int dp = 0;
  int ip;

  while (1) {
    scanf("%s", S);
    if (S[0] == 'q') break; // qを入力すると終了

    for (ip = 0; S[ip] != 0; ip++) {
      if (S[ip] == '>' && dp < D_SIZE) {
        dp++;
      } else if (S[ip] == '<' && dp > 0) {
        dp--;
      } else if (S[ip] == '+') {
        data[dp]++;
      } else if (S[ip] == '-') {
        data[dp]--;
      } else if (S[ip] == '.') {
        printf("%c", data[dp]);
      } else if (S[ip] == ',') {
        scanf("%c", &data[ip]);
      } else if (S[ip] == '[' && data[dp] == 0) {
        int cnt = 1;
        while (cnt != 0) {
          ip++;
          if (S[ip] == '\0') {
            printf("Error\n");
            return 0;
          }
          if (S[ip] == '[') cnt++;
          else if (S[ip] == ']') cnt--;
        }
      } else if (S[ip] == ']' && data[dp] != 0) {
        int cnt = -1;
        while (cnt != 0) {
          ip--;
          if (ip < 0) {
            printf("Error\n");
            return 0;
          }
          if (S[ip] == '[') cnt++;
          else if (S[ip] == ']') cnt--;
        }
      }
    }

    printf("\n");
  }
  return 0;
}
```

しかし今回PureScriptでBrainfuckを実装するにあたり、

- 命令を代数的データで扱う: 
  (文字の書き間違いにある程度は気づけるようになるし、`><+-.,[]`以外の命令セットにも対応できるようになるため。
- 入出力に汎用性を持たせる。
- 可視化をする。
- 適当にモジュールに分割する

などの制約を自分に課した結果、結構実装が大変になった。そして想像以上に長い記事となってしまった。

しかし実装に当たって初めて使ったパッケージ(avar, refs, halogen-subscriptionsなど)もあったし、
実装に当たってモナド変換子を利用できたので非常に勉強になった。
