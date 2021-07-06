---
title: "PureScriptで作るBrainfuckインタプリタ 2/4 CUIでの入出力"
date: 2021-07-05T17:05:00+09:00
tags: []
categories: ["PureScript", "Brainfuck"]
toc: true
---


## 入出力用のストリーム作成

例えば出力だけ考えてみると、まず考えられるのは単純に、
[log](https://pursuit.purescript.org/packages/purescript-console/5.0.0/docs/Effect.Class.Console#v:log)で出力することである。しかし`log`以外の選択肢も考えられる。
`log`でコンソール出力するだけでなく、Webページのテキスト上で出力したり、テキストファイルに吐き出したりできるような汎用性が持たせられると良い。

そこで今回は、いわゆる「ストリームオブジェクト」のようなものを作って、そこから入出力を行うような設計にしてみる。

### Streamの作成

`src/Brainfuck/Interp/Stream.purs`を作成。この後使うモジュールをインポート。

```haskell
module Brainfuck.Interp.Stream where

import Prelude

import Brainfuck.Interp (Interp)
```

`Stream`型を作成する。これは入出力を束ねた型になっている。
`input`は、外部からの入力を1文字受け取る。
`output`は、`Char`の値を外部に出力する。

```haskell
newtype Stream = Stream
  { input :: Interp Char
  , output ::Char -> Interp Unit
  }
```

`Stream`を通じてデータを読み書きする関数を作成。

```haskell
read :: Stream -> Interp Char
read (Stream { input }) = input


write :: Char -> Stream -> Interp Unit
write c (Stream { output }) =
  output c
```

```haskell
defaultStream :: Stream
defaultStream = Stream { input, output }
  where
    input = pure 'N' -- Not Implemented

    output _ = pure unit -- Not Implemented
```


### '.'と','

`src/Brainfuck/Interp/Command.purs`を修正する。まず以下のインポート文を追加。

```haskell
import Brainfuck.Interp.Util (readCharOrFail)
import Brainfuck.Interp.Stream (write, read, Stream)
import Data.Char (toCharCode) as Char
```

`Stream`は`Env`のレコードのフィールドとして扱いたいところだが、
それをやると`Brainfuck.Interp.Stream`、`Brainfuck.Env`、`Brainfuck.Interp`とでcircular importとなってしまう。
仕方ないので`interpCommand`の引数で扱うことにする。

`interpCommand`の引数を追加し、`.`命令と`,`命令を実装する。
`input`や`output`の実装は`interpCommand`の管轄外であり、
とにかく「`input`は1文字返してくれて、`output`は1文字送ってくれる」という気持ちを持って実装する。

```haskell
interpCommand :: Stream -> Command -> Interp Unit
interpCommand stream =
  case _ of
    -- ... 略 ...

     Output -> do
       c <- readCharOrFail
       write c stream

     Input -> do
       x <- read stream
       modifyDataOrFail (\_ -> Char.toCharCode x)

    -- ... 略 ...
```

### Brainfuckの修正

`src/Brainfuck.purs`を修正する。以下のモジュールを追加でインポートしておく。

```haskell
import Brainfuck.Interp.Stream (Stream, defaultStream)
```

`interpCommand`の修正に伴い、`interpProgram`を修正。

```haskell
interpProgram :: Stream -> Interp Unit
interpProgram stream = do
  -- ... 略 ...
  case readCommand program state of
    Just cmd -> do
      interpCommand stream cmd -- 引数を追加

      incInstPtr
      interpProgram stream -- 引数を追加
  -- ... 略 ...
```

`Stream`を引数にとるバージョンの`run`を定義。
それを用いて`runDefault`を書き直す。

```haskell
run :: Stream -> Program -> Effect (InterpResult Unit)
run stream program =
  runInterp (interpProgram stream) (makeEnv program) defaultState


runDefault :: Program -> Effect (InterpResult Unit)
runDefault program = run defaultStream program
```

## コンソール出力

### 出力ストリームの実装

`src/Brainfuck/Interp/Stream.purs`の`defaultStream`において、`output`を`log`で実装してみる。

```haskell
-- import文追加
import Effect.Class (liftEffect)
import Effect.Console (log)


defaultStream :: Stream
defaultStream = Stream { input, output }
  where
    input = pure 'N' -- Not Implemented

    output c = liftEffect $ log $ show c
```

これでようやくHello, Worldが出力できる。[Wikipedia](https://en.wikipedia.org/wiki/Brainfuck)にあるコードを借りる。

{{< cui >}}
> import Brainfuck.Interp.Stream
> runDefault $ fromString "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."
'H'
'e'
'l'
'l'
'o'
' '
'W'
'o'
'r'
'l'
'd'
'!'
'\n'

{ result: (Right unit), state: { dptr: 6, iptr: 106, memory: [0,0,72,100,87,33,10,0,0,0] } }
{{< /cui >}}

### 出力先の変更

`log`関数の仕様上改行が入ってしまう。そもそも`log`はデバッグ用のものであり、出力には適していない。
ではデバッグではない標準出力はあるのかとうと、それはNode.jsでいう`process.stdout.write`に当たる(とはいえNode.jsは詳しくないので確かではないが…)。
それをラッピングしたものが[purescript-node-process](https://pursuit.purescript.org/packages/purescript-node-process/8.2.0)に用意されているので、これを使うことにする。

該当パッケージをインストールする。

{{< cui >}}
% spago install node-process node-buffer node-streams
{{< /cui >}}

`src/Stream.purs`にNode.js用のストリームを定義する。以下のパッケージをインポートしておく。

```haskell
import Data.String.CodeUnits (singleton) as CodeUnits
import Node.Process (stdout)
import Node.Encoding (Encoding(UTF8))
import Node.Stream (writeString)
```

`nodeStream`を定義。
[writeString](https://pursuit.purescript.org/packages/purescript-node-streams/5.0.0/docs/Node.Stream#v:writeString)は、どうやら内部で[writable.write](https://nodejs.org/api/stream.html#stream_writable_write_chunk_encoding_callback)を呼び出している模様。
`UTF8`でエンコーディングを指定し、第4引数は出力後のコールバック関数のようだ。

```haskell
nodeStream :: Stream
nodeStream = Stream { input, output }
  where
    input = pure 'N' -- Not Implemented

    output c =
      void $ liftEffect $ writeString stdout UTF8 (CodeUnits.singleton c) (pure unit)
```

REPLで確認してみると、無事改行無しの出力ができている。

{{< cui >}}
> run nodeStream (fromString "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.")
Hello World!
{ result: (Right unit), state: { dptr: 6, iptr: 106, memory: [0,0,72,100,87,33,10,0,0,0] } }
{{< /cui >}}


## 修正: Interpの抽象化

入力を非同期処理で扱う必要があるため、全体の計算を`Aff`で扱えると良い。
もっと一般的に、`Effect`でも`Aff`でも使えるように`Interp`を抽象化する 
(やってみたら想像以上に修正箇所が多く、大変だった…)。

`Aff`を使いたいので、以下のパッケージをインストール。

{{< cui >}}
% spago install aff
{{< /cui >}}


### Interpの修正

`src/Brainfuck/Interp.purs`を修正。まず以下のインポート文を追加。

```haskell
TODO
```

根本となる`Interp`の型を修正する。`Interp`に型変数`m`を持たせる。
`Interp`自身がモナド変換子になったような感じ。

```haskell
newtype Interp m a = Interp (ReaderT Env (ExceptT Error (StateT State m)) a)
```

この時点で`spago build`すると型エラーがたくさん出るはずなので、エラーメッセージに従って修正していけばよい。
以下、修正箇所を示すが、抜けがあるかもしれない。

`runInterp`の型を修正。

```haskell
runInterp :: forall m a. Monad m => Interp m a -> Env -> State -> m (InterpResult a)
```

`derive newtype`を修正。どのように修正すべきかは、[StateTのinstance](https://pursuit.purescript.org/packages/purescript-transformers/5.1.0/docs/Control.Monad.State#t:StateT)を参考にする。
というのも、`m`の制約に直接影響するのは`StateT`だからだ。


```haskell
derive newtype instance (Functor m) => Functor (Interp m)
derive newtype instance (Monad m) => Apply (Interp m)
derive newtype instance (Monad m) => Applicative (Interp m)
derive newtype instance (Monad m) => Bind (Interp m)
derive newtype instance (Monad m) => Monad (Interp m)
derive newtype instance (Monad m) => MonadState State (Interp m)
derive newtype instance (Monad m) => MonadAsk Env (Interp m)
derive newtype instance (Monad m) => MonadThrow Error (Interp m)
derive newtype instance (MonadEffect m) => MonadEffect (Interp m)
```

`MonadAff`の`derive newtype`を追加。

```haskell
derive newtype instance (MonadAff m) => MonadAff (Interp m)
```

### Streamの修正

`src/Brainfuck/Interp/Stream`を修正。まず以下のimportを追加。

```haskell
import Effect (Effect)
import Effect.Aff (Aff)
```

`Stream`に型変数`m`をつける。

```haskell
newtype Stream m = Stream
  { input :: Interp m Char
  , output :: Char -> Interp m Unit
  }
```

それに合わせて`read`、`write`を修正。
`defaultStream`と`nodeStream`の`Stream m`には具体的な`m`を指定。

```haskell
read :: forall m. Stream m -> Interp m Char

write :: forall m. Char -> Stream m -> Interp m Unit

defaultStream :: Stream Effect

nodeStream :: Stream Aff
```

### Utilの修正

`src/Brainfuck/Interp/Util.purs`において、全ての関数の引数を修正。

```haskell
modifyDataOrFail ::  forall m. Monad m => (Int -> Int) -> Interp m Unit

readDataOrFail ::  forall m. Monad m => Interp m Int

readCharOrFail :: forall m. Monad m => Interp m Char

readCommandOrFail :: forall m. Monad m => Interp m Command

incInstPtr ::  forall m. Monad m => Interp m Unit

decInstPtr ::  forall m. Monad m => Interp m Unit
```

### Commandの修正

`src/Brainfuck/Interp/Command.purs`を修正。こちらも全ての関数の引数を修正。

```haskell
interpCommand :: forall m. Monad m => Stream m -> Command -> Interp m Unit

incDataPtr :: forall m. Monad m => Interp m Unit

decDataPtr :: forall m. Monad m => Interp m Unit

incData :: forall m. Monad m => Interp m Unit

decData :: forall m. Monad m => Interp m Unit

goToRBrace :: forall m. Monad m => Interp m Unit

goToLBrace :: forall m. Monad m => Interp m Unit

goToMate :: forall m. Monad m => Interp m Unit -> Interp m Unit
goToMate move = go 0
  where
    go :: Int -> Interp m Unit
    -- 略
```

### Brainfuckの修正

`src/Brainfuck.purs`を修正。`runDefault`以外の関数の型を修正。

```haskell
run :: forall m. Monad m => Stream m -> Program -> m (InterpResult Unit)

interpProgram :: forall m. Monad m => Stream m -> Interp m Unit
```

これで`spago build`するとエラーが無くなるはず。


(**補足**)
`Aff`は`Show`クラスのインスタンスではないので、REPLで出力を試したいなら`launchAff_`を利用する。

{{< cui >}}
> launchAff_ $ run nodeStream (fromString "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.")
Hello World!
{{< /cui >}}

しかし残念ながら`InterpResult Unit`は出力されない。もし出力したいのであれば、`log`とかをつかって出力する関数を新たに作る必要がある。

```haskell
-- 以下のimportを追加
import Effect.Class (class MonadEffect, liftEffect)
import Effect.Console (log)


runWithLog :: forall m. MonadEffect m => Stream m -> Program -> m Unit
runWithLog stream program = do
  res <- run stream program
  liftEffect $ log $ ("\n" <> show res)
```

{{< cui >}}
> launchAff_ $ runWithLog nodeStream (fromString "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]>>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++.")
Hello World!

{ result: (Right unit), state: { dptr: 6, iptr: 106, memory: [0,0,72,100,87,33,10,0,0,0] } }
{{< /cui >}}

## コンソール入力

2つの方法が考えられる。

- [stdin](https://pursuit.purescript.org/packages/purescript-node-process/8.2.0/docs/Node.Process#v:stdin)から
[readString](https://pursuit.purescript.org/packages/purescript-node-streams/5.0.0/docs/Node.Stream#v:readString)を使って文字列を読み取る。
ただし標準入力にデータが来ているかどうかを[onReadable](https://pursuit.purescript.org/packages/purescript-node-streams/5.0.0/docs/Node.Stream#v:onReadable)
で待つ必要がある。`onReadable`にてコールバック関数を指定する。
- [node-readlineパッケージ](https://pursuit.purescript.org/packages/purescript-node-readline/5.0.0)を利用。
プロンプトを表示して入力を促すだけなら[question](https://pursuit.purescript.org/packages/purescript-node-readline/5.0.0/docs/Node.ReadLine#v:question)関数が使いやすいと思う。
`question`にてコールバック関数を指定する。

いずれにせよ、affパッケージの[makeAff](https://pursuit.purescript.org/packages/purescript-aff/6.0.0/docs/Effect.Aff#v:makeAff)を使い、
コールバック処理を`Aff`に変換する必要がある
(後者について、node-readline-affというパッケージがあるようだが、現時点では古いようで利用できない)。

2種類の方法を試みたが、個人的に後者のほうが分かりやすかったのでそちらを紹介する。

該当パッケージをインストール。

{{< cui >}}
% spago install node-readline exceptions
{{< /cui >}}

`src/Stream.purs`を修正。該当モジュールをインポート。

```haskell
import Brainfuck.Error (Error(..))
import Control.Monad.Error.Class (throwError)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String.CodeUnits (take, toChar) as CodeUnits
import Effect.Exception (Error) as E
import Effect.Aff.Class (liftAff)
import Effect.Aff (Canceler, nonCanceler, makeAff)
import Node.ReadLine (createConsoleInterface, noCompletion, close, question, Interface) as RL
```

`input`を実装する。`interface`を作って、`questionAff`(これから実装する関数)を使って入力を促し、文字列を取得。
`close`で`interface`を閉じる。

```haskell
nodeStream :: Stream Aff
nodeStream = Stream { input, output }
  where
    input = do 
      interface <- liftEffect $ RL.createConsoleInterface RL.noCompletion
      s <- liftAff $ questionAff "input> " interface
      liftEffect $ RL.close interface
      case CodeUnits.toChar $ CodeUnits.take 1 s of
        Just c ->
          pure c

        Nothing ->
          throwError CharInputFailed

    output c =
      void $ liftEffect $ writeString stdout UTF8 (CodeUnits.singleton c) (pure unit)
```

`questionAff`は`question`関数を`Aff`用にラッピングしたもの。

```haskell
questionAff :: String -> RL.Interface -> Aff String
questionAff q interface = makeAff go
  where
    go :: (Either E.Error String -> Effect Unit) -> Effect Canceler
    go handler = do
      RL.question q (handler <<< Right) interface
      pure nonCanceler
```

`makeAff`は、

```haskell
  onSomeEvent (\x -> callback x)
```

というように、コールバック関数を引数にとる関数`onSomeEvent`を

```haskell
  x <- onSomeEventAff
  callback
```

みたいに使う関数`onSomeEventAff`に変換するために用いるようだ。

`handler`は`String`ではなく`Either Error String`を持っている。
今回エラーが起こることはないので、コード中では`(handler <<< Right)`のように無理矢理`Right`をくっつけている
(`<<<`演算子を使っているが、これは`(\s -> handler $ Right s)`と同義)。

`Canceler`というのは非同期処理中にキャンセルが起こった場合に呼ばれる関数の模様([参考](https://github.com/purescript-contrib/purescript-aff/tree/main/docs#escaping-callback-hell))。
まだその用途がいまいちよく分かっていないのだが、とりあえず`nonCanceler`を指定しておいた。

### 入力の確認

試したところ、REPLでは動作確認できない模様 (入力待ちになってくれない)。なので`src/Main.purs`に動作確認用のコードを書く。

3文字の入力を促して、アルファベットを1ずらして出力するBrainfuckプログラムを書いてみる。

```haskell
module Main where

import Prelude

import Brainfuck (runWithLog) as B
import Brainfuck.Interp.Stream (nodeStream) as BIS
import Brainfuck.Program (fromString) as BP
import Effect (Effect)
import Effect.Aff (launchAff_)

main :: Effect Unit
main =
  launchAff_ $ B.runWithLog BIS.nodeStream (BP.fromString ",>,>,<<+.>+.>+.")
```

`spago run`で実行してみる。

{{< cui >}}
% spago run
input> a
input> b
input> c
bcd
{ result: (Right unit), state: { dptr: 2, iptr: 15, memory: [98,99,100,0,0,0,0,0,0,0] } }
{{< /cui >}}

ちゃんと`bcd`が出力されている。

## 次回

CUIで可視化することを考える。Brainfuckのインタプリタが各ステップにおいて、どの命令を指しているのか、どこのメモリを指しているのかを可視化してみる。
