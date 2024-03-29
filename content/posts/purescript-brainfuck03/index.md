---
title: "PureScriptで作るBrainfuckインタプリタ 3/4 CUIでの可視化"
date: 2021-07-06T10:35:00+09:00
tags: []
categories: ["PureScript", "Brainfuck"]
toc: true
---

## 動作の可視化

インタプリタ動作中における内部状態を可視化できると面白い。
そこで、インタプリタ動作中のログを出力できるような仕組みを作る。
ログは以下のタイミングで起こるようにする。

- `onStart`: インタプリタが動作したときに起こる。
- `onState state`: 各ステップで状態を取得したときに起こる。
- `onCmd cmd`: 各ステップで命令を取得できたときに起こる。
- `onEnd`: インタプリタが終了するときに起こる。

これらはイベントリスナのように、関数の形で指定する。

### Logの作成

`src/Brainfuck/Interp/Log.purs`を作成。

以下のimport文を書く。

```haskell
module Brainfuck.Interp.Log where

import Prelude

import Brainfuck.Interp (Interp)
import Brainfuck.State (State)
import Brainfuck.Command (Command)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Console (log)
```

`Log`を定義。

```haskell
newtype Log m = Log
  { onStart :: Interp m Unit
  , onState :: State -> Interp m Unit
  , onCmd :: Command -> Interp m Unit
  , onEnd :: Interp m Unit
  }
```

関連する関数を定義。

```haskell
logStart :: forall m. Log m -> Interp m Unit
logStart (Log { onStart }) = onStart


logState :: forall m. Log m -> State -> Interp m Unit
logState (Log { onState }) = onState


logCmd :: forall m. Log m -> Command -> Interp m Unit
logCmd (Log { onCmd }) = onCmd


logEnd :: forall m. Log m -> Interp m Unit
logEnd (Log { onEnd }) = onEnd
```

いくつかの`Log m`を作っておく。

```haskell
noLog :: forall m. Monad m => Log m
noLog = Log
  { onStart: pure unit
  , onState: \_ -> pure unit
  , onCmd: \_ -> pure unit
  , onEnd: pure unit
  }


debugLog :: forall m. MonadEffect m => Log m
debugLog = Log
  { onStart: liftEffect $ log "start"
  , onState: \s -> liftEffect $ log ("state:" <> show s)
  , onCmd: \c -> liftEffect $ log ("cmd: " <> show c)
  , onEnd: liftEffect $ log "end"
  }
```

### Brainfuckの修正

`src/Brainfuck.purs`を修正。まず以下のimport文を追加。

```haskell
import Brainfuck.Interp.Log (Log, logStart, logState, logCmd, logEnd, noLog, debugLog)
```

`interpProgram`について、引数に`log`を追加。`log`に関する処理をうまく挟めるように修正する。

```haskell
interpProgram :: forall m. Monad m => Stream m -> Log m -> Interp m Unit
interpProgram stream log = do
  logStart log -- 開始
  loop
  logEnd log -- 終了
  where
    loop :: Interp m Unit
    loop = do
      program <- getProgram <$> ask
      state <- get
      logState log state -- 状態
      case readCommand program state of
        Just cmd -> do
          logCmd log cmd -- 命令
          interpCommand stream cmd

          incInstPtr
          loop

        Nothing ->
          pure unit
```

`interpProgram`の引数追加に伴い`run`を修正。

```haskell
run :: forall m. Monad m => Stream m -> Log m -> Program -> m (InterpResult Unit)
run stream log program =
  runInterp (interpProgram stream log) (makeEnv program) defaultState
```

`runDefault`と`runWithLog`は、それぞれ`noLog`と`debugLog`を持たせるようにしてみる。

```haskell
runDefault :: Program -> Effect (InterpResult Unit)
runDefault program = run defaultStream noLog program


runWithLog :: forall m. MonadEffect m => Stream m -> Program -> m Unit
runWithLog stream program = do
  res <- run stream debugLog program
  liftEffect $ log $ ("\n" <> show res)
```

この時点で`spago run`してみると、ログが出力される。`bcd`の出力に改行が無くて、`bstate`、`cstate`、`dstate`と出力されているのは仕様。

{{< cui >}}
start
state:{ dptr: 0, iptr: 0, memory: [0,0,0,0,0,0,0,0,0,0] }
cmd: ,
input> a
state:{ dptr: 0, iptr: 1, memory: [97,0,0,0,0,0,0,0,0,0] }
cmd: +
state:{ dptr: 1, iptr: 2, memory: [97,0,0,0,0,0,0,0,0,0] }
cmd: ,
input> b
state:{ dptr: 1, iptr: 3, memory: [97,98,0,0,0,0,0,0,0,0] }
cmd: +
state:{ dptr: 2, iptr: 4, memory: [97,98,0,0,0,0,0,0,0,0] }
cmd: ,
input> c
state:{ dptr: 2, iptr: 5, memory: [97,98,99,0,0,0,0,0,0,0] }
cmd: -
state:{ dptr: 1, iptr: 6, memory: [97,98,99,0,0,0,0,0,0,0] }
cmd: -
state:{ dptr: 0, iptr: 7, memory: [97,98,99,0,0,0,0,0,0,0] }
cmd: >
state:{ dptr: 0, iptr: 8, memory: [98,98,99,0,0,0,0,0,0,0] }
cmd: .
bstate:{ dptr: 0, iptr: 9, memory: [98,98,99,0,0,0,0,0,0,0] }
cmd: +
state:{ dptr: 1, iptr: 10, memory: [98,98,99,0,0,0,0,0,0,0] }
cmd: >
state:{ dptr: 1, iptr: 11, memory: [98,99,99,0,0,0,0,0,0,0] }
cmd: .
cstate:{ dptr: 1, iptr: 12, memory: [98,99,99,0,0,0,0,0,0,0] }
cmd: +
state:{ dptr: 2, iptr: 13, memory: [98,99,99,0,0,0,0,0,0,0] }
cmd: >
state:{ dptr: 2, iptr: 14, memory: [98,99,100,0,0,0,0,0,0,0] }
cmd: .
dstate:{ dptr: 2, iptr: 15, memory: [98,99,100,0,0,0,0,0,0,0] }
end

{ result: (Right unit), state: { dptr: 2, iptr: 15, memory: [98,99,100,0,0,0,0,0,0,0] } }
{{< /cui >}}

## (寄り道) questionAffを別モジュールに移動

`Brainfuck.Interp.Stream`にある`questionAff`を次の節で使いたい。
これを`Node.ReadLine.Aff`の`question`関数として移動する。

`src/Node/ReadLine/Aff.purs`を作成して、内容を以下のようにする。

```haskell
module Node.ReadLine.Aff where


import Prelude
import Effect.Aff (Aff, Canceler, nonCanceler, makeAff)
import Node.ReadLine (question, Interface) as RL
import Data.Either (Either(..))
import Effect.Exception (Error) as E
import Effect (Effect)


question :: String -> RL.Interface -> Aff String
question q interface = makeAff go
  where
    go :: (Either E.Error String -> Effect Unit) -> Effect Canceler
    go handler = do
      RL.question q (handler <<< Right) interface
      pure nonCanceler
```

`src/Brainfuck/Interp/Stream.purs`を修正。まず以下の関数をインポート。

```haskell
import Node.ReadLine.Aff (question)
```

`nodeStream`の`input`を修正。

```haskell
nodeStream :: Stream Aff
nodeStream = Stream { input, output }
  where
    input = do 
      interface <- liftEffect $ RL.createConsoleInterface RL.noCompletion
      s <- liftAff $ question "input> " interface -- questionAffをquestionに変更
    --- 略
```

## エスケープシーケンスを利用したBrainfuck CUI

以下のような構成を持つUIを作りたい。

{{< cui >}}
[プログラム表示エリア]
[メモリ表示エリア]
[入出力表示エリア]
{{< /cui >}}

具体的には次のようになる。
実行中の命令の位置、メモリの位置がハイライトされるようにしたい。

{{< cui >}}
++++++++[>++++++++<-]>+.
0 65 0 0 0 0 0 0 0 0
A
{{< /cui >}}

カーソルの移動や文字色の変更を行いたいので、エスケープシーケンスを利用する。

カーソル移動で問題になるのが、位置の把握である。
出力エリアでは改行が起こる可能性があり、それによってプログラムやメモリの出力がずれてしまう。
よって、カーソルの位置データをどこかに保存しておき、適宜参照できるようにしたい。

さらに、`Stream`の`output`は1文字出力しかできないため、いままで出力した文字が把握できない。
よって、`output`で出力した文字もどこかに保存しておきたい。

そのときの問題はどこに保存するかである。保存したい情報はCUIのみで用いるため、`Brainfuck.State.State`のフィールドとして扱うことはしたくない。
できれば`Stream`と`Log`だけが共有できるような場所に保存したい。

考えた結果、思いついたのは[refs](https://pursuit.purescript.org/packages/purescript-refs/5.0.0)パッケージの`Ref a`の利用だった。
`Stream`や`Log`の実装を変えることなくデータを共有するには、`Ref a`が適切なのかなと思う。

{{< cui >}}
% spago install refs
{{< /cui >}}

### 準備

`src/Brainfuck/CUI/State.purs`を作成し、`State`を作成。その初期値を生成する関数も作成。

```haskell
module Brainfuck.CUI.State where

import Prelude

import Effect (Effect)
import Effect.Ref (Ref, new) as Ref


newtype State = State
  { output :: String
  , y :: Int
  }


init :: Effect (Ref.Ref State)
init =
  Ref.new $ State
    { output: ""
    , y: 0
    }
```

`src/Brainfuck/CUI.purs`を作成し、`Stream`と`Log`の雛形を作成。これらは`CUI.State`の`Ref`を引数にとることに注目。

```haskell
module Brainfuck.CUI where

import Prelude

import Brainfuck.Interp.Log (Log(..))
import Brainfuck.Interp.Stream (Stream(..))
import Effect (Effect)
import Effect.Ref (Ref)
import Brainfuck.CUI.State (State, init) as CUI
import Effect.Aff.Class (class MonadAff, liftAff)


cuiStream :: forall m. MonadAff m => Ref CUI.State -> Stream m
cuiStream cuiState = Stream { input, output }
  where
    input = pure 'N'

    output c = pure unit


cuiLog :: forall m. MonadAff m => Ref CUI.State -> Log m
cuiLog cuiState = Log
  { onStart
  , onState
  , onCmd: \_ -> pure unit
  , onEnd
  }
  where
    onStart = pure unit

    onState state = pure unit

    onEnd = pure unit
```

`src/Main.purs`を以下のようにする。`cuiStream`、`cuiLog`の引数はここで与える。

```haskell
module Main where

import Prelude

import Brainfuck (run) as B
import Brainfuck.Program (fromString) as BP
import Effect (Effect)
import Effect.Aff (launchAff_)

import Brainfuck.CUI (cuiLog, cuiStream)
import Brainfuck.CUI.State (init) as CUIState


main :: Effect Unit
main = do
  ref <- CUIState.init
  launchAff_ $ B.run (cuiStream ref) (cuiLog ref) (BP.fromString "++++++++[>++++++++<-]>+.")
```

### ユーティリティ作成

`src/Brainfuck/CUI/State.purs`に関数を追加。
`output`の読み取りや文字の追加の関数を定義。
`y`の修正やセッターを定義。現在のカーソル位置から行きたい位置までどれだけ離れているかを返す関数を定義。


```haskell
-- 以下のimport文を追加
import Data.String.CodeUnits (singleton) as CodeUnits


getOutput :: State -> String
getOutput (State { output }) = output


appendOutput :: Char -> State -> State
appendOutput c (State s@{ output }) =
  State s { output = output <> (CodeUnits.singleton c) }


modifyY :: (Int -> Int) -> State -> State
modifyY f (State s@{ y }) = State s { y = f y }


dist :: Int -> State -> Int
dist y0 (State { y }) = y0 - y
```

続いて、`src/Brainfuck/CUI/Util.purs`を作成。
出力関数や、カーソル移動系の関数を定義。
特に重要なのは`printAt y`で、これは`y`行目に文字列を出力することができる。

エスケープシーケンスは[こちら](https://qiita.com/PruneMazui/items/8a023347772620025ad6)を参考にした。

```haskell
module Brainfuck.CUI.Util where

import Prelude

import Brainfuck.CUI.State (dist, modifyY, State)
import Brainfuck.Interp (Interp)
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Ref (Ref, modify_, read) as Ref
import Node.Encoding (Encoding(UTF8))
import Node.Process (stdout)
import Node.Stream (writeString)
import Data.Array (replicate) as Array
import Data.String (joinWith) as String


print :: forall m. MonadEffect m => String -> Interp m Unit
print str = void $ liftEffect $ writeString stdout UTF8 str (pure unit)


printAt :: forall m. MonadEffect m => Int -> Ref.Ref State -> String -> Interp m Unit
printAt y state str = do
  moveAt y state
  clearLine
  print str


moveAt :: forall m. MonadEffect m => Int -> Ref.Ref State -> Interp m Unit
moveAt y state = do
  dist <- liftEffect (dist y <$> Ref.read state)
  move dist state
  

move :: forall m. MonadEffect m => Int -> Ref.Ref State -> Interp m Unit
move x state = do
  liftEffect $ Ref.modify_ (modifyY (_ + x)) state
  if x > 0
    then down x
    else if x < 0
           then up (-x)
           else mostLeft


down :: forall m. MonadEffect m => Int -> Interp m Unit
down n = print ("\x01b[" <> show n <> "E")


up :: forall m. MonadEffect m => Int -> Interp m Unit
up n = print ("\x01b[" <> show n <> "F")


mostLeft :: forall m. MonadEffect m => Interp m Unit
mostLeft = print "\x01b[1G"


clearLine :: forall m. MonadEffect m => Interp m Unit
clearLine = print "\x01b[2K"


newLineTimes :: forall  m.  MonadEffect m => Int -> Interp m Unit
newLineTimes n = print $ String.joinWith "" $ Array.replicate n "\n"


highlight :: String -> String
highlight s = "\x01b[7m" <> s <> "\x01b[0m"
```

### 命令列とメモリの出力

`src/Brainfuck/CUI.purs`を修正。まず以下の関数をインポート。

```haskell
import Brainfuck.CUI.Util as CUI
import Brainfuck.State (State(..))
import Brainfuck.Env (getProgram)
import Control.Monad.Reader (ask)
import Data.Array (mapWithIndex) as Array
import Effect.Aff (Milliseconds(..), delay)
import Data.String (joinWith) as String
```

特定のインデックスにのみ適用する関数を変えるバージョンのmap関数、`mapWithASpecialIndex`を定義する。
それを用いて、命令列とメモリの出力をする関数を定義。

```haskell
mapWithASpecialIndex :: forall a b. Int -> (a -> b) -> (a -> b) -> Array a -> Array b
mapWithASpecialIndex j fThen fElse =
  Array.mapWithIndex (\i x -> if i == j then fThen x else fElse x)


showProgram :: Int -> Program -> String
showProgram iptr (Program program) =
  String.joinWith "" $
    mapWithASpecialIndex iptr
      (CUI.highlight <<< show)
      show
      program


showMemory :: Int -> Array Int -> String
showMemory dptr memory =
  String.joinWith " " $
    mapWithASpecialIndex dptr
      (CUI.highlight <<< show)
      show
      memory
```

`showProgram`と`showMemory`を用いて`onState`を実装する。
カーソル下のスペースを確保するために、`onStart`で前処理を行っている。
`onEnd`では適当にカーソルを下に移動させているが、ここは後でもう少しちゃんと実装する。

```haskell
cuiLog :: forall m. MonadAff m => Ref CUI.State -> Log m
cuiLog cuiState = Log
  { onStart
  , onState
  , onCmd: \_ -> pure unit
  , onEnd
  }
  where
    onStart = do
       CUI.newLineTimes 2
       CUI.up 2

    onState (State { iptr, dptr, memory }) = do
      program <- getProgram <$> ask
      CUI.printAt 0 cuiState $ showProgram iptr program
      CUI.printAt 1 cuiState $ showMemory dptr memory
      liftAff $ delay (Milliseconds 100.0)

    onEnd =
      CUI.down 4
```

この時点で`spago run`してみるとこんな感じで動く。

{{< figure src="mov00.gif" width="70%" >}}

### 入出力

`src/Brainfuck/CUI/Util.purs`で`questionAndReadChar`を定義。

```haskell
-- 以下のimport文を追加
import Node.ReadLine.Aff (question)
import Node.ReadLine (createConsoleInterface, noCompletion, close) as RL
import Data.String.CodeUnits (toChar, take) as CodeUnits
import Control.Monad.Error.Class (throwError)
import Brainfuck.Error (Error(..))
import Effect.Aff.Class (class MonadAff, liftAff)
import Data.Maybe (Maybe(..))


questionAndReadChar :: forall m. MonadAff m => Interp m Char
questionAndReadChar = do
  interface <- liftEffect $ RL.createConsoleInterface RL.noCompletion
  s <- liftAff $ question "input> " interface
  liftEffect $ RL.close interface
  case CodeUnits.toChar $ CodeUnits.take 1 s of
    Just c ->
      pure c

    Nothing ->
      throwError CharInputFailed
```

`src/Brainfuck/CUI.purs`の`Stream`を実装する。

```haskell
-- 以下のimport文を追加
import Effect.Ref (modify) as Ref
import Effect.Class (liftEffect)
import Effect.Aff (Aff)
import Brainfuck.CUI.State (appendOutput, getOutput) as CUI


cuiStream :: forall m. MonadAff m => Ref CUI.State -> Stream m
cuiStream cuiState = Stream { input, output }
  where
    input = do
      CUI.moveAt 2 cuiState
      s <- CUI.questionAndReadChar
      CUI.up 1 -- 入力時に改行が押されたことによる微調整
      CUI.clearLine
      pure s

    output c = do
      st <- liftEffect $ Ref.modify (CUI.appendOutput c) cuiState
      CUI.printAt 2 cuiState $ CUI.getOutput st
```

`src/Main.purs`にて`,>,>,<<+.>+.>+.`を実行するように書き換えて、`spago run`してみる。

{{< figure src="mov01.gif" width="70%" >}}

### 出力の改行に対応する

`A`、`B`、`C`を改行区切りで出力するプログラムを書く。本当は

{{< cui >}}
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
0 66 10 0 0 0 0 0 0 0
A
B
C
{{< /cui >}}

のように出力されて欲しいが、実際には以下のように表示が崩れてしまう。

{{< cui >}}
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
0 67 10 0 0 0 0 0 0 0
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
0 67 10 0 0 0 0 0 0 0
++++++++[>++++++++>+<<-]>>++<+.+>.<.+>.<.
0 67 10 0 0 0 0 0 0 0
{{< /cui >}}

これは、`output`の実装に改行文字の出力まで考慮されていないからだ。
改行が起こるたびにプログラムとメモリの出力位置がずれていってしまう。


`src/Brainfuck/CUI/State.purs`を修正。改行の個数をカウントするために、`State`のフィールドを追加。
ゲッターとインクリメントする関数を定義。

```haskell
newtype State = State
  { output :: String
  , y :: Int
  , outputLines :: Int
  }


init :: Effect (Ref.Ref State)
init =
  Ref.new $ State
    { output: ""
    , y: 0
    , outputLines: 0
    }


getOutputLines :: State -> Int
getOutputLines (State { outputLines }) = outputLines


incOntputLines :: State -> State
incOntputLines (State s@{ outputLines }) = State s { outputLines = outputLines + 1 }
```

`src/Brainfuck/CUI.purs`を修正。現れた改行の数をカウントし、その分だけカーソルを上にずらすことで出力位置を微調整している。

```haskell
-- 次のimport文を追加
import Effect.Ref (modify_, read) as Ref
import Brainfuck.CUI.State (incOntputLines, getOutputLines, modifyY) as CUI


cuiStream cuiState = Stream { input, output }
  where
    input = do
      -- 略

    output c = do
      when (c == '\n') do
         liftEffect $ Ref.modify_ CUI.incOntputLines cuiState
      liftEffect $ Ref.modify_ (CUI.appendOutput c) cuiState
      st <- liftEffect $ Ref.read cuiState
      CUI.printAt 2 cuiState $ CUI.getOutput st
      CUI.move (-CUI.getOutputLines st) cuiState
```

`cuiLog`の`onEnd`を修正。出力エリアの行数を元にして、終了後のプロンプトの位置を調整する。

```haskell
cuiLog cuiState = Log
  -- 略
  where
    -- 略

    onEnd = do
      st <- liftEffect $ Ref.read cuiState
      CUI.moveAt (3 + CUI.getOutputLines st) cuiState
      CUI.newLineTimes 2
```

これで`spago run`してみると、正常に出力されるようになる。

## (おまけ) プログラムを入力する仕組みの実装

プログラム開始時に、Brainfuckプログラムを入力するように実装する。

`Main.purs`を以下のようにする。`inputProgram`という関数を定義して、プログラムの入力を促す。

```haskell
module Main where

import Prelude

import Brainfuck (run) as B
import Brainfuck.CUI (cuiLog, cuiStream)
import Brainfuck.CUI.State (init) as CUIState
import Brainfuck.Program (fromString, Program) as BP
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Node.ReadLine (createConsoleInterface, noCompletion, close) as RL
import Node.ReadLine.Aff (question) as RL

main :: Effect Unit
main = do
  ref <- CUIState.init
  launchAff_ do
    program <- inputProgram
    B.run (cuiStream ref) (cuiLog ref) program


inputProgram :: Aff BP.Program
inputProgram = do
  interface <- liftEffect $ RL.createConsoleInterface RL.noCompletion
  s <- RL.question "program> " interface
  liftEffect $ RL.close interface
  pure (BP.fromString s)
```

{{< figure src="img00.png" width="70%" >}}

## ここまでのソースコード

[GitHubのRepository](https://github.com/bombrary/brainfuck-purescript)に上げた。
ただし、次回の記事での都合上、`Main.purs`は`MainCUI.purs`に変更している。

## 次回

今回はCUIでの入出力を行ったが、最後にWebページ上で動かすことをやってみる。
UIのフレームワークとして[halogen](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2)を使う予定。
