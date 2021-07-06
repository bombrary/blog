---
title: "PureScriptで作るBrainfuckインタプリタ 3/4 CUIでの可視化"
date: 2021-07-06T17:00:15+09:00
draft: true
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

## エスケープシーケンスを利用したBrainfuck CLI

以下のような構成を持つUIを作りたい。

```
[プログラム表示エリア]
[メモリ表示エリア]
[入出力表示エリア]
```

具体的には次のようになる。
実行中の命令の位置、メモリの位置がハイライトされるようにしたい。

```
++++++++[>++++++++<-]>+.
0 65 0 0 0 0 0 0 0 0
A
```

カーソルの移動や文字色の変更を行いたいので、エスケープシーケンスを利用する。

カーソル移動で問題になるのが、位置の把握である。
出力エリアでは改行が起こる可能性があり、それによってプログラムやメモリの出力がずれてしまう。
よって、カーソルの位置データをどこかに保存しておき、適宜参照できるようにしたい。
さらに、`Stream`の`output`は1文字出力しかできないため、いままで出力した文字が把握できない。
よって、`output`で出力した文字もどこかに保存しておきたい。

問題はどこに保存するかである。`Stream`と`Log`だけが共有できるような場所に保存したい。
そのために、[refs](https://pursuit.purescript.org/packages/purescript-refs/5.0.0)パッケージを使う。

{{< cui >}}
% spago install refs
{{< /cui >}}

### 準備

`src/Brainfuck/Cli/State.purs`を作成し、`State`を作成。

```haskell
module Brainfuck.Cli.State where

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

`src/Brainfuck/Cli.purs`を作成し、`Stream`と`Log`の雛形を作成。`Cli.State`の`Ref`を引数にとる。

```haskell
module Brainfuck.Cli where

import Prelude

import Brainfuck.Interp.Log (Log(..))
import Brainfuck.Interp.Stream (Stream(..))
import Effect (Effect)
import Effect.Ref (Ref)
import Brainfuck.Cli.State (State, init) as Cli
import Effect.Aff.Class (class MonadAff, liftAff)


cliStream :: forall m. MonadAff m => Ref Cli.State -> Stream m
cliStream cliState = Stream { input, output }
  where
    input = pure 'N'

    output c = pure unit


cliLog :: forall m. MonadAff m => Ref Cli.State -> Log m
cliLog cliState = Log
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

`src/Main.purs`を以下のようにする。`cliStream`、`cliLog`の引数はここで与える。

```haskell
module Main where

import Prelude

import Brainfuck (run) as B
import Brainfuck.Program (fromString) as BP
import Effect (Effect)
import Effect.Aff (launchAff_)

import Brainfuck.Cli (cliLog, cliStream)
import Brainfuck.Cli.State (init) as CliState


main :: Effect Unit
main = do
  ref <- CliState.init
  launchAff_ $ B.run (cliStream ref) (cliLog ref) (BP.fromString "++++++++[>++++++++<-]>+.")
```

### ユーティリティ作成

`src/Brainfuck/Cli/State.purs`に関数を追加。
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


setY :: Int -> State -> State
setY y = modifyY (\_ -> y)


dist :: Int -> State -> Int
dist y0 (State { y }) = y0 - y
```

続いて、`src/Brainfuck/Cli/Util.purs`を作成。
出力関数や、カーソル移動系の関数を定義。
特に重要なのは`printAt`で、これは`y`行目に出力することができる。

エスケープシーケンスは[こちら](https://qiita.com/PruneMazui/items/8a023347772620025ad6)を参考にした。

```haskell
module Brainfuck.Cli.Util where

import Prelude

import Brainfuck.Cli.State (dist, setY, modifyY, State)
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

`src/Brainfuck/Cli.purs`を修正。まず以下の関数をインポート。

```haskell
import Brainfuck.Cli.Util as Cli
import Brainfuck.State (State(..))
import Brainfuck.Env (getProgram)
import Control.Monad.Reader (ask)
import Data.Array (mapWithIndex) as Array
import Effect.Aff (Milliseconds(..), delay)
import Data.String (joinWith) as String
```

特定のインデックスにのみ適用する関数を変えるバージョンのmap関数を定義する。
それを用いて、命令列とメモリの出力をする関数を定義。

```haskell
mapWithASpecialIndex :: forall a b. Int -> (a -> b) -> (a -> b) -> Array a -> Array b
mapWithASpecialIndex j fThen fElse =
  Array.mapWithIndex (\i x -> if i == j then fThen x else fElse x)


showProgram :: Int -> Program -> String
showProgram iptr (Program program) =
  String.joinWith "" $
    mapWithASpecialIndex iptr
      (Cli.highlight <<< show)
      show
      program


showMemory :: Int -> Array Int -> String
showMemory dptr memory =
  String.joinWith " " $
    mapWithASpecialIndex dptr
      (Cli.highlight <<< show)
      show
      memory
```

`showProgram`と`showMemory`を用いて`onState`を実装する。
カーソル下のスペースを確保するために、`onStart`で前処理を行っている。

```haskell
cliLog :: forall m. MonadAff m => Ref Cli.State -> Log m
cliLog cliState = Log
  { onStart
  , onState
  , onCmd: \_ -> pure unit
  , onEnd
  }
  where
    onStart = do
       Cli.newLineTimes 4
       Cli.up 4

    onState (State { iptr, dptr, memory }) = do
      program <- getProgram <$> ask
      Cli.printAt 0 cliState $ showProgram iptr program
      Cli.printAt 1 cliState $ showMemory dptr memory
      liftAff $ delay (Milliseconds 100.0)

    onEnd = pure unit
```

この時点で`spago run`してみるとこんな感じで動く。

{{< figure src="mov00.gif" width="70%" >}}

### 入出力

`src/Brainfuck/Cli/Util.purs`で`questionAndReadChar`を定義。

```haskell
-- 以下のimport文を追加
import Brainfuck.Interp.Stream (questionAff)
import Node.ReadLine (createConsoleInterface, noCompletion, close, Interface) as RL
import Data.String.CodeUnits (toChar, take) as CodeUnits
import Control.Monad.Error.Class (throwError)
import Brainfuck.Error (Error(..))
import Effect.Aff.Class (class MonadAff, liftAff)
import Data.Maybe (Maybe(..))


questionAndReadChar :: forall m. MonadAff m => Interp m Char
questionAndReadChar = do
  interface <- liftEffect $ RL.createConsoleInterface RL.noCompletion
  s <- liftAff $ questionAff "input> " interface
  liftEffect $ RL.close interface
  case CodeUnits.toChar $ CodeUnits.take 1 s of
    Just c ->
      pure c

    Nothing ->
      throwError CharInputFailed
```

`src/Brainfuck/Cli.purs`の`Stream`を実装する。

```haskell
-- 以下のimport文を追加
import Effect.Ref (modify) as Ref
import Effect.Class (liftEffect)
import Effect.Aff (Aff)
import Brainfuck.Cli.State (appendOutput, getOutput) as Cli


cliStream :: forall m. MonadAff m => Ref Cli.State -> Stream m
cliStream cliState = Stream { input, output }
  where
    input = do
      Cli.moveAt 2 cliState
      s <- Cli.questionAndReadChar
      Cli.up 1 -- 入力時に改行が押されたことによる微調整
      Cli.clearLine
      pure s

    output c = do
      st <- liftEffect $ Ref.modify (Cli.appendOutput c) cliState
      Cli.printAt 2 cliState $ Cli.getOutput st
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


`src/Brainfuck/Cli/State.purs`を修正。改行の個数をカウントするために、`State`のフィールドを追加。
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

`src/Brainfuck/Cli.purs`を修正。現れた改行の数をカウントし、その分だけカーソルを上にずらすことで出力位置を微調整している。

```haskell
-- 次のimport文を追加
import Effect.Ref (modify_, read) as Ref
import Brainfuck.Cli.State (incOntputLines, getOutputLines, modifyY) as Cli


cliStream cliState = Stream { input, output }
  where
    input = do
      -- 略

    output c = do
      when (c == '\n') do
         liftEffect $ Ref.modify_ Cli.incOntputLines cliState
      liftEffect $ Ref.modify_ (Cli.appendOutput c) cliState
      st <- liftEffect $ Ref.read cliState
      Cli.printAt 2 cliState $ Cli.getOutput st
      Cli.up $ Cli.getOutputLines st
```

これで`spago run`してみると、正常に出力されるようになる。

## 次回

今回はCUIでの入出力を行ったが、最後にWebページ上で動かすことをやってみる。
UIのフレームワークとして[halogen](https://pursuit.purescript.org/packages/purescript-halogen/6.1.2)を使う予定。
