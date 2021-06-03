---
title: "PythonとFlask(+α)で作るToDoリストAPI"
date: 2021-06-03T23:29:00+09:00
tags: ["Web API", "ToDoリスト", "Flask", "peewee", "marshmallow"]
categories: ["Python", "Web"]
toc: true
---

シンプルなToDoリストのWeb APIを作る。
今まで[WSGIの仕様のみ]({{< ref "/posts/todo-api-wsgi" >}})、[Werkzeug]({{< ref "/posts/todo-api-werkzeug" >}})
の2通りで実装したが、今回はFlaskといくつかのライブラリを使う。使うのは以下の通り。

- [Flask](https://flask.palletsprojects.com/en/2.0.x/): WSGIアプリフレームワーク。
- [peewee](http://docs.peewee-orm.com/en/latest/): ORMライブラリ。
- [marshmallow](https://marshmallow.readthedocs.io/en/stable/): データの変換やvalidationをするためのライブラリ。

## Flaskとは

WSGIのWebアプリを作るためのフレームワーク。
フレームワークであるため、Flaskが用意した作法に従ってコードを書くことで比較的手軽にWebアプリが作成できる。
前回との比較でいうならば、例えばルーティングの仕組みをプログラマが書く必要はない。これはFlaskに備わっている。

Djangoのようなフレームワークとは違って、持っている機能は少ない。必要に応じて外部ライブラリを組み合わせる。
例えば、Djangoではデフォルトでデータベースの仕組みが内蔵されているが、Flaskにはない。その代わりに、
データベースのライブラリとして`sqlite3`や`SQLAlchemy`、`peewee`など、好きなものを用いれば良い。


## ToDoリストAPIの仕様

今回ToDoのデータは以下キーと値を持つJSONデータとする。

| key | value |
| --- | ----- |
| id | ID |
| content | ToDoの内容 |
| created_at | 作成日時 (ISO8601) |
| updated_at | 更新日時 (ISO8601) |

APIの仕様は以下の通り。

| URI | Method | 説明 | 返却値 |
| ---- | ---- | ---- | ---- |
| `/todo/` | GET | 全てのToDoを取得。 | ToDoのデータのリスト |
| `/todo/` | POST | ToDoを作成。 | 作成したToDoのid
| `/todo/<todo_id>` | GET | `todo_id`のidを持つToDoを取得。 | ToDoのデータ |
| `/todo/<todo_id>` | PUT | `todo_id`のidを持つToDoを変更。 | 空のオブジェクト |
| `/todo/<todo_id>` | DELETE | `todo_id`のidを持つToDoを削除 | 空のオブジェクト |

データはSQLiteで管理する。


## 雛形

`todo_list`ディレクトリを作成。`todo_list/__init__.py`を以下のようにする。

```python
from flask import Flask


def create_app():
    app = Flask(__name__)

    @app.route('/')
    def hello():
        return 'Hello, World'

    return app
```

`export`コマンドで環境変数を設定する。

{{< cui >}}
% export FLASK_APP=todo_list
% export FLASK_ENV=development
{{< /cui >}}

`flask run`でサーバーが起動する。

{{< cui >}}
% flask run
{{< /cui >}}

`curl`コマンドで試しにアクセスしてみる。

{{< cui >}}
% curl localhost:5000
Hello, World
{{< /cui >}}

### 雛形 - 解説

まず、`Flask(__name__)`でWSGIアプリを作ることができる。アプリを`app`としたとき、`@app.route`デコレータでURIに対応する関数を登録することができる。
以下は、URI `/`に対して関数`hello`を登録している。よって、URI `/`にアクセスされたときに、`Hello, World`というレスポンスが返ってくるようになる。

```python
    @app.route('/')
    def hello():
        return 'Hello, World'
```

HTMLデータやJSONなどの、アプリのユーザーが「見る部分」のことをviewという。
そして`hello`のような、`@app.route`で登録される関数をview関数という。
上のコードでは`'Hello, World'`を返すviewをview関数`hello`として定義していることになる。
view関数の書き方については[ドキュメントのQuickstart](https://flask.palletsprojects.com/en/2.0.x/quickstart/#about-responses)を参照。
例えば文字列ではなく`dict`を返すと、JSONデータとしてレスポンスが送られる。

`create_app`関数はWSGIアプリを返す関数である。この関数内で、WSGIアプリに関する様々な設定をする。
このようなパターンは[Application Factories](https://flask.palletsprojects.com/en/2.0.x/patterns/appfactories/)と呼ばれる。
後でここにデータベースのパスの設定など、色々書いていく。

環境変数`FLASK_APP`には、WSGIアプリがあるモジュールを指定している。
`flask run`コマンドは、`FLASK_APP`に設定されたモジュールの`create_app`関数を元にWSGIアプリを作成し、開発用サーバーを起動する。
環境変数`FLASK_ENV`に`development`を設定すると、自動リロードがONになったり、例外発生時にデバッグ用のレスポンスを送ったりしてくれる。

## Blueprintの利用

まず、Blueprintを作成する。`todo_list/todo.py`を作成し、ひとまず内容を以下の通りにする。

```python
from flask import Blueprint, request

bp = Blueprint('todo', __name__)


@bp.route('/', methods=["GET"])
def get_all():
    return 'get_all'


@bp.route('/', methods=["POST"])
def post():
    body = request.get_json()
    return f'post: {body}'


@bp.route('/<int:todo_id>/', methods=["GET"])
def get(todo_id: int):
    return f'get: {todo_id}'


@bp.route('/<int:todo_id>/', methods=["PUT"])
def put(todo_id: int):
    body = request.get_json()
    return f'put: {todo_id}, {body}'


@bp.route('/<int:todo_id>/', methods=["DELETE"])
def delete(todo_id: int):
    return f'delete: {todo_id}'
```

WSGIアプリにBlueprintを登録する。`todo_list/__init__.py`の内容を以下の通りにする。

```python
from flask import Flask


def create_app():
    app = Flask(__name__, url_prefix='/todo')

    @app.route('/')
    def hello():
        return 'Hello, World'

    # 以下2文を追加
    from . import todo
    app.register_blueprint(todo.bp)

    return app
```

`curl`で確認。

{{< cui >}}
% curl localhost:5000/todo/
get_all
% curl localhost:5000/todo/1/
get: 1
% curl -X POST -H "Content-Type: application/json" localhost:5000/todo/ -d '{"content": "部屋の掃除"}'
post: {'content': '部屋の掃除'}
% curl -X PUT -H "Content-Type: application/json" localhost:5000/todo/1/ -d '{"content": "部屋の掃除"}'
put: 1, {'content': '部屋の掃除'}
% curl -X DELETE localhost:5000/todo/1/
delete: 1
{{< /cui >}}


### Blueprint - 解説

Blueprintとは、viewをグループ化する仕組みである。
これによって、viewの使い回しができたり、同じprefixのURIでまとめたりできるようになる
([参考](https://flask.palletsprojects.com/en/2.0.x/blueprints/#why-blueprints))。

上のコードでは、`todo`というBlueprintを作り、それを`bp`とした。
使い方は`@app.route`と同じく、`@bp.route`のように用いる。
WSGIアプリにBlueprintを登録するには、`register_blueprint`メソッドを使う。
`url_prefix`引数を`/todo`とすることで、対応するBlueprintのURIのprefixを`/todo`に統一する。


## peeweeを使ったToDoモデルの作成

`todo_list/models/__init__.py`と`todo_list/models/todo.py`を作成。前者は空のままにし、後者は内容を以下のようにする。

```python
from peewee import Model, TextField, DateTimeField
from datetime import datetime


class Todo(Model):
    content = TextField()
    created_at = DateTimeField(default=datetime.now)
    updated_at = DateTimeField()

    def save(self, *args, **kwargs):
        self.updated_at = datetime.now()
        return super(Todo, self).save(*args, **kwargs)
```

### peeweeを使ったToDoモデルの作成 - 解説

peeweeはORMである。つまり、PythonのオブジェクトとRDBMS(上ではSQLite)のデータを相互に変換するためのライブラリである。
ORMを使う1つの利点は、SQL文を書かずに済むことである。
データは`Model`というクラスとして管理する。`Model`を介してRDBMSのデータを操作する。

上のコードでは`Todo`というモデルを作成し、その属性として`content, created_at, updated_at` を用意している。
これらはそれぞれ、テキスト、時刻、時刻の型を持つ。`id`は自動で追加される。

`created_at`には、`Todo`のインスタンス作成時に時刻が記録されるように、`default`引数を設定している。
`updated_at`について、`save`メソッドが呼ばれる度に時刻が記録されるように、`save()`メソッドをオーバーライドしている
([参考](https://stackoverflow.com/questions/18522600/is-there-an-auto-update-option-for-datetimefield-in-peewee-like-timestamp-in-mys))。


### peeweeを使ったToDoモデルの作成 - コンソール上でのテスト

うまく`Todo`が定義されているかテストしてみる。

まず、関連のモジュールをimportする。

{{< cui >}}
% python3
>>> from todo_list.models.todo import Todo
>>> from peewee import SqliteDatabase
{{< /cui >}}

次に、データベースを作成する。テストのため、データベースはメモリ上で動かす。
データベースに`Todo`クラスを紐づけた後、`create_table`で`Todo`のテーブルを作成する。

{{< cui >}}
>>> db = SqliteDatabase(':memory:')
>>> db.bind([Todo])
>>> db.create_table([Todo])
{{< /cui >}}

実はこのあたりはpeeweeの[Quickstart](http://docs.peewee-orm.com/en/latest/peewee/quickstart.html)とやり方が異なる。
Quickstartでは、`Todo`クラスの`Meta`内部クラスにデータベースを設定している。
ではなぜ今回は`bind`を使ったのかと言うと、Flaskのアプリを作る上での都合である。詳しくは後述する。
`bind`を使った話は[Setting the database at run-time](http://docs.peewee-orm.com/en/latest/peewee/database.html#setting-the-database-at-run-time)に載っている。

`Todo.create`で`Todo`のインスタンスを作成。`select`や`get`などのクラスメソッドで、データの取得が行える。`save`メソッドでデータの更新ができる。

{{< cui >}}
>>> todo = Todo.create(content='部屋の掃除')
>>> list(Todo.select())
[&lt;Todo: 1&gt;]
>>> todo.content = '犬の散歩'
>>> todo.save()
1
>>> Todo.get(Todo.id == 1).content
'犬の散歩'
{{< /cui >}}

peeweeでは便利な機能を[playhouse](https://docs.peewee-orm.com/en/latest/peewee/playhouse.html)として提供しているようで、
例えば`playhouse.shortcuts`の`model_to_dict`関数は、`Model`を`dict`に変換してくれる。

{{< cui >}}
>>> from playhouse.shortcuts import model_to_dict
>>> model_to_dict(todo)
{'id': 1, 'content': '犬の散歩', 'created_at': datetime.datetime(2021, 6, 2, 15, 45, 15, 247438), 'updated_at': datetime.datetime(2021, 6, 2, 15, 45, 39, 839677)}
{{< /cui >}}

ただし、`dict`への変換はmarshmallowに任せるので、`model_to_dict`はこの後使わない。

## marshmallowを使ったデータの変換とvalidation

`todo_list/models/todo.py`を以下のようにする。

```python
from peewee import Model, TextField, DateTimeField
from datetime import datetime
from marshmallow import Schema, fields


class Todo(Model):
  # ...
  # 省略
  # ...


class TodoSchema(Schema):
    id = fields.Integer()
    content = fields.Str(required=True)
    created_at = fields.DateTime()
    updated_at = fields.DateTime()


todo_schema = TodoSchema()
```

### marshmallowを使ったデータの変換とvalidation - 解説

marshmallowは、JSONデータとPythonオブジェクトを相互に変換する機能を提供する。
その変換のルールは`Schema`クラスで定義する。
上の`TodoSchema`は、以下の変換のルールを定義する。

- `id`は整数値
- `content`は文字列。必須項目なので、`required=True`を設定している。
- `create_at`、`update_at`は日付時刻。\
  `DateTime`は時刻を文字列として変換する。その形式のデフォルトはISO8601([参考](https://marshmallow.readthedocs.io/en/stable/marshmallow.fields.html#marshmallow.fields.DateTime))。

スキーマのインスタンスを`todo_schema`とする。`todo_schema.loads`でJSONからdict、`todo_schema.dumps`でPythonオブジェクトからJSONに変換する。
変換の際に、フィールドが存在しなかったり、型が合わなかったりした場合は、`ValidationError`例外を投げる。

### marshmallowを使ったデータの変換とvalidation - コンソール上でのテスト

再びPythonでテストする。

まずはデータベースを作る。

{{< cui >}}
>>> from todo_list.models.todo import Todo
>>> from peewee import SqliteDatabase
>>> db = SqliteDatabase(':memory:')
>>> db.bind([Todo])
>>> db.create_table([Todo])
{{< /cui >}}

`Todo`から`dict`への変換は`dump`で行う。JSONに変換する`dumps`というのもある。

{{< cui >}}
>>> todo = Todo.create(content='部屋の掃除')
>>> from todo_list.models.todo import todo_schema
>>> todo_schema.dump(todo)
{'created_at': '2021-06-02T16:32:55.820672', 'updated_at': '2021-06-02T16:32:55.820739', 'content': '部屋の掃除', 'id': 1}'
{{< /cui >}}

`dict`のvalidationは`load`で行う。不正な値を`load`すると`ValidationError`が発生することも確認する。

{{< cui >}}
>>> todo_schema.load({'content': '部屋の掃除'})
{'content': '部屋の掃除'}
>>> todo_schema.load({'foo': 1})
...
marshmallow.exceptions.ValidationError: {'content': ['Missing data for required field.'], 'foo': ['Unknown field.']}
>>> todo_schema.load({'content': 1})
...
marshmallow.exceptions.ValidationError: {'content': ['Not a valid string.']}
{{< /cui >}}


## Flaskとデータベースの連携

`todo_list/db.py`を作成し、内容を以下のようにする。

```python
from peewee import SqliteDatabase
from .models.todo import Todo
from flask import Flask

db = SqliteDatabase(None)


def init_app(app: Flask):
    db.init(app.config['DB_PATH'])
    db.bind([Todo])
    app.teardown_appcontext(close_db)


def close_db(e=None):
    if not db.is_closed():
        db.close()
```

`todo_list/app.py`を以下のようにする。

```python
from flask import Flask
import os # 追加


# 追加
def make_instance_path(app):
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass


def create_app():
    app = Flask(__name__)
    app.config['DB_PATH'] = os.path.join(app.instance_path, 'db.sqlite3') # 追加

    make_instance_path(app) # 追加

    # 以下の2行を追加
    from . import db
    db.init_app(app)

    @app.route('/')
    def hello():
        return 'Hello, World'

    from . import todo
    app.register_blueprint(todo.bp, url_prefix="/todo")

    return app
```


`todo_list/todo.py`に以下の内容を追記する。

```python
from .db import db

@bp.before_request
def connect_db():
    db.connect()
```

### Flaskとデータベースの連携 - 解説

Flaskでは、WSGIアプリの設定情報を管理するために`app.config`が提供されている。
`app.config`の設定方法はいくつかある。
外部のPythonファイルから読み込んだり(`app.config.from_pyfile`)、
`dict`から読み込んだり(`app.config.from_mapping`)できる。
これをうまく利用すれば、例えば本番環境と開発環境、テスト環境で異なる設定を適用することができる。
ここでは、データベースのパスを`app.config['DB_PATH']`に格納しておく。

Flaskには[instance folder](https://flask.palletsprojects.com/en/2.0.x/config/#instance-folders)というものがある。
これは、例えばGitでバージョン管理してほしくないもの(データベースファイルや設定ファイルなど)を入れるディレクトリである。
そのパスは`app.instance_path`で取得でき、デフォルトでは「アプリケーションの1つ上のディレクトリ」となる。
今回の場合は`todo_list`と同じ階層ある`instance`というディレクトリをinstance folderとみなす。
instance folderは自動で作られることはないため、その作成を`make_instance_folder`に任せている。

データベースの設定は`db.init_app`関数に任せる。
`db.init_app`では、まずデータベースの設定を`db.init`で行う。その後`db.bind`で`Todo`を紐付けている。
`SQLiteDatabase`の引数は本来データベースのパスを指定するはずだが、これを`None`とすることで、それを後回しにしている。
そして、そのパスを`db.init(app.config['DB_PATH'])`で設定している
([参考](http://docs.peewee-orm.com/en/latest/peewee/database.html#run-time-database-configuration))。
前前節で「TodoクラスのMeta内部クラスにデータベースを設定しないのはFlaskアプリを作るうえでの都合」と述べたが、
その理由はこのようにデータベースのパスを`app.config`で設定したかったからだ。

`app.teardown_appcontext`では、リクエストが送られてきて、それに対して何かしらの処理が終わった後に呼び出される関数を登録する。
ここでは、データベースがもし接続されていたら閉じる処理を行う。

`/todo/...`のURIにアクセスされた時は必ずにデータベースに接続するので、その接続処理を`connect_db`で行う。`@bp.before_request`デコレータを使うと、
リクエストの前に行われる処理を設定することができる。

`teardown_appcontext`や`before_request`で、リクエスト処理の前後に新たな処理を付け足せることが見て取れるだろう。
こういう機能が提供されていることはありがたい。

## データベースの初期化

`todo_list/db.py`を以下のようにする。

```python
from peewee import SqliteDatabase
from .models.todo import Todo
from flask import Flask
# 以下2行を追加
from flask.cli import with_appcontext
import click

db = SqliteDatabase(None)


def init_app(app: Flask):
    db.init(app.config['DB_PATH'])
    db.bind([Todo])
    app.teardown_appcontext(close_db)
    app.cli.add_command(init_db_command) # 追加


def close_db(e=None):
    if db.is_closed():
        db.close()

# 追加
def init_db():
    db.drop_tables([Todo])
    db.create_tables([Todo])


# 追加
@click.command('init-db')
@with_appcontext
def init_db_command():
    init_db()
    click.echo('Initizlized the database.')
```

以下のコマンドを実行すると、データベースが初期化される。
{{< cui >}}
% flask init-db
Initizlized the database.
{{< /cui >}}

### データベースの初期化 - 解説

Flaskでは自作のコマンドを作る機能が備わっている。コマンドに対応する関数を登録するメソッドは`app.cli.add_command`で行う。
登録する関数に対して`@click.command`デコレータを使うと、コマンド名を設定できる。上のコードではその名前を`init-db`にしているため、
`flask init-db`でコマンドが実行される。`@with_appcontext`で包むと、WSGIアプリが生成された後にこのコマンドが実行されることを保証してくれる。
今回の例では`init_app`が先に実行されていないとデータベースに接続できないため、このデコレータを用いている。

コマンドの内容は、単に`Todo`のテーブルを削除して、新たに作り直しているだけである。
`drop_tables`では、SQLの`DROP`文が実行される。これはデフォルトで`IF EXISTS`句をつけてくれる。この設定は`safe`引数で変えられる。
同様に、`create_tables`ではデフォルトで`IF NOT EXISTS`をつけてくれる。


## ToDoのレスポンスの実装

`todo_list/todo.py`を以下のようにする。

```python
from flask import Blueprint, request, jsonify
from .db import db
from .models.todo import Todo, dump_todo, load_todo_or_400

bp = Blueprint('todo', __name__)


@bp.before_request
def connect_db():
    db.connect()


@bp.route('/', methods=["GET"])
def get_all():
    todos = list(Todo.select())
    return jsonify(dump_todo(todos, many=True))


@bp.route('/', methods=["POST"])
def post():
    todo_dict = load_todo_or_400(request.get_json())
    todo = Todo.create(content=todo_dict['content'])
    return jsonify(todo.id)


@bp.route('/<int:todo_id>/', methods=["GET"])
def get(todo_id: int):
    todo = Todo.get_or_404(todo_id)
    return jsonify(dump_todo(todo))


@bp.route('/<int:todo_id>/', methods=["PUT"])
def put(todo_id: int):
    todo_dict = load_todo_or_400(request.get_json())
    todo = Todo.get_or_404(todo_id)
    todo.content = todo_dict['content']
    todo.save()
    return jsonify(dict())


@bp.route('/<int:todo_id>/', methods=["DELETE"])
def delete(todo_id: int):
    todo = Todo.get_or_404(todo_id)
    todo.delete_instance()
    return jsonify(dict())
```

`todo_list/models/todo.py`を以下のようにする。

```python
from peewee import Model, TextField, DateTimeField, DoesNotExist
from datetime import datetime
from marshmallow import Schema, fields, ValidationError
from werkzeug.exceptions import NotFound, BadRequest


class Todo(Model):
    # ... 省略 ...

    @classmethod
    def get_or_404(cls, todo_id: int):
        try:
            todo = Todo.get(Todo.id == todo_id)
        except DoesNotExist:
            raise NotFound
        return todo


class TodoSchema(Schema):
  # ... 省略 ...


todo_schema = TodoSchema()


def dump_todo(obj, many=False):
    return todo_schema.dump(obj, many=many)


def load_todo_or_400(obj):
    try:
        return todo_schema.load(obj)
    except ValidationError:
        raise BadRequest
```

`todo_list/__init__.py`に1行追加する。

```python
def create_app():
    app = Flask(__name__)
    app.config['DB_PATH'] = os.path.join(app.instance_path, 'db.sqlite3')
    app.config['JSON_AS_ASCII'] = False # 追加
    # ...省略
```

### ToDoのレスポンスの実装 - 解説

レスポンスボディを取得したり、`Todo`を返してデータベースを操作したり、それをJSONに変換して送ったりしているだけ。

`get`ではToDo、`get_all`では、ToDoのリストを返す必要がある。そのために、`dump_todo`関数を定義している。
`many`引数で、変換後の値がリストか否かを制御する。

`get, put, delete`では、idが`todo_id`に一致するToDoを探す処理を行っている。もし見つからなければ404 NotFoundを返すように、
クラスメソッド`get_or_404`を定義している。

レスポンスボディが正しい形式であるかを判定するために、`load_todo_or_400`を定義している。
もし正しい形式でなければ、400 BadRequestを返す。

レスポンスで日本語がエスケープされないようにするためには、`app.config['JSON_AS_ASCII']`を`False`に設定する。
レスポンスとして`jsonify`関数を返すと、MIMEタイプを`application/json`に設定してくれる。
なので、`todo_schema.dumps`を使わずにあえて`jsonify`を使っている。


## pytestによるテスト

Werkzeugと同様、Flaskにもテスト用のクライアントが用意されている。これについて軽く書いておく。

### pytestによるテスト - 準備

まず、アプリ側でテスト用の設定を受け付けられるようにする。`todo_list/__init__.py`の`create_app`関数を以下のように追記する。

```python
def create_app(test_config: dict = None): # 追加
    app = Flask(__name__)
    app.config['DB_PATH'] = os.path.join(app.instance_path, 'db.sqlite3')
    app.config['JSON_AS_ASCII'] = False

    # 以下2行を追加
    if test_config is not None:
        app.config.from_mapping(test_config)

    # ... 省略 ...
```

引数に`test_config`が設定されていた場合、`app.config.from_mapping`メソッドでそれを`app.config`に割り当てる。

`tests`ディレクトリを作成し、`tests/conftest.py`を作成。内容を以下のようにする。
これは[FlaskのTutorial](https://flask.palletsprojects.com/en/2.0.x/tutorial/tests/)に書いてある内容とほぼ同じである。

```python
import pytest
from todo_list import create_app
from todo_list.db import init_db
import tempfile
import os


@pytest.fixture
def app():
    db_fd, db_path = tempfile.mkstemp()

    app = create_app({
        'TESTING': True,
        'DB_PATH': db_path,
    })

    with app.app_context():
        init_db()

    yield app

    os.close(db_fd)
    os.unlink(db_path)


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def runner(app):
    return app.test_cli_runner
```

`app`のfixtureをまず作成し、それを使って`client`と`runner`のfixtureを作成する。
`client`はテスト用のクライアントを返す。これはもちろんアプリのテストに用いる。
`runner`はコマンドのテストを行うために用いる。

テスト用のアプリでは、データベースを一時ファイルとして作成するため、その初期処理を`app` fixtureで行っている。

### pytestによるテスト - コマンド

`tests/test_db.py`を作成し、内容を以下のようにする。
これは[FlaskのTutorial](https://flask.palletsprojects.com/en/2.0.x/tutorial/tests/#database)とほぼ同じ。

```python
def test_init_db(runner, monkeypatch):
    class Recorder:
        called = False

    def fake_init_db():
        Recorder.called = True

    monkeypatch.setattr('todo_list.db.init_db', fake_init_db)
    result = runner.invoke(args=['init-db'])
    assert 'Initialized' in result.output
    assert Recorder.called
```

`runner.invoke`でコマンドを実行し、その出力結果を`result.output`で取得できる。
ちゃんと`Initialized`で始まるメッセージが出力されているかをテストしている。

`monkeypatch`は、pytestで標準で用意されているfixtureである。
`init_db`が呼ばれたかどうかをテストするために、`monkeypatch`を使って`todo_init_.db.init_db`を`fake_init_db`にすり替え、
`fake_init_db`が呼ばれたかどうかのフラグを`Recorder`クラスで管理している。


### pytestによるテスト - ToDo

`tests/test_todo.py`を作成し、内容を以下のようにする。
本当はいろいろテストしなければならないのだが、ここでは一例のみ示す。

```python
def test_get_all(client):
    res = client.get('/todo/')
    assert res.get_json() == []

    contents = ["aaa", "bbb", "ccc"]
    for content in contents:
        res = client.post('/todo/', json={'content': content})

    res = client.get('/todo/')
    for content, todo in zip(contents, res.get_json()):
        assert content == todo['content']
```

`client`はWerkzeugのものと使い方は同じ。
例えば`client.get`や`client.post`で、それぞれGETメソッド、POSTメソッドを送ることができる。


## ソースコード

ソースコードは[GitHubのRepositry](https://github.com/bombrary/todo-api-flask)にあげた。
