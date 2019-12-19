---
title: "Elm/JavaScript ローカルサーバーで通信する際にハマったこと"
date: 2019-12-19T09:50:00+09:00
tags: ["Elm", "JavaScript", "Node.js", "Network", "HTTP", "Server"]
categories: ["Elm", "JavaScript", "Node.js", "Network"]
---

今回たまたまクライアント側でElmを使ったけど、これはElmに限ったことではない。

## 結論

### Client側での留意点

- `url`は`localhost:[port]`ではなく`http://localhost:[port]`と指定しなければならない。つまり、URLにはちゃんとスキーム名を指定する。

### Server側での留意点

- `Access-Control-Allow-Origin`に関連するヘッダーをちゃんと設定する。

## 成功コード

### プログラムの内容

サーバーは`{ "msg" : "Hello, World!" }`という内容のJSONを送ってくるので、クライアントはその値を受け取って"Success: Hello, World!"を出力する。それだけ。

### Client: Elm

{{< highlight elm >}}
module Main exposing (..)
import Browser exposing (..)
import Json.Decode exposing (..)
import Http exposing (..)
import Html exposing (..)
import Html.Attributes exposing (..)

main = Browser.element
  { init = init
  , update = update
  , view = view
  , subscriptions = subscriptions
  }

type Model
  = Loading
  | Failed
  | Success String

init : () -> (Model, Cmd Msg)
init _ =
  ( Loading, getServer )

type Msg
  = GotData (Result Http.Error String)

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    GotData result ->
      case result of
        Ok str ->
          (Success str, Cmd.none)
        Err _ ->
          (Failed, Cmd.none)

getServer : Cmd Msg
getServer =
  Http.get
    { url = "http://localhost:3000"
    , expect = Http.expectJson GotData dataDecoder
    }

dataDecoder : Decoder String
dataDecoder =
  field "msg" string

view : Model -> Html Msg
view model =
  case model of
    Failed ->
      p []
      [ text "Failed!" ]

    Loading ->
      p []
      [ text "Loading..." ]

    Success str ->
      p []
      [ text ("Success : " ++ str) ]

subscriptions : Model -> Sub Msg
subscriptions _ = Sub.none
{{< /highlight >}}

### Server: JavaScript (Node.js)

{{< highlight js >}}
const http = require('http');
const server = http.createServer();

server.on('request', (req, res) => {
  res.writeHead(200, {
    'Access-Control-Allow-Origin': '*',
    'Content-Type': 'application/json'
  });
  const body = {
    msg: 'Hello, World!'
  };
  res.write(JSON.stringify(body))
  res.end();
});

server.listen(3000);
{{< /highlight >}}


## 失敗と解決までの流れ

### Http.getの引数

初めはサーバー側で次のようにしていた。

{{< highlight js >}}
server.on('request', (req, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  const body = {
    msg: 'Hello, World!'
  };
  res.write(JSON.stringify(body))
  res.end();
});
{{< /highlight >}}

Elm側でのGetメソッドは次のように呼び出していた。

{{< highlight elm >}}
getServer : Cmd Msg
getServer =
  Http.get
    { url = "localhost:3000"
    , expect = Http.expectJson GotData dataDecoder
    }
{{< /highlight >}}

すると、ブラウザ(Safari)のConsole上で次のようなエラーが出ていた。

```
Cross origin requests are only supported for HTTP.
XMLHttpRequest cannot load localhost:3000 due to access control checks.
```

この時、「サーバー側はHTTPモジュールを使って通信してるのになんで`only supperted for HTTP`なんだ&hellip;？」と思った。

調べても情報が見つからないので、自分でちゃんと考えてみる。「HTTPだけに対応しています」というエラーが出ているということは、サーバがHTTP通信として認識されていないということ。ではHTTP通信として認識されるための条件とは何か。

とりあえずパッと思いついたのは「ポート番号」。HTTP通信は基本的に80番ポートで通信しているはずで、その時はポートを指定する必要が無い。

そこで、クライアント側では以下のように変えた。サーバ側ではポートを80番で`listen`することにした。

{{< highlight elm >}}
  Http.get
    { url = "localhost"
    , expect = Http.expectJson GotData dataDecoder
    }
{{< /highlight >}}

今度は次のようなエラーが出た。

```
Failed to load resource: the server responded with a status of 404 (Not Found)   http://localhost:8000/localhost
```

意味不明なURL`http://localhost:8000/localhost`にアクセスしようとしている&hellip;。`elm reactor`で起動しているWebサーバのURL`http://localhost:8000`とNode.js側のサーバのURL`localhost`が重なってなんか変なことになっている。

ここで、ふと「エラーメッセージだと`localhost`の前に`http://`が付いているな、これを試しにつけてみよう」と閃く。

{{< highlight elm >}}
  Http.get
    { url = "http://localhost"
    , expect = Http.expectJson GotData dataDecoder
    }
{{< /highlight >}}

すると、次のようなエラーに変わった。

```
Origin http://localhost:8000 is not allowed by Access-Control-Allow-Origin.
XMLHttpRequest cannot load http://localhost/ due to access control checks.
Failed to load resource: Origin http://localhost:8000 is not allowed by Access-Control-Allow-Origin.
```

このエラーは以前別の機会で調べたことがあった。サーバ側で次のようにヘッダを付加してあげると解決。

{{< highlight js >}}
res.writeHead(200, {
  'Access-Control-Allow-Origin': '*',
  'Content-Type': 'application/json'
});
{{< /highlight >}}

これでうまく動くようになった。ここで、「実はクライアント側の問題は`http://`を付けていなかったことだけが原因？」と思い、次のように書き換えた。

{{< highlight elm >}}
  Http.get
    { url = "http://localhost:3000"
    , expect = Http.expectJson GotData dataDecoder
    }
{{< /highlight >}}

サーバー側もポート3000で`listen`したところ、正常に動いた。

## 補足検証

クライアント側をElmではなくJSでやってみる。

やっぱり以下のコードだとエラーが出た。

{{< highlight js >}}
fetch('localhost:3000')
  .then(res => {
    return res.json();
  })
  .then(data => {
    return data.msg
  })
  .then(msg => {
    console.log(msg)
  })
{{< /highlight >}}

これなら問題ない。

{{< highlight js >}}
fetch('http://localhost:3000')
  .then(res => {
    return res.json();
  })
  .then(data => {
    return data.msg
  })
  .then(msg => {
    console.log(msg)
  })

// ちなみにasync/awaitで書くとこうなる
(async () => {
  res = await fetch('http://localhost:3000');
  data = await res.json();
  console.log(await data.msg)
})()
{{< /highlight >}}

## 結果の考察

`localhost`だと`ftp://localhost`とも`http://localhost`とも取れてしまうから、確かに必要だ、と後で思った。

いつもブラウザのURL欄に`localhost`と入力してアクセスできていたため、同じように`http://`を省いて通信できるものだと無意識に思っていた。しかしこれが通用するのはブラウザだけで、恐らく「スキーマが指定されていなかったら`http://`をつけたものとみなす」という仕様なのだろう。
