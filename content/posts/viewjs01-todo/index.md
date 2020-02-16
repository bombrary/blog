---
title: "Vue.js勉強メモ(1) - 簡易Todoリストの作成"
date: 2020-02-16T18:52:20+09:00
tags: ["JavaScript", "Vue.js"]
categories: ["JavaScript", "Vue.js"]
---

[公式ガイド](https://jp.vuejs.org/v2/guide/)の、コンポーネントの詳細の手前まで読み終えたので、この時点でTodoリストっぽいものを作ってみる。データベースを用意しないため、厳密にはTodoリストではない。

コンポーネントについてはまだ学んでいないため、これから書くコードにはまだ改善の余地があるだろう。

## 準備

`index.html`を用意する。

```html
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charet="utf-8">
    <script src="https://cdn.jsdelivr.net/npm/vue/dist/vue.js"></script>
  </head>
  <body>
    <h1>Todo List</h1>
    <script src="script.js"></script>
  </body>
</html>
```

以下の部分でVue.jsを読み込んでいる。

```html
<script src="https://cdn.jsdelivr.net/npm/vue/dist/vue.js"></script>
```

`script.js`を作成しておく。中身はまだ空。


## 実装する機能

初めにも述べたが、データベースは用意しない。以下の簡単な機能だけ実装する。

- 入力エリア
- Todoリスト表示エリア
  - 各要素に削除ボタンをつける。

勉強を兼ねて、いくらか遠回りしながら作っていく。

## 配列の要素をli要素として表示

`index.html`に追記する。

```html
<div id="app">
  <ul>
    <li v-for="todo in todos">{{ todo }}</li>
  </ul>
</div>
```

`Vue.js`が用意したテンプレート構文をHTMLに埋め込むことによって、データとDOMを結びつけることができる。`v-`という接頭辞がついた属性はディレクティブと呼ばれる。今回の`v-for`ディレクティブは、その名の通りfor文を実現する。構文から分かると思うが、JSとかPythonで使われているfor-in文と同じ文法。

式の埋め込みは`{{ 式 }}`で行う。[ガイドではMustache(口髭)構文と呼んでいる](https://jp.vuejs.org/v2/guide/syntax.html#%E3%83%86%E3%82%AD%E3%82%B9%E3%83%88)。良いネーミングだなと思ったけど、`{{ }}`の書式をそう呼ぶのはわりと一般的みたい？

さて、そうすると`todos`というデータを用意する必要がありそうだが、これは`script.js`で行う。

```js
const app = new Vue({
  el: '#app',
  data: {
    todos: ['todo1', 'todo2', 'todo3', 'todo4', 'todo5']
  }
})
```

`el`プロパティに、データと結びつく要素を指定する。これはセレクタの書式。`el`とは恐らく`element`の略。`data`プロパティに、結びつけるデータを指定する。`v-for`で利用するために、`todos`プロパティは配列にする。

こんな感じで、Vue.jsでは「データとDOMを結びつける」みたいなコーディングを行っていくみたい。この部分に関してはD3.jsと通ずるものがある。

`index.html`を開くとこんな感じになる。`todos`の各要素が`li`要素の内部に埋め込まれていることが分かる。

{{< figure src="./sc01.png" width="50%" >}}

面白いことに、`todos`の変更がリアルタイムで反映される。このことをガイドでは「リアクティブ」と表現している。データとDOMを結び付けておけば、データの変化が起こったとしてもプログラマが再描画を指示する必要がない。

ちなみに、結びついたデータは`app`のプロパティからアクセスできる。

{{< figure src="./sc02.png" width="50%" >}}

## 入力エリアの追加

新しいTodoを追加する入力エリアを追加する。`index.html`にて、`input`要素を追加する。

```html
<div id="app">
  <input v-model="todoInput">
  <ul>
    <li v-for="todo in todos">{{ todo }}</li>
  </ul>
</div>
```

`v-model`ディレクティブを上のように指定することで、`todoInput`プロパティを変更すれば`input`要素の中身が更新される。また反対に、`input`要素にテキストを入力すると、`todoInput`プロパティが更新される。このような仕組みを「双方向バインディング」という。

`todoInput`については、`script.js`で次のように定義する。

```js
const app = new Vue({
  el: '#app',
  data: {
    todoInput: '',
    todos: ['todo1', 'todo2', 'todo3', 'todo4', 'todo5']
  }
})
```

双方向バインディングを実感するためには、次のようにする。`app.todoInput`の値を変更すると、`input`の値が変わる。

{{< figure src="./sc03.png" width="50%" >}}

`input`を変更すると、`app.todoInput`の値が変更される。

{{< figure src="./sc04.png" width="50%" >}}

`input`は`type`属性で、チェックボックスやラジオボタンなど、様々なフォーム要素に変更できる。それに応じて`v-model`に結びつく要素の型が変化する。詳しくは[ガイドのフォーム入力バインディングの項](https://jp.vuejs.org/v2/guide/forms.html)にて。

## 追加ボタン

addボタンを追加する。ボタンを押したら、`input`要素の中身が`todos`に追加されるようにする。

`index.html`にて、`button`要素を追加する。

```html
<div id="app">
  <input v-model="todoInput">
  <button v-on:click="addTodo">add</button>
  <ul>
    <li v-for="todo in todos">{{ todo }}</li>
  </ul>
</div>
```

`v-on`ディレクティブで、イベントハンドラを指定する。コロン以下の記述は`v-on`の引数。ここでは`click`イベントを設定している。

`addTodo`メソッドを用意する。これは`script.js`で、`methods`プロパティ内部に指定する。

```js
const app = new Vue({
  el: '#app',
  data: {
    todoInput: '',
    todos: ['todo1', 'todo2', 'todo3', 'todo4', 'todo5']
  },
  methods: {
    addTodo: function(e) {
      this.todos.push(this.todoInput)
    }
  }
})
```

`addTodo`プロパティの値は`function`文でなけらばならない。アロー関数だと`this`の指す値が変わってしまうため。引数にはイベントオブジェクトを指定する。

## 削除機能

`index.html`にて、新たにdelボタンを追加する。

```html
<div id="app">
  <input v-model="todoInput">
  <button v-on:click="addTodo">add</button>
  <ul>
    <li v-for="(todo,i) in todos">
      {{ todo }}
      <button v-on:click="delTodo(i)">del</button>
    </li>
  </ul>
</div>
```

「配列のi番目を削除」という風に書きたいので、`delTodo`関数に配列の添え字を指定する。配列の添え字は`v-for`の構文を上記のようにすることで取得できる。`(key, val) in object`のようにして、Objectに対してループを回すこともできる。さらなる機能については[ガイドのリストレンダリングの項](https://jp.vuejs.org/v2/guide/list.html)にて。

`delTodo(i)`のように引数を明示すると、第一引数はイベントオブジェクトでは無くなる。もしイベントオブジェクトが欲しいなら、`delTodo(i, $event)`と指定する。

`script.js`は次のようにする。

```js
const app = new Vue({
  el: '#app',
  data: {
    todoInput: '',
    todos: ['todo1', 'todo2', 'todo3', 'todo4', 'todo5']
  },
  methods: {
    addTodo: function(e) {
      this.todos.push(this.todoInput)
    },
    delTodo: function(i) {
      this.todos.splice(i, 1)
    }
  }
})
```

最終的には次のようになる。

{{< figure src="./sc05.png" width="40%" >}}

形にはなった。今回はここまで。

## 参考

[ガイド - Vue.js](https://jp.vuejs.org/v2/guide/)
