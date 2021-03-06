---
title: "Socket通信勉強(3) - 簡易HTTPサーバー作成"
date: 2021-03-06T22:00:00+09:00
toc: true
tags: ["Socket", "HTTP"]
categories: ["Python", "Network"]
---

[1年以上前に書いた記事]({{< ref "/posts/socket02-python/index.md" >}})
で、HTTPサーバーもどき(リクエストを読まず、ただ一方的にレスポンスを返すだけのサーバ)を書いた。
今回はもう少しだけこれを進化させる。

## 動機

非常にどうでもいいのだが動機を記しておく。

[Land of Lisp](https://www.oreilly.co.jp/books/9784873115870/)の13章でソケット通信が出てきた。
Land of Lispで扱っているCommon Lispの処理系がCLISPなのに対し、今自分が利用しているのはSBCLなので、
本文中のコードが動かない。そこで色々調べて、[usocket](https://github.com/usocket/usocket)を利用しようと思いつく。
その後なんとか書き上げる。ところがChromeや`curl`では動くのに、Safari(現バージョンは14.0.2)では動かない。ページを読み込んだ後、タイムアウトしたかのような挙動を起こす。

その理由を明らかにしたくて「そもそもLisp以外では動くのか。例えばPythonのソケット通信では動くのか」「PythonのWebアプリ、例えばFlaskの開発用サーバーで動くのはなぜか」
など色々調べた。cpythonのsocketserverやhttp.serverなどのソースコードも読んだ。

調べた結果、どうやらSafariがたまに「何も送らない通信(?)」を行うことが原因だった。
何も送ってくれないと、リクエストを`recv`で受け取るときに、ブロッキングが働いてサーバー側が固まってしまう。
ただし普通のリクエストも送ってくるので、マルチスレッドなどの多重化を行なっておけば
問題なくSafariでもページが読み込まれる。なのでFlaskの開発用サーバーでは大した問題にならなかった。
Safariがなぜこんな通信をするのかはよく分からない。HTTPの仕様をちゃんと読んでいないので、何か見落としがあるのだろうか。もしくはバグか何かなのか。

何はともあれ、色々ソースコードを読んでいくうちに、リクエストヘッダの取得のやり方など参考になった。
せっかくなのて得た知見を元に再びHTTPサーバを作ってみようと思い立った。

## 作るもの

以下の条件を満たすHTTPサーバのようなものを作る(そもそも、どこまで実装できたらHTTPサーバと呼べるのだろうか)。

- マルチスレッドにする。
- HTTPリクエストのリクエストライン、ヘッダ情報をパースする。
- リクエストボディは今回は考慮しない。


前回に比べてPythonについての知見が広がったため、
コードにおいてf-stringsやtype-annotation、dataclassなどの機能を使ってみている。
また処理を細かく関数に分ける。


## listen用のソケットの作成

待ち受け用のソケットを作成し、それを返す関数を作成する。
`bind`や`listen`は前回説明した通り。
動作確認を何度も行う都合上、`TIME_WAIT`状態のポートを待つのは面倒なので、`setsockopt(...)`の記述でそれを解決している。
(この辺りの詳細は"TIME_WAIT"とか"REUSEADDR"あたりのキーワードで検索すれば出てくる)


```python
import socket


def server_socket(port: int):
    soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, True)
    soc.bind(('', port))
    soc.listen(5)
    return soc
```

### 動作確認

以下のように`run_server`を作る。

```python
def run_server(port: int):
    with server_socket(port) as soc:
        while True:
            conn, addr = soc.accept()
            print(f'Connected: {addr}')
            with conn:
                conn.shutdown(socket.SHUT_RDWR)

if __name__ == '__main__':
    run_server(8080)
```

作ったサーバーを実行し、別の端末で`curl localhost:8080`とすると、サーバー側で以下のようなメッセージが出力される。
60724の部分は実行の度に異なる。

{{< cui >}}
Connected: ('127.0.0.1', 60724)
{{< /cui >}}

## ハンドラの作成とマルチスレッド化

リクエストハンドラを作成する。これは、クライアントから送られてきたリクエストの情報を元にしてレスポンスを返す関数。
リクエストを受信したりレスポンスを送信したりする必要があるため、引数にソケットをとっている。第2引数はログ用。

以下では、テストのため適当なレスポンスを返している
(前回は改行文字を特に考えず送信してうまくいっていたが、HTTPの仕様では改行文字はCRLFのようだ)。

```python
from typing import Tuple


def handle_request(conn: socket.socket, addr: Tuple[str, str]):
    with conn:
        conn.send(b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello, World')
        print(addr, '200 OK')
        conn.shutdown(socket.SHUT_RDWR)
```

続いて、`run_server`を修正する。`threading.Thread`で、`handle_request`を別スレッドで実行することができる。

```python
import threading


def run_server(port: int):
    with server_socket(port) as soc:
        while True:
            conn, addr = soc.accept()
            print(f'Connected: {addr}')
            t = threading.Thread(target=handle_request, args=[conn, addr])
            t.start()
```

作ったサーバーを実行し、別の端末で`curl localhost:8080`とすると、`curl`側で以下のようなメッセージが出力される。
{{< cui >}}
Hello, World
{{< /cui >}}

サーバー側では以下のようなメッセージが出力される。
{{< cui >}}
Connected: ('127.0.0.1', 63066)
('127.0.0.1', 63066) 200 OK
{{< /cui >}}


## リクエストライン、リクエストヘッダの受信とパース

`handle_request`を修正する。
`makefile`を使うと、ソケットをファイルのように扱えるようになる。
こうしておくと、例えば`readline`メソッドで1行毎にデータを取得することができるようになるので、`recv`メソッドよりも使い勝手が良い。

```python
def handle_request(conn: socket.socket, addr: Tuple[str, str]):
    with conn:
        with conn.makefile('rb') as rfile:
            request_line = get_request_line(rfile) #これから書く
            headers = get_request_headers(rfile) #これから書く
            print(addr, request_line)
            print(addr, headers)
            conn.send(b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello, World')
            print(addr, '200 OK')
            conn.shutdown(socket.SHUT_RDWR)
```


### リクエストラインの取得とパース

[HTTPの仕様](https://tools.ietf.org/html/rfc2616#section-5.1)より、リクエストラインは
メソッド、URI、HTTPのバージョンが空白区切りで並んでいることがわかる。
なので、`split`を使って3つを切り出せば良い。
丁寧に`RequestLine`という`dataclass`を作ってそれを返すようにする。


```python
from typing import Tuple, BinaryIO 


@dataclass
class RequestLine:
    method: str
    uri: str
    http_version: str


def get_request_line(rfile: BinaryIO) -> RequestLine:
    [method, uri, http_version] = rfile.readline(65535).decode('ascii').strip().split()
    return RequestLine(method, uri, http_version)
```

### リクエストヘッダの取得とパース

1行ずつデータを取得して、`:`で`key`と`value`に分ける。
`\r\n`のみの行が現れれば、それがリクエストヘッダの終わりだと分かる。

`split`メソッドで`maxsplit=1`としているのは、余計に`:`が分割されるのを防ぐため。例えば、`host: localhost:8080`が`['host', 'localhost', '8080']`となるのを防ぐ。

`lower`メソッドで`key`を小文字にしているのは、[HTTPの仕様](https://tools.ietf.org/html/rfc2616#section-4.2)上ヘッダ名がcase-insensitiveであるため。
例えば、`Content-Type`と`content-type`が区別されるのを防ぐ。

```python
from typing import Tuple, BinaryIO, Dict

def get_request_headers(rfile: BinaryIO) -> Dict[str, str]:
    headers = dict()

    while True:
        line = rfile.readline(65535)
        if line == b'\r\n':
            break
        key, value = line.decode('ascii').split(':', maxsplit=1)
        key = key.strip().lower()
        value = value.strip()
        headers[key] = value

    return headers
```

### 動作確認

作ったサーバーを起動し、別の端末で`curl localhost:8080`を実行。サーバー側で以下のメッセージが出力される。

{{< cui >}}
Connected: ('127.0.0.1', 50076)
('127.0.0.1', 50076) RequestLine(method='GET', uri='/', http_version='HTTP/1.1')
('127.0.0.1', 50076) {'host': 'localhost:8080', 'user-agent': 'curl/7.64.1', 'accept': '*/*'}
('127.0.0.1', 50076) 200 OK
{{< /cui >}}

## (おまけ)HTTPクライアントもどきの作成

サーバーに適当なリクエストをして、レスポンスをヘッダごと出力するだけのプログラムを書いてみる。

`recv_all`はサーバーからのレスポンスを全て読み取る関数。
`recv`は**相手のソケットが閉じられた場合に**0バイトのデータを受信する。よって、それを読み込み終わりの条件としている。
クライアントではこのような条件が書けるが、サーバでは書けないことに注意。
クライアントに送信するまでソケットを閉じることができないから、ブロッキングが働いてサーバーは固まってしまう。
ちなみに同様の理由で、リクエストヘッダに`Content-Length`が無ければリクエストボディを読み取れない。

```python
import socket


def connect(host: str, port: int):
    soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    soc.connect((host, port))
    return soc


def recv_all(conn) -> bytes:
    chunks = []
    while True:
        chunk = conn.recv(4096)
        if chunk == b'':
            break
        chunks.append(chunk)
    return b''.join(chunks)


def send_request(conn: socket.socket):
    conn.send(b'GET / HTTP/1.1\r\n\r\n')


if __name__ == '__main__':
    with connect('localhost', 8080) as conn:
        send_request(conn)
        response = recv_all(conn)
        print(response.decode('ascii'))
```

サーバーを起動後、このクライアントを実行すると、クライアント側で以下のメッセージが出力される。

{{< cui >}}
HTTP/1.1 200 OK
Content-Type: text/plain

Hello, World
{{< /cui >}}

## サーバーのエラー処理

上のようなクライアントもどきを作っておくことで、以下、サーバー側で問題が発生するメッセージが送れる。

### HTTPリクエストの書式に従っていないメッセージ

`send_request`を以下のようにすると、サーバーはエラーを吐く。
第1行目はリクエストラインが期待されるが、まったく異なる文字列を送っている。

```python
def send_request(conn: socket.socket):
    conn.send(b'this is not a http request.\r\nthis is not a header')
```

クライアントを実行すると、サーバー側で以下の例外が発生している。

{{< cui >}}
Connected: ('127.0.0.1', 58254)
Exception in thread Thread-1:
Traceback (most recent call last):
  ...
  File "server.py", line 23, in get_request_line
    [method, uri, http_version] = rfile.readline(65535).decode('ascii').strip().split()
ValueError: too many values to unpack (expected 3)
{{< /cui >}}

### 何のリクエストも送らない

`send_request`を以下のようにすると、サーバ側で固まったスレッドが発生してしまう。またクライアントも固まる。
どちらかがCtrl+Cで強制終了しない限り、お互い身動きができない。

```python
def send_request(conn: socket.socket):
    pass
```

### エラー処理

上2つのエラーを処理するのは単純で、以下のように`try`文を用いれば良い。

timeoutの時間を決めるために、`conn.settimeout(30)`を呼び出す。これにより、30秒ブロッキングが行われていた場合は
`socket.timeout`例外が送出される。

また不正な書式が送信されてきた場合は`ValueError`例外が送出されるため、その時は`404 BadRequest`を送るようにする。

しかしそれだけだと、例えば相手がソケットを最初に閉じてしまった場合などに対応できないため、そのための例外を`OSError`で捕捉する。

エラー処理を入れるとコードが結構複雑になることが分かる。

```python
def handle_request(conn: socket.socket, addr: Tuple[str, str]):
    with conn:
        try:
            conn.settimeout(30)
            with conn.makefile('rb') as rfile:
                try:
                    request_line = get_request_line(rfile)
                    headers = get_request_headers(rfile)
                    print(addr, request_line)
                    print(addr, headers)
                    conn.send(b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\nHello, World')
                    print(addr, '200 OK')
                    conn.shutdown(socket.SHUT_RDWR)
                except socket.timeout:
                    print(addr, 'timeout')
                except ValueError:
                    conn.send(b'HTTP/1.1 400 BadRequest\r\nContent-Type: text/plain\r\n\r\n')
                    conn.shutdown(socket.SHUT_RDWR)
        except OSError as e:
            print(addr, f"OSError: {e}")
```


## (おまけ)簡易的なルーティング

試しにルーティングをやってみる。次のような処理を行う。

- '/'にアクセスされたら"Hello, World"を表示
- '/greeting/\<name\>'にアクセスされたら"Hello, \<name\>"を表示
- いずれでもなければNotFoundを表示

レスポンスを返すために`conn.send(...)`というを何度も書いているとコードが読みづらくなるため、
`send_response`という関数を定義する。ステータスコードやヘッダ、ボディを実際に組み合わせる処理は`make_response`に任せる。

```python
from typing import Tuple, BinaryIO, Dict, List

def make_response(status: str, headers: List[Tuple[str, str]], body: str) -> bytes:
    headers_string = '\r\n'.join([f'{h[0]}: {h[1]}' for h in headers])
    response = '\r\n'.join([f'HTTP/1.1 {status}', headers_string, '', body])
    return response.encode('ascii')


def send_response(conn: socket.socket, addr: Tuple[str, str], status: str, headers: List[Tuple[str, str]], body: str):
    conn.send(make_response(status, headers, body))
    print(addr, status)
```


これを元に`handle_request`を修正する。

```python
def handle_request(conn: socket.socket, addr: Tuple[str, str]):
    with conn:
        try:
            conn.settimeout(30)
            with conn.makefile('rb') as rfile:
                try:
                    request_line = get_request_line(rfile)
                    headers = get_request_headers(rfile)
                    route(conn, addr, request_line, headers)
                    conn.shutdown(socket.SHUT_RDWR)
                except socket.timeout:
                    print(addr, 'timeout')
                except ValueError:
                    send_response(conn, addr, '400 BadRequest', [('Content-Type', 'text/plain')], 'BadRequest')
                    conn.shutdown(socket.SHUT_RDWR)
        except OSError as e:
            print(addr, f"OSError: {e}")
```

URIに応じて適切なレスポンスを送る関数`route`を作成する。`/greeting/<name>`の`name`の部分を取り出すために、ここでは正規表現を使っている。

```python
import re


def route(conn: socket.socket, addr: Tuple[str, str], request_line: RequestLine, headers: Dict[str, str]):
    m = re.match(r'/greeting/(\w+)', request_line.uri)

    if request_line.uri == "/":
        send_response(conn, addr, '200 OK', [('Content-Type', 'text/plain')], 'Hello, World')
    elif m is not None:
        name = m.group(1)
        send_response(conn, addr, '200 OK', [('Content-Type', 'text/plain')], f'Hello, {name}!')
    else:
        send_response(conn, addr, '404 NotFound', [('Content-Type', 'text/plain')], '404 NotFound')
```

作ったサーバーを起動し、別の端末で`curl localhost:8080`を実行すると、`curl`側で以下のメッセージが出力される。

{{< cui >}}
Hello, World
{{< /cui >}}

`curl localhost:8080/greeting/Taro`を実行すると、`curl`側で以下のメッセージが出力される。

{{< cui >}}
Hello, Taro!
{{< /cui >}}

`curl localhost:8080/foo`を実行すると、`curl`側で以下のメッセージが出力される。

{{< cui >}}
404 NotFound
{{< /cui >}}

ちなみに日本語には対応していない。`localhost:8080/greeting/太郎`としても、URIのエンコード処理を`encode('ascii')`で行なっているため失敗する。
そもそもURIの仕様上、日本語を直接埋め込むことはできない。日本語を間接的に埋め込む方法としてパーセントエンコーディングというものがあり、これは`urllib.parse.urlencode`でできそうだが、
詳しくは未調査。


## 最終的なコード

100行に満たないコードで、HTTPサーバーっぽいものが実現できることが分かる。

```python
import socket
import threading
from typing import List, BinaryIO, Tuple, Dict
from dataclasses import dataclass
import re


def server_socket(port: int):
    soc = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    soc.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, True)
    soc.bind(('', port))
    soc.listen(5)
    return soc


@dataclass
class RequestLine:
    method: str
    uri: str
    http_version: str


def get_request_line(rfile: BinaryIO) -> RequestLine:
    [method, uri, http_version] = rfile.readline(65535).decode('ascii').strip().split()
    return RequestLine(method, uri, http_version)


def get_request_headers(rfile: BinaryIO) -> Dict[str, str]:
    headers = dict()

    while True:
        line = rfile.readline(65535)
        if line == b'\r\n':
            break
        key, value = line.decode('ascii').split(':', maxsplit=1)
        key = key.strip().lower()
        value = value.strip()
        headers[key] = value

    return headers


def make_response(status: str, headers: List[Tuple[str, str]], body: str) -> bytes:
    headers_string = '\r\n'.join([f'{h[0]}: {h[1]}' for h in headers])
    response = '\r\n'.join([f'HTTP/1.1 {status}', headers_string, '', body])
    return response.encode('ascii')


def send_response(conn: socket.socket, addr: Tuple[str, str], status: str, headers: List[Tuple[str, str]], body: str):
    conn.send(make_response(status, headers, body))
    print(addr, status)


def route(conn: socket.socket, addr: Tuple[str, str], request_line: RequestLine, headers: Dict[str, str]):
    m = re.match(r'/greeting/(\w+)', request_line.uri)

    if request_line.uri == "/":
        send_response(conn, addr, '200 OK', [('Content-Type', 'text/plain')], 'Hello, World')
    elif m is not None:
        name = m.group(1)
        send_response(conn, addr, '200 OK', [('Content-Type', 'text/plain')], f'Hello, {name}!')
    else:
        send_response(conn, addr, '404 NotFound', [('Content-Type', 'text/plain')], '404 NotFound')


def handle_request(conn: socket.socket, addr: Tuple[str, str]):
    with conn:
        try:
            conn.settimeout(30)
            with conn.makefile('rb') as rfile:
                try:
                    request_line = get_request_line(rfile)
                    headers = get_request_headers(rfile)
                    route(conn, addr, request_line, headers)
                    conn.shutdown(socket.SHUT_RDWR)
                except socket.timeout:
                    print(addr, 'timeout')
                except ValueError:
                    send_response(conn, addr, '400 BadRequest', [('Content-Type', 'text/plain')], 'BadRequest')
                    conn.shutdown(socket.SHUT_RDWR)
        except OSError as e:
            print(addr, f"OSError: {e}")


def run_server(port: int):
    with server_socket(port) as soc:
        while True:
            conn, addr = soc.accept()
            print(f'Connected: {addr}')
            t = threading.Thread(target=handle_request, args=[conn, addr])
            t.start()


if __name__ == '__main__':
    run_server(8080)
```

## 補足: WSGIサーバー

もちろん今まで作ってきたHTTPサーバーは車輪の再発明である。HTTPサーバーはPythonのモジュール[http.server](https://docs.python.org/ja/3/library/http.server.html)として用意されている。
さらに一歩進んで、WebアプリとHTTPサーバをつなぐ仕様にWSGIというものがある。WSGIの仕様に則ったWebアプリを書けば、WSGIの仕様に則ったどんなサーバでもそれを動かすことができる。
WSGIサーバーの実装は[wsgiref](https://docs.python.org/ja/3/library/wsgiref.html)で用意されているので、試しに使ってみる。

以下は、前節でのルーティングをWSGIの仕様に則って書いたもの。


```python
import re
from wsgiref.simple_server import make_server


def app(env, start_response):
    uri = env['PATH_INFO']
    m = re.match(r'/greeting/(\w+)', uri)

    if uri == "/":
        start_response('200 OK', [('Content-Type', 'text/plain')])
        return [b'Hello, World']
    elif m is not None:
        name = m.group(1)
        start_response('200 OK', [('Content-Type', 'text/plain')])
        return [f'Hello, {name}!'.encode('ascii')]
    else:
        start_response('404 NotFound', [('Content-Type', 'text/plain')])
        return ['404 NotFound']


if __name__ == '__main__':
    with make_server('', 8080, app) as httpd:
        httpd.serve_forever()
```

WSGIの仕様により、Webアプリを表す関数(上のコードでは`app`、もしクラスなら`__call__`メソッド)の引数は2つと定められている。そして、第1引数`env`はリクエストに関するあらゆる情報を持っており、
第2引数`start_response`はステータスコードとレスポンスヘッダを引数にとる関数である。
関数`app`の返り値はレスポンスボディである。このようなルールに従って関数`app`を定義したことにより、`make_server`関数でサーバーを動かすことができる。
WSGIはWebアプリとWebサーバー間の仕様であるため当前と言えば当前なのだが、ソケット通信のことは一切考えることなくWebアプリを書けるようになる。

とはいえ`app`を直接書くと、
「ルーティングを正規表現で行なったが、正規表現より読みやすい方法が欲しい」
「URIが増えるとその度に`if`文が増えるため、コードが読みづらくなる」
「ステータスコードやヘッダをいちいち指定しなければいけないのが面倒」
など色々不満が出てくる。ライブラリやフレームワークは、それらの不満を解決するだけでなく、便利な機能(フレームワークによるが、例えばCookieの取得、データベース連携、アカウント認証など)を簡単に利用できる。
WSGI対応のWebアプリを作るためのライブラリとして[werkzeug](https://werkzeug.palletsprojects.com/en/1.0.x/)がある。
Webアプリのフレームワークとして[Flask](https://flask.palletsprojects.com/en/1.1.x/)や[Django](https://www.djangoproject.com)がある。

wsgirefはリファレンス実装のため、おそらく機能が簡素であったり、性能面に問題がある(詳しくは調べていないので確かなことは言えないが)。
なのでWebアプリを実際にデプロイしようとなったときは、wsgirefではなく外部のWSGI対応サーバを利用することになる。
WSGI対応のサーバーとしては、[uWSGI](https://uwsgi-docs.readthedocs.io/en/latest/)や[Gunicorn](https://gunicorn.org)がある。

