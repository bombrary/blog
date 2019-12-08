---
title: "Androidアプリ開発勉強(4) - LiveData/TableLayout/電卓アプリ作成"
date: 2019-11-28T14:24:39+09:00
tags: ["Programming", "Android", "Kotlin", "LivaData", "TableLayout", "電卓アプリ"]
categories: ["Programming", "Android", "Kotlin", "ViewModel", "DataBinding"]
---

## どんなアプリを作るか

電卓を作る。

市販の電卓とは違い、括弧が使えるようにする。なので、軽い構文解析を書くことになる。しかし今回の記事ではデータの扱い方やViewの組み方に焦点を当てているため、電卓の計算処理についてはかなり軽めに説明する。

## プロジェクト作成

- プロジェクト名は"Calculator"とする。
- DataBindingは有効にする

## Fragmentに分ける

今回は1画面のアプリなのでわざわざFragmentに分ける必要もないのだが、「もしかしたら他にもFragmentを追加するかもしれない」というケースを想定して、一応分けてみる。

1. `CalcFragment`を作成する。xmlファイルは`fragment_calc.xml`とする。
2. `activity_main.xml`の内容を以下のようにする。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<merge xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context=".MainActivity">

    <fragment
        android:id="@+id/calcFragment"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:name="com.example.calculator.CalcFragment" />
</merge>
{{< /highlight >}}

### merge

[Android Kotlin Fundamentals 06.2](https://codelabs.developers.google.com/codelabs/kotlin-android-training-coroutines-and-room/index.html?index=..%2F..android-kotlin-fundamentals#2)で存在を初めて知った。こうすると`activity_main.xml`でLayoutを作って、`fragment`の中でもまたLayoutを作るといった冗長性を排除できる。

## CalcFragmentの設定

### string.xml

`fragment_calc.xml`に設定するための文字列定数を定義する。`string.xml`を以下のようにする。

{{< highlight xml >}}
<resources>
    <string name="app_name">Calculator</string>
    <string name="calc_0">0</string>
    <string name="calc_1">1</string>
    <string name="calc_2">2</string>
    <string name="calc_3">3</string>
    <string name="calc_4">4</string>
    <string name="calc_5">5</string>
    <string name="calc_6">6</string>
    <string name="calc_7">7</string>
    <string name="calc_8">8</string>
    <string name="calc_9">9</string>
    <string name="calc_plus">+</string>
    <string name="calc_minus">-</string>
    <string name="calc_mul">*</string>
    <string name="calc_div">/</string>
    <string name="calc_ac">AC</string>
    <string name="calc_eq">=</string>
    <string name="calc_lp">(</string>
    <string name="calc_rp">)</string>
</resources>
{{< /highlight >}}

### fmagment_calc.xml

`fragment_calc.xml`を以下のようにする。初めて触れた要素・属性があるので、これらは後で補足する。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<layout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    tools:context=".CalcFragment" >

    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent" >
        <TextView
            android:id="@+id/textView"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:textSize="48sp"
            android:paddingLeft="8dp"
            android:paddingRight="8dp"
            android:paddingTop="8dp"
            android:paddingBottom="8dp"
            android:gravity="end|center_vertical"
            android:text="@string/calc_0"
            app:layout_constraintTop_toTopOf="parent"/>
        <TableLayout
            android:layout_width="match_parent"
            android:layout_height="0dp"
            app:layout_constraintLeft_toLeftOf="parent"
            app:layout_constraintRight_toRightOf="parent"
            app:layout_constraintBottom_toBottomOf="parent"
            app:layout_constraintTop_toBottomOf="@+id/textView"
            android:gravity="fill">
            <TableRow
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:gravity="center">
                <!-- Dummy Button for table layout. -->
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:visibility="invisible" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_lp"/>
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_rp"/>
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_ac"/>
            </TableRow>
            <TableRow
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:gravity="center">
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_7"
                    android:id="@+id/button7" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_8"
                    android:id="@+id/button8" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_9"
                    android:id="@+id/button9" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_mul"
                    android:id="@+id/buttonMul" />
            </TableRow>
            <TableRow
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:gravity="center">
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_4"
                    android:id="@+id/button4" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_5"
                    android:id="@+id/button5" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_6"
                    android:id="@+id/button6" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_div"
                    android:id="@+id/buttonDiv" />
            </TableRow>
            <TableRow
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:gravity="center">
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_1"
                    android:id="@+id/button1" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_2"
                    android:id="@+id/button2" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_3"
                    android:id="@+id/button3" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_plus"
                    android:id="@+id/buttonPlus" />
            </TableRow>
            <TableRow
                android:layout_width="match_parent"
                android:layout_height="0dp"
                android:layout_weight="1"
                android:gravity="center">
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_0"
                    android:id="@+id/button0" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_period"
                    android:id="@+id/buttonPeriod" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_eq"
                    android:id="@+id/buttonEq" />
                <Button
                    android:layout_width="0dp"
                    android:layout_weight="1"
                    android:layout_height="match_parent"
                    android:text="@string/calc_minus"
                    android:id="@+id/buttonMinus" />
            </TableRow>
        </TableLayout>

    </androidx.constraintlayout.widget.ConstraintLayout>
</layout>
{{< /highlight >}}

### TableLayout

電卓アプリを作る場合、ボタンは格子状に並べたい。これはTableLayoutで実現できる。次のように書く。`TableRow`はテーブルの行を定義する要素で、その中に実際のセル要素を並べていく。

{{< highlight xml >}}
<TableLayout ...>
  <TableRow ...>
    <要素...>
    ...
  </TableRow>

  <TableRow ...>
    <要素...>
    ...
  </TableRow>

  ...
</TableLayout>
{{< /highlight >}}

他に似たようなレイアウトを実現する方法にGridLayoutというものがあるらしいので、必要になったらまた勉強する。

### layout_weight

テーブル幅もしくは高さの比率を設定する。例えば次のように設定されたいた場合、ボタンは1:2:1の比率で並ぶ。幅の比率を設定したいなら、`layout_width="0dp"`を設定する。

{{< highlight xml >}}
<Button
  layout_height="wrap_content"
  layout_width="0dp"
  layout_weight="1"/>
<Button
  layout_height="wrap_content"
  layout_width="0dp"
  layout_weight="2"/>
<Button
  layout_height="wrap_content"
  layout_width="0dp"
  layout_weight="1"/>
{{< /highlight >}}

### layout_gravity

位置や幅を制御するための属性。その名の通り、重力が発生していると捉えるのが適当。例えば`center`なら中央に重力が発生するため、Viewの部品は中央に移動する。

今回の例では`fill`が設定されている。四隅に重力が発生するので、Viewの部品は全体に引き伸ばされる。前にも見た通り`layout_height="0dp"`や`layout_width="0dp"`は特殊な意味を持つようで、今回の場合は`height`にのみ`0dp`を設定し、上下方向だけ引き伸ばされるようにしているようだ。`layout_height="match_parent"`と挙動が似ているが、こっちの方は「親要素に高さを合わせる」という意味なので微妙に異なる。

{{< highlight xml >}}
<TableLayout
    android:layout_width="match_parent"
    android:layout_height="0dp"
    ...
    android:gravity="fill">
  ...
</TableLayout>
{{< /highlight >}}

### visibility

要素の可視を設定する。`visible/invisible/gone`の3つの値が設定できる。

- `visible`: 可視
- `invisible`: 不可視だがView上で領域が確保される
- `gone`: 要素は存在しないものとして扱われる。つまりView上で領域は確保されない。

今回の例では、次のように設定することで、ACボタンを右寄せかつ他のテーブルセルに幅を合わせている。

{{< highlight xml >}}
<TableRow ... >
    <Button
        android:layout_width="0dp"
        android:layout_weight="3"
        android:layout_height="match_parent"
        android:visibility="invisible" />
    <Button
        android:layout_width="0dp"
        android:layout_weight="1"
        android:layout_height="match_parent"
        android:layout_column="3"
        android:text="@string/calc_lp"/>
    ...
</TableRow>
{{< /highlight >}}


### CalcFragment.ktの設定

`CalcFragment.kt`の内容を以下の通りにする。

{{< highlight kotlin >}}
class CalcFragment : Fragment() {
    private lateinit var binding: FragmentCalcBinding
    private lateinit var viewModel: CalcViewModel
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        binding = DataBindingUtil.inflate(inflater, R.layout.fragment_calc, container, false)
        return binding.root
    }
}
{{< /highlight >}}

これでアプリを起動してみると、以下のようになっている。ボタンの設定はまだ何もしていないので、ボタンを押しても反応しない。

{{< figure src="./sc01.png" width="30%" >}}

## CalcViewModelの作成 - LiveDataの利用

LiveDataとは、「監視可能なデータ」のこと。監視可能、ということは、例えば「データが変更された時にある処理を行う」が簡単に記述できることになる。プログラミングで監視といえばObserverパターンだが、LiveDataの内部実装では実際にObserverパターンを用いている。

今回のアプリでは次の目的のみで用いる。

- 何かボタンを押したら電卓の表示が変化する

### CalcViewModel.kt

持たせるデータは「電卓の表示」だけで良いだろう。ここには数字だけでなく演算子の記号も入りうるので、型は`String`とする。

{{< highlight kotlin >}}
class CalcViewModel : ViewModel() {
    private var _text = MutableLiveData<String>()
    val text: LiveData<String>
        get() = _text
    init {
        _text.value = "0"
    }
}
{{< /highlight >}}

以下の記述はある種のパターンとして覚えて良いかもしれない。1行目は「読み書き可能なLiveData」で、2行目は「読み取り専用のLiveData」である。`fragment_calc.xml`や`CalcFragment.kt`では`text`の方を用いることで、データが変更されることを防いでいる。`CalcFragment`では「データ`CalcViewModel`から読み取って描画する」、`CalcViewModel`では「データに関する整形や変更の処理をする」という分業になっていることに注目。

`get() = _text`という文法は初めて見たが、これはゲッターの設定みたい。

{{< highlight kotlin >}}
private var _text = MutableLiveData<String>()
val text: LiveData<String>
    get() = _text
{{< /highlight >}}

LivaDataは次のように`value`メンバ変数でアクセスできる。

{{< highlight kotlin >}}
  _text.value = "0"
{{< /highlight >}}

### fragment_calc.xml

DataBindingを用いて、CalcViewModelのデータを利用できるようにする。

ViewModel自体をFragmentに結びつけるのがポイント。データに対する諸々の情報は全て`ViewModel`がまとめてくれているから、`variable`をたくさん書く必要はない。

{{< highlight xml >}}
<layout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    tools:context=".CalcFragment" >

    <data>
        <variable
            name="calcViewModel"
            type="com.example.calculator.CalcViewModel" />
    </data>
    ...
{{< /highlight >}}

さらに、`TextView`要素の`text`属性を変更する。

{{< highlight xml >}}
  <TextView
      android:id="@+id/textView"
      ...
      android:text="@{String.valueOf(calcViewModel.text)}"
      ... />
{{< /highlight >}}

LiveDataを文字列として埋め込みたいなら、`String.valueOf(calcViewModel.text)`のように書く。この場合は`calcViewModel.text.value`でなくても良い。

## CalcFragment.kt

`viewModel`を宣言する。`ViewModelProviders`を用いて初期化するところは前回の通り。

{{< highlight kotlin >}}
class CalcFragment : Fragment() {
    private lateinit var binding: FragmentCalcBinding
    private lateinit var viewModel: CalcViewModel
    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        binding = DataBindingUtil.inflate(inflater, R.layout.fragment_calc, container, false)
        viewModel = ViewModelProviders.of(this)
            .get(CalcViewModel::class.java)
        binding.calcViewModel = viewModel
        binding.lifecycleOwner = this
        return binding.root
    }
}
{{< /highlight >}}


`binding.lifecycleOwner = this`とすると、`CalcViewModel.text`の変化を感知して`TextView`の値が変更されるようになる。

これを設定せずにやる方法として、次の`observe`メソッドがある。これは`viewModel.text`に`Observer`を設定する。`fragment_calc.xml`に変更を反映するという目的だけなら`binding.lifecycleOwner = this`だけで良いが、それ以外のことをやりたい場合はこのメソッドを使うことになりそう。

{{< highlight kotlin >}}
viewModel.text.observe(this, Observer { newText: String ->
    binding.invalidateAll()
})
{{< /highlight >}}

まだボタンを押した時の挙動を一切設定していないので、設定する。

## ボタンを押した時の挙動

`CalcViewModel.kt`に次のメソッドを追加する

- `onAllClearButtonClicked()`: ACボタンが押された時に呼び出す。`text_`の内容を`"0"`にするだけ。
- `onEqualButtonClicked()`: =ボタンが押された時に呼び出す。実際に計算した結果を返す。ここは別の項で書く。
- `onCharacterButtonClicked(c: String)`: ACと=以外のボタンが押された時に呼び出す。単に_textの末尾に文字を追加するだけ。引数は`calc_fragment.xml`で呼び出す際に使用し、これは押された文字を指定する。xmlファイルとの兼ね合いにより、「左括弧のときは`"lp"`、右括弧のときは`rp`が引数に渡される」と約束する。

`when`文は、他言語でいう`switch`文のこと。場合分けが結構シンプルに表現できて良い。

{{< highlight kotlin >}}
class CalcViewModel : ViewModel() {
    private var _text = MutableLiveData<String>()
    val text: LiveData<String>
        get() = _text

    init {
        _text.value = ""
    }
    fun onCharacterButtonClicked(c: String) {
        when(c) {
            "lp" -> _text.value += "("
            "rp" -> _text.value += ")"
            else -> _text.value += c
        }
    }
    fun onAllClearButtonClicked() {
        _text.value = ""
    }
    fun onEqualButtonClicked() {
        // TODO
    }
}
{{< /highlight >}}

### fragment_calc.xml

各`Button`要素について、`onClick`属性を追加する。

以下はACボタンについての記述。以下のように、`@{ラムダ式}`みたいな文法が使えるようだ。

{{< highlight xml >}}
  <Button
      android:layout_width="0dp"
      android:layout_weight="1"
      android:layout_height="match_parent"
      android:text="@string/calc_ac"
      android:onClick="@{() -> calcViewModel.onAllClearButtonClicked()}"/>
{{< /highlight >}}

以下は=ボタンについての記述。

{{< highlight xml >}}
  <Button
      android:layout_width="0dp"
      android:layout_weight="1"
      android:layout_height="match_parent"
      android:text="@string/calc_eq"
      android:id="@+id/buttonEq"
      android:onClick="@{() -> calcViewModel.onEqualButtonClicked()}"/>
{{< /highlight >}}

以下は.ボタンについての記述。

{{< highlight xml >}}
  <Button
      android:layout_width="0dp"
      android:layout_weight="1"
      android:layout_height="match_parent"
      android:text="@string/calc_period"
      android:id="@+id/buttonPeriod"
      android:onClick="@{() -> calcViewModel.onPeriodButtonClicked()}"/>
{{< /highlight >}}

以下はそれ以外のボタンについての記述。ここでは7ボタンについてを例にしているが、他のボタンもちゃんと書く。ボタン数が多くて大変だが頑張る。左括弧は`lp;`、右括弧は`rp;`と書かなければいけないことに注意。

{{< highlight xml >}}
  <Button
      android:layout_width="0dp"
      android:layout_weight="1"
      android:layout_height="match_parent"
      android:text="@string/calc_7"
      android:id="@+id/button7"
      android:onClick="@{() -> calcViewModel.onCharacterButtonClicked(&quot;7&quot;)}"/>
{{< /highlight >}}

これでアプリを起動してみると、数字や演算子が入力できるようになっている。

## 計算処理の実行

構文解析用のクラス`CalcParser`を作って実行するという流れ。この部分については、本記事の本質的なところではないのでさらりと説明する。

作り方については[Java再帰下降構文解析 超入門](https://qiita.com/7shi/items/64261a67081d49f941e3)や[構文解析HowTo](https://gist.github.com/draftcode/1357281)を参考にした。ただし前者はJava、後者はC++で書かれている。

まず`State`クラスを作る。これは文字列に対して「今どの位置を見ているのか」「見ている位置を1つずらす」処理を持つクラスである。いわゆるイテレータである。前者は`peek`、後者は`next`というメンバ関数で実現する。`peek`について、もし位置が終端に達していたら`null`を返す。

あとはBNFっぽいルールを作って、ルール通りに解析すれば良い。構文解析に失敗したら例外を投げるようにする。

`number`関数については補足する。連続する数字とピリオドを取得し、これを Doubleに変換する。ただしピリオドが2個以上現れるなどの不正な入力があるかもしれないので、もしDoubleへの変換に失敗したら例外を投げるようにしている。

{{< highlight kotlin >}}
package com.example.calculator

class CalcParser(str: String) {
    class State(private var str: String) {
        private var i: Int = 0
        fun peek(): Char? {
            if (i < str.length) {
                return str[i]
            } else {
                return null
            }
        }
        fun next() {
            i++
        }
    }
    private var s = State(str)

    fun parse(): String {
        try {
            return expr().toString()
        } catch(e: Exception) {
            return e.message ?: "Error"
        }
    }
    private fun expr(): Double {
        var ret = term()
        while (true) {
            val op = s.peek() ?: break
            if (op == '+') {
                s.next()
                ret += fact()
            } else if (op == '-') {
                s.next()
                ret -= fact()
            } else {
                break
            }
        }
        return ret
    }
    private fun term(): Double {
        var ret = fact()
        while (true) {
            val op = s.peek() ?: break
            if (op == '*') {
                s.next()
                ret *= fact()
            } else if (op == '/') {
                s.next()
                ret /= fact()
            } else {
                break
            }
        }
        return ret
    }
    private fun fact(): Double {
        val c = s.peek() ?: throw Exception("Something wrong on fact")
        if (c == '(') {
            s.next()
            val ret = expr()
            s.next()
            return ret
        } else {
            return number()
        }
    }
    private fun number(): Double {
        var numStr = ""
        while (true) {
            val c = s.peek() ?: break
            if (c.isDigit() || c == '.') {
                numStr += c
                s.next()
            } else {
                break
            }
        }
        return numStr.toDoubleOrNull() ?: throw Exception("Failed on number")
    }
}
{{< /highlight >}}

最後に、`CalcViewModel.kt`の`onEqualButtonClicked`を編集すれば完成。

{{< highlight kotlin >}}
  fun onEqualButtonClicked() {
      val str = _text.value
      if (str != null) {
          _text.value = CalcParser(str).parse()
      }
  }
{{< /highlight >}}

### 補足

今回は括弧の機能つきの電卓を作ったが、市販で安く売っている電卓アプリを作る場合は構文解析を明にやる必要がない。電卓のボタンが押された時の状態遷移を設計しそれに基づいてプログラムを設計すれば良さそう。

今日はここまで。
