---
title: "PureScriptでパーサーコンビネータを触る (2) テキストファイル"
date: 2021-12-31T15:26:00+09:00
toc: true
tags: ["parser"]
categories: ["PureScript"]
---

[前回の記事]({{< ref "posts/purescript-parser-combinator01" >}}) と合わせて1つの記事にする予定だったが、前回があまりに長くなってしまったので分割した。

ある書式に従ったテキストファイルをパースすることを考える。パースしたデータを整形し、HTML文書として出力するところまでやる。

前回インポートした関数で今回使うものは、(漏れが無ければ)以下の通り。

```haskell
import Control.Alt ((<|>))
import Control.Lazy (defer)
import Text.Parsing.Parser (Parser, fail)
import Text.Parsing.Parser.String (char)
```

## テキストの仕様

- テキストファイルは、複数の`entry`で構成される。
- 1つの`entry`はタイトル`title`と中身`body`で構成される。
- `title`は`[`と`]`でくくられる。
- `title`と`body`の間、`body`と次の`entry`の`title`の間には、1つの改行と、0個以上の空行があり得る。それらは`body`には含まない。
- 空行とは、0個以上のスペースだけから構成される行のことである。

BNF風に書くと次のようになるだろう。

```txt
    <entries> = (0個以上の<entry>)
      <entry> = <title> "\n" <empty lines> <body> "\n" <empty lines>
      <title> = "["  (文字列)  "]"
       <body> = (先頭、末尾が<empty lines>でないような文字列)
<empty lines> = (0個以上の<empty line>)
 <empty line> = (0個以上のスペース) "\n"
```

例えば、以下のファイルがあったとする。

```txt
[Title1]
line1
line2
line3
line4


[Title2]


line1
line2
[Title3]

line1

line2


line3
```

これは次のようにパースされる。

```haskell
[ { title: "Title1", body: "line1\nline2\nline3\nline4" }
, { title: "Title2", body: "line1\nline2" }
, { title: "Title3", body: "line1\n\nline2\n\nline3" }
]
```

以下では、`title`、`body`、`entry`の順にパーサーを作成していく。

## titleのパース

`[<text>]`の形の文字列をパースし、`<text>`の部分を取得するパーサーを作成する。
素朴には以下のように書けそうだ。

```haskell
import Data.Array as Array
import Data.String.CodeUnits as String
import Text.Parsing.Parser.String (anyChar)

title :: Parser String String
title = String.fromCharArray <$>
  (char '[' *> (Array.many anyChar) <* char ']')
```

ところが、パースは成功しない。

{{< cui >}}
> runParser "[Title]" title
(Left (ParseError "Expected ']'" (Position { line: 1, column: 8 })))
{{< /cui >}}

というのも、`Array.manny anyChar`は任意の文字を0回以上受け入れてしまうため、その中で`]`もパースされてしまうからだ。

そのため、`anyChar`の代わりに、「`]`以外の文字にマッチするパーサー」を定義すればうまくいく。

```haskell
import Text.Parsing.Parser.String (satisfy)


title :: Parser String String
title = String.fromCharArray <$>
  (char '[' *> (Array.many titleChar) <* char ']')


titleChar :: Parser String Char
titleChar = satisfy (_ /= ']')
```

## bodyのパース

1つの`entry`に対して、`body`の終わりを判定するにはどうすればよいのか。
もし読み取り中に`[<text>]`の文字列を発見したら、次の`entry`に入ったことになるので、これが終了点になるだろう。また、ファイルの終端も`entry`の終了条件となる。
以上のことから、次の手順で`body`をパースしていくことを考える。

1. 先頭の空行を読み飛ばす。
2. `title`、もしくはEOFが来るまでパースし続ける。
3. 最後の空行は`Data.String.Utils`の`trimEnd`関数で取り除く。

`trimEnd`を使うために、パッケージ[purescript-stringutils](https://pursuit.purescript.org/packages/purescript-stringutils/0.0.10/docs/Data.String.Utils)をインストール。

{{< cui >}}
% spago install stringutils
{{< /cui >}}


そのために、まずは空行のパーサーを作成する。

### 空行のパース

準備として改行を読み取るパーサーを作成する。LFとCRLFの2パターンに対応させておく。

```haskell
newline :: Parser String String
newline = do
  c <- anyChar
  case c of
    '\n' ->
      pure "\n"

    '\r' ->
      satisfy (_ == '\n') *> pure "\r\n"

    _ ->
      fail "newline"
```

続いて、空行のパーサーを作成する。今回は、スペースだけが含まれている行も空行とみなす。そこで、空行かどうかを判定するためには、「改行が現れるまでスペースを取り除く」という処理を行えば良い。

これはパーサーの視点に立ってみると、
1. まず`newline`のパースを試みる。成功したらパース終了。
2. `newline`のパースに失敗した場合、スペースのパースを試みる。成功したら1に戻る。

という手順を踏む。これは再帰的なパーサーとなる。

コードにすると以下の通り。Applicative styleにすると`scan`関数に`defer`をつけなくてはいけないのは少し残念なところ。
なお、`Text.Parsing.Parser.String`に`whiteSpace`という関数があるが、これはスペースだけでなく改行文字もパースしてしまうのでここでは使えない。
また配列の結合に`(:)`を使っているが、この計算量に注意 。もし効率を重視したいなら、`Array`ではなく`List`を使えば良い。

```haskell
sp :: Parser String Char
sp = satisfy (_ == ' ')

emptyLine :: Parser String String
emptyLine = String.fromCharArray <$> scan
  where
    scan = defer \_ ->
       ([] <$ newline) <|> ((:) <$> sp <*> scan)
```

実はこれは期待通りに動作しない。パースが成功してほしいところでエラーが返ってくる。

{{< cui >}}
> runParser "      \n" emptyLine
(Left (ParseError "newline" (Position { line: 1, column: 2 })))
{{< /cui >}}

これは、以下のParsecを使ったHaskellのコードでも期待通りに動作しない。

```haskell
type Parser s = Parsec s ()

newline :: Parser String String
newline = do
  c <- anyChar
  case c of
    '\n' ->
      pure "\n"

    '\r' ->
      satisfy (== '\n') *> pure "\r\n"

    _ ->
      fail "newline"

sp :: Parser String Char
sp = satisfy (== ' ')

emptyLine :: Parser String String
emptyLine = ([] <$ newline) <|> ((:) <$> sp <*> emptyLine)
```

これは、`newline`が文字列を消費してしまうからである。
実際、[Parsecの<|>のドキュメント](https://hackage.haskell.org/package/parsec-3.1.15.0/docs/Text-Parsec-Prim.html#v%3a-60--124--62-)を読んでみると、

<blockquote>
If p fails <i>without consuming any input</i>, parser q is tried. 
</blockquote>

と書かれている。これはpurescript-parsingでも同じである (`Alt`型クラス実装のソースコードを見て分かった。しかしドキュメントの記載は見当たらず)。

文字列を消費しないようにするためには、`try`関数を用いれば良い。
[try関数のドキュメント](https://hackage.haskell.org/package/parsec-3.1.15.0/docs/Text-Parsec.html#v:try)にも、`<|>`との併用について詳しく説明されている。

```haskell
import Text.Parsing.Parser.Combinators (try)


newline :: Parser String String
newline = try do -- tryを追加
  -- 略


emptyLine :: Parser String String
emptyLine = String.fromCharArray <$> scan
  where
    scan = defer \_ ->
       ([] <$ newline) <|> ((:) <$> sp <*> scan)
```

{{< cui >}}
> runParser "   \n" emptyLine
(Right "   ")
{{< /cui >}}

ちなみに`fix`関数を使うと、以下のように無名関数で再帰できる。`fix`で指定する関数の引数`self`が、その関数自身を指している。この場合`defer`をつけなくて済む。

```haskell
import Control.Lazy (fix)

emptyLine :: Parser String String
emptyLine = String.fromCharArray <$> fix \self ->
       ([] <$ newline) <|> ((:) <$> sp <*> self)
```

実はこのような、「改行が現れるまでスペースのパースを続ける」という処理は、`manyTill`というパーサーで実現できる。実装は上の場合とほとんど同じだが、効率面の理由で`Array`ではなく`List`を使って実装されている。

パース結果は`List Char`で返ってくるため、`Data.Array.toFoldable`で配列に変換し、`String.fromCharArray`で文字列に変換する。

```haskell
listToString :: List Char -> String
listToString = String.fromCharArray <<< Array.fromFoldable

emptyLine :: Parser String String
emptyLine = try $ listToString <$>
   manyTill sp newline
```

### bodyのパース

まず、titleの後には必ず改行が来るものとする。そのために`titleLine`を定義。

```haskell
titleLine :: Parser String String
titleLine = title <* newline
```

`body`の終了はタイトルまたはEOFとしたいから、そのためのパーサーを作成。

```haskell
import Text.Parsing.Parser.String (eof)


bodyEnd :: Parser String Unit
bodyEnd = try $ (unit <$ titleLine)  <|> eof
```

以上を踏まえて、`body`パーサーを作成する。空行を`skipMany`で読み飛ばし、`bodyEnd`が来るまで文字列を読み取る。最後に`String.trimEnd`で末尾の空行を削除している。

```haskell
import Data.String.Utils (trimEnd) as String
import Text.Parsing.Parser.Combinators (skipMany)


body :: Parser String String
body = String.trimEnd <<< listToString <$> do
  skipMany emptyLine
  manyTill anyChar bodyEnd
```

{{< cui >}}
> runParser "\n\n   aaa\n\nbbb\ncc" body
(Right "aaa\n\nbbb\ncc")

> runParser "\n\n   aaa\n\nbbb\ncc[title]\n" body
(Right "aaa\n\nbbb\ncc")
{{< /cui >}}


## entryのパース

以上の道具立てで、`entry`をパースする。

```haskell
type Entry =
  { title :: String
  , body :: String
  }


entry :: Parser String Entry
entry = do
  t <- title
  b <- body
  pure { title: t, body: b }
```

{{< cui >}}
> runParser "[title]\n\nline1\n\nline2\nline3\n\n\n\n" entry
(Right { body: "line1\n\nline2\nline3\n\n\n\n[title2]", title: "title" })

> runParser "[title]\n\nline1\n\nline2\nline3\n\n\n\n[title2]\n" entry
(Right { body: "line1\n\nline2\nline3", title: "title" })
{{< /cui >}}


## manyTillの問題点とその解決

現在の`entry`は、期待した動作にならない。実際、以下のように複数の`entry`が入ったテキストをパースしてみる。

{{< cui >}}
> runParser "[title1]\nline1\nline2\n[title2]\nline1\nline2" (Array.many entry)
(Right [{ body: "line1\nline2", title: "title1" }])
{{< /cui >}}

本来なら、以下のように2つの`entry`が返ってきて欲しい。

{{< cui >}}
(Right [{ body: "line1\nline2", title: "title1" }
       ,{ body: "line1\nline2", title: "title2" }])
{{< /cui >}}

期待通りに動作しない理由は、`body`パーサーで使っている`manyTill`にある。
この問題をみるために、次のパーサーを定義する。これは、パースの結果だけでなく、まだ消費していない文字列も返すパーサーである。
`Parser`は`StateT`を使って実装されているため、`Parser`の状態を取得するためには`get`を使えば良い。

```haskell
import Control.Monad.State.Class (get)
import Text.Parsing.Parser (ParseState)


verbose :: forall s a. Parser s a -> Parser s { result :: a, remain :: s }
verbose p = do
    result <- p
    ParseState remain _ _ <- get
    pure { result, remain }
```

これを用いて先程の`entry`をパースしてみると、`[title2]`が`remain`に残っていないことが確認できる。
つまり、`entry`によって残って欲しい`[title2]`が消費されてしまったのだ。

{{< cui >}}
> runParser "[title1]\nline1\nline2\n[title2]\nline1\nline2" (verbose entry)
(Right { remain: "line1\nline2", result: { body: "line1\nline2", title: "title1" } })
{{< /cui >}}

実は、`body`パーサーの`manyTill anyChar bodyEnd`の部分に問題がある。例えば以下のようなパースを実行すると、`manyTill p end`の`end`の部分が消費されていることが分かる。今回の目的としては、`end`の部分は消費されてほしくない。


{{< cui >}}
> runParser "aaabbbccc" $ verbose (manyTill anyChar (string "bbb"))
(Right { remain: "ccc", result: ('a' : 'a' : 'a' : Nil) })
{{< /cui >}}

そこで、`manyTill p end`の`end`が消費されないようなパーサーを作る必要がある。この関数を、今回は`manyTill_`という名前にする。消費されないようにするためには、`lookAhead`を使う。

```haskell
import Text.Parsing.Parser.Combinators (lookAhead)


manyTill_ :: forall s a b. Parser s a -> Parser s b -> Parser s (List a)
manyTill_ p end = scan
  where
    scan = defer \_ ->
      (Nil <$ lookAhead end) <|> (Cons <$> p <*> scan)
```

これでちゃんと`end`が消費されなくなる。

{{< cui >}}
> runParser "aaabbbccc" $ verbose (manyTill_ anyChar (string "bbb"))
(Right { remain: "bbbccc", result: ('a' : 'a' : 'a' : Nil) })
{{< /cui >}}

それでは`body`パーサーを修正する。`manyTill`を`manyTill_`に置き換える。

```haskell
body :: Parser String String
body = String.trimEnd <<< listToString <$> do
  skipMany emptyLine
  manyTill_ anyChar bodyEnd
```

{{< cui >}}
> runParser "[title1]\nline1\nline2\n[title2]\nline1\nline2" (Array.many entry)
(Right [{ body: "line1\nline2", title: "title1" },{ body: "line1\nline2", title: "title2" }])
{{< /cui >}}

## 標準入力から読み取る

`node`の機能を使う。標準入力からの読み取りに関連するライブラリをインストール。

{{< cui >}}
% spago install node-streams node-process node-buffer refs
{{< /cui >}}

`stdin`からの読み取りを行う。`node`の関数をそのままラッピングしているようで、以下のようにコールバック関数を使って処理を書く必要がある。
`onDataString`は文字列が送られてきたとき、`onEnd`は読み取りが終了したときに発生するイベント。
やってきた文字列を`ref`に連結していく。

とりあえずここでは、単に入力した文字列をパースするだけとする。

```haskell
import Effect.Ref as Ref
import Node.Stream as NS
import Node.Process (stdin)
import Node.Encoding (Encoding(..))


onEndInput :: String -> Effect Unit
onEndInput input =
  log $ show $ runParser input (Array.many entry)

main :: Effect Unit
main = do
  ref <- Ref.new ""
  NS.onDataString stdin UTF8 \s ->
    Ref.modify_ (_ <> s) ref

  NS.onEnd stdin do
    s <- Ref.read ref
    onEndInput s
```

次のようなテキストファイルを作り、`sample.txt`として保存する。

```txt
[Title1]
line1
line2
line3
line4


[Title2]


line1
line2
[Title3]

line1

line2


line3
```

実行してみると、正しくテキストファイルがパースされていることが確認できる (見やすいように改行してある)。

{{< cui >}}
% spago run < sample.txt

(Right [{ body: "line1\nline2\nline3\nline4", title: "Title1" }
       ,{ body: "line1\nline2", title: "Title2" }
       ,{ body: "line1\n\nline2\n\n\nline3", title: "Title3" }])
{{< /cui >}}

## (おまけ) HTML文書への変換

せっかくなので、データをHTML文書に書き起こしてみる。変換の仕様は以下の通り。

- 1つの`entry`は`div`で括る
- `title`は`h1`タグで括る
- `body`は`pre`タグで括る

まず簡単にHTML要素のデータ型を作成する。

```haskell
data HTMLElem
  = Div (Array HTMLElem)
  | Pre String
  | H1 String


instance Show HTMLElem where
  show (Div elems) =
    "<div>\n" <> (Array.intercalate "" $ map show elems) <> "</div>\n"
  show (Pre text) =
    "<pre>" <> text <> "</pre>\n"
  show (H1 text) =
    "<h1>" <> text <> "</h1>\n"
```

1つの`entry`をHTMLに変換する関数を作成。

```haskell
entryToHTML :: Entry -> HTMLElem
entryToHTML { title, body } =
  Div
    [ H1 title
    , Pre body
    ]
```

最後に、`onEndInput`を修正する。`entry`をHTMLに変換し、それを`log`で出力。

```haskell
onEndInput :: String -> Effect Unit
onEndInput input =
  case runParser input (Array.many entry) of
    Right entries ->
      logShow $ Div (map entryToHTML entries)

    Left e ->
      logShow e
```

これで`spago run < sample.txt`を実行すると、以下のHTMLが出力される。

```html
<div>
<div>
<h1>Title1</h1>
<pre>line1
line2
line3
line4</pre>
</div>
<div>
<h1>Title2</h1>
<pre>line1
line2</pre>
</div>
<div>
<h1>Title3</h1>
<pre>line1

line2


line3</pre>
</div>
</div>
```

## (おまけ) パーサーコンビネータを使わない方法

今回みるべきは行ごとである。このような、行に分けられる書式のデータについては、`lines`関数で切り出して1行ずつ見ていく手法の方が、実は手軽だったりしないのか。
そこで、パーサーコンビネータを(ほぼ)使わずに、テキストファイルのパーサーを実装してみた。

結果として、「ここには`try`を入れなくてはいけない」みたいなハマりポイントは無く実装できたが、再帰関数をどう実装するか、どんな手順でパースしていけばよいのか、どう機能を分割すれば見通しの良いコードが書けるかなどでかなり時間を使った。

結局、以下の手順でパースすることで落ち着いた。

1. `Data.String.Utils`の`lines`関数で、テキストを行ごとに分割。
2. 再帰関数で実装する。関数の引数に、`(暫定entry, 未消費の行)`を持たせる。
3. 未消費の行から1つ取って、それがタイトルなのか、そうでないのかを調べる。
   - もしタイトルなら、次の`entry`に入ったということなので、暫定だった`entry`
   - そうでないなら、それを暫定`entry`の`body`部にくっつける。
4. `title`と`body`の間の空行は読み飛ばす。`body`と次の`title`の間の空行は、後で`String.trimEnd`で取り除く。

別ファイルを作ってコードを書く。ファイルは`src/LineParser.purs`とでもしておく。

天下り的だが、以下の文を先頭に書く。

```haskell
module LineParser where

import Prelude

import Text.Parsing.Parser (Parser, runParser)
import Text.Parsing.Parser.String (char, satisfy)
import Data.String.CodeUnits (fromCharArray, toCharArray) as String
import Data.String.Utils (lines, trimEnd) as String
import Data.Array as Array
import Data.List as List
import Data.List (List(..))
import Data.Either (isRight) as Either
import Data.Maybe (Maybe(..))
```

### 行の種類を判別する関数

`title`か否かを判別する関数を作る。これに関しては`Text.Parsing.Parser`の`Parser`を使わせてもらう。

```haskell
parserTitle :: Parser String String
parserTitle = String.fromCharArray <$>
  (char '[' *> (Array.many $ satisfy (_ /= ']')) <* char ']')

isTitle :: String -> Boolean
isTitle text = Either.isRight $ runParser text parserTitle
```

### 空行を取り除く関数

空行を取り除く関数`dropEmptyLines`を作成。

```haskell
allSpaces :: String -> Boolean
allSpaces = Array.all (_ == ' ') <<< String.toCharArray


dropEmptyLines :: List String -> List String
dropEmptyLines = List.dropWhile allSpaces
```

### Entryとそれを操作するユーティリティ関数

`title`だけ入った`entry`を作成する関数。`body`に追記する関数、`body`の末尾の空行を取り除く関数を作成する。

```haskell
type Entry =
  { title :: String
  , body :: String
  }


newEntry :: String ->  Entry
newEntry newTitle =
  { title: newTitle, body: "" }


appendBody :: String -> Entry -> Entry
appendBody line entry = 
  case entry.body of
    "" ->
        entry { body = line }

    _ ->
        entry { body = entry.body <> "\n" <> line }
        
trimBodyEnd :: Entry -> Entry
trimBodyEnd entry =
  entry { body = String.trimEnd entry.body }
```

### 再帰関数

テキスト中に初めて現れる`title`を見つける関数`findFirstTitle`を作成。
これを用いて、本命の`parseEntries`を作成。

```haskell
findFirstTitle :: List String -> Maybe { title :: String, rest :: List String }
findFirstTitle Nil = Nothing
findFirstTitle (Cons x xs) =
  if isTitle x then
    Just { title: x, rest: xs }
  else
    findFirstTitle xs


parseEntries :: String -> Array Entry
parseEntries text =
  case findFirstTitle allLines of
    Nothing ->
      []

    Just { title, rest } ->
      Array.fromFoldable $ map trimBodyEnd $ scan { title, body: "" } rest
  where
    allLines :: List String
    allLines = Array.toUnfoldable $ String.lines text 

    scan :: Entry -> List String -> List Entry
    scan entry Nil = Cons entry Nil
    scan entry (Cons line lines) =
      if isTitle line then
        Cons entry $
             scan (newEntry line)
                  (dropEmptyLines lines)
      else
        scan (appendBody line entry) lines
```

`parseEntries`のコード量がだいぶ大きくなってしまった(自分の力量不足もある)。
`parseEntries`が何をやっているのかについて、パッとみて分かるとは言いづらい。

### テキストファイルのパース

`src/Main.purs`に戻り、`onEndInput`を次のようにすれば、作ったパーサーが動くことが確かめられる。

```haskell
import LineParser (parseEntries)


onEndInput :: String -> Effect Unit
onEndInput input = 
  log $ show $ Div (map entryToHTML $ parseEntries input)
```

## まとめ・感想

`skipMany`、`lookAhead`、`manyTill`など、色々なパーサーを使うことができた。また`try`がどんなところが役に立つのかを知ることができた。

`Parser`の内部状態を取得するには`get`を使えば良いという点については、個人的に盲点だった。

パーサーコンビネータを使う方法と使わない方法で比べてみた。前者はパーサーという小さな関数に分け、それを組み合わせるようなコーディングをすることになるため、
1つのパーサーあたりの記述量は比較的少ない。そのため、後者に比べ読みやすいコードが書けるのではないかと思う。ただし、デフォルトで用意されているパーサーの性質、パーサーの動作など、いくつか注意しなければならないところはある。
