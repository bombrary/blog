---
title: "PureScriptメモ - Generics"
date: 2020-11-03T13:17:39+09:00
toc: true
tags: ["ジェネリックプログラミング", "Generics"]
categories: ["PureScript"]
---

purescript-generics-repパッケージを使ってGenericな`Serializer`型クラスを作った。以下はそのメモ。

## 準備

プロジェクトを作成。

{{< cui >}}
$ spago init
{{< /cui >}}


Arrayを使うので、パッケージをインストールして`src/Main.purs`にimport文を書き込んでいく。
本記事の本命であるgenerics-rep入れる。
{{< cui >}}
$ spago install arrays
$ spago install generics-rep
{{< /cui >}}

```haskell
import Data.Array ((:))
```

REPLで色々実験するので、あらかじめ起動しておく。
{{< cui >}}
$ spago repl
> import Main
{{< /cui >}}

以降は`src/Main.purs`に色々書き足していく。REPLで`:r`(もしくは`:reload`)とコマンドを打てばモジュールが再読み込みされるので、`src/Main.purs`を書き換える度にこのコマンドを打つと良い。

## Serializer

そもそもSerializerとは何か。ここでは単に「データをビット列に変換するもの」程度の意味で捉えれば良い。
厳密にはJSONなどの階層を持つデータを，文字列などの平坦なデータに変換するという意味合いとしてシリアライズ(直列化)という言葉を使う。実際、本記事では最終的に木構造をシリアライズする。

まずビットは次のように定義する。
```haskell
data Bit = O | I

instance showBit :: Show Bit where
  show O = "O"
  show I = "I"
```

`Serializer`型クラスを以下のように定義する。
```haskell
class Serializer a where
  serialize :: a -> Array Bit
```

試しに適当な型をつくり、それを`Serializer`型クラスのインスタンスにしてみる。
```haskell
data Person = Alice | Bob | Carol

instance serializerUser :: Serializer Person where
  serialize Alice = [ I ]
  serialize Bob   = [ O, I ]
  serialize Carol = [ O, O, I ]
```

余談。今回はデシリアライザは実装しないので、シリアライズしたデータを同じ形に戻せるかは考えない。このあたりは情報理論の授業で「一意復号化可能性」などをやった気がするけど、忘れてしまった。

REPLで実験してみる。

{{< cui >}}
> serialize Alice
[I]

> serialize Bob
[O,I]

> serialize Carol
[O,O,I]
{{< /cui >}}

## Tree型をSerializer型クラスのインスタンスにする(素朴な方法)

2分木のデータ構造である`Tree`型を作る。

```haskell
data Tree a = Node (Tree a) (Tree a) | Leaf a

instance serializerTree :: Serializer a => Serializer (Tree a) where
  serialize (Node l r) = I : (serialize l <> serialize r)
  serialize (Leaf x) = O : serialize x
```

テスト用のデータを作ってREPLでシリアライズしてみる。
```haskell
tree :: Tree Person
tree = Node (Node (Leaf Alice) (Leaf Bob)) (Leaf Carol)
```

{{< cui >}}
> serialize tree
[I,I,O,I,O,O,I,O,O,O,I]
{{< /cui >}}

## 一般化

さて、3分木なら例えば次のように`Serializer`型クラスのインスタンスにできる。
```haskell
data Tree a = Node (Tree a) (Tree a) (Tree a) | Leaf a

instance serializerTree :: Serializer a => Serializer (Tree a) where
  serialize (Node n1 n2 n3) = I : (serialize n1 <> serialize n2 <> serialize n3)
  serialize (Leaf x) = O : serialize x
```

木に限らず、有名な型については例えば次のようにインスタンスにできるだろう。
```haskell
instance serializerMaybe :: Serializer a => Serializer (Maybe a) where
  serialize (Just x) = I : serialize x
  serialize Nothing  = []

instance serializerEither :: (Serializer a, Serializer b) => Serializer (Either a b) where
  serialize (Left x)  = I : serialize x
  serialize (Right y) = O : serialize y

instance serializerList :: (Serializer a) => Serializer (List a) where
  serialize (Cons x xs) = I : serialize x <> serialize xs
  serialize Nil  = []
```

3つの値を持つデータ型なら例えば次のようにできる。
```haskell
data T0 a b c = One a b | Two b | Three c b a

instance serializerT0 :: (Serializer a, Serializer b, Serializer c) => Serializer (T0 a b c) where
  serialize (One x y) = I : (serialize x <> serialize y)
  serialize (Two x)   = O : I : serialize x
  serialize (Three x y z) = O : O : I : (serialize x <> serialize y <> serialize z)
```

上の例はアドホックなものであり、実装そのものに共通点はない。ただし、実装する上での気持ち「**データの値ではなくデータの表現に注目する**」では共通している。
ここでいう表現というのは、たとえば3つ目の例でいうと、

`One`と`Two`と`Three`という値を持ち，
- `One`は`a`型の値と`b`型の値を引数に持つ。
- `Two`は`b`型の値を引数を持つ。
- `Three`は`c`型の値，`b`型の値，`a`型の値を引数に持つ。

が`T0`の持つ表現である。

そのような、データの表現に応じてシリアライズの仕方を実装することができれば、いちいち`Maybe`や`Either`や`T0`など個別に`Serializer`型クラスのインスタンス宣言を書かずに済む。
それを可能にするのが、purescript-generics-repパッケージである。これは、データ型の持つ表現そのものを型にする手段を提供する。

## Data.Generic.Rep

モジュールをインポートする。
```haskell
import Data.Generic.Rep
```

### Generic型クラス

`Generic`型クラスのインスタンスを導出させることで、`Tree`の表現が生成される。アンダーバーはコンパイラが自動で埋めてくれる。
```haskell
derive instance genericTree :: Generic (Tree a) _
```

[ドキュメント](https://pursuit.purescript.org/packages/purescript-generics-rep/6.1.1/docs/Data.Generic.Rep)によると、`Generic`型クラスは次のように定義されている。
```haskell
class Generic a rep | a -> rep where
  to :: rep -> a
  from :: a -> rep
```

`rep`が、型`a`の表現を表す(`rep`というのは、恐らく*representation*(表現)の略)。`from`を使えば、`a`の表現が得られる。REPLで`Tree`の表現の型を確認してみる。
{{< cui >}}
> import Data.Generic.Rep
> :t from tree
Sum (Constructor "Node" (Product (Argument (Tree Person)) (Argument (Tree Person)))) (Constructor "Leaf" (Argument Person))
{{< /cui >}}

なので実際には、アンダーバーのところを埋めると次のようになるようだ(ただし、必ずアンダーバーでなければならないようで、これはコンパイルエラーになる)。

```haskell
derive instance genericTree
  :: Generic
       (Tree a)
       (Sum (Constructor "Node" (Product (Argument (Tree a))
                                         (Argument (Tree a))))
            (Constructor "Leaf" (Argument a)))
```

### 表現の構成要素

表現が構成する型は次の4つ。
```haskell
data Sum a b = Inl a | Inr b
data Constructor (name :: Symbol) a = Constructor a
data Product a b = Product a b
data Argument a = Argument a
data NoConstructors
data NoArguments = NoArguments
```

- `Sum`は直和型を表現する型。
- `Product`は直積型を表現する型。
- `Constructor name a`は値コンストラクタを表現する型。
- `Argument`は値コンストラクタの引数を表現する型。
- `NoConstructors`はコンストラクタが存在しないことを表現する型。
- `NoArguments`は値コンストラクタの引数が存在しないことを表現する型。

であることを踏まえると、 

```haskell
(Sum (Constructor "Node" (Product (Argument (Tree a))
                                  (Argument (Tree a))))
     (Constructor "Leaf" (Argument a)))
```
は、次のように読める：この型は2つのコンストラクタがあることを表現している。1つ目の値コンストラクタ名は`Node`で、その引数として`Tree a`型の値を2つ持つ。
2つめの値コンストラクタ名は`Leaf`で、その引数として`a`型の値を1つ持つ。

ちなみに`derive`を使わないで`Tree`についてのインスタンス宣言をすると次のようになる。勿論`derive`を使えばいい話なので、普通こんなことはやらない。
```haskell
instance genericTree
  :: Generic
       (Tree a)
       (Sum (Constructor "Node" (Product (Argument (Tree a))
                                         (Argument (Tree a))))
            (Constructor "Leaf" (Argument a)))
  where
    to (Inl (Constructor (Product (Argument l) (Argument r)))) = Node l r
    to (Inr (Constructor (Argument x))) = Leaf x
    from (Node l r) = Inl (Constructor (Product (Argument l) (Argument r)))
    from (Leaf x) = Inr (Constructor (Argument x))
```

### 応用例：Showクラスのインスタンスにする

PureScriptでは、Haskellと違って、`Show`型クラスのインスタンス導出ができない([参考](https://github.com/purescript/documentation/blob/master/language/Type-Classes.md#type-class-deriving))。しかし代わりに、`Generic`型クラスを利用すれば、導出と同じようなことができる。

まずは、関連モジュールをインポートする。
```haskell
import Data.Generic.Rep.Show
```

試しに、`Person`型を`Show`型クラスのインスタンスにしてみる。
```haskell
derive instance genericPerson :: Generic Person _
instance showPerson :: Show Person where
  show x = genericShow x
```

`genericShow`は、`Person`の表現をもとに値を文字列に変換する関数。単に`Person`を`Generic`型クラスのインスタンスにするだけで利用できる。

{{< cui >}}
> Alice
Alice

> Bob
Bob

> Carol
Carol
{{< /cui >}}

`Tree`も同様に`Show`型クラスのインスタンスにできる。

```haskell
instance showTree :: Show a => Show (Tree a) where
  show x = genericShow x
```

{{< cui >}}
> tree
(Node (Node (Leaf Alice) (Leaf Bob)) (Leaf Carol))
{{< /cui >}}

[Data.Generic.Rep.Showのコード](https://github.com/purescript/purescript-generics-rep/blob/v6.1.1/src/Data/Generic/Rep/Show.purs)を読んでみると、どうやって表現を使って実装するのかがよく分かる。

### 補足：Showクラスのインスタンス化に関する注意点

次のように書くと、`show`関数を呼び出した際に実行時エラー：`Maximum call stack size exceeded`起こす。

```haskell
instance showTree :: Show a => Show (Tree a) where
  show = genericShow
```

`show x = genericShow x`も`show = genericShow`も本質的には同じ意味なのに、前者はうまくいき、後者は実行時エラーを吐くのはおかしい。

この問題について[generics-repのissue](https://github.com/purescript/purescript-generics-rep/issues/23)や[purescriptのissue](https://github.com/purescript/purescript/issues/3807)でも上がっている。
後者のissueではClosedになってしまっているようだし、修正されないのだろうか。単に`show x = genericShow x`と書けば防げる問題なので、そこまで大した問題ではないのかもしれないが…。


## 本題：Tree型をSerializer型クラスのインスタンスにする(表現を利用する方法)

[Data.Generic.Rep.Showのコード](https://github.com/purescript/purescript-generics-rep/blob/v6.1.1/src/Data/Generic/Rep/Show.purs#L14-L15)の手法を真似て、次のように作る。

- 表現をシリアライズする型クラスは`Serializer'`が担う。
- `Tree`や`Person`などの普通の値をシリアライズする型クラスは`Serializer`が担う。

そこで、`Serializer'`型クラスを作る。
```haskell
class Serializer' a where
  serialize' :: a -> Array Bit
```

表現に関連する部分は全て`Serializer'`型クラスのインスタンスにする。最後の`Argument`だけ、引数に普通の型が含まれているため、型クラス制約が`Serializer'`ではなく`Serializer`であることに注意。

```haskell
instance serializerSum :: (Serializer' a, Serializer' b) => Serializer' (Sum a b) where
  serialize' (Inl x) = I : serialize' x
  serialize' (Inr x) = O : serialize' x

instance serializerConstructor :: (Serializer' a) => Serializer' (Constructor name a) where
  serialize' (Constructor x) = serialize' x

instance serializerProduct :: (Serializer' a, Serializer' b) => Serializer' (Product a b) where
  serialize' (Product x y) = serialize' x <> serialize' y

instance serializerNoArguments :: Serializer' NoArguments where
  serialize' _ = []

instance serializerArgument :: (Serializer a) => Serializer' (Argument a) where
  serialize' (Argument x) = serialize x
```

最後に、`serialize'`を使って`Tree`を`Serializer`型クラスのインスタンスにする。[前に作成したインスタンス宣言](#tree型をserializer型クラスのインスタンスにする素朴な方法)は消す。

```haskell
instance serializerTree :: (Serializer a) => Serializer (Tree a) where
  serialize x = serialize' $ from x
```

素朴に作った場合と同じ結果が出ている。

{{< cui >}}
> serialize tree
[I,I,O,I,O,O,I,O,O,O,I]
{{< /cui >}}

**Tree型の値そのものに注目せずにSerializerが実装できた**ことに注目してほしい。`Tree a`に限らず、例えば型`T0 a b c`があったとき、
- `T0`は`Generic`型クラスのインスタンスである
- `a, b, c`は`Serializer`型クラスのインスタンスである

という2つの条件が揃えば、`T0`はシリアライズできることになる。


### 補足：Tree以外の型をSerializer型クラスのインスタンスにする

自作の型なら、容易に`Serizlizer`のインスタンスにできる。
```haskell
data T0 a b c = One a | Two b | Tree c

derive instance genericT0 :: Generic (T0 a b c) _

instance serializerT0 :: (Serializer a, Serializer b, Serialier c) => Serializer (T0 a b c) where
  serialize x = serialize' $ from x
```

`Maybe a`に関しては特別に`Data.Generic.Rep`でインスタンス宣言がなされているため、次のように`Serializer`のインスタンスにできる。

```haskell
instance serializerTree :: (Serializer a) => Serializer (Tree a) where
  serialize x = serialize' $ from x
```

別モジュールで定義された型を、`Generic`を使って`Serializer`のインスタンスにすることはできない。
なぜなら、今回の場合「`Main`外で定義された型」に対して「`Main`外で定義された型クラス`Generic`」のインスタンス宣言をすることになり、これはOrphan instanceに当たるからだ
PureScriptではOrphan instanceは禁止されている([参考](https://github.com/purescript/documentation/blob/master/language/Type-Classes.md#orphan-instances))。

この問題を解決するためにぱっと思いついた方法は、以下のようなもの。以下は`Either`を`Serializer`型クラスのインスタンスにしている。`Either`の別表現として`Either'`を用意する。
`Either`は`Main`外のモジュールで定義されているため、直接`Generic`型インスタンスにすることはできない。しかし、`Either'`は`Generic`にすることはできる。
よって、一旦`Either'`を経由して`Either`の`Serializer`インスタンス宣言をすることができる。

```haskell
data Either' a b = Left' a | Right' b

fromEither :: forall a b. Either a b -> Either' a b
fromEither (Left x) = Left' x
fromEither (Right x) = Right' x

derive instance genericEither' :: Generic (Either' a b) _

instance serializerEither :: (Serializer a, Serializer b) => Serializer (Either a b) where
  serialize x = serialize' $ from  $ fromEither x 
```

ちなみに、最近[EitherをGenericのインスタンスにする動き](https://github.com/purescript/purescript-generics-rep/pull/34)あるようだ。


## 参考文献

本記事を書くに当たって参考にした文献を挙げておく。

### Haskell方面

PureScriptはHaskellの影響を受けているので、Haskellの資料が参考になることは結構ある。ただし、構文や型名、パッケージ名など違いがあるので、それらについては根気強く調べる必要がある。
- [GHC.Genericsのドキュメント](https://hackage.haskell.org/package/base-4.14.0.0/docs/GHC-Generics.html)：そもそも、purescript-generics-repはこれにインスパイアされて作ったもの([参考](http://pursuit.purescript.org/packages/purescript-generics-rep))。
- [Haskell wiki](https://wiki.haskell.org/GHC.Generics)：Serializerという型クラスを実装する例を与えている。
- [GHC.Genericsを利用したgeneric programming - tiqwablog](https://blog.tiqwab.com/2017/01/09/ghc-generics.html)：日本語の文献。こちらも同様、Serializableという型クラスを実装している(名前は違うが上と同じ機能を持つ型クラス)。

### PureScript方面

あまり見つからなかった…。
- [purescript-generics-repのドキュメント](http://pursuit.purescript.org/packages/purescript-generics-rep)
- [雰囲気で PureScript の Generics プログラミングを始める - Qiita](https://qiita.com/asua/items/bc3c99111cf6c70d84a8)：日本語の文献。

