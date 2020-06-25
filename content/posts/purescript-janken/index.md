---
title: "PureScriptでじゃんけんゲーム(CUI)を作る"
date: 2020-06-25T09:05:09+09:00
toc: true
tags: ["じゃんけん", "Node.js", "CUI"]
categories: ["PureScript"]
---

プログラミングの初歩で作りそうなじゃんけんゲームを作る。ただし、PureScriptで作る。

## 方針

- `Janken`というモジュールを作る
  - グー・チョキ・パーを`Hand`として定義する
  - じゃんけんの勝負の結果を`Judgement`として定義する
  - コンピュータが出す手はランダムに出したいので、ランダムな手を出す関数`random`を作っておく
  - 入力は文字列にしたいので、文字列から手に変換する関数`fromString`を作っておく
- 入出力は`Main`に書く。`Node.ReadLine`モジュールの力で入力を受け付ける。

## 準備

適当なプロジェクトディレクトリを作っておいて、

{{< cui >}}
$ spago init
{{< /cui >}}

`/src/Main.purs`と`/src/Janken.purs`を作っておく。

`/src/Main.purs`はとりあえず以下のようにしておく。

```haskell
module Main where

import Prelude

import Effect (Effect)
import Effect.Console (log)

main :: Effect Unit
main = do
  log "Hello"
```

次のコマンドで`Hello`が出力されることを確認する。

{{< cui >}}
$ spago run
{{< /cui >}}

## Jankenモジュールの定義

この節では`/src/Janken.purs`を編集していく。

```haskell
module Janken where

import Prelude
```

### Handの定義

じゃんけんの手を表す型`Hand`を定義する。

```haskell
data Hand = Rock | Scissors | Paper
```

余談。これは公式では[タグ付き共用体](https://github.com/purescript/documentation/blob/master/language/Types.md#tagged-unions)と呼ばれているもの。Haskellでは代数的データ型と呼ばれているが、正直名前はどうでもいい。データをこのように表現すれば、「データはこの値しかとりえない」という制限が得られる。制限があれば、プログラムのバグも減らせる。たとえば、「グーを0、チョキを1、パーを2」として表現すると、万が一それ以外の値が来た場合に困る。上のような`Hand`の定義では、「それ以外の値」が入る余地すら与えない。&hellip;この話は、[Elm Guide](https://guide.elm-lang.jp/appendix/types_as_sets.html)の受け売り。

### Judgementの定義

同じようにして、じゃんけんの勝敗を表す型`Judgement`を定義する。

```haskell
Judgement = WinLeft | WinRight | Draw
```

なぜ`Win`とか`Lose`ではないのかというと、これは`judge`関数の都合である。`Judge`は、2つの手を引数にとり、その勝負結果を返す。`Win`や`Lose`だと、どっちが勝ちでどっちが負けか分からない。なので、「`judge`の左側の引数が勝ったら`WinLeft`、右側が勝ったら`WinRight`、引き分けなら`Draw`」と定義している。

```haskell
judge :: Hand -> Hand -> Judgement
judge Rock Rock = Draw
judge Scissors Scissors = Draw
judge Papser Paper = Draw
judge Rock Scissors = WinLeft
judge Scissors Paper = WinLeft
judge Paper Rock = WinLeft
judge _ _ = WinRight
```

### REPLで遊ぶ

REPLでテストしてみたい。`Show`クラスのインスタンスにすることで、REPLで値が出力できるようになる。

```haskell
data Hand = Rock | Scissors | Paper

-- 追加
instance showHand :: Show Hand where
  show Rock = "Rock"
  show Scissors = "Scissors"
  show Paper = "Paper"

data Judgement = WinLeft | WinRight | Draw

-- 追加
instance showJudgement :: Show Judgement where
  show WinLeft = "WinLeft"
  show WinRight = "WinRight"
  show Draw = "Draw"
```

{{< cui >}}
$ spago repl
> import Janken
> judge Rock Rock
Draw

> judge Rock Paper
WinRight

> judge Rock Scissors
WinLeft
{{< /cui >}}

### ランダムに出す手の定義

まずは乱数を扱えるパッケージを導入する。

{{< cui >}}
$ spago install random
{{< /cui >}}

モジュールを読み込み、`random`を定義する。

乱数は副作用付きなので、`Effect Hand`型を返す。

```haskell
import Effect (Effect)
import Effect.Random (randomInt) as Random

...

random :: Effect Hand
random = do
  n <- Random.randomInt 0 2
  case n of
       0 -> pure Rock
       1 -> pure Scissors
       _ -> pure Paper
```

## 文字列 &rarr; 手に変換する関数の定義

Rock、Scissors、Paper以外の値が入力されたら変換に失敗するため、関数の型は`Maybe Hand`である。なので、`Maybe`が入ったパッケージを導入する。

{{< cui >}}
$ spago install maybe
{{< /cui >}}

```haskell
import Data.Maybe (Maybe(Just, Nothing))

...

fromString :: String -> Maybe Hand
fromString "Rock" = Just Rock
fromString "Scissors" = Just Scissors
fromString "Paper" = Just Paper
fromString _ = Nothing
```

REPLで遊んでみる。

{{< cui >}}
> import Prelude
> import Janken
> judge Rock <$> fromInt "Rock"
(Just Draw)

> judge Rock <$> fromInt "Scissors"
(Just WinLeft)

> judge Rock <$> fromInt "Paper"
(Just WinRight)

> judge Rock <$> fromInt "aaa"
Nothing

> judge Rock <$> fromInt "hoge"
Nothing
{{< /cui >}}

## 入出力インターフェースの作成

この節では、`/src/Main.purs`を編集していく。

まず`readline`が使えるパッケージを導入する。

{{< cui >}}
$ spago install node-readline
{{< /cui >}}

このパッケージには`Node.js`の`readline`をPureScript用にラッピングしただけので、使い勝手はそれと似ている。

使う流れとしては、

1. `createConsoleInterface`でCUIの入力を受け付けるインターフェースを作る
2. `setLineHandler`で、入力が確定されたときのコールバック関数を指定する。

だけ。だけなのだが、入力が不正だった場合は再度入力を促すようにするので、少しコードが複雑になる。

### import文の追加

とりあえずこれだけ書いておく。

```haskell
import Janken as Janken 
import Janken (Judgement(WinLeft, WinRight, Draw), Hand)
import Data.Maybe (Maybe(Just, Nothing))
import Node.ReadLine as NR
```

### インターフェースの作成

`createConsoleInterface`で、コンソール用のインターフェースを作成する。引数には入力補完のための設定を入れるのだが、詳細は[Node.ReadLineのドキュメント](https://pursuit.purescript.org/packages/purescript-node-readline/4.0.1/docs/Node.ReadLine)や[readlineのドキュメント](https://nodejs.org/api/readline.html#readline_use_of_the_completer_function)を参照。今回は補完は必要ないので、`noCompletion`を指定している。

`runGame`は次で作る。

```haskell
main :: Effect Unit
main = do
  interface <- NR.createConsoleInterface NR.noCompletion
  runGame interface
```

### 入力処理の作成

`runGeme`では、入力を促し、それに応じて処理する機構を書く。

`setLineHandler`で、指定されたインターフェースに入力を促す。入力した文字列は`handler`に回され、処理される。`prompt`でプロンプトを出力する。プロンプトの内容は`setPrompt`で設定できる。

`handler`では、まず入力文字列が正しいものかを判定する。正しかったら、相手の手をランダムに作って、判定を行う。`close`でインターフェースを閉じる。もし入力が正しくなかったら、`setLineHandler`を再び呼んで再度入力を促す。

```haskell
runGame :: NR.Interface -> Effect Unit
runGame interface = do
  let handler :: String -> Effect Unit
      handler input = 
        case Janken.fromString input of
          Just yourHand -> do
            computerHand <- Janken.random
            printJudgement yourHand computerHand
            NR.close interface
          Nothing -> do
            log "Type Rock, Scissors, or Paper."
            NR.setLineHandler interface handler
            NR.prompt interface
  NR.setPrompt "> " 2 interface
  NR.prompt interface
  NR.setLineHandler interface handler
```

`printJudgement`では、じゃんけんの勝敗を出力する。

```haskell
printJudgement :: Hand -> Hand -> Effect Unit
printJudgement yourHand computerHand = do
  log $ "You: " <> show yourHand
  log $ "Computer: " <> show computerHand
  case Janken.judge yourHand computerHand of
      WinLeft -> log "You win!"
      WinRight -> log "You lose."
      Draw -> log "Draw."
```

### 完成

{{< cui >}}
$ spago run
> hoge
Type Rock, Scissors, or Paper.
> Rock
You: Rock
Computer: Scissors
You win!
{{< /cui >}}

## 感想

PureScriptを書く良い練習になった。

`Janken`ではなく`Janken.Hand`と`Janken.Judgement`というモジュールに分割すべきか、と悩んだ。そうすれば、`Janken.fromString`ではなくて`Janken.Hand.fromString`と書けて、より意味が明らかになる。ただ、そこまで大きなコードではないのでまとめてしまった。

今回`Node.ReadLine`モジュールを使ったが、そもそもNode.jsの`readline`を使ったことがなかった。調べてなんとかなった。
