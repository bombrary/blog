---
title: "webpackに入門する - p5.jsの開発環境作り"
date: 2020-03-19T09:44:48+09:00
tags: []
categories: ["JavaScript", "webpack", "p5.js"]
---


webpackを利用してp5.jsの開発環境を作り、ボールが弾むプログラムを作成する。


## 動機

ふとしたきっかけで久々に[p5.js](https://p5js.org)を触りたくなった。

昔使っていたときは、p5.jsのファイルをダウンロードしてscriptタグに直接指定することで書いていた。しかし最近、Vue.jsのガイドを読んでいてwebpackの存在を知った。名前は知っていたのだが、具体的に何をするためのものなのかはよく分かっていなかったので調べた。

### webpackとは

以下、個人的に調べた限りの理解を書く。

[Concept](https://webpack.js.org/concepts/)によれば、webpackとは"module bundler"の一種。bundleという意味から、「複数のモジュールを一つに束ねるツール」だと予想できる。JSのプログラムを、モジュールとして複数の単位に分割して開発する。それを一つのファイルにまとめ上げてくれるのがwebpack。

例えばp5.jsで、ボールが弾むだけのプログラムを書こう、と思った場合、

- ボールを管理するモジュールを`Ball.js`に書く
- スケッチを管理するモジュールを`sketch.js`に書く
- メインの処理を`index.js`に書く

みたいにモジュールを分けられる。

ただし、モジュールを扱うための機能であるimport/export文はES2015の仕様で標準採用され、[多くのブラウザで実装されている](https://developer.mozilla.org/ja/docs/Web/JavaScript/Guide/Modules)。じゃあwebpackの他の強みは何かというと、おそらく「JS以外のファイルもまとめてくれる点」だと思う。例えばcssやsassのファイルもJSに埋め込むことができる。TypeScriptやJSXのファイルもwebpackでまとめられる。ただしwebpackの核の機能はあくまでJSのモジュールをまとめることなので、JS以外のファイルはloaderと呼ばれる変換器を通しておく必要がある。とはいえ、「このファイルはこのloaderに通してね」というのをあらかじめ設定ファイルに書いておけば、少ないコマンドで変換からbundleまでやってくれるので、便利である。

今回はp5.jsの開発環境づくりのためにwebpackを用意するのだが、JSのモジュールしか扱うつもりはない。なのでwebpackの恩恵は少ないかもしれない。しかし練習として使ってみる。

## webpackの導入と動作確認

まず適当にプロジェクト用のディレクトリを作る。npmでプロジェクトを初期化する。

{{< cui >}}
$ mkdir p5-sandbox
$ cd p5-sandbox
$ npm init -y
{{< /cui >}}

以下、このプロジェクトのルートディレクトリを`/`で表す。

webpack本体を入れる。webpackをコマンドラインから実行するためにはwebpack-cliが必要なので、それも入れる。個人で使う分にはどうでもよいと思うが、これらは開発のみに利用されるパッケージなので、`--save-dev`をつけておく。

{{< cui >}}
$ npm install webpack webpack-cli --save-dev
{{< /cui >}}

### ディレクトリの作成

今回は次のようにする。

- ソースコードは`/src/index.js`に書く。
- bundle後のファイルは`/public/js/bundle.js`として出力されるようにする。

あらかじめディレクトリを作成しておく。

{{< cui >}}
$ mkdir src
$ mkdir -p public/js
{{< /cui >}}

### index.jsの作成

`/src/index.js`を作成。動作確認のため適当に書く。

```js
console.log("Hello, World");
```

### webpackの設定

`/webpack.config.js`を作成する。

```js
const path = require('path');

module.exports = {
  mode: 'development',
  entry: './src/index.js',
  output: {
    filename: 'bundle.js',
    path: path.resolve(__dirname, 'public/js')
  }
}
```

#### 説明

`module.exports`の中に色々設定項目を書いていく。基本的なことは[Configuration](https://webpack.js.org/configuration/)に載っている。

- [mode](https://webpack.js.org/configuration/mode/): webpackのモードを設定。`development/production/none`が設定できる。モードよっていくつかの設定項目が自動でセットされるみたい。
- [enrty](https://webpack.js.org/configuration/entry-context/#entry): どのJSファイルをbundleするかをここに書く。
- [output](https://webpack.js.org/configuration/output/): 出力先ファイルを設定。
    - filename: 出力先ファイル名
    - path: 出力先ファイルのパス。絶対パスである必要があるため、`path.resolve`で相対パスを絶対パスに変換する。`__dirname`はnode.jsが初めから持っている変数で、現在のディレクトリのパスが入っている。

### bundleする

次のコマンドを実行すると、`webpack.config.js`の設定をもとに、`/public/js/bundle.js`が作成される。`-p`オプションを指定すると、改行やスペースを取り払って出力ファイルのサイズを小さくしてくれる。

{{< cui >}}
$ npx webpack -p
{{< /cui >}}

nodeで実行できることが確認できる。

{{< cui >}}
$ node public/js/bundle.js
Hello, World
{{< /cui >}}

## webpack-dev-serverの導入と動作確認

ローカルWebサーバーを動かすために、webpack-dev-serverを使ってみる。npmでインストールする。

{{< cui >}}
$ npm install webpack-dev-server --save-dev
{{< /cui >}}

### 設定

`webpack.config.js`の`module.exports`に`devServer`プロパティを追記する。

```js
module.exports = {
  ...
  devServer: {
    contentBase: path.resolve(__dirname, 'public'),
    publicPath: "/js/"
  }
}
```

#### 説明

[DevServer](https://webpack.js.org/configuration/dev-server/#devserverhot)に詳しいことが載っている。

- [contentBase](https://webpack.js.org/configuration/dev-server/#devservercontentbase): サーバのルートを決める。ドキュメントによると絶対パスが推奨されているみたいなので、`path.resolve`を使って書く。
- [publicPath](https://webpack.js.org/configuration/dev-server/#devserverpublicpath-): bundleされたJSファイルがどこに置かれるのかを、dev-serverに教える。`contentBase`が`/public`、`publicPath`が`/js/`なので、`/public/js/`にbundleされたファイルが置かれる。

### 起動

次のコマンドで実行できる。デフォルトは`http://localhost:8080`のようだ。

{{< cui >}}
$ npx webpack-dev-server
(i) ｢wds｣: Project is running at http://localhost:8080/
(i) ｢wds｣: webpack output is served from /js/
...
{{< /cui >}}

webpack-dev-serverにはlive reloading機能が付いている。なので`index.js`を変更すると、自動でbundleが行われ、ページがリロードされる。

## コマンドの別名を追加する

`/package.json`を編集する。`script`プロパティに`build`と`start`の2項目を追加。

```js
{
...
  "scripts": {
    "test": "echo \"Error: no test specified\" && exit 1",
    "build": "webpack -p",
    "start": "webpack-dev-server"
  },
...
}
```

このようにすると、以下のコマンドで`webpack -p`が実行される。

{{< cui >}}
$ npm run build
{{< /cui >}}

以下のコマンドで`webpack-dev-server`が実行される。

{{< cui >}}
$ npm start
{{< /cui >}}

## p5.jsの導入と動作確認

次のコマンドでp5.jsをイントールする。

{{< cui >}}
$ npm install p5
{{< /cui >}}

試しに円を書いてみる。

`/src/index.js`を以下のようにする。

p5.jsがモジュールである都合上、p5.jsは[instance mode](https://github.com/processing/p5.js/wiki/Global-and-instance-mode)で用いる必要がある。また、p5.jsのキャンバスに余白が空くため、`body`要素のmarginを0にしている。

```js
import p5 from 'p5';
import { sketch } from './sketch.js';

document.body.style.margin = "0";

const app = new p5(sketch, document.body);
```

`/src/sketch.js`を作成し、内容を以下のようにする。

```js
export const sketch = (p) => {
  p.setup = () => {
    p.createCanvas(p.windowWidth, p.windowHeight);
  }
  p.draw = () => {
    p.background('#0f2350');
    p.noStroke();
    p.fill(255);
    p.ellipse(p.windowWidth/2, p.windowHeight/2, 50, 50);
  }
};
```

`index.js`では`sketch.js`の`sketch`をimportしていることに注目。また、`sketch.js`では`sketch`という変数をexportしていることに注目。webpackではこの情報をもとに、2つのファイルをまとめて`bundle.js`に変換する。また`p5`は`./`という相対パス表現を用いずにimportしている。このように書くと、`/node_modules/`にあるパッケージを参照する(これは[resolve.module](https://webpack.js.org/configuration/resolve/#resolvemodules)のデフォルト値として設定されている)。

ブラウザ上では以下のように表示される。

{{< figure src="sc01.png" width="50%" >}}

## 弾むボールの作成

書き方の基本は[The Nature of Code](https://natureofcode.com/book/chapter-2-forces/)が参考になる。ただしコードはProcessingで書かれているので、うまく読み替える。

### sketch.js

`/src/sketch.js`を以下のようにする。

`setup`にて、`Ball`のインスタンスを作成。引数は`(p, 位置ベクトル, 速度ベクトル, 直径)`の順に指定する。`Ball`の実装は次の項で行う。

`draw`にて、`ball.applyForce`で重力を加え、`ball.run`で位置、速度の更新、画面描画を行う。

```js
import { Ball } from './Ball';

export const sketch = (p) => {
  let ball;
  p.setup = () => {
    p.createCanvas(p.windowWidth, p.windowHeight);
    ball = new Ball(
      p,
      p.createVector(p.windowWidth/2, p.windowHeight/2),
      p.createVector(10, -20),
      50,
      10
    );
  }
  p.draw = () => {
    p.background('#0f2350');
    ball.applyForce(p.createVector(0, 9.8));
    ball.run();
  }
};
```

### Ball.js

上のコードが動くように、`/src/Ball.js`を作成する。

- `run`: `update`と`display`を呼び出す。
- `update`: 位置、速度を更新する。加速度は0に初期化する。
- `collide`: 壁との当たり判定をする。衝突したら位置を補正し、速度の向きを逆にする。非弾性衝突を仮定し、速度の大きさを減衰させる。
- `display`: ボールを描画する。
- `applyForce`: 外力を加える。運動方程式を満たすように、力&div;質量を加速度として加える。

```js
import p5 from 'p5';

export class Ball {
  constructor(p, location, velocity, diameter, mass) {
    this.p = p;
    this.r = location;
    this.v = velocity;
    this.d = diameter;
    this.a = p.createVector(0, 0);
    this.m = mass;
  }
  run() {
    this.update();
    this.display();
  }
  update() {
    this.v.add(this.a);
    this.r.add(this.v);
    this.a.mult(0);
    this.collide();
  }
  collide() {
    const [x, y] = [this.r.x, this.r.y];
    const r = this.d / 2;
    const [w, h] = [this.p.windowWidth, this.p.windowHeight];
    const decay = 0.9;
    if (x - r < 0) {
      this.v.x *= -decay;
      this.r.x = r;
    }
    if(w < x + r) {
      this.v.x *= -decay;
      this.r.x = w - r;
    }
    if (y - r < 0) {
      this.v.y *= -decay;
      this.r.y = r;
    }
    if (h < y + r) {
      this.v.y *= -decay;
      this.r.y = h - r;
    }
  }
  applyForce(f) {
    let a = p5.Vector.div(f, this.m);
    this.a.add(a);
  }
  display() {
    const p = this.p;
    p.noStroke();
    p.fill(255);
    p.ellipse(this.r.x, this.r.y, 50, 50);
  }
}
```

こんな感じになる。

{{< figure src="sc02.gif" width="50%" >}}

ちなみにこの状態で`npm run build`を行うと、ファイルサイズが大きすぎる旨の警告が出る。警告をを消すにはファイル分割などの設定をする必要があるが、これについてはまたいつか調べる。今回はここまで。

## 参考

- [Documentation - webpack](https://webpack.js.org/concepts/)
- [p5.js](https://p5js.org)
- [The Nature of Code](https://natureofcode.com/book/chapter-2-forces/)
