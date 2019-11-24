---
title: "Androidアプリ開発勉強(2) - Navigationの基本"
date: 2019-11-20T09:03:17+09:00
tags: ["Programming", "Android", "Kotlin", "Navigation" ]
categories: ["Programming", "Android", "Kotlin"]
---

Navigationを用いて画面遷移をやってみる。具体的には以下の処理を行う。

- Fragment01とFragment02を用意する
- Fragment01でボタンが押されたらFragment02に遷移する

[Android Kotlin Fundamentals Course](https://codelabs.developers.google.com/android-kotlin-fundamentals/)での03辺りを勉強した記録なので、詳しいことはそちらに載っている。

## Navigationについて

異なるFragment間の遷移を制御する仕組み。遷移の設定を視覚的に行えるらしい。

これ以前はIntentという仕組みを用いていたらしい。これについては必要になりそうならいつか調べる。

## プロジェクト作成

Empty Activityを選択し、名前をNavigation Testとする。

`build.gradle(Module: app)`でDataBindingを有効にしておく。

## Fragmentの作成

`layouts/`にFragmentを作成する。"Create layout XML?"だけチェックをつけておく。Fragmentは2つ作成し、それぞれ"Fragment01"と"Fragment02"とする。xmlファイルはそれぞれ`fragment_fragment01.xml`、`fragment_fragment02.xml`とする。

まず`TextView`の`text`要素に設定するための定数を`strings.xml`に内容を追加しておく。
{{< highlight xml >}}
<resources>
    <string name="app_name">NavigationTest</string>

    <!-- TODO: Remove or change this placeholder text -->
    <string name="hello_blank_fragment">Hello blank fragment</string>
    <string name="fragment01">Fragment01</string>
    <string name="fragment02">Fragment02</string>
    <string name="click">Click</string>
</resources>
{{< /highlight >}}

`fragment_fragment01.xml`の内容は以下の通りにする。`Button`を追加し、`text`を`@string/click`に設定する。`TextView`の`text`を`@string/fragment01`に設定する。また全体を`ConstraintLayout`で包み、DataBindingのために`layout`でさらに包む。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<layout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    tools:context=".Fragment01">

    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <TextView
            android:id="@+id/text_fragment01"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/fragment01"
            app:layout_constraintBottom_toBottomOf="parent"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toTopOf="parent" />

        <Button
            android:id="@+id/button"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/click"
            app:layout_constraintBottom_toTopOf="@+id/text_fragment01"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toTopOf="parent" />
    </androidx.constraintlayout.widget.ConstraintLayout>

</layout>
{{< /highlight >}}

`fragment_fragment02.xml`もほぼ同じ。`Button`が無い点だけ異なる。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<layout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    tools:context=".Fragment02">

    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent">

        <TextView
            android:id="@+id/text_fragment02"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:text="@string/fragment02"
            app:layout_constraintBottom_toBottomOf="parent"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toTopOf="parent" />
    </androidx.constraintlayout.widget.ConstraintLayout>

</layout>
{{< /highlight >}}

## Navigationの作成

`res/`を右クリックして、"New" &rarr; "Android Resource File"をクリック。次のように設定。

- File neme: navigation
- Resource Type: Navigation

"OK"を押すと、ポップアップが出てきて、"Add dependencies?"みたいなメッセージが出てくるので"OK"を押す。このとき、Navigationを利用するための依存関係が`build.gradle(Module: app)`に設定されていることが確認できる。

{{< highlight gradle >}}
dependencies {
    ...
    implementation 'androidx.navigation:navigation-fragment-ktx:2.1.0'
    implementation 'androidx.navigation:navigation-ui-ktx:2.1.0'
}
{{< /highlight >}}

`navigation/navigation.xml`ができているので、それを開く。ここでFragmentの遷移が設定できる。+ボタンでFragmentを追加する。画面同士の接続関係はConstraintLayoutと同じ要領で行う。

以下のような接続関係にする。

{{< figure src="./sc01.png" >}}

textで表示すると以下のようになっている。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<navigation xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:id="@+id/navigation"
    app:startDestination="@id/fragment01">

    <fragment
        android:id="@+id/fragment01"
        android:name="com.example.navigationtest.Fragment01"
        android:label="fragment_fragment01"
        tools:layout="@layout/fragment_fragment01" >
        <action
            android:id="@+id/action_fragment01_to_fragment02"
            app:destination="@id/fragment02" />
    </fragment>
    <fragment
        android:id="@+id/fragment02"
        android:name="com.example.navigationtest.Fragment02"
        android:label="fragment_fragment02"
        tools:layout="@layout/fragment_fragment02" />
</navigation>
{{< /highlight >}}

接続関係は`action`要素として定義されている。`id`属性は、「ボタンを押した時遷移する」という処理を書くときに必要になるので注目しておきたい。

## Navigationをactivity_mainに設定

`activity_main.xml`を編集する。まず`layout`で全体を包み、さらに`LinearLayout`-`fragment`と階層構造にしている。

`fragment`の`name`属性に`androidx.navigation.fragment.NavHostFragment`を設定すると、この`fragment`が`Navigation`として振る舞うようになる。`navGraph`には接続関係を記した`xml`ファイルを指定する。ここでは`navigation/navigation.xml`を設定している。`defaultNavHost="true"`としておくと、backボタンで戻れるようになるらしい。

{{< highlight xml >}}
<?xml version="1.0" encoding="utf-8"?>
<layout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    tools:context=".MainActivity">
    <LinearLayout
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:orientation="vertical" >

      <fragment
          android:id="@+id/myNavHostFragment"
          android:name="androidx.navigation.fragment.NavHostFragment"
          android:layout_width="match_parent"
          android:layout_height="match_parent"
          app:navGraph="@navigation/navigation"
          app:defaultNavHost="true" />

    </LinearLayout>
</layout>
{{< /highlight >}}

この時点でアプリを動かしてみると、ボタンは反応しないが`Fragment01`が表示されている。

## (寄り道)DataBindingの設定

`MainActivity.kt`と`Fragment02.kt`のDataBindingを設定しておく。

`MainActivity.kt`を編集する。

{{< highlight kotlin >}}
class MainActivity : AppCompatActivity() {

    private lateinit var binding: ActivityMainBinding
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = DataBindingUtil.setContentView(this, R.layout.activity_main)
    }
}
{{< /highlight >}}

`Fragment02.kt`を編集する。

{{< highlight kotlin >}}
class Fragment02 : Fragment() {

    private lateinit var binding: FragmentFragment02Binding
    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        binding = DataBindingUtil.inflate(inflater, R.layout.fragment_fragment02, container, false)
        return binding.root
    }

}
{{< /highlight >}}

## ボタンが押された時の遷移の設定

`Fragment01.kt`を編集する。

`view.findNavController()`で`Navigation`を取得し、`navigate(actionのid)`で遷移する。

{{< highlight kotlin >}}
class Fragment01 : Fragment() {
    private lateinit var binding: FragmentFragment01Binding
    override fun onCreateView(
        inflater: LayoutInflater, container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View? {
        binding = DataBindingUtil.inflate(inflater, R.layout.fragment_fragment01, container, false)
        binding.button.setOnClickListener { view: View ->
            view.findNavController().navigate(R.id.action_fragment01_to_fragment02)
        }
        return binding.root
    }
}
{{< /highlight >}}

これでアプリを動かしてみる。"Click"ボタンを押すとFragment02に遷移するはず。

今回はここまで。他にも、異なるFragment間のデータの受け渡しだったり、遷移時のアニメーションだったり、まだ学べることはありそう。
