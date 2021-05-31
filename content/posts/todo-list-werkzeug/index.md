---
title: "PythonとWerkzeugで作るToDoリストAPI"
date: 2021-05-30T11:49:40+09:00
tags: ["Web API", "ToDoリスト", "Werkzeug"]
categories: ["Python", "Web"]
toc: true
---


シンプルなToDoリストのWeb APIを作る。
[前回]({{< ref "/posts/todo-list-wsgi" >}})はWSGIの仕様のみを参考にして作ったが、
今回は[Werkzeug](https://werkzeug.palletsprojects.com/en/2.0.x/)というライブラリを利用する。

## Werkzeugとは

[Werkzeugのドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/)の
"Werkzeug is a comprehensive WSGI web application **library**."という文面にもある通り、
これはWSGIのWebアプリを作るためのライブラリである。
あくまでフレームワークではなく、ライブラリであることに注意する。
Webアプリを作るうえで、便利なクラスや関数が用意された「道具箱」のようなイメージを持つとよいかもしれない
(そもそも"werkzeug"という単語はドイツ語で「道具」という意味)。
あくまで道具があるだけなので、どういう設計を行うかなどを考える余地がある。


## ToDoリストAPIの仕様

[前回]({{< ref "/posts/todo-list-wsgi" >}})と同じだが、再掲する。

簡単のため、今回ToDoのデータはidと内容のみ持つデータとし、`{ id: 0, "content": "やること" }`というJSON形式とする。

APIの仕様は以下の通り。

| URI | Method | 説明 | 返却値 |
| ---- | ---- | ---- | ---- |
| `/todo/` | GET | 全てのToDoを取得。 | ToDoのデータのリスト |
| `/todo/` | POST | ToDoを作成。 | 作成したToDoのid
| `/todo/<todo_id>` | GET | `todo_id`のidを持つToDoを取得。 | ToDoのデータ |
| `/todo/<todo_id>` | PUT | `todo_id`のidを持つToDoを変更。 | 空のオブジェクト |
| `/todo/<todo_id>` | DELETE | `todo_id`のidを持つToDoを削除 | 空のオブジェクト |

データは最終的にはSQLiteで管理する。


## 雛形

`app.py`を以下のようにする。

```python
from werkzeug.wrappers import Response


def app(env, start_response):
    response = Response('Hello, World')
    return response(env, start_response)


if __name__ == '__main__':
    from werkzeug.serving import run_simple
    run_simple('127.0.0.1', 5000, app, use_debugger=True, use_reloader=True)
```

以降、サーバーを起動する際は`python3 app.py`を実行する。

試しに、コマンドラインで接続を確認してみると良い。

{{< cui >}}
% curl localhost:5000
Hello, World
{{< /cui >}}


### 雛形 - 解説

`Response`を使わないWSGIアプリは以下のようになる。

```python
def app(env, start_response):
    start_response('200 OK', [('Content-type', 'text/plain; charset=utf-8')])
    return [b'Hello, World.']
```

一方で`Response`を使えば、レスポンスに関する情報を`Response`に包むことができるため、コードの意味が分かりやすくなっている。
`Response`のインスタンスは`__call__(env, start_response)`を実装しており、これもまたWSGIアプリとみなせる。
それゆえ、`app`関数の最後で`return response(env, start_response)`のような使い方をしている。

`Respons`オブジェクトについては[ドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/wrappers/#werkzeug.wrappers.Response)
を読めばわかるが、引数にステータスコード、ヘッダ、MIMEタイプなどを指定することができる
(ドキュメントには明記されていないが、`mimetype`を未指定にすると勝手に`text/plain`、エンコーディングはUTF8になるようだ)。


`werkzeug.serving`ではデバッグ用のWSGIサーバーが用意されており、`run_simple`として利用できる。
詳細は[ドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/serving/#werkzeug.serving.run_simple)を参照。
`use_debugger`引数を`True`にすると、サーバー側でデバッグ用のログが出力されるようになる。
`use_reloader`引数を`True`にすると、ファイルの変更を検知しサーバーを自動でリロードしてくれる。


## ルーティング


`app.py`を以下のようにする。


```python
from wsgiref.simple_server import make_server
from werkzeug.wrappers import Request, Response
from werkzeug.routing import Map, Rule, Submount
from werkzeug.exceptions import HTTPException
from views import todo


def hello(request: Request):
    return Response('Hello, World')


URL_MAP = Map([
    Rule('/', endpoint=hello),
    Submount('/todo', [
        Rule('/', methods=['GET'], endpoint=todo.get_all),
        Rule('/', methods=['POST'], endpoint=todo.post),
        Rule('/<int:todo_id>/', methods=['GET'], endpoint=todo.get),
        Rule('/<int:todo_id>/', methods=['PUT'], endpoint=todo.put),
        Rule('/<int:todo_id>/', methods=['DELETE'], endpoint=todo.delete)
    ])
])


def route(request: Request):
    adapter = URL_MAP.bind_to_environ(request.environ)
    try:
        endpoint, values = adapter.match()
        return endpoint(request, **values)
    except HTTPException as e:
        return e


def app(env, start_response):
    request = Request(env)
    response = route(request)
    return response(env, start_response)

# if __name__ == '__main__': ... はここでは省略
```

`views/__init__.py`と`views/todo.py`を作成し、前者は空のまま、後者は以下のようにする。

```python
from werkzeug.wrappers import Request, Response


def get_all(request: Request):
    return Response('todo.get_all')


def post(request: Request):
    return Response('todo.post')


def get(request: Request, todo_id: int):
    return Response(f'todo.get: {todo_id}')


def put(request: Request, todo_id: int):
    return Response(f'todo.put: {todo_id}')


def delete(request: Request, todo_id: int):
    return Response(f'todo.delete: {todo_id}')
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


### ルーティング - 解説

まず`app`関数に注目する。`Request`は、`env`を使いやすいように包んだクラスである。
詳細は[Requestのドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/wrappers/#werkzeug.wrappers.Request)を参照。

例えば、`Request`を使わずに`env`を使ってjsonデータを取得するには、以下のようにしなければならない。

```python
import json

content_length = int(env['CONTENT_LENGTH']) # 中身が空かどうかの処理はここではサボっている
body_str = env['wsgi.input'].read(content_length)
body_json = json.loads(body_str)
```

`Response`を使うと、これが簡潔になる。なお、jsonのデコードに失敗した場合は、デフォルトで`BadRequest`例外を投げる
(詳細は[get_jsonのドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/wrappers/#werkzeug.wrappers.Request.get_json)参照)。
```python
# response = Response(env)とした
body_json = response.get_json()
```

`app`関数では、`env`を`Request`で包んだ後、ルーティングの処理を`route`関数に任せている。

前回は、「どのURIに対してどの関数が呼ばれるか」という対応関係を、listとtupleのみで表現していた。
`werkzeug.routing`では、これを`Map`と`Rule`で管理する。`Submount`を使うと、`/todo`をprefixに持つURIをまとめることができる。

上の例のように、`/<int:todo_id>/`とすると、URLに含まれる整数値を`todo_id`として取得することができる。`int`の部分はconverterと呼ばれ、
標準で使えるconverterは[ドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/routing/#built-in-converters)で確認できる。
前回の正規表現を使った取り出し方よりも見やすくなっている。

`Map`の使い方は`route`関数を見るとわかる。`URL_MAP.bind_to_environ`メソッドで`environ`と`URL_MAP`を結びつけ、
`adapter.match`メソッドで実際に`URI`、メソッドの照合を行う。返却値は対応する`endpoint`と、URLに含まれる変数である。

`URL_MAP`の中に対応する`URI`、メソッドが存在しなかった場合は、`NotFound`例外を投げる。
これは`HTTPException`を継承したクラスである。前回はこれらを自前で実装したが、werkzeugでは`werkzeug.exceptions`で実装されている。


## ToDoリストのインターフェース作成


[前回]({{< ref "posts/todo-list-wsgi" >}})同様、以下の`Todo`クラスを作る。

|メソッド(引数) | 説明 |
| ---- | ---- |
| `__init__(self, content)` | `content`を内容とするToDoを作成。|
| `insert(self)` | `todo`をToDoリストに追加。|
| `update(self)` | `todo`の変更を反映させる。|
| `delete(self)` | idが`todo_id`であるToDoを削除 |

<br/>

|クラスメソッド(引数) | 説明 | 例外 |
| ---- | ---- | ---- |
| `get_all(cls)` | 全てのToDoを取得。 | |
| `get(cls, todo_id)` | idが`todo_id`であるToDoを取得。 | `todo_id`が存在しなかった場合に`TodoNotFound`例外を投げる。 |


上の定義で、実際に`views/todo.py`で使ってみると以下の通りになる。

```python
from werkzeug.wrappers import Request, Response
from models.todo import Todo, TodoNotFound
from werkzeug.exceptions import BadRequest, NotFound
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


def get_all(request: Request):
    todos_dict = [todo_to_dict(todo) for todo in Todo.get_all()]
    todos_json = json.dumps(todos_dict, ensure_ascii=False)
    return Response(todos_json, mimetype='application/json')


def post(request: Request):
    todo_dict = request.get_json(force=True)

    try:
        validate_todo(todo_dict)
    except ValidationError:
        raise BadRequest('Todo ValidationError')

    todo_id = Todo(todo_dict['content']).insert()
    return Response(str(todo_id), mimetype='application/json')


def get(request: Request, todo_id: int):
    try:
        todo = Todo.get(todo_id)
    except TodoNotFound:
        raise NotFound('Todo NotFound')
    todo_dict = todo_to_dict(todo)
    todo_json = json.dumps(todo_dict, ensure_ascii=False)
    return Response(todo_json, mimetype='application/json')


def put(request: Request, todo_id: int):
    todo_dict = request.get_json(force=True)

    try:
        validate_todo(todo_dict)
        todo = Todo.get(todo_id)
    except ValidationError:
        raise BadRequest('Todo ValidationError')
    except TodoNotFound:
        raise NotFound('Todo NotFound')

    todo.content = todo_dict['content']
    todo.update()
    return Response('{}', mimetype='application/json')


def delete(request: Request, todo_id: int):
    try:
        todo = Todo.get(todo_id)
    except TodoNotFound:
        raise NotFound('Todo NotFound')
    todo.delete()
    return Response('{}', mimetype='application/json')
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

### ToDoリストのインターフェース作成 - 解説

`todo_to_dict`や`validate_todo`の処理は前回と全く同じ。

`get_all`や`get`などの関数の引数は`Request`クラスのインスタンスである。
また、関数の返却値は`Response`のオブジェクトを返すようにしている。
これは、`app.py`の`app`関数や`route`関数の実装による。

`Request`クラスのインスタンスであることで、JSONの取得に`get_json`メソッドが使える。
`get_json`メソッドの引数に`force=True`を指定すると、リクエストヘッダのMIMEタイプを気にしないようにできる。
今回それをやるのは大した理由ではなく、単にcurlでテストするときにMIMEタイプを指定するのが面倒だから(あまり行儀は良くないと思うが…)。

`NotFound`や`BadRequest`などのクラスを投げる際に、クラスそのものではなく`NotFound(message)`のようにインスタンスを投げることができる。
すると、レスポンスに`message`が出力される。以下は、次節の`models/todo.py`のコードのうえで実行した例(上のコードではこのレスポンスは返ってこないことに注意)。

{{< cui >}}
% curl localhost:5000/4/
&lt;!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN"&gt;
&lt;title&gt;404 Not Found&lt;/title&gt;
&lt;h1&gt;Not Found&lt;/h1&gt;
&lt;p&gt;Todo NotFound&lt;/p&gt;
{{< /cui >}}


## ToDoリストの実装

ここでは、SQLiteでデータを管理する。内容は[前回]({{<ref "posts/todo-list-wsgi">}})と全く同じ。
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

うまく動いているか確認する。

{{< cui >}}
% curl -X POST localhost:5000/todo/ -d '{"content": "部屋の掃除"}'
1

% curl -X POST localhost:5000/todo/ -d '{"content": "犬の散歩"}'
2

% curl -X POST localhost:5000/todo/ -d '{"content": "風呂を洗う"}'
3

% curl localhost:5000/todo/
[{"id": 1, "content": "部屋の掃除"}, {"id": 2, "content": "犬の散歩"}, {"id": 3, "content": "風呂を洗う"}]%

% curl localhost:5000/todo/2/
{"id": 2, "content": "犬の散歩"}

% curl -X PUT localhost:5000/todo/1/ -d '{"content": "aaa"}'
{}

% curl localhost:5000/todo/
[{"id": 1, "content": "部屋の掃除"}, {"id": 2, "content": "aaa"}, {"id": 3, "content": "風呂を洗う"}]%

% curl -X DELETE localhost:5000/todo/2/
{}

% curl localhost:5000/todo/
[{"id": 1, "content": "部屋の掃除"}, {"id": 3, "content": "風呂を洗う"}]
{{< /cui >}}


## werkzeug.testとpytestを用いたテスト

curlでうまく動いているのか確認するだけでなく、ちゃんとテストコードを書いて検証してみる。
今回はテストのツールとして[pytest](https://docs.pytest.org/en/6.2.x/)を用いる。
また、`werkzeug.test`モジュールの`Client`を使えば、サーバーを起動せずにクライアントを作成することができ、
リクエストの送受信をシミュレーションできる。

`pytest`はあまり使った経験がないため、`pytest`についても備忘のため簡単に解説を書く。


### 簡単な使い方

`tests/test_todo.py`を作成して、ひとまず内容を次のようにする。

```python
import pytest
from models.todo import Todo
import tempfile
import os
from werkzeug.test import Client
from app import app


@pytest.fixture
def client():
    db_fd, Todo.DB_PATH = tempfile.mkstemp()
    Todo.init_table()
    os.close(db_fd)
    return Client(app)


def test_hello(client):
    res = client.get('/')
    assert res.get_data(as_text=True) == 'Hello, World'
```

テストを実行する場合、以下のコマンドを実行する。

{{< cui >}}
% pytest
{{< /cui >}}

うまくいくと`1 passed`というメッセージが出力される。

### 簡単な使い方 - 解説

pytestコマンドを実行すると、`tests`ディレクトリの`test_*.py`というファイル内の`test_*`という関数を実行してテストを行う。
よって、上の例では`tests/test_todo.py`の`test_hello`がテストの対象となる。

`@pytest.fixture`というデコレータを定義すると、テストの前処理を行うことができる。デコレータで修飾された関数の返却値は、
テスト関数の引数として利用できるようになる。ただし、その引数名は`pytest.fixture`で修飾した関数と同名にする必要がある。
上の例では、`client`関数を`pytest.fixture`で修飾しているから、`test_hello`関数では`client`関数の返却値を引数`client`として使えるようになる。

`Client`は`werkzeug.test`で定義されているクラス。引数にWSGIアプリを与えてインスタンス化することで、クライアントを作成することができる。
このインスタンスを使えば、GETやPOSTなどのリクエストを`get`や`post`メソッドで行える。実際、`test_hello`では`client.get('/')`でURI `'/'`にGETリクエストを送っている。
`Client`の詳細は[ドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/test/#werkzeug.test.Client)を参照。

`Client`オブジェクトの`get`や`post`メソッドの返却値は`TestResponse`クラスのインスタンスで、`get_data`や`get_json`などのメソッドでデータを取得できる。
詳細は[ドキュメント](https://werkzeug.palletsprojects.com/en/2.0.x/test/#werkzeug.test.TestResponse)を参照。

pytestにおいて、結果の正しさを確認するためには、シンプルに`assert`文を使う。
上の例では、レスポンスで得られたデータ`res.get_data()`が`'Hello, World'`であるかどうかを判定している。

`client`関数では、`Client`クラスのインスタンスを作るだけでなく、データベースの初期化を行っている。
また、そのテスト限りのデータベースを作成するために、そのファイルを`tempfile.mkstemp()`関数で作成している。
これはファイルのディスクリプタとファイルのパスをタプルで返すため、後者を`Todo`のデータベースのパスに設定している。

### Todoのテスト

大体のことは上で説明したので、後はテストを書くだけ。
`tests/test_todo.py`の内容を以下のようにする。

```python
import pytest
from models.todo import Todo
import tempfile
import os
from werkzeug.test import Client
from app import app
import json


@pytest.fixture
def client():
    db_fd, Todo.DB_PATH = tempfile.mkstemp()
    Todo.init_table()
    os.close(db_fd)
    return Client(app)


@pytest.fixture
def todos_req():
    todo1 = {'id': 1, 'content': '部屋の掃除'}
    todo2 = {'id': 2, 'content': '犬の散歩'}
    todo3 = {'id': 3, 'content': '風呂を洗う'}
    return [todo1, todo2, todo3]


def test_empty_db(client):
    res = client.get('/todo/')
    assert res.get_json() == []


def test_add_todos(client, todos_req):
    for todo_req in todos_req:
        res = client.post('/todo/', data=json.dumps({"content": todo_req['content']}))
        assert res.get_json() == todo_req['id']

    todos_res = client.get('/todo/').get_json()
    assert todos_req == todos_res

    todo_res = client.get('/todo/1/').get_json()
    assert todos_req[0] == todo_res


def test_put_todo(client, todos_req):
    for todo_req in todos_req:
        res = client.post('/todo/', data=json.dumps({"content": todo_req['content']}))

    todo_new = {'id': 2, 'content': 'aaa'}
    res = client.put('/todo/2/', data=json.dumps({"content": todo_new['content']}))
    res = client.get('/todo/')
    assert res.get_json() == [todos_req[0], todo_new, todos_req[2]]


def test_delete_todo(client, todos_req):
    for todo_req in todos_req:
        res = client.post('/todo/', data=json.dumps({"content": todo_req['content']}))

    res = client.delete('/todo/2/')
    assert res.get_json() == dict()

    res = client.get('/todo/')
    assert res.get_json() == [todos_req[0], todos_req[2]]
```

`pytest`コマンドを実行すると、`4 passed`というメッセージが出力される。

## ソースコード

ソースコードは[GitHubのRepository](https://github.com/bombrary/todo-api-werkzeug)にあげた。
