---
title: "PythonとWSGIで作るTodoリストAPI"
date: 2021-05-29T13:00:00+09:00
tags: ["Web API", "Todoリスト", "WSGI"]
categories: ["Python", "Network"]
toc: true
---

シンプルなTodoリストを作る。
今回は勉強のため、Webアプリケーションフレームワークは使わずに、
敢えてWSGIの仕様のみ参考にして書く．

## WSGIとは


WSGIとは、WebサーバーとWebアプリとの間の標準的なインターフェース。
WSGIの仕様に沿ってWebアプリを作れば、
WSGI対応のどんなWebサーバーとも連携することができる。

WSGIの仕様は[PEP3333](https://www.python.org/dev/peps/pep-3333/)に書かれている．


## TodoリストAPIの仕様

簡単のため、今回Todoのデータはidと内容のみ持つデータとし、`{ id: 0, "content": "やること" }`というJSON形式とする。

APIの仕様は以下の通り。

| URI | Method | 説明 | 返却値 |
| ---- | ---- | ---- | ---- |
| `/todo/` | GET | 全てのTodoを取得。 | ToDoのデータのリスト |
| `/todo/` | POST | Todoを作成。 | 作成したToDoのid
| `/todo/<todo_id>` | GET | `todo_id`のidを持つTodoを取得。 | ToDoのデータ |
| `/todo/<todo_id>` | PUT | `todo_id`のidを持つTodoを変更。 | 空のオブジェクト |
| `/todo/<todo_id>` | DELETE | `todo_id`のidを持つTodoを削除 | 空のオブジェクト |

データは最終的にはSQLiteで保存するが、最初は単純にlistで扱う。


## 雛形

まずはサーバーを作る。この時点ではルーティング処理を書いていない。
どのようなリクエストをしても`Hello, World`をレスポンスとして返す。


```python
from wsgiref.simple_server import make_server


def app(env, start_response):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'Hello, World.']


if __name__ == '__main__':
    httpd = make_server('', 5000, app)
    httpd.serve_forever()
```

以降、サーバーを起動する際は`python3 app.py`を実行する。

試しに、コマンドラインで接続を確認してみると良い。

{{< cui >}}
% curl localhost:5000
Hello, World.
{{< /cui >}}


### 解説

以下、[PEP3333のSpecification Details](https://www.python.org/dev/peps/pep-3333/#specification-details)を参考に書く。

Webアプリの実態は関数`app`そのもの。厳密には、Webアプリは2引数を持つcallableなオブジェクトとして定義される。
callableであれば良いので、例えば以下のように`__call__`を実装したクラスのインスタンスもWebアプリとみなせる。

```python
from wsgiref.simple_server import make_server


class App:
  def __call__(self, env, start_response):
      start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
      return [b'Hello, World.']

app = App()

if __name__ == '__main__':
    httpd = make_server('', 5000, app)
    httpd.serve_forever()
```


`app`の2つの引数の名前はなんでも良いが、ここではそれぞれ`env`、`start_response`と記す。

`env`はリクエストに関するあらゆる情報を含んでいる。`env`はdictオブジェクトであり、
何が入っているかは[PEP3333のenviron variables](https://www.python.org/dev/peps/pep-3333/#environ-variables)で分かる。
この記事でお世話になる`env`のキーは以下の4つ。

- `PATH_INFO`: URI。
- `REQUEST_METHOD`: リクエストメソッド。
- `CONTENT_LENGTH`: リクエストボディの長さ。
- `wsgi.input`: リクエストボディを読み取るために使う。ファイルオブジェクトとして扱う。

`start_response`は関数であり、文字通りレスポンスの開始のために呼びだすもの。
`start_response(ステータス, レスポンスヘッダのlist)`の形式で呼び出す。

返り値はbyte型のiterableオブジェクトを返す仕様となっている。
iterableであればなんでも良いので、上のコードではlistでbyteを包んで返している。

今回WSGIで知っておくべきことは実はこれしかない。
あとはURIやメソッドの情報を使ってどうルーティングするか、Todoリストのデータをどう処理するかなどの話に移っていく。

`wsgiref.simple_server`モジュールを使うと，WSGIサーバーが利用できる。`make_server`の引数にホスト、ポート、Webアプリを指定する。
`server_forever`でサーバーを動かす。

### (補足) WSGIサーバーを別のものにする

`wsgiref.simple_server`はWSGIのリファレンス実装であり，機能や性能は期待できない。
しかしPythonの標準で含まれているため、開発環境で用いられることがある。
これ以外のWSGIサーバーとして、ここでは[gunicorn](https://docs.gunicorn.org/en/stable/)を利用する。これはpipでインストールできる。

[ドキュメントのRunning Gunicorn](https://docs.gunicorn.org/en/stable/run.html)もしくは`gunirocn --help`を見ればわかるが、
以下のコマンドでgunicornを実行できる。`app:app`というのは「`app.py`の`app`関数」という意味。`-b`引数でホスト、ポートを指定するが、
これを指定しなかった場合`localhost:8000`になる。

{{< cui >}}
% gunicorn -b localhost:5000 app:app
{{< /cui >}}


## ルーティング

URIとリクエストメソッドは`env`から取得できるので、`if`文を使って以下のように書くことも、一応はできる。

```python
def app(env, start_response):
  path = env['PATH_INFO'] or '/'
  method = env['REQUEST_METHOD']
  if path == '/todo/' and method == 'GET':
    # 全てのTodoを取得する処理
  elif path == ...
    ...
  elif path == ...
    ...
  elif path == ...
    ...
```

しかしこれだと、if文が何個も連なって読みづらい。しかも`/todo/<todo_id>`のようなURIの場合は、URIから`todo_id`という整数値を取り出す必要があり、
さらに処理は複雑になる。そこで、以下のような方針でルーティング処理をapp関数から切り分けることにする。

コードについては[ルーティング - Webアプリケーションフレームワークの作り方 in Python](https://c-bata.link/webframework-in-python/routing.html)
を一部参考にしている。

まず、`app.py`を以下のようにする(`if __name__ == '__main__'...`の処理は省略)。

```python
from views import todo
from util import HTTPException, NotFound
import re


ROUTES = [
    (r'/todo/$', 'GET', todo.get_all),
    (r'/todo/$', 'POST', todo.post),
    (r'/todo/(?P<todo_id>\d+)/$', 'GET', todo.get),
    (r'/todo/(?P<todo_id>\d+)/$', 'DELETE', todo.delete),
    (r'/todo/(?P<todo_id>\d+)/$', 'PUT', todo.put),
]


def route(method, path):
    for r in ROUTES:
        m = re.compile(r[0]).match(path)
        if m and r[1] == method:
            url_vars = m.groupdict()
            return r[2], url_vars
    raise NotFound


def app(env, start_response):
    method = env['REQUEST_METHOD'].upper()
    path = env['PATH_INFO'] or '/'
    try:
        callback, kwargs = route(method, path)
        return callback(env, start_response, **kwargs)
    except HTTPException as e:
        return e(env, start_response)
```

`util.py`を作成して、内容は以下のようにする。`BadRequest`例外については次節で使う。

```python
class HTTPException(Exception):
    pass


class NotFound(HTTPException):
    def __call__(self, env, start_response):
        start_response('404 Not Found', [('Content-type', 'text/plain; charset=utf-8')])
        return [b'404 Not Found']


class BadRequest(HTTPException):
    def __call__(self, env, start_response):
        start_response('400 Bad Requet', [('Content-type', 'text/plain; charset=utf-8')])
        return [b'400 Bad Request']
```

`views/__init__.py`と`views/todo.py`を作成。前者は空のファイルのままで、後者はとりあえず以下のようにする。
これらの関数の中身は後で大きく書き換える。

```python
def get_all(env, start_response):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'todo.get_all']


def post(env, start_response):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'todo.post']


def get(env, start_response, todo_id):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'todo.get: ' + todo_id.encode('utf-8')]


def put(env, start_response, todo_id):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'todo.put: ' + todo_id.encode('utf-8')]


def delete(env, start_response, todo_id):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'todo.delete: ' + todo_id.encode('utf-8')]
```

リクエストを試しに送ってみる。

{{< cui >}}
% curl localhost:5000/todo/
todo.get_all
% curl -X POST localhost:5000/todo/
todo.post
% curl localhost:5000/todo/1/
todo.get: 1
% curl -X PUT localhost:5000/todo/1/
todo.put: 1
% curl -X DELETE localhost:5000/todo/1/
todo.delete: 1
{{< /cui >}}

### 解説

`ROUTE`というグローバル変数は、`(URI, メソッド, 対応するコールバック関数)`という形のリスト。
`route`関数でURIとメソッドを照合し、対応するコールバック関数を返す。

このように`ROUTE`をまとめて書いておくと、
[API仕様](#todoリストapiの仕様)との対応が分かりやすい。Djangoでのコーディングはこれと似ていて、`urls.py`においてURLと対応するviewをリストでまとめておくようなフレームワークになっている。
一方で、対応するコールバック関数が離れたところで定義されているため、URI、メソッドに対してどんな処理が行われるのかが
一目で分かりづらい、というデメリットもある。FlaskやBottleなどのフレームワークでは、`ROUTES`にまとめる代わりに、デコレータを使って以下のように書けるように設計されている(以下はFlaskの例)。
どちらの設計にも良し悪しがあるので、どちらを選ぶかは好みだと思う。

```python
@app.route('/todo/', methods=['GET'])
def get_todo_all(todo_id):
  ...

@app.route('/todo/<todo_id>/', methods=['GET'])
def get_todo(todo_id):
  ...

...
```

`/todo/<todo_id>`のようなURIから`todo_id`を読み取りたいので、それを実現するために正規表現を用いている。
以下は、REPLでの正規表現の例。`(?P<name>...)`という記法については[正規表現 HOWTOのグルーピングの項](https://docs.python.org/ja/3/howto/regex.html#non-capturing-and-named-groups)
が分かりやすい。
{{< cui >}}
>>> import re
>>> m = re.compile('/todo/(?P&lt;todo_id&gt;\d+)/$').match('/todo/123/')
>>> m
&lt;re.Match object; span=(0, 10), match='/todo/123/'&gt;
>>> m.groupdict()
{'todo_id': '123'}
{{< /cui >}}

`route`関数では、正規表現で抜き出した部分を`url_vars`とし、コールバック関数と共に返している。
対応するURI、メソッドが存在しなかった場合は、`NotFound`例外を送出する。その例外クラスは`util.py`で定義している。
`NotFound`例外は`HTTPException`例外を継承しており、これは`app`関数で受け取る。
このクラスは`__call__`を定義しているため、`ROUTE`で指定したコールバック関数たちと同じ振る舞いをする。


`app`関数では、`env['REQUEST_METHOD']`でメソッドを、`env['PATH_INFO']`でURIを取得し、routeでコールバック関数を取得し、
後の処理をコールバック関数に回す処理を書いているだけとなっている。


## Todoリストのインターフェース作成

以下の`Todo`クラスを作る。

|メソッド(引数) | 説明 |
| ---- | ---- |
| `__init__(self, content)` | `content`を内容とするTodoを作成。|
| `insert(self)` | `todo`をTodoリストに追加。|
| `update(self)` | `todo`の変更を反映させる。|
| `delete(self)` | idが`todo_id`であるTodoを削除 |


|クラスメソッド(引数) | 説明 | 例外 |
| ---- | ---- | ---- |
| `get_all(cls)` | 全てのTodoを取得。 | |
| `get(cls, todo_id)` | idが`todo_id`であるTodoを取得。 | `todo_id`が存在しなかった場合に`TodoNotFound`例外を投げる。 |


上の定義で、実際に`views/todo.py`で使ってみると以下の通りになる。

```python
from models.todo import Todo, TodoNotFound
from util import BadRequest, NotFound
import json


def todo_to_dict(todo):
    return {'id': todo.id, 'content': todo.content}


class ValidationError(Exception):
    pass


def validate_todo(todo_dict):
    if 'content' not in todo_dict:
        raise ValidationError

    if type(todo_dict['content']) is not str:
        raise ValidationError


def get_all(env, start_response):
    todos = Todo.get_all()
    todos_dict = [todo_to_dict(todo) for todo in todos]
    todos_json = json.dumps(todos_dict, ensure_ascii=False).encode('utf-8')

    start_response('200 OK', [('Content-type', 'application/json; charset=utf-8')])
    return [todos_json]


def post(env, start_response):
    try:
        content_length = int(env.get('CONTENT_LENGTH', 0) or 0)
        todo_dict = json.loads(env['wsgi.input'].read(content_length))
        validate_todo(todo_dict)

        todo_id = Todo(todo_dict['content']).insert()

        start_response('200 OK', [('Content-type', 'application/json; charset=utf-8')])
        return [str(todo_id).encode('utf-8')]
    except (json.JSONDecodeError, ValidationError):
        raise BadRequest


def get(env, start_response, todo_id):
    try:
        todo_dict = todo_to_dict(Todo.get(int(todo_id)))
        todo_json = json.dumps(todo_dict, ensure_ascii=False).encode('utf-8')

        start_response('200 OK', [('Content-type', 'application/json; charset=utf-8')])
        return [todo_json]
    except TodoNotFound:
        raise NotFound


def put(env, start_response, todo_id):
    try:
        content_length = int(env.get('CONTENT_LENGTH', 0) or 0)
        todo_dict = json.loads(env['wsgi.input'].read(content_length))
        validate_todo(todo_dict)

        todo = Todo.get(int(todo_id))
        todo.content = todo_dict['content']
        todo.update()

        start_response('200 OK', [('Content-type', 'application/json; charset=utf-8')])
        return [b'{}']
    except (json.JSONDecodeError, ValidationError):
        raise BadRequest
    except TodoNotFound:
        raise NotFound


def delete(env, start_response, todo_id):
    try:
        Todo.get(todo_id).delete()

        start_response('200 OK', [('Content-type', 'application/json; charset=utf-8')])
        return [b'{}']
    except TodoNotFound:
        raise NotFound
```

ひとまずダミーを実装する。`models/__init__.py`と`models/todo.py`を作成し、前者は空のままで、後者は以下の通りにする。

```python
class TodoNotFound(Exception):
    pass


class Todo:
    def __init__(self, content: str):
        self.id = None
        self.content = content

    def insert(self):
        self.id = 0
        return self.id

    def update(self):
        pass

    def delete(self):
        pass

    @classmethod
    def get_all(cls):
        return []

    @classmethod
    def get(cls, todo_id: int):
        return Todo('dummy')

```

接続を確認してみる。

{{< cui >}}
% curl localhost:5000/todo/
[]
% curl localhost:5000/todo/1/
{"id": null, "content": "dummy"}
% curl -X POST localhost:5000/todo/ -d '{"content": "aaa"}'
0
% curl -X PUT localhost:5000/todo/1/ -d '{"content": "aaa"}'

% curl -X DELETE localhost:5000/todo/1/
{{< /cui >}}

### 解説

`Todo`はそのままではJSONに変換できないので、一旦`dict`に変換している。それを行っているのが`todo_to_dict`関数。

`post`関数と`put`関数では、リクエストボディからJSONのデータを読み取る必要がある。リクエストボディは`env['wsgi.input']`から読み取れる。
リクエストボディの長さは`env['CONTENT_LENGTH']`で得られるのだが、これは[PEP3333のenviron](https://www.python.org/dev/peps/pep-3333/#environ-variables)によると
"May be empty or absent."と記載されている。よって、この値は空もしくは`None`である可能性がある。
`env['CONTENT_LENGTH']`が`None`だけであれば`int(env('CONTENT_LENGTH', 0))`だけで良いのだが、空文字だった場合にエラーが発生する(実際、curlで空のPOSTリクエストを送ったら`TypeError`になった)。
よって、`int(env('CONTENT_LENGTH', 0) or 0)`という形でリクエストボディの長さを取得する必要がある(もしかしたらもっと良い方法があるかもしれない…)。

リクエストボディのvalidationを`validate_todo`関数で行う。JSONデータに`content`キーを含んでいなかったり、また含んでいたとしても文字列出なかった場合は、`ValidationError`例外を投げる。
余談だが、validationを行うライブラリに[marshmallow](https://marshmallow.readthedocs.io/en/stable/)がある。扱うモデルが複雑になった場合に使うと良いだろう。

リクエストボディがJSON形式でなかったり、validationに失敗した場合は、最終的に`BadRequest`例外を投げる。
存在しない`todo_id`にアクセスされた場合は、`NotFound`例外を投げる。2つとも`HTTPException`を継承しているので、`app.py`の`app`関数で捕捉され、それぞれ400 BadRequest、404 NotFoundのレスポンスを返す。


## Todoリスト - listによる実装

データが永続ではないが、一応listでTodoリストを実装してみる。`models/todo.py`を次のようにする。

```python
from copy import copy


class TodoNotFound(Exception):
    pass


class Todo:
    TODOS = []
    NEXT_ID = 0

    def __init__(self, content: str):
        self.id = None
        self.content = content

    def insert(self):
        self.id = Todo.NEXT_ID
        Todo.NEXT_ID += 1
        Todo.TODOS.append(copy(self))
        return self.id

    def update(self):
        todos_idx = [i for i, todo in enumerate(Todo.TODOS) if todo.id == self.id]
        if not todos_idx:
            raise TodoNotFound
        Todo.TODOS[todos_idx[0]] = copy(self)

    def delete(self):
        todos_idx = [i for i, todo in enumerate(Todo.TODOS) if todo.id == self.id]
        if not todos_idx:
            raise TodoNotFound
        del Todo.TODOS[todos_idx[0]]

    @classmethod
    def get_all(cls):
        return Todo.TODOS

    @classmethod
    def get(cls, todo_id: int):
        todos = [todo for todo in Todo.TODOS if todo.id == todo_id]
        if not todos:
            raise TodoNotFound
        return copy(todos[0])
```

うまく動いているか確認する。

{{< cui >}}
% curl -X POST localhost:5000/todo/ -d '{"content": "部屋の掃除"}'
0

% curl -X POST localhost:5000/todo/ -d '{"content": "犬の散歩"}'
1

% curl -X POST localhost:5000/todo/ -d '{"content": "風呂を洗う"}'
2

% curl localhost:5000/todo/
[{"id": 0, "content": "部屋の掃除"}, {"id": 1, "content": "犬の散歩"}, {"id": 2, "content": "風呂を洗う"}]%

% curl localhost:5000/todo/1/
{"id": 1, "content": "犬の散歩"}

% curl localhost:5000/todo/3/
404 Not Found

% curl -X POST localhost:5000/todo/ -d 'not json data'
400 Bad Request

% curl -X PUT localhost:5000/todo/1/ -d '{"content": "aaa"}'

% curl localhost:5000/todo/
[{"id": 0, "content": "部屋の掃除"}, {"id": 1, "content": "aaa"}, {"id": 2, "content": "風呂を洗う"}]%

% curl -X DELETE localhost:5000/todo/1/

% curl localhost:5000/todo/
[{"id": 0, "content": "部屋の掃除"}, {"id": 2, "content": "風呂を洗う"}]
{{< /cui >}}

## Todoリスト - sqliteによる実装

RDBMSでTodoリストを管理するようにしてみる。使うRDBMSはここではSQLiteとする。
`models/todo.py`を次のようにする．

```python
import sqlite3


class TodoNotFound(Exception):
    pass


class Todo:
    TODOS = []
    NEXT_ID = 0
    DB_PATH = 'db.sqlite3'

    def __init__(self, content: str, todo_id=None):
        self.id = todo_id
        self.content = content

    def insert(self):
        with Todo.get_db() as con:
            con.execute('insert into Todo(content) values (?)', (self.content,))
            cur = con.cursor()
            row = cur.execute('select * from Todo where id=last_insert_rowid()').fetchone()
            self.id = row['id']
        return self.id

    def update(self):
        if self.id is None:
            raise TodoNotFound
        with Todo.get_db() as con:
            con.execute('update Todo set content=? where id=?', (self.content, self.id))

    def delete(self):
        if self.id is None:
            raise TodoNotFound
        with Todo.get_db() as con:
            con.execute('delete from Todo where id=?', (self.id,))

    @classmethod
    def get_all(cls):
        with Todo.get_db() as con:
            cur = con.cursor()
            rows = cur.execute('select * from todo').fetchall()
        return [Todo(row['content'], row['id']) for row in rows]

    @classmethod
    def get(cls, todo_id: int):
        with Todo.get_db() as con:
            cur = con.cursor()
            row = cur.execute('select * from todo where id=?', (todo_id,)).fetchone()
            if not row:
                raise TodoNotFound
        return Todo(row['content'], row['id'])

    @classmethod
    def get_db(cls):
        con = sqlite3.connect(Todo.DB_PATH)
        con.row_factory = sqlite3.Row
        return con

    @classmethod
    def init_table(cls):
        with Todo.get_db() as con:
            con.execute('drop table if exists Todo')
            con.execute('''create table Todo(
                              id integer primary key autoincrement,
                              content text not null
                           )''')
            con.commit()
```

データベースを初期化するためには`Todo.init_table()`を実行する。そこで、初期化用のスクリプト`init_db.py`を作成する。

```python
from models.todo import Todo

if __name__ == '__main__':
    Todo.init_table()
```

データベースを初期化したい時は、コマンドラインで以下のように実行する。

{{< cui >}}
% python3 init_db.py
{{< /cui >}}

基本動作は前節と同様になる。ただし、sqliteのautoincrementの都合上、idが1から始まる。


## ソースコード

SQLiteによる実装は[GitHubのRepository](https://github.com/bombrary/todo-api-wsgi)にあげた。
