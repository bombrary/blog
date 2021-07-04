---
title: "PureScriptで作るBrainfuckインタプリタ 3/3"
date: 2021-07-03T18:59:19+09:00
draft: true
tags: ["Halogen"]
categories: ["PureScript", "Brainfuck"]
toc: true
---

## Halogenの利用

続いて、GUIでBrainfuckを動かすことをやってみる。
GUIのフレームワークとして、ここでは[purescript-halogen](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2)を使ってみる。
あまりしっかり学びきれてはいないため、分からないところはぼかして書く。

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

Elmとの比較でいうと、`State`が`Model`、`Action`が`Msg`、`render`が`view`、`handleAction`が`update`に当たる。

何やら各関数の型がごついので、これについて一応補足しておく。
型変数`query`、`output`に関しては、複数のコンポーネントを作った場合にそれら同士のやりとりで使うようだが、今回は必要ないため、型変数のままにしておく。
`H.ComponentHTML Action () m`の`()`についても同様に、複数コンポーネントを扱う場合に関わってくるものなので、今回は必要ない。
`input`は、コンポーネントの状態を初期化するときに指定する引数の型。これは入力エリア作成のときに利用する。
`m`はモナドで、`handleAction`で副作用を扱うときに必要となる。
後で`Aff`関係の処理を書きたいときに、`MonadAff m`の型クラス制約を追加する (実際は、[runUI](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2/docs/Halogen.VDom.Driver#v:runUI)のときに`m`は`Aff`に推論される)。
この辺りについて、詳しくは[Halogen Guide 02](https://github.com/purescript-halogen/purescript-halogen/blob/master/docs/guide/02-Introducing-Components.md)を参照。

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

1. プログラム入力エリアにプログラムを入力
2. 実行ボタンを押すとプログラムが実行される
3. 実行後の`iptr`、`dptr`、`memory`を表示する。
4. 実行時に出力命令を踏んだときに、出力エリアに文字が表示される。
5. 実行時に入力命令を踏んだときに、入力エリアが出現。それまでプログラムは停止し、入力を確定すると再開する。

1と2は簡単。3は`Brainfuck.State.State`の内部状態をダンプする関数を実装すれば良いだけなので、難しくない。
4は[Halogen GuideのSubscriptionの項](https://github.com/purescript-halogen/purescript-halogen/blob/master/docs/guide/04-Lifecycles-Subscriptions.md#subscriptions)を読むとできる。

5が結構悩ましく、2つの方法が思いついた。

- `interpProgram`や`interpCommand`を使わず、`handleAction`の中で`Interp`を逐次評価する。すると入力処理は`Action`の中で自然に扱える。
- [avar](https://pursuit.purescript.org/packages/purescript-avar/4.0.0)を使い、BrainfuckプログラムとComponent間でデータのやりとりをする。

後者が実装が楽なのでこれを用いる。

## プログラム入力エリアと実行結果エリアの作成

### dump関数

`src/Brainfuck/State.purs`に以下の関数を追記。

```haskell
dump :: State -> { dptr :: Int, iptr :: Int, memory :: Array Int }
dump (State s) = s
```

### componentの状態

`src/Component.purs`に戻る。以下のインポート文を追加。

```haskell
import Brainfuck as B
import Brainfuck.Env as BE
import Brainfuck.Interp  as BI
import Brainfuck.Interp.Command  as BIC
import Brainfuck.Interp.Stream  as BIS
import Brainfuck.Interp.Util  as BIU
import Brainfuck.Program as BP
import Brainfuck.State as BS
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect.Aff.Class (class MonadAff, liftAff)
import Halogen.HTML.Events as HE
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
      res <- liftAff $ B.run (BP.fromString program) BIS.defaultStream
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
      { program, stream } <- H.get
      H.modify_ _ { result = Nothing, isExecutable = false }
      res <- liftAff $ B.run (BP.fromString program) stream
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

そのために、Halogen専用のStreamを作成する必要がある。ストリームの初期化は`component`の初期化時に行う。

まず以下のインポート文を追加。

```haskell
import Data.String.CodeUnits (singleton) as CodeUnits
import Halogen.Subscription (Listener, create, notify) as HS
import Brainfuck.Interp.Stream (Stream) as BIS
```

### State、Viewの追加

出力結果を`output`として、`State`に持たせる。`Stream`も`State`に持たせる。

```haskell
type State =
  { --- 略
  , stream :: BIS.Stream
  , output :: String
  }


initialState :: forall input. input -> State
initialState _ =
  { --- 略
  , stream: BIS.defaultStream
  , output: ""
  }
```

Viewにて、出力エリア`outputArea`を追加。

```haskell
render :: forall m. State -> H.ComponentHTML Action () m
render state =
  HH.div_
    [ programArea
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
component :: forall query input output m. MonadAff m => H.Component query input output m
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

`HS.create`は`Emitter a`と`Listener a`を返す関数。`Emitter a`とはイベントの受信者であり、`Listener a`はイベントの送信者である。
イベントとはただの`a`型の値のことである。`String`でも`Int`でもなんでもありえるが、`H.subscribe`の都合上`Action`をイベントとする。

`H.subscribe emitter`を使うと、`emitter`で受け取った`Action`を`handleAction`に回すことができる。
`H.notify listener x`を使うと、`listener`に紐づいた`emitter`に対して値`x`を送ることができる。

```haskell
handleAction =
  case _ of
    Initialize -> do
      { emitter, listener } <- liftEffect HS.create
      _ <- H.subscribe emitter
      H.modify_ _ { stream = createStream listener }

    -- 略


createStream :: HS.Listener Action -> BIS.Stream
createStream listener = { input, output }
  where
    input = pure 'N' -- Not Implemented

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

`ExecuteProgram`を修正。`stream`を使って`Brainfuck`プログラムを走らせる。`output`は実行の度に空に初期化しておく。

```haskell
handleAction =
  case _ of
    -- 略

    ExecuteProgram -> do
      { program, stream } <- H.get
      H.modify_ _ { output = "" , result = Nothing, isExecutable = false }
      res <- liftAff $ B.run (BP.fromString program) stream
      H.modify_ _ { result = Just res, isExecutable = true }
```

`bundle-app`してみると、Hello, Worldのプログラムが動くようになる。

{{< figure src="img01.png" width="70%" >}}

## 入力エリアの作成

[avar](https://pursuit.purescript.org/packages/purescript-avar/4.0.0)を利用する。

{{< cui >}}
% spago install avar
{{< /cui >}}

avarパッケージは`AVar a`を提供する。これは、`a`型の値が入る「非同期の変数」を表す。
「非同期の変数」と聞くとよく分からないが、ソケット通信におけるソケットのようなものだと理解すれば良さそう。
この`AVar a`を介してデータのやりとりを行う。

`AVar a`に対し[put](https://pursuit.purescript.org/packages/purescript-avar/4.0.0/docs/Effect.Aff.AVar#v:put)で値を入れることができ、
[take](https://pursuit.purescript.org/packages/purescript-avar/4.0.0/docs/Effect.Aff.AVar#v:take)で値を取り出すことができる。
大事なのは、`take`関数は変数に値が入るまで待機するという点である。よって、以下の動作を実現できる。

1. 入力命令`,`を踏むと、入力エリアが出現(これは`H.notify`を利用すれば可能)
2. `take`関数で`AVar Char`に値が入ってくるまで待つ
3. 入力エリアに文字を入力し、確定ボタンを押すと、`put`関数によって`AVar Char`に値が入る。
4. 待機中だった`take`関数が完了し、Brainfuckプログラムの動作が再開する。


以下のインポート文を追加しておく。

```haskell
import Effect.Aff.AVar (AVar, put, take) as AVar
import Data.String.CodeUnits (take, toChar) as CodeUnits
```

### Stateの追加

以下のフィールドを追加。

- `avar`: Brainfuckプログラムと入力エリアをつなぐ変数
- `input`: 入力エリアに入っている文字
- `isInputEnabled`: 入力エリアが表示されているかどうか

```haskell
type State =
  { -- 略
  , avar :: AVar.AVar Char
  , input :: String
  , isInputEnabled: Boolean
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

main :: Effect Unit
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

- `RequestInput`: Brainfuckプログラムが`,`命令を踏んだときに起こる。
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
  -- 略

    ExecuteProgram -> do
      { program, stream } <- H.get
      H.modify_ _ { output = "" , result = Nothing }
      res <- liftAff $ B.run (BP.fromString program) stream
      H.modify_ _ { result = Just res }


createStream :: HS.Listener Action -> AVar.AVar Char -> BIS.Stream
createStream listener avar = { input, output }
  where
    input = do
      liftEffect $ HS.notify listener RequestInput
      liftAff $ AVar.take avar

    output c =
      liftEffect $ HS.notify listener (Output c)
```

### Viewの実装

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

Brainfuckプログラムの動きを可視化するためには、ステップごとのプログラムの状態をComponentに出力してあげる必要がある。
残念ながら、これを行う機能を`B.interpProgram`は持ち合わせていない。状態を出力する機能をつけた新しい`interpProgram`を作る必要がある。

### LogStateの定義

`BIS.Stream`のときと同じように、`BS.State`を引数にとって何か外部に出力する関数を作るひつようがある。
この型のエイリアスとして`LogState`を定義しておく。

`LogState`を`State`に持たせておく。

```haskell
type LogState = BS.State -> BI.Interp Unit
```

```haskell
type State =
  { -- 略
  , stateMay :: Maybe BS.State
  , logState :: LogState
  }


initialState :: AVar.AVar Char -> State
initialState avar =
  { -- 略
  , stateMay: Nothing
  , logState: \_ -> pure unit
  }
```

### Actionの定義

`RequestLogState`を追加。これは`logState`が呼び出されたときに引き起こされる`Action`。

```haskell
data Action
  = -- 略
  | RequestLogState BS.State
```

`handleAction`の`Initialize`の際に、`logState`をセットする。
これは単に`RequestLogState`を呼び出しているだけである。

`RequestLogState`が起こると、`stateMay`に現在のプログラムの状態をセットする。

```haskell
handleAction =
  case _ of
    Initialize -> do
      -- 略
      let logState state = liftEffect $ HS.notify listener (RequestLogState state) -- 追加
      H.modify_ _ { stream = createStream listener avar, logState = logState }


    RequestLogState state -> do
       H.modify_ _ { stateMay = Just state }
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
stateArea program state =
  let { iptr, dptr, memory } = BS.dump state
  in
    HH.div_
      [ programLogArea iptr program
      , memoryLogArea dptr memory
      ]


programLogArea :: forall w i. Int -> BP.Program -> HH.HTML w i
programLogArea iptr program =
  let f i cmd = if i == iptr
                  then HH.span [ HP.style "background-color: salmon;" ] [ HH.text $ show cmd ]
                  else HH.span [ HP.style "background-color: white;" ] [ HH.text $ show cmd ]
  in
    HH.div_
      (mapWithIndex f $ BP.dump program)



memoryLogArea :: forall w i. Int -> Array Int -> HH.HTML w i
memoryLogArea dptr memory =
  let f i dat = if i == dptr
                  then HH.span [ HP.style "background-color: salmon; margin-right: 1em;" ] [ HH.text $ show dat ]
                  else HH.span [ HP.style "background-color: white; margin-right: 1em;" ] [ HH.text $ show dat ]
  in
    HH.div_
      (mapWithIndex f memory)
```

### interpProgramの再定義

`logState`を入れた新しい`interpProgram`を定義する。また可視化したときに見やすくするために、`delay`関数を使って動作を遅くしている。

```haskell
interpProgram :: LogState -> BIS.Stream -> BI.Interp Unit
interpProgram logState stream = do
  program <- BE.getProgram <$> ask
  state <- get

  logState state
  liftAff $ delay (Milliseconds 100.0)

  case BS.readCommand program state of
    Just cmd -> do
      BIC.interpCommand stream cmd

      BIU.incInstPtr
      interpProgram logState stream

    Nothing ->
      pure unit
```

これに伴い`run`関数も再定義。

```haskell
run :: LogState -> BP.Program -> BIS.Stream -> Aff (BI.InterpResult Unit)
run logState program stream =
  BI.runInterp (interpProgram logState stream)
               (BE.makeEnv program)
               BS.defaultState
```

`ExecuteProgram`の処理を`run`を使ったものに修正する。

```haskell
handleAction =
  -- 略

    ExecuteProgram -> do
      { program, stream, logState } <- H.get
      H.modify_ _ { output = "" , result = Nothing, isExecutable = false }
      res <- liftAff $ run logState (BP.fromString program) stream -- 変更
      H.modify_ _ { result = Just res, isExecutable = true }
```

いい感じで可視化されている。

{{< figure src="mov01.gif" width="70%" >}}
