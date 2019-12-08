---
title: "Socket通信勉強(2) - Pythonでの書き方/HTTPサーバーもどき作成"
date: 2019-12-08T11:09:35+09:00
tags: ["TCP", "Python", "Socket", "HTTP"]
categories: ["Python", "Network"]
---

## PythonでのSocket通信

やってることはCでやったときと同じである。サーバーとクライアントの通信手順は同じだし、関数名も同じである。しかしCで書いた場合に比べてシンプルに書ける。エラーは例外として投げられるため、自分で書く必要がない。また`sockaddr_in`などの構造体が登場することはなく、Pythonでの`bind`関数と`connect`関数の引数に直接アドレス・ポートを指定する。

### server.py

前回と同じく、以下の手順で通信を行う。

1. listen(待ち受け)用のソケット作成 - socket
2. 「どこからの接続を待つのか」「どのポートにて待ち受けするのか」を決める - bind関数の引数
3. ソケットにその情報を紐つける - bind
4. 実際に待ち受けする - listen
5. 接続要求が来たら受け入れる - accept
6. 4によって通信用のソケットが得られるので、それを用いてデータのやりとりをする- send/recv

{{< highlight py >}}
import socket

s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("", 8000))
s.listen(5)
(sock, addr) = s.accept()
print("Connected by" + str(addr))
sock.send("Hello, World".encode('utf-8'))
sock.close()
s.close()
{{< /highlight >}}

上のコードを見れば各関数がどんな形で引数をとって、どんな値を返すのかがわかると思う。いくつか補足しておく。

#### bind

`(受け入れアドレス, ポート)`というタプルを引数にとる。受け入れアドレスを空文字列にしておけば、どんなアドレスからの接続も受け入れる。つまりCでやった`INADDR_ANY`と同じ。

{{< highlight py >}}
s.bind(("", 8000))
{{< /highlight >}}

#### encode

Pythonのstring型をそのまま送ることはできないので、byte型に変換する。これは`string.encode`で行える。

{{< highlight py >}}
sock.send("Hello, World".encode('utf-8'))
{{< /highlight >}}

### client.py

1. サーバーとの通信用のソケット作成 - socket
2. サーバが待ち受けている宛先を設定 - connectの引数
3. 2で設定した宛先に対して接続する - connect
4. 1で作ったソケットを用いてデータのやりとりをする。 - send/recv

{{< highlight py >}}
import socket

sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.connect(("localhost", 8000))
data = sock.recv(64)
print(data)
sock.close()
{{< /highlight >}}

これも2点補足する。

#### connect

`(接続先のアドレス, ポート)`というタプルを指定する。接続先に`localhost`を指定すると、`127.0.0.1`と解釈される。

{{< highlight py >}}
sock.connect(("localhost", 8000))
{{< /highlight >}}

#### recv

引数には受け取る最大バイト数を指定する。

{{< highlight py >}}
data = sock.recv(64)
{{< /highlight >}}

受け取ったデータのサイズが64バイト以上の場合、ソケットから先頭64バイトだけ読み取ることになるので注意。つまり残りのデータがソケットに残っている。大量のデータを受け取ることがあるなら、受け取ったデータのサイズをきちんと調べ、必要なら再度`sock.recv`を呼び出す。実際のコードは[ソケットプログラミングHOWTO](https://docs.python.org/ja/3/howto/sockets.html#using-a-socket)に載っている。

### 実行結果

`server.py`を起動した後に、`client.py`を起動する。

`server.py`では以下の文が出力される。
{{< highlight txt >}}
Connected by('127.0.0.1', 51894)
{{< /highlight >}}

`client.py`では以下の文が出力される。
{{< highlight txt >}}
b'Hello, World'
{{< /highlight >}}

なお、serverを連続で起動しようとすると「Address already in use」みたいなエラーが出る。これは前回も説明したようなエラーで、`setsockopt`関数を利用して解決できる。これについては今回は省略する。30秒くらい待つと復活するようなので我慢する。

## with構文の利用

Pythonにはwith構文というものがある。これは例えばファイルのクローズ処理を自動で行ってくれる(注意:with構文自体はファイル操作のためだけの構文ではない)。ソケットでもwith構文が利用できる。

### server.py

{{< highlight py >}}
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(("", 8000))
    s.listen(5)
    (sock, addr) = s.accept()
    print("Connected by" + str(addr))
    with sock:
        sock.send("Hello, World".encode('utf-8'))
{{< /highlight >}}

### client.py

{{< highlight py >}}
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.connect(("localhost", 8000))
    data = sock.recv(64)
    print(data)
{{< /highlight >}}

### server.py

## HTTP通信の基礎知識

PythonにはHTTP通信用のモジュールがあるのでそれを使うべきなのだが、勉強としてSocket通信でHTTP通信っぽいことをしてみる。

HTTP通信の基本は「リクエスト」と「レスポンス」である。クライアントからサーバーに「何かデータをください」などと要求するメッセージを送る。サーバーはそれを受け取って、適切なメッセージを返す。ブラウザ上でページが表示されるのも同じ仕組みで、ここでは「このページのHTMLファイルが欲しい」とブラウザが要求し、サーバーはそれに応じてHTMLファイルを返す。

{{< figure src="./http-model.svg" >}}

HTTPプロトコルとは、「サーバーはリクエストを受け取って、レスポンスを返す」「クライアントはリクエストを受け取って、レスポンスを受け取る」「リクエストはこんな書式で、レスポンスはこんな書式にしてね」などの取り決めに過ぎない。具体的な通信方法については下位のプロトコルが決めることであって、TCPやUDPでなくても構わない(もちろん、他に通信方法があればの話だが)。

リクエストもレスポンスも、下位プロトコルにとっては結局ただのデータに過ぎないことに注意。サーバーもクライアントも、単にデータを送受信し、その前後で何か処理をしているに過ぎない。

もう一度まとめると、サーバーは以下の動作を行う。

1. リクエストを受け取る
2. リクエストを解釈し、適切なレスポンスを送信する

クライアントは以下の動作を行う。

1. リクエストを送信する
2. レスポンスを受け取る

## HTTPサーバーもどきを作る

とりあえずどんなリクエストであっても決まったレスポンスしか返さないHTTP通信もどきを作ってみる。

`server.py`を次のようにする。`client.py`は作らないことにする。

{{< highlight py >}}
import socket

response = '''\
HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Page Title</title>
  </head>
  <body>
    <h1>Hello, World</h1>
  </body>
</html>
'''

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(("", 8000))
    s.listen(5)
    (sock, addr) = s.accept()
    print("Connected by" + str(addr))
    with sock:
        request = sock.recv(1024)
        print("Request: " + request.decode('utf-8'))
        sock.send(response.encode('utf-8'))
{{< /highlight >}}

## レスポンスの書式

responseは「ステータス行」「ヘッダ」「ボディ」で構成される。

ステータス行は以下の部分。`HTTP/1.1`によってプロトコルとバージョンを識別する。後の数字で「通信に成功したか」「失敗した場合、その原因は何か」を識別する。この数字のことを「ステータスコード」と呼び、後に続くメッセージを「ステータスメッセージ」と呼ぶ。ステータスコード/メッセージの種類は多種多様である。以下の例は`200 OK`であるが、これは通信に成功したことを表す。例えばページが存在しなかった場合は`404 Not Found`が記される。

{{< highlight txt >}}
HTTP/1.1 200 OK
{{< /highlight >}}

ヘッダは`フィールド名: 値`の形式で記述される。フィールドの種類は多種多様である。

例えば以下では、`Content-Type`というフィールドを指定している。これはボディがどんな種類のデータであるかを指定し、ここでは「ボディ部はhtmlで書かれている」ことを表している(なぜ`text/`という接頭辞がついているのかというと、htmlは`text`という分類に属しているかららしい)。単なるテキストファイルであることを明示したい場合は`text/plain`を指定する。

{{< highlight txt >}}
Content-Type: text/html
{{< /highlight >}}

続いて1行空行を空けた後に、ボディが記述される。今回はhtmlを返すことにする。
{{< highlight html >}}
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Page Title</title>
  </head>
  <body>
    <h1>Hello, World</h1>
  </body>
</html>\
{{< /highlight >}}

HTTPクライアントはレスポンスを読み取り、ボディ部から欲しいデータを読み取る。

## HTTPサーバもどきとの通信

curlコマンドやブラウザはHTTPクライアントの一種である。試しにこれらを使って`server.py`と通信してみる。

### curlコマンドの場合

`server.py`を実行した後、以下のコマンドを実行する。

{{< highlight txt >}}
$ curl localhost:8000
{{< /highlight >}}

すると次のメッセージが出力される。curlがHTTPリクエストを`server.py`に送り、レスポンスを受け取った証拠である。

{{< highlight txt >}}
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Page Title</title>
  </head>
  <body>
    <h1>Hello, World</h1>
  </body>
</html>
{{< /highlight >}}

一方`server.py`では次の文が出力されている。これが、curlが送ってきたリクエストである。本来はこのリクエスト内容をきちんと解釈する必要があるが、HTTPサーバーもどきなのでただ受け取っているだけ。

{{< highlight txt >}}
Request: GET / HTTP/1.1
Host: localhost:8000
User-Agent: curl/7.54.0
Accept: */*
{{< /highlight >}}

### リクエストの書式

リクエストは「リクエスト行」「ヘッダ」「ボディ」で構成される。

リクエスト行は`Request: メソッド パス プロトコル情報`の書式で記述される。
メソッドには、サーバーに対してどんな要求をするかを指定する。何か情報をもらうだけなら`GET`、サーバーに情報を送って何かしてほしい場合は`POST`を指定する。他にも`PUT`や`DELETE`などいろいろある。

{{< highlight txt >}}
Request: GET / HTTP/1.1
{{< /highlight >}}

パスには、サーバーの何に対してリクエストを送るかを指定する。例えば、「localhostにある`hello`ディレクトリの`foo.html`の内容が欲しい」というリクエストを送りたい場合、curlでは次のように送る。

{{< highlight txt >}}
$ curl localhost:8000/hello/foo.html
{{< /highlight >}}

`server.py`では次のように出力されている。パス部分に注目。

{{< highlight txt >}}
Request: GET /hello/foo.html HTTP/1.1
Host: localhost:8000
User-Agent: curl/7.54.0
Accept: */*
{{< /highlight >}}

もちろん、「どんなパスが来たらどんな処理をして、どんなレスポンスを送るか」についてはサーバーが判断する。実際、今回の場合パスのことは一切考えていないため、どんなパスでも同じHTML文書が帰ってくる。ちなみにDjangoではこれを`urls.py`で行えるように設計されていた。

リクエスト行に続いて、ヘッダが現れる。これはレスポンスのときと同様、`フィールド名: 値`の書式で表される。

`POST`メソッドなどを利用して何かしらの情報をサーバーに送りたい場合、ヘッダの次にボディを書く。今回の例は`GET`メソッドなので、ボディには何も書かない。

### ブラウザを使った場合

今度はブラウザを利用して、`server.py`と通信してみる。

`server.py`を起動した後、ブラウザから`localhost:8000`にアクセスする。

以下はSafariでアクセスした場合の結果。ブラウザはヘッダから`Content-Type: text/html`を見つけると、ボディ部に書かれたHTML文書を元に描画してくれる。

{{< figure src="./browser.png" >}}

`server.py`の出力は以下のようになる。curlコマンドに比べ、いろいろなものをヘッダに乗せてリクエストを送っていることが分かる。

{{< highlight txt >}}
Request: GET /hello/ HTTP/1.1
Host: localhost:8000
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
Upgrade-Insecure-Requests: 1
Cookie: csrftoken=9V4MgzSbODzE32fMurrp8AVhurtRWnJNLI3c1QZClGVdhtjh1tVAGdkskK999aVY
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Safari/605.1.15
Accept-Language: ja-jp
Accept-Encoding: gzip, deflate
Connection: keep-alive
{{< /highlight >}}

## 複数回の通信

現在の`server.py`は、1人のクライアントと通信が終わると、プログラム自体が終了してしまう。これを防ぐのは簡単で、accept以下をwhileループにすれば良い。

{{< highlight py >}}
import socket

response = '''\
HTTP/1.1 200 OK
Content-Type: text/html

<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <title>Page Title</title>
  </head>
  <body>
    <h1>Hello, World</h1>
  </body>
</html>\
'''

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
    s.bind(("", 8000))
    s.listen(5)
    while True:
        (sock, addr) = s.accept()
        print("Connected by" + str(addr))
        with sock:
            request = sock.recv(1024)
            print("Request: " + request.decode('utf-8'))
            sock.send(response.encode('utf-8'))
{{< /highlight >}}

`server.py`の終了はCtrl+Cで行う。Ctrl+CによってKeyboardInterrupt例外が投げられ、プログラムは終了する。with構文の性質上、例外が投げられたらソケットを閉じてくれる。(ソース:[with構文の説明](https://docs.python.org/ja/3/reference/compound_stmts.html#the-with-statement)と[socketオブジェクト説明の2段落目](https://docs.python.org/ja/3/library/socket.html#socket-objects))

今回はここまで。
