---
title: "Elmでテトリスを作った話"
date: 2021-07-26T19:50:48+09:00
tags: ["テトリス"]
categories: ["Elm"]
toc: true
---

Elmでテトリスを作った。この記事では実装にあたって考えたポイントをメモしておく。
コードは説明のために断片的に載せる。

## 製作物

[ここ](https://bombrary.github.io/tetris-elm/)で遊べる．

Repositryは[こちら](https://github.com/bombrary/tetris-elm)。


## 実装しなければいけない処理

大まかに作らなければいけないのは以下の処理．

- ボード・テトリミノのデータ構造
- テトリミノの出現・回転・落下・固定
- テトリミノの衝突判定
- ラインがそろった時に消滅する処理
- ゲームオーバー処理
- キー操作
- 画面描画

この中からいくつかの項目について説明する。

## ボードのデータ構造

ボードの落とす場は10x20のブロックで構成されている。
壁をボードに含めるかどうか、上部にマージンを設けるかどうかで、実際のボードサイズは変わる。

まず、ボードのブロックをセルと呼ぶことにする。セルを次のように定義する。`Color`は適当に定義しておく。

```haskell
type Cell
  = Block Color
  | Empty
```

このセルを使ってボードを定義したいが、悩ましい選択が現れる。

- セルを要素に持つ`List`。セルの座標はリストの添字で判断する。
- (座標, セル)を要素に持つ`List`。
- キーを座標、値をセルとした`Dict`。

`List`を`Array`にした実装も考えられる。参考までに、3つは以下のように定義できる。

```haskell
type alias Board = List Cell

type alias Board = List
  { pos : Vec Int
  , cell : Cell
  }

type alias Board = Dict (Vec Int) Cell
```

ボードのデータ構造によって諸々の関数の実装方法が大きく変わってくるので、どれを選ぶか慎重になる必要がある。

2つ目と3つ目のデータ構造は[elm-gamesのRepository](https://github.com/rofrol/elm-games#tetris)に載っているテトリスのコードから発見した。
それらのコードを見つけた時にはすでに1番目で作ってしまっていたので、現状の自分の実装は1番目のものである。

TEAのView関数としての扱いやすさを考えるなら、2番目の実装が一番良いと思う。例えばセルの描画関数を`viewCell`として、`viewBoard`は次のように書ける。

```haskell
import Svg


viewBoard : Board -> Svg Msg
viewBoard board =
  Svg.g []
    (List.map viewCell board)
```

他のデータ構造で実装する場合でも、`viewBoard`に渡す前に一旦`{ pos, cell }`のデータ構造に変換しておいた方が書きやすい。

座標系については、SVGのものと合わせる。つまり、右向きがx軸正、下向きがy軸正のものとして扱う。

## 寄り道: ベクトルの定義

回転や平行移動などの計算が現れるため、ベクトルを定義しておくと便利。

```haskell
type alias Vec a =
  { x : a
  , y : a
  }
```

適当に`add`や`sub`、`mul`などのベクトル演算を定義しておく。

## テトリミノのデータ構造

以下のように代数的データ型で定義する。

```haskell
type Mino = I | O | L | J | S | Z | T
```

`Mino`の実際の形を定義する必要があるが、考えられるデータ構造は以下の2つ。

- ブロックそのものの2次元データ
- 相対的位置(x, y)のリスト

前者の場合もそこまで難しくはないと思うが、
後者が個人的にシンプルで良いなと思ったので後者を採用する。

後者の場合は、ブロック毎の回転数の最大値を持っていた方が良い。
例えば、Oテトリミノの場合は回転しても向きが変わらないため、回転数1である。
[Super Rotation System](https://tetris.wiki/Super_Rotation_System)を実装する場合は、O以外のテトリミノの回転数は4にする。

また、それ以外にも色の情報があるとよいので、
以下のようなデータ構造を実装することになる。

```haskell
type alias MinoInfo =
  { rotMax : Int 
  , positions : List (Vec Int)
  , color : Color
  }
```

```haskell
info : Mino -> MinoInfo
info mino =
  case mino of
    I ->
      MinoInfo 4 [Vec -2 0, Vec -1 0, Vec 0 0, Vec 1 0] Lightblue

    O -> ...
    L -> ...
```

## テトリミノ関連の実装

### テトリミノの位置データ

落下中のテトリミノの種類、位置、回転数を持つデータ構造を作る。

```haskell
type alias MinoState =
  { mino : Mino
  , pos : Vec Int
  , rot : Int
  }
```

### テトリミノの回転

テトリミノの各座標を回転させれば良い。
(x, y) の座標変換について考える。半時計周りに90度回転させることを考えると、座標変換後は (y, -x) となる。
これは複素数平面を考えるなり、回転行列を掛けるなりして導出できる。ただし、下向きがy軸正になるため、
よくある上向き座標系とは符号が異なることに注意。

```haskell
rotate90 : Vec number -> Vec number
rotate90 ({ x, y } as v) =
  { v | x = y, y = -x }
```

回転を複数回適用するために、`applyN`関数を定義する。例えば、`applyN 3 f`を評価すると`f << f << f`が得られる。

```haskell
applyN : Int -> (a -> a) -> a -> a
applyN n f = List.foldr (<<) identity (List.repeat n f)
```

### テトリミノのボード上への反映

まず絶対座標を計算する関数を作る。`MinoState`の情報をもとに、回転と平行移動の変換を行うたけ。

```haskell
toAbsolute : MinoState -> List (Vec Int)
toAbsolute { mino, pos, rot } =
  let
    { rotMax, positions } = info mino
    rotMod = modBy rotMax rot
  in
    List.map (add pos << applyN rotMod rotate90) positions
```

以下の`putBlock`を定義しておけば、ボードと落下中のテトリミノを統合できる。

```haskell
putBlock : List (Vec Int) -> Cell -> Board -> Board
putBlock positions cell board =
  -- 実装はBoardのデータ構造による
```


### テトリミノの衝突判定

厳密には衝突というより、壁や他のテトリミノに被っているかどうかの判定を行う。
テトリミノが被るケースとして，以下の3つが考えられる．

- 左右移動: 右/左に移動させてみたら被った
- 固定: 下に移動させてみたら被った
- 回転: 回転させてみたら被った

```haskell
overlapped : List (Vec Int) -> Board -> Bool
overlapped ps bord =
  -- 実装はBoardのデータ構造による
```

### テトリミノの固定

1つ下のラインとの衝突判定を行い、判定が真なら固定する。さらに拡張して、次のようにする。

- `lifeTime`というフィールドを用いることで、着地後少しの時間だけテトリミノを動かせるようにする
- 回転キーが押されたら`lifeTime`を初期値に戻す。すると、回転連打している間は固定されないようになる。


## キー状態の管理

長押ししているときはテトリミノが回転しないように実装する。そのためには、キーが長押しされているかどうかを判定する必要がある。

キーが押されたか、離されたかは`onKeyDown`、`onKeyUp`で判定できる。ところが「キーが長押しされているか否か」を判定するのは少し工夫がいる。

判定のために、キーの状態を管理するデータ型を定義する。

```haskell
type KeyState
  = KeyIdle
  | KeyPressed
  | KeyPressing
```

これを用いて、キーの状態を変更する関数を定義する。

```haskell
updateKeyState : Bool -> KeyState -> KeyState
updateKeyState keyDowned state =
  case state of
    KeyIdle ->
      if keyDowned then
        KeyPressed
      else
        KeyIdle

    KeyPressed ->
      if keyDowned then
        KeyPressing
      else
        KeyIdle

    KeyPressing ->
      if keyDowned then
        KeyPressing
      else
        KeyIdle
```

キーが押されたかどうかのフラグとキーの状態は別々に定義しておく必要がある。
なぜなら、ゲームの1ステップのタイミングと、`onKeyUp/onKeyDown`に関する`Msg`が送られてくるタイミングが別だからである。

```haskell
type alias KeyPressFlag =
  { left : Bool
  , right : Bool
  , up : Bool
  , ...
  }

type alias KeyStates =
  { left : KeyState
  , right : KeyState
  , up : KeyState
  , ...
  }
```

前者は`onKeyDown`、`onKeyUp`のときに更新され、後者はタイマーイベントの時に更新されるように実装する。

## 乱数の取得

テトリミノが固定されるたびに、新しいテトリミノが出現する。次の出現するテトリミノを決めるために、
[elm/random](https://package.elm-lang.org/packages/elm/random/latest/)を利用する。

`Cmd Msg`で取得せず、`Random.step`で実装。ただし、初期のシードは`Random.independentSeed`で取得する。

`Random.generate`を使わないのは、今回のケースだと実行順序が分かりづらくなるからだ。
`Random.generate`を使うことで、ランダム値を`Msg`として受け取ることができる。
今回はテトリミノをランダムに発生させたいが、それが起こるのは以下の太字のとき。

1. テトリミノが固定される。
2. **新しいテトリミノが生成される。**
3. そのテトリミノが画面上部におけるかチェックし、できなければゲームオーバー。

もし`Random.generate`を使いたいなら、`Cmd Msg`としてTEAのランタイムに依頼することになる。
例えば擬似的に書くと以下のようになるだろうか。

```haskell
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    ...

    NextMino ->
      -- 新しいテトリミノをセットする処理


    Tick _ ->
      ( erapseTime model
          |> ...
          ...
          |> fixMino
          |> checkGameOver
      , checkNewMino model -- 新しいテトリミノが必要なら乱数生成を依頼する
      )
```


そうなると、コード上で2を書く場所が分断されて読みづらくなる。
それを避けるために、`Random.step`を使うことにした。すると、以下のように順番を意識して書ける。

```haskell
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
  case msg of
    ...

    Tick _ ->
      (model
        |> ...
        ...
        |> fixMino
        |> nextMino -- この関数の中で`Random.step`を使う
        |> checkGameOver
      , Cmd.none
      )
```

## Super Rotation System

回転させてみて衝突が起こった場合は、テトリミノを上下左右に動かせないか試してみる。
動かし方はテトリミノの回転した状態によって異なる。しかもO、Iテトリミノとそれ以外で場合分けが生じる。
これらの情報は[Tetris WikiのWall Kicks](https://tetris.wiki/Super_Rotation_System#Wall_Kicks)に載っている。

Wikiの"J, L, S, T, Z Tetromino Wall Kick Data"、"I Tetromino Wall Kick Data"に注目する。
回転前の状態と回転後の状態に依存していることが分かる。Wiki中の"0, R, L, 2"をそれぞれ次のように表現する。

```haskell
type Direction
    = Zero
    | RotRight
    | RotLight
    | Two
```

`Direction`の取得を行う関数を作成しておく。O以外のテトリミノの`rotMax`は4であることに注意。

```haskell
direction : Mino -> Int -> Direction
direction mino rot =
  let
    { rotMax } = info mino
  in
  case modBy rotMax rot of
    0 ->
      Zero

    1 ->
      RotRight

    2 ->
      Two

    _ ->
      RotLeft
```

Wikiのテーブルの行を返す関数を返す。

```haskell
kickList : Mino -> Direction -> Direction -> List (Vec Int)
kickList before after =
  case mino of
    O ->
      [Vec 0 0]

    I ->
      kickListI before after

    _ ->
      kickListOthers before after


kickListI : Direction -> Direction -> List (Vec Int)
kickListI before after =
  case (before, after) of
    ...


kickListOthers : Direction -> Direction -> List (Vec Int)
kickListOthers before after =
  case (before, after) of
    ...
```

Wikiのtableに書かれていることをコードに手書きするのは面倒。そこでHTMLパーサーをPythonで実装する。

まずWikiの`table`要素2つを、開発者モードやソースコードからコピーしてきて、適当なHTMLファイルに貼り付ける。ここでは`sample.html`としておく。

```html
<table border="1" cellspacing="0">
<caption><b>J, L, S, T, Z Tetromino Wall Kick Data</b>
</caption>
...略
</table>

<table border="1" cellspacing="0">
<caption><b>I Tetromino Wall Kick Data</b>
</caption>
...略
</table>
```

ここではBeautifulSoup4を使ってパースする(余談: 実はBeautifulSoup4を使うのはこれが初めて)。
Wikiの表記では座標系がy軸上向きに取られているため、y座標の符号を反転させる処理を施しておく。

```python
from bs4 import BeautifulSoup
from dataclasses import dataclass
import re


@dataclass
class Vec:
    x: int
    y: int

    def __repr__(self):
        return f'Vec {self.x} {self.y}'


def parse_rot(c):
    if c == '0':
        return 'RotZero'
    elif c == 'R':
        return 'RotRight'
    elif c == 'L':
        return 'RotLeft'
    elif c == '2':
        return 'RotTwo'
    else:
        return '?'


def parse_cond(s):
    [before, after] = [parse_rot(c) for c in s.split('->')]
    return f'({before}, {after})'


def parse_tuple(s):
    [x, y] = [int(c) for c in re.sub(r'[() ]', '' , s).split(',')]
    return Vec(x, -y)


with open("sample.html") as f:
    soup = BeautifulSoup(f, 'html.parser')
    for table in soup.find_all('table'):
        print("[" + table.find('caption').get_text().strip() + "]")
        for tr in table.find_all('tr')[1:]:
            kick_condition = parse_cond(tr.find('td').get_text())
            kick_tests = [parse_tuple(tt.get_text()) for tt in tr.find_all('tt')]
            print(f'{kick_condition} -> \n     {kick_tests}\n')
```

実行すると以下のコードが出力されるので、これをElmのコードにコピペすればよい。

{{< cui >}}
[J, L, S, T, Z Tetromino Wall Kick Data]
(RotZero, RotRight) ->
     [Vec 0 0, Vec -1 0, Vec -1 -1, Vec 0 2, Vec -1 2]

(RotRight, RotZero) ->
     [Vec 0 0, Vec 1 0, Vec 1 1, Vec 0 -2, Vec 1 -2]

(RotRight, RotTwo) ->
     [Vec 0 0, Vec 1 0, Vec 1 1, Vec 0 -2, Vec 1 -2]

(RotTwo, RotRight) ->
     [Vec 0 0, Vec -1 0, Vec -1 -1, Vec 0 2, Vec -1 2]

(RotTwo, RotLeft) ->
     [Vec 0 0, Vec 1 0, Vec 1 -1, Vec 0 2, Vec 1 2]

(RotLeft, RotTwo) ->
     [Vec 0 0, Vec -1 0, Vec -1 1, Vec 0 -2, Vec -1 -2]

(RotLeft, RotZero) ->
     [Vec 0 0, Vec -1 0, Vec -1 1, Vec 0 -2, Vec -1 -2]

(RotZero, RotLeft) ->
     [Vec 0 0, Vec 1 0, Vec 1 -1, Vec 0 2, Vec 1 2]

[I Tetromino Wall Kick Data]
(RotZero, RotRight) ->
     [Vec 0 0, Vec -2 0, Vec 1 0, Vec -2 1, Vec 1 -2]

(RotRight, RotZero) ->
     [Vec 0 0, Vec 2 0, Vec -1 0, Vec 2 -1, Vec -1 2]

(RotRight, RotTwo) ->
     [Vec 0 0, Vec -1 0, Vec 2 0, Vec -1 -2, Vec 2 1]

(RotTwo, RotRight) ->
     [Vec 0 0, Vec 1 0, Vec -2 0, Vec 1 2, Vec -2 -1]

(RotTwo, RotLeft) ->
     [Vec 0 0, Vec 2 0, Vec -1 0, Vec 2 -1, Vec -1 2]

(RotLeft, RotTwo) ->
     [Vec 0 0, Vec -2 0, Vec 1 0, Vec -2 1, Vec 1 -2]

(RotLeft, RotZero) ->
     [Vec 0 0, Vec 1 0, Vec -2 0, Vec 1 2, Vec -2 -1]

(RotZero, RotLeft) ->
     [Vec 0 0, Vec -1 0, Vec 2 0, Vec -1 -2, Vec 2 1]
{{< /cui >}}

## 実装していて気づいたこと

### asパターンマッチ

HaskellやPureScriptの`@`と同じ機能を、`as`として提供しているようだ。以下のように使う。

```haskell
mult : number -> Vec number
mult c ({ x, y } as v) =
  { v
    | x = c * x
    , y = c * y
  }
```

この文法について、[Elmのドキュメント](https://elm-lang.org/docs)では見つけられなかったが、[FAQの方で情報があった](https://faq.elm-community.org/#how-can-i-pattern-match-a-record-and-its-values-at-the-same-time)

### 内部関数のミス

例えば以下のようなコードを書いたとする。このコード自体は以前に書いたもので、今は存在しない。

```haskell
eraseFilledLine field =
    let
        go i fld = {- ...何か再帰的な処理... -}
    in
    go (height - 1) field
```

実は、`fld`を`field`に書き間違えたことによって、無限再帰が発生してしまったことがあった。

このようなミスくらい自分で気づくべきかもしれないが、
ここでは「ミスを起こさないコードを書くためにはどうすればよいのか」について考える。

このミスがコンパイルエラーを引き起こさなかったのは、`go`関数がより外のスコープである`field`に参照できたからである。
よって、初めからこのようなミスを起こす余地をなくすためには、以下のように内部関数をやめてしまうのが良い。

```haskell
eraseFilledLine field =
    eraseFilledLineGo (height - 1) field


eraseFilledLineGo i fld = {- ...何か再帰的な処理... -}
```

しかし、今度は手軽さが失われてしまう。内部関数なら`go`みたいに雑な名前でも、グローバル空間を汚さないので問題ないのだが、
普通の関数として定義するとそうはしづらい。`go`みたいにに命名が雑すぎると、今度はなんのための関数なのか分かりづらくなる。
結局、それぞれ一長一短がある。

### ゲームの背後で行われる処理をモジュールに分割する

`update`関数で行われている処理のうち、テトリスのゲームを進める部分はほんの一部である。
具体的には、タイマーイベントの`Msg`である`Tick`でしかゲームを進める処理を行っていない。

```haskell
update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        ...

        Tick _ ->
            ( elapseTime model
                |> ...
                |> ...
                |> ...
                ...
                |> checkGameOver
            , Cmd.none
            )

        ...
```

コードの見通しをよくするためには、以下の2つに処理を分割すべきなのかなと思った。

- テトリスのゲームを進める処理
- 乱数のシードの処理・キー操作に関する処理

後者を別モジュールに分割して、前者を`Main.elm`で書けるようにすると良いのではないのかと思った。

例えば以下のように関数が定義できると良い。

```haskell
type GameState =
  { time : Int
  , keys : KeyStates
  , seed : Seed
  }

updateGame : GameState -> Model -> Model
updateGame gameState model =
   elapseTime model
      |> ...
      |> ...
      |> ...
      ...
      |> checkGameOver
```
