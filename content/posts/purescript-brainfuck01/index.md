---
title: "PureScriptで作るBrainfuckインタプリタ 1/3 基礎部分の作成"
date: 2021-07-04T11:40:00+09:00
tags: ["モナド変換子"]
categories: ["PureScript", "Brainfuck"]
toc: true
---

Brainfuckの記事ではあるが、実はモナド変換子を使ってみたかっただけだったりする。

以下の3部の記事で構成されている。

1. インタプリタと基本的な命令の実装 (**この記事**)
2. CUIでの入出力処理の実装
3. Halogenを用いた入出力処理の実装

この記事でインタプリタの基本的な部分を実装し、
残りの2記事はインタプリタとはあまり関係ない話となる
(とはいえ出力ができないと Hello, World すら書けないので、必要な記事ではある)。

## Brainfuckインタプリタの構造

Brainfuckインタプリタは以下の情報を内部に持っているものとする。

- `program`: 命令の列。
- `iptr`: インストラクションポインタ。実行する命令の位置を示す。プログラムカウンタみたいなもの。
- `dptr`: データポインタ。メモリ上のある位置を示す。
- `memory`: メモリ。

インタプリタは以下の手順を踏む。

1. `iptr`番目の命令を`program`から読み取る。
   読み取れなかったらプログラムを終了する。
2. 命令に応じて`memory`、`dptr`の書き換えだったり、入出力を行う。
3. `iptr`を1進め、手順1に戻る。

どんな命令があるのかについては[Wikipedia](https://ja.wikipedia.org/wiki/Brainfuck)参照。

## 準備

適当なディレクトリを作って、プロジェクトの初期化を行う。

{{< cui >}}
% spago init
{{< /cui >}}


## 命令列の作成

`src/Brainfuck/Command.purs`を作成する。

`Command`を定義。`Show`クラスのインスタンスにして、`Char`からの変換をする関数を作る。

```haskell
module Brainfuck.Command where

import Prelude

data Command
  = IncPtr -- "+"
  | DecPtr -- "-"
  | IncDat -- ">"
  | DecDat -- "<"
  | LBrace -- "["
  | RBrace -- "]"
  | Output -- "."
  | Input -- ","
  | Nop -- otherwise


instance Show Command where
  show =
    case _ of
      IncPtr -> "+"
      DecPtr -> "-"
      IncDat -> ">"
      DecDat -> "<"
      LBrace -> "["
      RBrace -> "]"
      Output -> "."
      Input -> ","
      Nop -> "nop"


fromChar :: Char -> Command
fromChar =
  case _ of
    '>' -> IncPtr
    '<' -> DecPtr
    '+' -> IncDat
    '-' -> DecDat
    '[' -> LBrace
    ']' -> RBrace
    '.' -> Output
    ',' -> Input
    _ -> Nop
```

続いて、`src/Brainfuck/Program.purs`を作成。この後使う関数をまとめて読み込んでおく。

```haskell
module Brainfuck.Program where

import Prelude

import Brainfuck.Command (Command, fromChar)
import Data.Array ((!!))
import Data.Array (intercalate) as Array
import Data.Maybe (Maybe)
import Data.String.CodeUnits (toCharArray) as CodeUnits
```


`Program`を定義する。`String`から変換する関数、`Program`から命令を1つ読み取る関数を作る。

(**補足**) [PureScript v0.14.2](https://github.com/purescript/purescript/releases/tag/v0.14.2)からinstance nameが省略可能になったので、
`instance showProgram Show Program`みたいには書かず`instance Show Program`と書いている。


```haskell
newtype Program = Program (Array Command)


instance Show Program where
  show (Program p) =
    "\"" <> (Array.intercalate " " $ map show p) <> "\""


fromString :: String -> Program
fromString str =
  Program $ map fromChar $ CodeUnits.toCharArray str


readAt :: Int -> Program -> Maybe Command
readAt i (Program xs) = xs !! i
```

関連パッケージをインストールする。

{{< cui >}}
spago install arrays maybe strings
{{< /cui >}}

REPLで動作確認してみる。

{{< cui >}}
> import Brainfuck.Program
> fromString "+++[>+++<-]++>,<.hoge"
"> > > [ + > > > - < ] > > + , - . nop nop nop nop"
{{< /cui >}}


## Interpモナド

### 要件

インタプリタは以下の機能を持つものとする。

- `iptr`、`dptr`、`memory`の3つはインタプリタの状態を表し、これらは計算中に変わる。これを`State`モナドで扱う。
- `program`は読み取るだけ。これを`Reader`モナドで扱う。
- `dpt`がメモリ外の範囲を参照してしまったり、`iptr`がプログラム外の範囲を参照してしまう可能性がある。
  そのような例外を扱うために、`Except`モナドを使う。
- 標準入力や標準出力を行うために、`Effect`モナドを使う。

これらを組み合わせるためには、[transformers](https://pursuit.purescript.org/packages/purescript-transformers/5.1.0)のモナド変換子が必要になる。
よって、`State, Reader, Except`はそれぞれ`StateT, ReaderT, ExceptT`となる。

以下のように組み合わせる。`Env`、`Error`、`State`はこれから作る型。

```haskell
type Interp a = ReaderT Env (ExceptT Error (StateT State Effect)) a
```

なにやらごちゃごちゃしてしまっている。ためしに`runReaderT, runExceptT, runStateT`を使って、手動でモナドを引き剥がしてみる
(以下はプログラムのコードではなく、モナド変換子の型の遷移をみるためのメモ)。

```haskell
x :: ReaderT Env (ExceptT Error (StateT State Effect)) a
x1 = runReaderT program x :: ExceptT Error (StateT State Effect) a
x2 = runExceptT x1 :: StateT State Effect (Either Error a)
x3 = runStateT x2 :: Effect (Tuple (Either Error a) State)
```

どうやら、`(エラー付きの値, 最終状態)` というタプルを返すようだ。ただし、`Effect`に包まれた状態で返ってくる。

`type`で`Interp`を宣言すると、コンパイルエラーで`ReaderT Env (ExceptT Error (StateT State Effect)) a`
が表示されてしまい見づらい。よって、`newtype`で包んで使用する。

### Envの作成

`Interp`の外部状態である`State`を作成する。`src/Brainfuck/Env.purs`を作成。

`Env`は`Program`のみが入っているレコードとする。
`Env`から`Program`取り出す関数と、`Env`を作る関数を定義。

```haskell
module Brainfuck.Env where

import Prelude

import Brainfuck.Program (Program)

newtype Env = Env
  { program :: Program
  }

instance Show Env where
  show (Env { program }) = show program


getProgram :: Env -> Program
getProgram (Env { program } ) = program


makeEnv :: Program -> Env
makeEnv program = Env
  { program
  }
```

### Stateの作成

`Interp`の内部状態である`State`を作成する。まず`src/Brainfuck/State.purs`を作成。

```haskell
module Brainfuck.State where

newtype State = State
  { dptr :: Int
  , iptr :: Int
  , memory :: Array Int
  }
  }
```

### Errorの作成

`Interp`の例外の型である`Error`を作成する。`src/Brainfuck/Error.purs`を作成。

考えられる例外は以下の通り。

- `IPtrOutOfRange`: 命令列の配列外参照
- `DPtrOutOfRange`: メモリの配列外参照
- `CharDecodeError`: `.`命令によってメモリ上の整数を文字に変換して出力するが、その変換に失敗した場合(整数がUnicodeでなかった場合に起こる)。
- `CharInputFailed`: 文字の入力に失敗した場合に起こる

```haskell
module Brainfuck.Error where

import Prelude


data Error
  = IPtrOutOfRange
  | DPtrOutOfRange
  | CharDecodeFailed
  | CharInputFailed


instance Show Error where
  show err =
    case err of
      IPtrOutOfRange -> "Error: Instruction pointer out of range"
      DPtrOutOfRange -> "Error: Data oointer out of range"
      CharDecodeFailed -> "Error: Failed to decode integer to char"
      CharInputFailed -> "Error: Failed to input char"
```

### Interpの作成

`src/Brainfuck/Interp.purs`を作成。
この後使うパッケージを読み込んでおく。


```haskell
module Brainfuck.Interp where

import Prelude

import Brainfuck.Env (Env)
import Brainfuck.Error (Error)
import Brainfuck.State (State)
import Control.Monad.Except.Trans (class MonadThrow, ExceptT, runExceptT)
import Control.Monad.Reader.Trans (class MonadAsk, ReaderT, runReaderT)
import Control.Monad.State.Trans (class MonadState, StateT, runStateT)
import Data.Either (Either)
import Data.Tuple (Tuple(..))
import Effect.Class (class MonadEffect)
```

まず型を作成。

```haskell
newtype Interp a = Interp (ReaderT Env (ExceptT Error (StateT State Effect)) a)
```

`Interp`の計算を実行して結果を返す関数を返す。単に`run***`を実行してモナドを引き剥がすだけ。
計算結果が`Effect`で包まれて返ってくることに注意。

```haskell
runInterp :: forall a. Interp a -> Env -> State -> Effect (InterpResult a)
runInterp (Interp ip) env s = do
  Tuple result state <- runStateT (runExceptT (runReaderT ip env)) s
  pure { result, state }
```

`InterpResult a`は次のように定義しておく。

```haskell
type InterpResult a =
  { result :: Either Error a
  , state :: State
  }
```


関連パッケージをインストールしておく。

{{< cui >}}
spago install transformers either tuples
{{< /cui >}}

## Interpのインスタンス化 - derive newtype

`Interp`を`newtype`に包んでしまったせいで、`Interp`自身は`Monad`インスタンスではない。
よって現状は`do`記法を使うことができない。それだけでなく、せっかく`StateT`や`ReaderT`、`ExceptT`
を使ったのに`modify`、`ask`、`throwError`などの関数が利用できない。もちろん`Effect`関連の関数も利用できない。

そこで、以下のように手動でインスタンス宣言してみるが、`Interp`を引き剥がしたり包んだりして混乱するし、面倒である。

```haskell
instance Functor Interp where
  map f (Interp ip) = Interp (map f ip)

instance Apply Interp where
  apply (Interp f) (Interp ip) = Interp (apply f ip)

instance Applicative Interp where
  pure x = Interp (pure x)

instance Bind Interp where
  bind (Interp ip) f = Interp (bind ip g)
    where
      g x =
        let (Interp y) = f x
        in
          y

instance Monad Interp
```

幸いにも、`newtype`の場合には[derive newtype](https://github.com/purescript/documentation/blob/master/guides/Type-Class-Deriving.md#derive-from-newtype)という機能がある
(詳しくは[Newtype Deriving](https://github.com/paf31/24-days-of-purescript-2016/blob/master/4.markdown)も参照)。
`newtype`で包まれたデータは、吐き出されたJavaScriptコードでは中身そのものして扱われる([参考](https://github.com/purescript/documentation/blob/master/language/Types.md#newtypes))。
`derive newtype`を使うと、包んだ中身の型のインスタンスをそのまま使うことができる。

例えば、以下の例では`Num`を`Show`クラスのインスタンスにしている。

```haskell
newtype Num = Num Int

derive newtype instance Show Num
```

あくまで包んだ中身の`Int`の`show`を使うだけなので、以下では`Num 123`とかではなく`123`と出力される。

{{< cui >}}
> Num 123
123
{{< /cui >}}

以上の話を元に、`src/Brainfuck/Interp.purs`に追記する。

```haskell
derive newtype instance Functor Interp
derive newtype instance Apply Interp
derive newtype instance Applicative Interp
derive newtype instance Bind Interp
derive newtype instance Monad Interp
derive newtype instance MonadState State Interp
derive newtype instance MonadAsk Env Interp
derive newtype instance MonadThrow Error Interp
derive newtype instance MonadEffect Interp
```

ついでに`State`についても`Show`インスタンスにしておく。
以下の内容を`src/Brainfuck/State.purs`に追記。

```haskell
derive newtype instance Show State
```

## 状態変更に関連する関数の作成

`src/Brainfuck/State.purs`に追記する。

まずimport文を追記。

```haskell
import Prelude

import Brainfuck.Command (Command)
import Brainfuck.Program (Program, readAt)
import Data.Array (modifyAt, (!!))
import Data.Maybe (Maybe)
```

メモリや命令列、それらのポインタの操作を行う関数を作成。

```haskell
modifyDataPtr :: (Int -> Int) -> State -> State
modifyDataPtr f (State s@{ dptr }) = State s { dptr = f dptr }


readData :: State -> Maybe Int
readData (State { memory, dptr }) = memory !! dptr


modifyData :: (Int -> Int) -> State -> Maybe State
modifyData f (State s@{ memory, dptr }) =
  map
    (\newMem -> State s { memory = newMem })
    (modifyAt dptr f memory)


modifyInstPtr :: (Int -> Int) -> State -> State
modifyInstPtr f (State s@{ iptr }) = State s { iptr = f iptr }
```

プログラムから命令を読み取る関数も作っておく。

```haskell
readCommand :: Program -> State -> Maybe Command
readCommand p (State { iptr }) = readAt iptr p
```

## ユーティリティの作成

`src/Brainfuck/Interp/Util.purs`を作成。ここに`Interp`に関するいくつかのユーティリティを定義しておく。

```haskell
module Brainfuck.Interp.Util where

import Prelude

import Brainfuck.Command (Command)
import Brainfuck.Env (getProgram)
import Brainfuck.Error (Error(..))
import Brainfuck.Interp (Interp)
import Brainfuck.State (modifyData, modifyInstPtr, readCommand, readData)
import Control.Monad.Except.Trans (throwError)
import Control.Monad.Reader.Trans (ask)
import Control.Monad.State.Trans (get, gets, modify_, put)
import Data.Char (fromCharCode) as Char
import Data.Maybe (Maybe(..))
```

`+`、`-`、`.`、`,`でメモリからデータにアクセスする必要があるので、関連の関数を定義する。
失敗したら例外を投げるようにする。また`.`では整数値を文字に変換する必要があるため、その関数を定義しておく。

```haskell
modifyDataOrFail ::  (Int -> Int) -> Interp Unit
modifyDataOrFail f = do
  state <- get
  case modifyData f state of
    Just newState ->
      put newState

    Nothing ->
      throwError DPtrOutOfRange


readDataOrFail ::  Interp Int
readDataOrFail = do
  gets readData >>=
    case _ of
      Just x ->
        pure x

      Nothing ->
        throwError DPtrOutOfRange


readCharOrFail :: Interp Char
readCharOrFail = do
  x <- readDataOrFail
  case Char.fromCharCode x of
    Just c ->
      pure c

    Nothing ->
      throwError CharDecodeFailed
```

命令列を読み取る関数、インストラクションポインタを操作する関数を定義する。

```haskell
readCommandOrFail :: Interp Command
readCommandOrFail = do
  state <- get
  program <- getProgram <$> ask
  case readCommand program state of
    Just cmd ->
      pure cmd

    Nothing ->
      throwError IPtrOutOfRange


incInstPtr ::  Interp Unit
incInstPtr = modify_ $ modifyInstPtr (_ + 1)


decInstPtr ::  Interp Unit
decInstPtr = modify_ $ modifyInstPtr (_ - 1)
```


## プログラム実行の処理の雛形

`src/Brainfuck/State.purs`に追記する。

以下のimport文を追加。

```haskell
import Data.Array (replicate) as Array
```

`defaultState`を作成。今回は出力の見やすさのために、`memory`を要素数10の配列にしている
(Brainfuckの仕様では、本当は30000要素以上を持っていないといけない)。

```haskell
defaultState :: State
defaultState = State
  { iptr: 0
  , dptr: 0
  , memory: Array.replicate 10 0
  }
```

`src/Brainfuck.purs`を作成する。この後使う関数をまとめて読み込んでおく。
`Brainfuck.Interp.Command`はこの後作る。

```haskell
module Brainfuck where

import Prelude

import Brainfuck.Env (getProgram, makeEnv)
import Brainfuck.Interp (Interp(..), InterpResult, runInterp)
import Brainfuck.Interp.Command (interpCommand)
import Brainfuck.Interp.Util (incInstPtr)
import Brainfuck.Program (Program(..))
import Brainfuck.State (defaultState, readCommand)
import Control.Monad.Reader.Class (ask)
import Control.Monad.State.Class (get)
import Data.Maybe (Maybe(..))
import Effect (Effect)
```

まずプログラムを受け取って実行する関数を定義する。細かい処理は`interpProgram`に任せる。

```haskell
runDefault :: Program -> Effect (InterpResult Unit)
runDefault program = runInterp interpProgram (makeEnv program) defaultState
```

プログラムを解釈する関数`interpProgram`を作成。
ここでは命令を取得し、インストラクションポインタを1進めるという処理を行っている。
命令の解釈は`interpCommand`に任せる。
`interpProgram`を再帰的に呼び出し、コマンドが取得できなかった場合は終了する。

```haskell
interpProgram :: Interp Unit
interpProgram = do
  program <- getProgram <$> ask
  state <- get
  case readCommand program state of
    Just cmd -> do
      interpCommand cmd

      incInstPtr
      interpProgram

    Nothing ->
      pure unit
```

続いて、`src/Brainfuck/Interp/Command.purs`を作成。コマンドの処理はここに書くことにする。

```haskell
module Brainfuck.Interp.Command where

import Prelude

import Brainfuck.Command (Command(..))
import Brainfuck.Interp (Interp)
```

コマンドを読み取り実行する関数の雛形を作る。

```haskell
interpCommand :: Command -> Interp Unit
interpCommand =
  case _ of
     IncPtr ->
       pure unit

     DecPtr ->
       pure unit

     IncDat ->
       pure unit

     DecDat ->
       pure unit

     LBrace ->
       pure unit

     RBrace ->
       pure unit

     Output ->
       pure unit

     Input ->
       pure unit

     Nop ->
       pure unit
```

この時点で`spago repl`してみて、正常に動くか確認する。とはいえ命令はまだ何も実装していないため、
ただ`iptr`が動くだけのプログラムとなっている。

{{< cui >}}
> import Brainfuck
> import Brainfuck.Program
> runDefault (fromString "++-->><<")
{ result: (Right unit), state: { dptr: 0, iptr: 8, memory: [0,0,0,0,0,0,0,0,0,0] } }
{{< /cui >}}


## 各々のコマンドの実装

`src/Brainfuck/Interp/Command.purs`にて、以下のimport文を追記。

```haskell
import Brainfuck.Interp.Util (incInstPtr, decInstPtr, readCommandOrFail, readDataOrFail, modifyDataOrFail)
import Brainfuck.State (modifyDataPtr)
import Control.Monad.State.Class (modify_)
```

### '&gt;' と '&lt;'

まず`incDataPtr`と`decDataPtr`を作成。

```haskell
incDataPtr :: Interp Unit
incDataPtr = modify_ $ modifyDataPtr (_ + 1)


decDataPtr :: Interp Unit
decDataPtr = modify_ $ modifyDataPtr (_ - 1)
```

`interpCommand`に追加。

```haskell
interpCommand =
  case _ of
    IncPtr -> 
      incDataPtr

    DecPtr ->
      decDataPtr

    -- 略
```

REPLで動かしてみる。 `dptr`の値がちゃんと2になってくれている。

{{< cui >}}
> runDefault $ fromString ">>>>><<<"
{ result: (Right unit), state: { dptr: 2, iptr: 8, memory: [0,0,0,0,0,0,0,0,0,0] } }
{{< /cui >}}

### '+' と '-'

`incData`、`decData`を作成。

```haskell
incData :: Interp Unit
incData = modifyDataOrFail (_ + 1)


decData :: Interp Unit
decData = modifyDataOrFail (_ - 1)
```

`interpCommand`に追加。

```haskell
interpCommand =
  case _ of
    -- 略 

    IncDat ->
      incData

    DecDat ->
      decData

    -- 略 
```

REPLで動作確認。

{{< cui >}}
> runDefault $ fromString "+>++>+++<->>++++"
{ result: (Right unit), state: { dptr: 3, iptr: 16, memory: [1,1,3,4,0,0,0,0,0,0] } }
{{< /cui >}}

### '[' と ']'

`[`命令、`]`命令の処理を実装。
`goToLBrace`と`goToRBrace`というのが、対応する括弧に移動する関数となる。

```haskell
interpCommand =
  case _ of
    -- 略

    LBrace -> do
      x <- readDataOrFail
      when (x == 0)
        goToRBrace

    RBrace -> do
      x <- readDataOrFail
      when (x /= 0)
        goToLBrace

    -- 略
```

`goToLBrace`と`goToRBrace`は前に進めるか前に進めるかの違いしかないので、共通の関数`goToMate`に任せる。
進め方を`goToMate`の第1引数に指定。

```haskell
goToRBrace :: Interp Unit
goToRBrace = goToMate incInstPtr


goToLBrace :: Interp Unit
goToLBrace = goToMate decInstPtr
```

`goToMate`を作成。ここは設計とは別種の、アルゴリズム的な難しさが(多少)ある。
通り過ぎた括弧の数を`cnt`でカウントする。`[`が来た時は`cnt + 1`、`]`が来た時は`cnt - 1`する。
`cnt`が0になった地点が、対応する括弧となる。

```haskell
goToMate :: Interp Unit -> Interp Unit
goToMate move = go 0
  where
    go :: Int -> Interp Unit
    go cnt = do
      cmd <- readCommandOrFail
      let newCnt =
            case cmd of
              LBrace ->
                cnt + 1

              RBrace ->
                cnt - 1

              _ ->
                cnt
      if newCnt == 0
        then
          pure unit
        else do
          move
          go newCnt
```

REPLで動作確認。

{{< cui >}}
> runDefault $ fromString "++++[>+++++<-]"
{ result: (Right unit), state: { dptr: 0, iptr: 14, memory: [0,20,0,0,0,0,0,0,0,0] } }
> runDefault $ fromString "+++>[foofoo]---"
{ result: (Right unit), state: { dptr: 1, iptr: 15, memory: [3,-3,0,0,0,0,0,0,0,0] } }
{{< /cui >}}

## 次回

まだHello, Worldすら出力できないBrainfuckだが、
入出力の扱いは長くなるので次の記事に回す。
