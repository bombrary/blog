---
title: "LuaのパターンマッチングライブラリLPegを用いて四則演算の文法をパースする"
date: 2025-11-03T08:00:00+09:00
tags: [ "LPeg" ]
categories: [ "lua" ]
---

## 前置き

* PandocでRedmineのwiki記法（textile）をGitLab Flavor Markdownに変換したかった
* しかしデフォルトのReaderだと完全な変換は不可能
    * Redmineのマクロに対応できない。特に `{{collapse(...) ...}}` マクロを折り畳み形式に変換したい
    * パース後にLua filterで修正する方針もやろうとしたが、ASTの木構造を書き換えるレベルの修正が必要になり力尽きた
        * 箇条書きの中に `collapse` が含まれているケースがきつい
* ところでPandocにはCustom Readerという機能があり、Luaを使って自分でReaderをかける
    * [Pandoc - Creating Custom Pandoc Readers in Lua](https://pandoc.org/custom-readers.html)
* LPegというライブラリを使えばBNFっぽい書き方で文法が書けて楽そう

という経緯があり、まずLuaのLPegライブラリを勉強することにした。以下はその備忘録。

## やること

* 四則演算の式を木構造（入れ子のテーブル構造）にパースすることが目的。
    * 逆に、木構造に変換した後の処理はしない。例えば式を評価して計算値を出すことはここではやらない。
* 文法の正しさをチェックするために、ユニットテストを適宜書きながらコードを書いていく
    * テスト駆動開発的にやっていく

## 免責事項

自分はLuaをほとんど書いたことがない。ほとんど雰囲気で書いており、何らかのベストプラクティスから外れている書き方をしている可能性がある。

## LPegとは

公式サイト： [LPeg - Parsing Expression Grammars For Lua](https://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html)

PEG（Parsing Expression Grammer）がベースとなるパターンマッチングライブラリ。PEGというのは今回自分も初めて知った。どうやらCFG（Context Free Grammer; 文脈自由文法）とはまた別の形式文法らしい。

[Parsing expression grammar - Wikipedia](https://ja.wikipedia.org/wiki/Parsing_expression_grammar)

「最初の解析がうまくいったらそれを、失敗なら次を順に試してゆき、成功したものを採用」という点がCFGとの違いの一つみたいで、これでCFGが持つ曖昧さを排除できるとか。

## 実行環境の準備

以下が入った環境を準備する。
* Luaのインタプリタ
* Luaのライブラリ
    * [LPeg](https://www.inf.puc-rio.br/~roberto/lpeg/lpeg.html)：PEG用のライブラリ
    * [busted](https://lunarmodules.github.io/busted/)：ユニットテスト用のライブラリ

### 一例： Nixで環境を用意する場合

Nix flakeで環境を準備する場合、以下を `flake.nix` として作成して `nix develop` コマンドを実行すれば、Luaの実行環境が作成される。

```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let pkgs = nixpkgs.legacyPackages.${system}; in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            (lua.withPackages(ps: with ps; [ lpeg busted ]))
          ];
        };
      }
    );
}
```

## テスト環境の準備

* メインのコードは `main.lua` に書くようにする
* テストは `test.lua` に書くようにする

まず `test.lua` に以下を記載。`main` に含まれる `add` 関数（まだ未定義）のテストを試しに書いてみる。

```lua
require "busted.runner" ()

local main = require "main"

describe("test for grammer", function()
  it("test", function()
    local n = main.add(1, 1)
    assert.True(n == 2)
  end)
end)
```

`busted test.lua` でテスト結果が出る。想定通りエラーが出る。

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
true
✱
0 successes / 0 failures / 1 error / 0 pending : 0.000492 seconds

Error → test.lua @ 7
test for grammer test
test.lua:8: attempt to index global 'main' (a boolean value)
```

続いて `main.lua` に `add` 関数を追加する。

```lua
return {
  add = function(a, b) return a + b end
}
```

今度はテストを通過する。
```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●
1 success / 0 failures / 0 errors / 0 pending : 0.000464 seconds
```

これで busted の動作確認と main が読まれることの動作確認ができた。

## 四則演算のパース

早速四則演算を定義していこう。

### 文法（Grammer）の準備

* [Pandoc - Creating Custom Pandoc Readers in Lua](https://pandoc.org/custom-readers.html#example-plain-text-reader) の例に習って、lpegで使う関数をローカル変数に入れる
* 文法を `G = P { ... }` の中に記述していく
    * `P` 関数はテーブルを引数にとると [Grammers](https://www.inf.puc-rio.br/~roberto/lpeg/#grammar) を意味する
        * テーブルの中身が未定義だとエラーになるので、適当な値を入れている
    * `P` 関数は文字列を引数にとると、「文字列に完全マッチするようなパターン」を意味する


```lua
local lpeg = require "lpeg"
local P, S, R, Cf, Cc, Ct, V, Cs, Cg, Cb, B, C, Cmt =
  lpeg.P, lpeg.S, lpeg.R, lpeg.Cf, lpeg.Cc, lpeg.Ct, lpeg.V,
  lpeg.Cs, lpeg.Cg, lpeg.Cb, lpeg.B, lpeg.C, lpeg.Cmt

local G = P {
  "Dummy",
  Dummy = P("dummy"),
}

return {
  G = G,
}
```

### 整数の定義

整数とは、`0` から `9` の連続した数字の集まりで、負数の場合は先頭に `-` が付く。そのようにテストを書く。
* `match` 関数は、文字列をパースし、マッチした文字の次の位置を返す。ただし **文法のパターンがキャプチャされている場合は、その値を返す** 。

```lua
local lpeg = require "lpeg"
local main = require "main"

describe("main test", function()
  describe("test for grammer", function()
    it("number", function()
      local r = main.G:match("123")
      assert.are.same("123", r)

      local r = main.G:match("-34")
      assert.are.same("-34", r)

      local r = main.G:match("0")
      assert.are.same("0", r)

      local r = main.G:match("-0")
      assert.are.same("-0", r)
    end)
  end)
  describe("lpeg test", function()
    it("match関数の動作確認", function()
      -- P("string") で "string" にマッチするパターンを定義
      local result = lpeg.P("12"):match("123")
      assert.are.same(3, result) -- 1-2文字がマッチして、その直後の位置3が帰ってくる

      -- Cでマッチしたパターンをキャプチャする
      local result = lpeg.C(lpeg.P("12")):match("123")
      assert.are.same("12", result) -- キャプチャした値が返ってくる
    end)
  end)
end)
```

この時点では文法が定義されていないのでエラーになる。
```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
◼●
1 success / 1 failure / 0 errors / 0 pending : 0.0012 seconds

Failure → test.lua @ 8
main test test for grammer number
test.lua:10: Expected objects to be the same.
Passed in:
(nil)
Expected:
(string) '123'
```

実際に文法を書いてみよう。[Parsing expression grammar - Wikipedia](https://ja.wikipedia.org/wiki/Parsing_expression_grammar) で定義されている文法で書くと、整数は次のようになる。
* `?` は直前の文字が現れる個数が0または1であるパターン
* `[0-9]` は`0`から`9`の数字のパターン
* `+` は直前の文字が連続して1個以上現れるパターン

```txt
Number <- "-"? [0-9]+
```

これをLPegで書くと次のようになる。
* パターンについて
    * `^-1` は直前の文字が現れる個数が0または1であるパターン
    * `R(09)` は`0`から`9`の数字のパターン
    * `^1` は直前の文字が連続して1個以上現れるパターン
* `C` でマッチした値をキャプチャ
* `Number` がこの文法の始点であることを示すために、テーブルの第一要素に `"Number"` を書く
* `*` 演算子は文字の連接を意味する

```lua
local G = P {
  "Number",
  Number = C(P("-")^-1 * R("09")^1)
}
```

これでテストが通る。

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●
2 successes / 0 failures / 0 errors / 0 pending : 0.001204 seconds
```

### 式（Expr）の定義

`1+1` や `1-1` のような、足し算と引き算をパースできるようにしよう。パースして、それぞれ `{ 1, +, 1 }` や `{ 1, -, 1 }` のような単位に分解して返すようにする。

* マッチした文字列をテーブルで返すようにするためには `Ct` を使う。
* 今後、式がテーブルを返すようになるので、 `number` のテストの出力結果もテーブルになる

```lua
describe("main test", function()
  describe("test for grammer", function()
    it("number", function()
      local r = main.G:match("123")
      assert.are.same({ "123" } , r)

      local r = main.G:match("-34")
      assert.are.same({ "-34" }, r)

      local r = main.G:match("0")
      assert.are.same({ "0" }, r)

      local r = main.G:match("-0")
      assert.are.same({ "-0" }, r)
    end)

    it("expr", function()
      local r = main.G:match("1+1")
      assert.are.same({ "1", "+", "1" }, r)

      local r = main.G:match("1-1")
      assert.are.same({ "1", "-", "1" }, r)

      local r = main.G:match("12+345")
      assert.are.same({ "12", "+", "345" }, r)

      local r = main.G:match("-12-345")
      assert.are.same({ "-12", "-", "345" }, r)
    end)
  end)

  describe("lpeg test", function()
    -- 中略

    it("CとCtの動作確認", function()
      -- Cでマッチしたパターンをキャプチャする
      local pat = lpeg.C(lpeg.P("12")) * lpeg.C(lpeg.P("34"))
      local result1, result2 = pat:match("12345") -- 多値で返ってくる
      assert.are.same("12", result1)
      assert.are.same("34", result2)

      -- CでマッチしたパターンをキャプチャしてそれをさらにCtでキャプチャ
      local pat = lpeg.Ct(lpeg.C(lpeg.P("12")) * lpeg.C(lpeg.P("34")))
      local result = pat:match("12345") -- テーブルで返ってくる
      assert.are.same({ "12", "34" }, result)
    end)
  end)
end)
```

今の実装ではテストは通らない。
```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
◼◼●●
2 successes / 2 failures / 0 errors / 0 pending : 0.001544 seconds

Failure → test.lua @ 8
main test test for grammer number
test.lua:10: Expected objects to be the same.
Passed in:
(string) '123'
Expected:
(table: 0x555555787bd0) {
  [1] = '123' }

Failure → test.lua @ 22
main test test for grammer number
test.lua:24: Expected objects to be the same.
Passed in:
(string) '1'
Expected:
(table: 0x55555570b310) {
  [1] = '1'
  [2] = '+'
  [3] = '1' }
```

PEGでこれを書いてみよう。まず素朴に浮かぶのは次かもしれない。
```txt
Expr <- Number / Expr ("+" / "-") Expr
Number <- "-"? [0-9]+
```

しかしこれだと、`Expr + Expr` の左オペランドところで左再帰となり、評価順の都合上無限に展開されてしまうため、`Expr` の部分は `Number` とする必要がある。

```txt
Expr <- Number / Number ("+" / "-") Expr
Number <- "-"? [0-9]+
```

これをコードにしてみよう。
* `V` 関数は、文法中で非終端文字であることを表すための関数
* `S` 関数は、引数に指定された文字のいずれかにマッチさせるためのパターン
```lua
local VNumber = V"Number"
local VExpr = V"Expr"
local VNumber = V"Number"
local op = C(S"-+")
local G = P {
  "Expr",
  Expr = Ct(VNumber + VNumber * op * VExpr),
  Number = C(P("-")^-1 * R("09")^1),
}
```

ところがエラーになる。`1+1`をパースしたのに`1`が返ってくる。

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●◼●●
3 successes / 1 failure / 0 errors / 0 pending : 0.001539 seconds

Failure → test.lua @ 22
main test test for grammer number
test.lua:24: Expected objects to be the same.
Passed in:
(table: 0x55555570d810) {
  [1] = '1' }
Expected:
(table: 0x55555570da20) {
  [1] = '1'
 *[2] = '+'
  [3] = '1' }
```

これがPEGの特徴「最初のパースがうまくいったらそれを、失敗なら次を順に試してゆき、成功したものを採用」であり、文法

```txt
Expr <- Number / Number ("+" / "-") Expr
Number <- "-"? [0-9]+
```

において最初の `Number` のパースに成功してしまったのでそこでパースが終了してしまった。なので、それをケアして、以下のように順番を入れ変えればよい。

```txt
Expr <- Number ("+" / "-") Expr / Number
Number <- "-"? [0-9]+
```


```lua
local G = P {
  "Expr",
  Expr = Ct(VNumber * op * VExpr + VNumber),
  Number = C(P("-")^-1 * R("09")^1),
}
```

これでもまだテストに失敗する。

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●◼●●
3 successes / 1 failure / 0 errors / 0 pending : 0.001621 seconds

Failure → test.lua @ 22
main test test for grammer number
test.lua:24: Expected objects to be the same.
Passed in:
(table: 0x5555557c6540) {
  [1] = '1'
  [2] = '+'
 *[3] = {
    [1] = '1' } }
Expected:
(table: 0x5555557c6810) {
  [1] = '1'
  [2] = '+'
 *[3] = '1' }
```

というのも、文法のルール的に、以下の構文木としてパースしたためである。
```txt
Expr [
    1,
    +,
    Expr [
      1,
    ]
]
```

演算子の適用順を構文木の中で扱うのであればこれでよいのだが、今回は以下のようにパースしたい。

```txt
Expr [
    1,
    +,
    1,
]
```

そもそも `Expr` 中に `Expr` を入れると入れ子構造になってしまうのだから、 `Expr` を消してしまい最終的には以下のようになる。
```txt
Expr <- Number (("+" / "-") Number)*
Number <- "-"? [0-9]+
```

```lua
local G = P {
  "Expr",
  Expr = Ct(VNumber * (op * VNumber)^0),
  Number = C(P("-")^-1 * R("09")^1),
}
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●
4 successes / 0 failures / 0 errors / 0 pending : 0.001533 seconds
```

### 項（Term）の追加

掛け算・割り算のパースもできるようにする。式の中に項がネストする都合上、既存のテストもテーブルがネストする形で書き換える必要がある。

```lua
describe("main test", function()
  describe("test for grammer", function()
    it("number", function()
      local r = main.G:match("123")
      assert.are.same({ { "123" }  } , r)

      local r = main.G:match("-34")
      assert.are.same({ { "-34" } }, r)

      local r = main.G:match("0")
      assert.are.same({ { "0" } }, r)

      local r = main.G:match("-0")
      assert.are.same({ { "-0" } }, r)
    end)

    it("expr", function()
      local r = main.G:match("1+1")
      assert.are.same({ { "1" }, "+", { "1" } }, r)

      local r = main.G:match("1-1")
      assert.are.same({ { "1" }, "-", { "1" } }, r)

      local r = main.G:match("12+345")
      assert.are.same({ { "12" }, "+", { "345" } }, r)

      local r = main.G:match("-12-345")
      assert.are.same({ { "-12" }, "-", { "345" } }, r)
    end)

    it("term", function()
      local r = main.G:match("12+3*4")
      assert.are.same({ { "12" }, "+", {"3", "*", "4"} }, r)

      local r = main.G:match("1*1")
      assert.are.same({ { "1", "*", "1" } }, r)

      local r = main.G:match("1/1")
      assert.are.same({ { "1", "/", "1" } }, r)
    end)
  end)
    --- 中略
end)
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●◼◼●●
3 successes / 2 failures / 0 errors / 0 pending : 0.001896 seconds

Failure → test.lua @ 22
main test test for grammer expr
test.lua:24: Expected objects to be the same.
Passed in:
(table: 0x5555557c2030) {
 *[1] = {
    [1] = '1'
   *[2] = '+'
    [3] = '1' } }
Expected:
(table: 0x5555557c22d0) {
 *[1] = {
    [1] = '1' }
  [2] = '+'
  [3] = {
    [1] = '1' } }

Failure → test.lua @ 36
main test test for grammer term
test.lua:38: Expected objects to be the same.
Passed in:
(table: 0x5555557cc670) {
 *[1] = {
    [1] = '12'
   *[2] = '+'
    [3] = '3' } }
Expected:
(table: 0x5555557cc910) {
 *[1] = {
    [1] = '12' }
  [2] = '+'
  [3] = {
    [1] = '3'
    [2] = '*'
    [3] = '4' } }
```

PEGは以下のようになる。基本的な考え方はExprと同じ。
```txt
Expr <- Term (("+" / "-") Term)*
Term <- Number (("*" / "/") Number)*
Number <- "-"? [0-9]+
```

```lua
local VNumber = V"Number"
local VExpr = V"Expr"
local VTerm = V"Term"
local VNumber = V"Number"
local exprop = C(S"-+")
local termop = C(S"*/")
local G = P {
  "Expr",
  Expr = Ct(VTerm * (exprop * VTerm)^0),
  Term = Ct(VNumber * (termop * VNumber)^0),
  Number = C(P("-")^-1 * R("09")^1),
}
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●●
5 successes / 0 failures / 0 errors / 0 pending : 0.00176 seconds
```

### 因数（Fact）の追加 - 括弧対応

`2*(1+1)` のように括弧が入った式もパースできるようにする。


```lua
describe("main test", function()
  describe("test for grammer", function()
    -- 中略

    it("fact", function()
      local r = main.G:match("(3+4)")
      assert.are.same({ { { { "3" }, "+", { "4" } } } }, r)

      local r = main.G:match("1+2*(3+4))")
      assert.are.same(
        { { "1" }
        , "+"
        , { "2"
          , "*"
          , { { "3" }
            , "+"
            , { "4" }
            }
          }
        }, r)
    end)
  end)

  -- 中略
end)
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●◼●●
5 successes / 1 failure / 0 errors / 0 pending : 0.002039 seconds

Failure → test.lua @ 60
main test test for grammer fact
test.lua:62: Expected objects to be the same.
Passed in:
(nil)
Expected:
(table: 0x5555557d3fd0) {
  [1] = {
    [1] = {
      [1] = { ... more }
      [2] = '+'
      [3] = { ... more } } } }
```

PEGは以下のようになる。新たに `Fact` （因数）を定義して、それが `Number` か括弧つきの `Expr` であることを定義する。
```txt
Expr <- Term (("+" / "-") Term)*
Term <- Fact (("*" / "/") Fact)*
Fact <- Number / "(" Expr ")"
Number <- "-"? [0-9]+
```

```lua
local VNumber = V"Number"
local VExpr = V"Expr"
local VTerm = V"Term"
local VFact = V"Fact"
local VNumber = V"Number"
local exprop = C(S"-+")
local termop = C(S"*/")
local G = P {
  "Expr",
  Expr = Ct(VTerm * (exprop * VTerm)^0),
  Term = Ct(VFact * (termop * VFact)^0),
  Fact = VNumber + "(" * VExpr * ")",
  Number = C(P("-")^-1 * R("09")^1),
}
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●●●
6 successes / 0 failures / 0 errors / 0 pending : 0.002047 seconds

```

### スペース対応

空白スペースにも対応できるようにする。

```lua
describe("main test", function()
  describe("test for grammer", function()
    -- 中略
    it("spaces", function()
      local r = main.G:match("123   ")
      assert.are.same({ { "123" } } , r)

      local r = main.G:match("1 + 1  ")
      assert.are.same({ { "1" }, "+", { "1" } }, r)

      local r = main.G:match("1  * 1  ")
      assert.are.same({ { "1", "*", "1" } }, r)

      local r = main.G:match("(  3 + 4 )  ")
      assert.are.same({ { { { "3" }, "+", { "4" } } } }, r)

      local r = main.G:match("  1")
      assert.are.same({ { "1" } } , r)
    end)
  end)
  -- 中略
end)
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●◼●●
6 successes / 1 failure / 0 errors / 0 pending : 0.002883 seconds

Failure → test.lua @ 78
main test test for grammer spaces
test.lua:83: Expected objects to be the same.
Passed in:
(table: 0x5555557e38f0) {
  [1] = {
    [1] = '1' } }
Expected:
(table: 0x5555557e3b40) {
  [1] = {
    [1] = '1' }
 *[2] = '+'
  [3] = {
    [1] = '1' } }
```

これの対応は実はそこまで難しくない。以下のケースを考えると、スペースが入る位置が網羅できる。
* 数字の直後にスペースが入るケース
* 演算子 `+-*/` の直後にスペースが入るケース
* 括弧の `()` の直後にスペースが入るケース
* 式の始まりにスペースが入るケース

任意のスペースが入るパターンである `sp` を定義し、適切な場所に `sp` を連接させる。最後に `G` 自身にも先頭に `sp` をくっつける。

```lua
local sp = P(" ")^0
local VNumber = V"Number"
local VExpr = V"Expr"
local VTerm = V"Term"
local VFact = V"Fact"
local VNumber = V"Number"
local exprop = C(S"-+") * sp
local termop = C(S"*/") * sp
local G = P {
  "Expr",
  Expr = Ct(VTerm * (exprop * VTerm)^0),
  Term = Ct(VFact * (termop * VFact)^0),
  Fact = VNumber + ("(" * sp) * VExpr * (")" * sp),
  Number = C(P("-")^-1 * R("09")^1) * sp,
}
G = sp * G
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●●●●
7 successes / 0 failures / 0 errors / 0 pending : 0.002803 seconds
```


### （おまけ）構文木っぽく出力する

いままでただのテーブル形式で返していたが、わかりづらいので構文木っぽく出力したい。具体的には以下のようなテストをクリアするようにしたい。
```lua
describe("main test", function()
  describe("test for grammer", function()
    -- 中略
    it("tree", function()
      local r = main.G:match("123")
      assert.are.same(tostring(r), "Expr[Term[123]]")

      local r = main.G:match("1+1")
      assert.are.same(tostring(r), "Expr[Term[1],+,Term[1]]")

      local r = main.G:match("1*1")
      assert.are.same(tostring(r), "Expr[Term[1,*,1]]")

      local r = main.G:match("(3+4)")
      assert.are.same(tostring(r), "Expr[Term[Expr[Term[3],+,Term[4]]]]")
    end)

  end)
  -- 中略
end)
```

Luaの世界にはクラスの概念は特別用意されていないが、metatableの属性 `__tostring` をオーバーライドすれば、文字列に変換された時のフォーマットを制御できる（Pythonでいう `__str__()` のようなもの）。

そして、`pattern / function` における `/` 演算子は、キャプチャした結果に関数 `function` を適用して返す。こうすることで、キャプチャした結果の値に対して `__tostring` を上書きして返すことができる。

```lua
function to_string_table(t)
  local result = {}
  for _, v in ipairs(t) do
    table.insert(result, tostring(v))
  end
  return result
end

function Node(v)
  return function(t)
    return setmetatable(t, {
      __tostring = function(t)
        return v .."[" .. table.concat(to_string_table(t), ",") .. "]"
      end
    })
  end
end

local sp = P(" ")^0
local VNumber = V"Number"
local VExpr = V"Expr"
local VTerm = V"Term"
local VFact = V"Fact"
local VNumber = V"Number"
local exprop = C(S"-+") * sp
local termop = C(S"*/") * sp
local G = P {
  "Expr",
  Expr = Ct(VTerm * (exprop * VTerm)^0)/Node("Expr"),
  Term = Ct(VFact * (termop * VFact)^0)/Node("Term"),
  Fact = VNumber + ("(" * sp) * VExpr * (")" * sp),
  Number = C(P("-")^-1 * R("09")^1) * sp,
}
G = sp * G
```

```console
[bombrary@nixos:~/pworks/lua-lpeg]$ busted test.lua
●●●●●●●●
8 successes / 0 failures / 0 errors / 0 pending : 0.002354 seconds
```

## 終わりに

四則演算のパースを通してLPegの使い方を学んだ。あとついでにテスト駆動っぽい形でコードを書いていって、文法の正しさを担保した。

PEGさえ書ければあとは簡単にコードに書き下せるなと感じた。
しかし構文エラーの仕組みがないので、構文エラーになったときにどこがミスってるのかを探すのが大変だなと感じる。
そもそもパターンマッチングライブラリと謳っており厳密にはパーサーライブラリではないので仕方ないのかも。
