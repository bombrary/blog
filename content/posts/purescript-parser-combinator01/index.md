---
title: "PureScriptでパーサーコンビネータを触る (1) 四則演算のパース"
date: 2021-12-26T14:55:59+09:00
toc: true
tags: ["parser", "遅延評価"]
categories: ["PureScript"]
---

PureScriptのパーサーコンビネータに[purescript-parsing](https://pursuit.purescript.org/packages/purescript-parsing/7.0.1)がある。これはHaskellの[Parsec](https://hackage.haskell.org/package/parsec)が基になっているので、使い方はParsecとほとんど同じだと思われる(とはいえ、Parsecを使ったことはあまりない)。これを用いて四則演算のパーサーを実装してみたが、うまく動かず詰まる点がいくつかあった。その備忘録。

## パーサーコンビネータの準備

{{< cui >}}
% spago install parsing
{{< /cui >}}

後々使うので以下のパッケージもインストール。

{{< cui >}}
% spago install either integers maybe strings arrays lists
{{< /cui >}}

`src/Main.purs`に以下の記述を追加。

```haskell
import Text.Parsing.Parser (Parser)

parser :: Parser String String
parser = pure "Hello"
```

REPLを起動して、動くか確認する。どんな文字列を食わせても`"Hello"`としか結果を返さないパーサーの完成。

{{< cui >}}
> import Main
> import Text.Parsing.Parser (runParser)
> runParser "hoge" parser
(Right "Hello")
{{< /cui >}}

REPLで`Main.purs`をリロードする場合は`:r`をREPLで実行する。

## 数字のパース

### 1文字取得

1文字の数字を読み取りたいなら、`Text.Parsing.Parser.Token`に`digit`があるのでそれを使う。

```haskell
import Text.Parsing.Parser.Token (digit)


parser :: Parser String Char
parser = digit
```

{{< cui >}}
> runParser "12345" parser
(Right '1')
{{< /cui >}}

### 1文字以上取得

1文字以上を取得したいなら、`Data.Array.Some`を使う。

```haskell
import Data.Array as Array


parser :: Parser String (Array Char)
parser = Array.some digit
```

{{< cui >}}
> runParser "12345" parser
(Right ['1','2','3','4','5'])
{{< /cui >}}

0文字以上の場合は`Data.Array.many`を使えば良い。
ただし、この関数は実装で`(:)`を使っている。この計算量は O(配列の長さ) のため([参考](https://pursuit.purescript.org/packages/purescript-arrays/6.0.1/docs/Data.Array#v:(:)))、
もし効率を重視したいのであれば`Data.List.many`もしくは`Data.List.some`を使えば良い。

`Char`の配列ではなく`String`が欲しいのであれば、`Data.String.CodeUnits.fromCharArray`で変換すれば良い。

```haskell
import Data.String.CodeUnits as CodeUnits

parser :: Parser String String
parser = do
  arr <- Array.some digit
  pure $ CodeUnits.fromCharArray arr
```

{{< cui >}}
> runParser "12345" parser
(Right "12345")
{{< /cui >}}

### 数字を整数値で取得

`Int.fromString`で整数に変換すれば良い。
文脈的にこれに失敗することなどあり得ないのだが、関数の定義上仕方ないため、`Maybe`の値で場合分けをしている。

```haskell
import Text.Parsing.Parser (fail)
import Data.Int as Int
import Data.Maybe (Maybe(..))


integer :: Parser String Int
integer = do
  arr <- Array.some digit
  case Int.fromString (CodeUnits.fromCharArray arr) of
    Just i -> pure i

    Nothing -> fail "parse error"
```

{{< cui >}}
> runParser 12345 integer
(Right 12345)
{{< /cui >}}

### 符号付き整数

最初に符号の有無、有ったとして`+`と`-`のどちらなのかを確認する。

「+または-」を`char '+' <|> char '-'`で表すのはなかなか直感的で良い。

```haskell
import Control.Alt ((<|>))
import Text.Parsing.Parser.String (char)
import Text.Parsing.Parser.Combinators (optionMaybe)


signedInteger :: Parser String Int
signedInteger = do
  sign <- optionMaybe (char '+' <|> char '-')
  i <- integer
  case sign of
    Just '+' ->
      pure i

    Just '-' ->
      pure (-i)

    Nothing ->
      pure i

    _ ->
      fail "parse error" -- ここには来ないはず
```

{{< cui >}}
> runParser "123" signedInteger
(Right 123)

> runParser "+123" signedInteger
(Right 123)

> runParser "-123" signedInteger
(Right -123)
{{< /cui >}}


`fail`があるのが気持ち悪いなら、以下のように書くことも可能。
「符号`+`がついている」「符号`-`がついている」「符号がついていない」の3種類に分離した。

```haskell
integer :: Parser String Int 
integer = do
  arr <- Array.some digit
  case Int.fromString (CodeUnits.fromCharArray arr) of
    Just i -> pure i

    Nothing -> fail "parse error"


plusInteger :: Parser String Int
plusInteger = do
  _ <- char '+'
  x <- integer
  pure x


minusInteger :: Parser String Int
minusInteger = do
  _ <- char '-'
  x <- integer
  pure (-x)


signedInteger :: Parser String Int
signedInteger = integer <|> plusInteger <|> minusInteger
```

ちなみに`plusInteger`と`minusInteger`はもっと短く書ける (いわゆる Applicative style と呼ばれるやつ)。

```haskell
plusInteger :: Parser String Int
plusInteger =
  char '+' *> integer


minusInteger :: Parser String Int
minusInteger =
  (\x -> -x) <$> (char '-' *> integer)
```

### すでに用意されているやつを使う

さて、整数値はトークンの一種である。

`Text.Parsing.Parser.Token`の[makeTokenParser](https://pursuit.purescript.org/packages/purescript-parsing/7.0.1/docs/Text.Parsing.Parser.Token#v:makeTokenParser)と使うと、様々なトークンのパーサーが使えるようになる。
その中に整数値のパーサーがあるため、それを使ってみる。

`makeTokenParser`は、`LanguageDef`型の値を引数にとり、トークンパーサーが詰まったレコードを返す。
`LanguageDef`は、`makeTokenParser`を作るに当たっての設定の入ったレコードである。
`LanguageDef`という名前から察するに、`makeTokenParser`はプログラミング言語を字句解析する目的で使われるのだろう。

今回は特にプログラミング言語のパーサーを作るわけではないので、`Text.Parsing.Parser.Language`の`emptyDef`を指定する。

```haskell
import Text.Parsing.Parser.Language (emptyDef)
import Text.Parsing.Parser.Token (makeTokenParser, GenTokenParser)
import Data.Identity (Identity)


tokenParser :: GenTokenParser String Identity
tokenParser = makeTokenParser emptyDef
```

[GenTokenParserの定義](https://pursuit.purescript.org/packages/purescript-parsing/7.0.1/docs/Text.Parsing.Parser.Token#t:GenTokenParser)を見ると、`integer`フィールドに整数のパーサーがあることがわかる．[ソースコード](https://github.com/purescript-contrib/purescript-parsing/blob/v7.0.1/src/Text/Parsing/Parser/Token.purs#L136-L273)まで見にいくと、各パーサーの説明が書かれているので見ると良い。

```haskell
integer :: Parser String Int
integer = tokenParser.integer
```

{{< cui >}}
> runParser "-123" integer
(Right -123)

> runParser "+123" integer
(Right 123)

> runParser "123" integer
(Right 123)
{{< /cui >}}

## 足し算のパース

手始めに、次のBNFのパーサーを書いてみる。

```
<expr> = <expr> + <integer> | <integer>
```

ただし、ここでは`+`は左結合とし、パース結果を以下の`Expr`に入れる。

```haskell
data Expr = Plus Expr Int | First Int


instance Show Expr where
  show (Plus e i) = "(" <> show e <> "+" <> show i <> ")"
  show (First i)  = show i
```

### エラーになる例

BNF通りに素直に実装すると以下のようになる。

```haskell
expr :: Parser String Expr
expr = plusExpr <|> (First <$> integer)
  where
    plusExpr = do
       e <- expr
       _ <- char '+'
       i <- integer
       pure (Plus e i)
```

ところが、以下のエラーが出る。

```
The value of expr is undefined here, so this reference is not allowed.

See https://github.com/purescript/documentation/blob/master/errors/CycleInDeclaration.md for more information,
or to contribute content related to this error.
```

[エラーのURL先](https://github.com/purescript/documentation/blob/master/errors/CycleInDeclaration.md)を見れば分かるが、要するにJavaScriptコードへの変換の際、`func = func`のような、循環した代入が起こったらしい。

このエラーの原因場所を探るために、エラー場所以外のコードだけに絞る。

まず`plusExpr`を無くす。

```haskell
expr :: parser string expr
expr = (do e <- expr
           _ <- char '+'
           i <- integer
           pure (plus e i))
       <|> (first <$> integer)
```

`First <$> integer`の部分も関係ないので取り除く。

```haskell
expr :: parser string expr
expr = do e <- expr
           _ <- char '+'
           i <- integer
           pure (plus e i)
```

`do`構文を`>>=`に直し、その後半を切り捨てる。

```haskell
expr = expr >>= \e -> char '+'
```

さらに`>>=`は`bind`関数であったから、以下のように書き換える。

```haskell
expr = bind expr (\e -> char '+')
```

この状態でも同じエラーが出ることが確認できる。

実は、`expr`の定義の中に`expr`が含まれていると、定義が循環してしまうため、このようなコンパイルエラーとなる。ただし、`\_ -> expr`のようにラムダ式の中に`expr`が含まれている場合はエラーとはならない。このことについて以下で詳しく見ていくが、細かい話なので面倒な場合は飛ばしても良い。

### (寄り道) どんなJavaScriptコードが生成されるのか

ここでの環境はPureScript 0.14.5を想定する。バージョンが変わると生成されるコードも変わるかもしれない。

適当に`src/Experiment.purs`を作成し、以下のようなコードを書いてみる。`func1`は`inc`をそのまま参照し、`func2`は適当な無名関数で包む。

```haskell
inc :: Int -> Int
inc x = x + 1

func1 :: Int -> Int
func1 = inc

func2 :: Int -> Int
func2 = (\_ -> inc) unit
```

これを`spago build`でビルドすると、JavaScriptのコードが`output/Experiment/indes.js`に生成される。結果は以下のようになっていた。

```js
var Data_Unit = require("../Data.Unit/index.js");
var inc = function (x) {
    return x + 1 | 0;
};
var func2 = (function (v) {
    return inc;
})(Data_Unit.unit);
var func1 = inc;
```

`func1`の方は`inc`をそのまま代入しているが、後者は`inc`が含まれた無名関数を呼び出すような形となっている。

よって、もし次のように書いたとすると、

```haskell
func1 :: Int -> Int
func1 = func1
```

次のようにコードが生成されることが予想できる。右辺の`func1`はこの代入文の時点ではまだ定義されていないため、`undefined`と評価される。実際にはPureScriptコンパイラの方でエラーとなる。

```js
var func1 = func1;
```

もし次のように書いたとすると、

```haskell
func1 :: Int -> Int
func1 = (\_ -> func1) unit


main :: Effect Unit
main = do
  logShow $ func1 0
```

次のようなコードとなる。この`main`関数を実行したいなら、`spago run -m Experiment`とする。

```js
var func1 = (function (v) {
    return func1;
})(Data_Unit.unit);

var main = Effect_Console.logShow(Data_Show.showInt)(func1(0));
```

こちらはPureScriptコンパイラの方では通る。ラムダ式の場合は細かくチェックせずにそのまま無名関数を生成するようだ。しかしコンパイルに成功しても、以下のランタイムエラーが発生する (！)。

{{< cui >}}
TypeError: func1 is not a function
{{< /cui >}}

というのも、`var func1 = ...`の右辺を評価すると`undefined`が返ってくるからである。`func1(0)`が`undefined(0)`と評価され、`undefined`は関数じゃないと怒られている。

要するに、`func1`が定義される前に右辺の`func1`を評価しないで欲しいのである。そのためには次のようにすればよい。

```haskell
func1 :: Int -> Int
func1 = \s -> (\_ -> func1) unit s
```

これは以下のJavaScriptコードに展開される。

```js
var func1 = function (s) {
    return (function (v) {
        return func1;
    })(Data_Unit.unit)(s);
};
```

先ほどと違うのは、関数`function (s) { ... }`に包まれて返ってきた点である。これは関数オブジェクトとして評価され、その中身の`func1`までは評価されない。`function (s) { ... }`の`s`に具体的な値を入れて初めて`func1`が評価される。その時点では`func1`は`undefined`ではなく、ちゃんと関数への参照が入っている。

これは、いわゆる評価を遅延させていることに対応する。遅延評価についての関数・型クラスは[Control.Lazy](https://pursuit.purescript.org/packages/purescript-control/5.0.0/docs/Control.Lazy)で定義されており、`Lazy`型クラスを実装している型でれば`defer`で評価の遅延が行える。関数型`a -> b`は`Lazy`型クラスのインスタンスであるため、次のコードで遅延させることができる (実質上のコードと同じである)。

```haskell
import Control.Lazy (defer)

func1 :: Int -> Int
func1 = defer \_ -> func1
```

とはいえ、`func1`の中で`func1`を呼び出しているので、これは無限再帰となる。

{{< cui >}}
RangeError: Maximum call stack size exceeded
{{< /cui >}}

ちなみに、次のコードはどうだろうか。

```haskell
func1 :: Int -> Int
func1 x = func1 x
```

なんとこれはコンパイルが通り、次のようなコードが生成される。再帰の部分が`while`に置き換えられている (恐らく、末尾再帰最適化が働いた)。実行した際は無限ループとなる。

```js
var func1 = function ($copy_x) {
    var $tco_result;
    function $tco_loop(x) {
        $copy_x = x;
        return;
    };
    while (!false) {
        $tco_result = $tco_loop($copy_x);
    };
    return $tco_result;
};
```

どうやら`func x`のように引数付きで定義していれば、PureScriptのコンパイラは`func`を関数だと認識し、それ専用のコードを生成するらしい。`func = func`と`func x = func x`が区別できていないということは、PureScriptコンパイラはコード生成時に型を考慮していないということなのだろうか (PureScriptコードの型チェックを行うが、JSに変換する際には型の情報を捨てている？)。

遅延評価で`\s -> (\_ -> func1) unit s`のような記述をしたが、この定義は実際には冗長である。もっと簡潔に次のコード

```haskell
func1 :: Int -> Int
func1 = \s -> func1 s
```

で動く。そして以下のJavaScriptコードに展開されるかも、と思うかもしれない。

```js
var func1 = function (s) {
    return func1(s);
};
```

実際、以下の定義とほぼ同じコードが出力される。ただし、末尾再帰最適化が行われるようで、無限再帰ではなく単なる無限ループとなる (そもそも、これは`func x = func x`と同義)。

`defer`を使わず自分で`\s -> ...`を書いて遅延させる分には、上のような簡潔な書き方で良い。しかし`defer`を使う際には必ず`\_ -> func1`の記述が必要になることに注意。実際、

```haskell
func1 :: Int -> Int
func1 = defer func1
```

と書いてしまうと、右辺の`func1`が`undefined`となってしまいコンパイルエラーになる。


### エラーを抑える方法

前節を踏まえて、コンパイルエラーを抑えるため方法がいくつか考えられる (ただし後述するが、コンパイルエラーが無くなるだけで期待した動作はしない)。

1つ目は、余分な`_ <- pure unit`を挟むことである。これだけで、`do`構文を外したときに
`pure unit >>= \_ -> expr >>= ...`のように、`expr`が後ろのラムダ式の中に入る。


```haskell
expr :: Parser String Expr
expr = plusExpr <|> (First <$> integer)
  where
    plusExpr = do
       _ <- pure unit
       e <- expr
       _ <- char '+'
       i <- integer
       pure (Plus e i)
```

2つ目は、`expr`に余分な引数を加えることである。

```haskell
expr :: Unit -> Parser String Expr
expr _ = plusExpr <|> (First <$> integer)
  where
    plusExpr = do
       e <- expr unit
       _ <- char '+'
       i <- integer
       pure (Plus e i)
```

3つ目の方法は、`defer`関数を利用してパーサーの評価を遅延させることである。
`Parser`は`Lazy`型クラスのインスタンスであるから、`defer`が使える。

```haskell
import Control.Lazy (defer)


expr :: Parser String Expr
expr = plusExpr <|> (First <$> integer)
  where
    plusExpr = defer \_ -> do
       e <- expr
       _ <- char '+'
       i <- integer
       pure (Plus e i)
```

### BNFの見直し

さて、コンパイルエラーはなくなったが、実際に実行してみると無限再帰に陥り、ランタイムエラーが発生する。

{{< cui >}}
> runParser "1+2+3+4" expr

RangeError: Maximum call stack size exceeded
{{< /cui >}}

これは、コンパイルエラーを抑えたとしても、「`expr`は`expr`を呼び、その中でさらに`expr`を呼び…」という無限ループは排除できていないからである。

これを解決するには、BNFを見直す必要がある。すなわち、もっと具体的に

```
<expr> = <integer> + <integer> + ... + <integer>
```

と解釈する必要がある。左結合だから、`foldl`みたいな関数を実装すればよいことが分かる。

以下の補助関数`expr'`は、「`+ <integer>`をパースしてみて、失敗したら引数の値を返し、成功したら引数の値と結合させる」という処理を行っている。
これでコードは動作する。

```haskell
expr :: Parser String Expr
expr = do
  i <- integer
  expr' (First i)


expr' :: Expr -> Parser String Expr
expr' e0 =
  plusExpr <|> pure e0
  where
    plusExpr :: Parser String Expr
    plusExpr = do
      _ <- char '+'
      i <- integer
      expr' (Plus e0 i)
```

{{< cui >}}
> runParser "1+2+3+4" expr
(Right (((1)+2)+3)+4)
{{< /cui >}}

ちなみに、`plusExpr`はApplicative styleで次のように書ける。
`'+' <integer>`という文面がここから読み取れるため、慣れると読み易い。

```haskell
plusExpr = Plus e0 <$ char '+' <*> integer
```

### chinlの利用

再び以下のBNFを考える。

```
<expr> = <integer> + <integer> + ... + <integer>
```

実は`Text.Parsing.Parser.Combinators`に`chainl`という関数があり、左結合の式をパースすることができる。
今回は少なくとも1つ式が存在しなければならないバージョンの`chainl1`を使う。

[chainl1](https://pursuit.purescript.org/packages/purescript-parsing/7.0.1/docs/Text.Parsing.Parser.Combinators#v:chainl)
の型は以下の通り。

```haskell
chainl1 :: forall m s a. Monad m => ParserT s m a -> ParserT s m (a -> a -> a) -> ParserT s m a
```

今回の例でいうと、第1引数には`integer`のパーサー、第2引数には`+`のパーサーを入れる。
ただし、第2引数のパーサーの返却値は、`foldl`と同じような`(accumulator, elem)`を引数にとる関数である。

ただし、`foldl`とは違って関数の型がやや弱い。`foldl`の場合は`b -> a -> b`だったが、`chainl`はaccumulatorの型と要素の型が一致していないといけない。そのため、前節の`Expr`を`chainl`で作るのは(おそらく)難しい。


代わりに次のようにする。データ型の方では式の結合順序の情報を無くしてしまう。

```haskell
data Expr = Plus Expr Expr | Elem Int

instance Show Expr where
  show (Plus e1 e2) = "(" <> show e1 <> "+" <> show e2 <> ")"
  show (Elem i) = show i
```

その上で`expr`は次のように書ける。

```haskell
import Text.Parsing.Parser.Combinators (chainl1)

expr :: Parser String Expr
expr = chainl1 (Elem <$> integer) do
  _ <- char '+'
  pure \acc e -> Plus acc e
```

ちなみに以下のようにもっと短く書ける。

```haskell
expr :: Parser String Expr
expr = chainl1 (Elem <$> integer) (Plus <$ char '+')
```

型の定義では結合順序の情報が失われているが、パーサーの方で結合順序が考慮できている。

{{< cui >}}
> runParser "1+2+3+4" expr
(Right (((1+2)+3)+4))
{{< /cui >}}

## 四則演算のパース

四則演算をパースし、その計算をパース結果とするようなプログラムを書く。BNFは以下の通り。

```
<expr> = <expr> + <term> | <expr> - <term> | <term>
<term> = <term> * <factor> | <term> / <factor> | <factor>
<factor> = ( <expr> ) | <integer>
```

数字は整数値しか受け取らないものとし、数値計算の結果は浮動小数点数とする。

今までのことを踏まえて、四則演算を計算するパーサーを書く。

素朴にこれを書くと以下のようになる。

```haskell
expr :: Parser String Int
expr = chainl1 term
  ((char '+' *> pure (+)) <|> (char '-' *> pure (-)))


term :: Parser String Int
term = chainl1 factor
  ((char '*' *> pure (*)) <|> (char '/' *> pure (/)))


factor :: Parser String Int
factor = (char '(' *> expr <* char ')') <|> integer
```

ところが、これは動かない。再び次のエラーにぶつかる。

```
The value of expr is undefined here, so this reference is not allowed.

The value of term is undefined here, so this reference is not allowed.

The value of factor is undefined here, so this reference is not allowed.
```

ちなみにHaskellのParsecライブラリを使うと、以下のコードが動く(簡単のため割り算は省略)。

```haskell
import           Data.Functor.Identity (Identity)
import           Lib
import           Text.Parsec           (Parsec, chainl1, char, (<|>))
import           Text.Parsec.Language  (emptyDef)
import qualified Text.Parsec.Token     as P

type Parser s = Parsec s ()


tokenParser :: P.GenTokenParser String () Identity
tokenParser = P.makeTokenParser emptyDef


integer :: Parser String Integer
integer = P.integer tokenParser


expr :: Parser String Integer
expr = chainl1 term
  ((char '+' *> pure (+)) <|> (char '-' *> pure (-)))


term :: Parser String Integer
term = chainl1 factor
  (char '*' *> pure (*))


factor :: Parser String Integer
factor = (char '('  *> expr <* char ')') <|> integer
```

このようにHaskellとPureScriptで同じコードを書いているにも関わらず異なる動作をする理由は、
評価戦略の違いである。前者は遅延評価だが、後者は正格評価である。

今回の場合、`expr`の中で`term`を参照し、`term`の中で`factor`を参照し、`factor`の中で`expr`を参照するという定義の循環が起こっている。JavaScriptのコードの気持ちになって考えると、これら3つをどのように定義しても、一番最初の宣言の時点で右辺に`undefined`が現れる。例えば、

```js
var expr = ...
var term = ...
var factor = ...
```

の順番で行うと、`var expr = ...`の右辺の`term`はまだ宣言されていないから`undefined`である。また、

```js
var factor = ...
var term = ...
var expr = ...
```

の順番だったとしても、`var factor = ...`の右辺の`expr`がまだ宣言されていないから`undefined`である。このように、定義が循環していると`undefined`が現れてしまう。

これは正格評価だから起こってしまう問題である。もし右辺の値が宣言時に`undefined`とも何とも評価されておらず、パーサーの実行の時にその値が評価されるのであれば、`undefined`ではなく確かに値が入っているはずである。

そこで、以下のように`defer`を挟んで評価を遅延させれば解決できる。

```haskell
expr :: Parser String Int
expr = defer \_ ->
  chainl1 term
    ((char '+' *> pure (+)) <|> (char '-' *> pure (-)))


term :: Parser String Int
term = defer \_ ->
  chainl1 factor
    ((char '*' *> pure (*)) <|> (char '/' *> pure (/)))


factor :: Parser String Int
factor = defer \_ ->
  (char '('  *> expr <* char ')') <|> integer
```

{{< cui >}}
> runParser "1+2+3" expr
(Right 6)

> runParser "4*(1+2+3)" expr
(Right 24)
{{< /cui >}}

### 整数以外の計算

`Int.toNumber`を使うと`Int`から`Number`に変換できる。これで整数以外にも対応できる。
`expr`、`term`、`factor`の型を変更する必要があることに注意。

```haskell
import Data.Int as Int

expr :: Parser String Number

term :: Parser String Number

factor :: Parser String Number
factor = defer \_ ->
  (char '('  *> expr <* char ')') <|> (Int.toNumber <$> integer)
```

### buildExprParserの利用

なんと`Text.Parsing.Parser.Expr`にて、式のパーサーを半自動で生成してくれる関数がある。
手順は以下の通り。

1. 演算子、その優先順位などをまとめた`OperatorTable`を定義。
2. `buildExprParser`で式のパーサーを生成。

`OperatorTable`の定義方法について。[ドキュメント](https://pursuit.purescript.org/packages/purescript-parsing/7.0.1/docs/Text.Parsing.Parser.Expr#v:buildExprParser)には使用例しか書かれていないが、[ParsecのOperatorTable](https://hackage.haskell.org/package/parsec-3.1.15.0/docs/Text-Parsec-Expr.html)と同じだと思われる。
一番外側の`Array`が優先順位を決め、内側の`Array`に演算子の情報を入れる。以下では、次の情報を定義している。

- 中値(`Infix`)演算子`*`と`/`は高順位で、左結合(`AssocLeft`)。
- 中値(`Infix`)演算子`+`と`-`は低順位で、左結合(`AssocLeft`)。

```haskell
import Text.Parsing.Parser.String (string)
import Text.Parsing.Parser.Expr (OperatorTable, Operator(..), Assoc(..))


operatorTable :: OperatorTable
operatorTable =
  [ [ Infix (string "*" $> (*)) AssocLeft
    , Infix (string '/' $> (/)) AssocLeft
    ]
  , [ Infix (string "+" $> (+)) AssocLeft
    , Infix (string '-' $> (-)) AssocLeft
    ]
  ]
```

若干先ほどあげたBNFとずれてしまうが、以下のようにしてパーサーを生成する。
`<term> [*/+-] <term> [*/+-] ...`の形のパーサーを作成できる。

```haskell
term :: Parser String Number
term = (char '(' *> expr <* char ')') <|> integer

expr :: Parser String Number
expr = buildExprParser operatorTable term
```

…としたいが再び `The value of ... is undefined`のエラーがでるので、`defer`を使う。

```haskell
term :: Parser String Number
term = defer \_ ->
  (char '(' *> expr <* char ')') <|> (toNumber <$> integer)

expr :: Parser String Number
expr = defer \_ ->
  buildExprParser operatorTable term
```

ちなみに、`Control.Lazy`の`fix`関数を使うと以下のように書くこともできる。
`fix`関数を使うと、`expr`自身を`\e -> ...`の引数`e`として受け取り、自分自身を再帰させるような処理を書くことができる。
`defer`が消える代わりに、`term`が`expr`に相当する引数を取るようになる。

```haskell
import Control.Lazy (fix)


term :: Parser String Number -> Parser String Number
term e = (char '(' *> e <* char ')') <|> (toNumber <$> integer)

expr :: Parser String Number
expr = fix \e ->
  buildExprParser operatorTable e
```


## まとめ・感想

`makeTokenParser`、`buildExprParser`などの便利な関数があることを知った。

`CycleInDeclaration`のエラーの原因を探るためにかなり時間を使ったが、その分PureScriptコンパイラの動作を、ほんの少しだが垣間見ることができた。

評価戦略の違いにより、HaskellのParsecで書いたコードがそのまま動かない場合があることを実感した。
