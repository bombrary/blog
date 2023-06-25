---
title: "FastAPIとOAuth2でユーザログイン機能（備忘録）"
date: 2023-06-14T05:18:31+09:00
draft: true
tags: []
categories: []
---

## 何をするか

以下の3つの機能を実装する。

- ユーザを作成する。
- ユーザを認証してトークンを生成し返す。
- ユーザがログインしていないと401を返す：ここでは「ユーザ情報を返すAPI」を作成。
- ユーザがログインしているかどうかで異なるレスポンスを返す：ここでは「ログインしているかどうかを真偽値で返すAPI」を作成。


## 方針

### 使う技術・フレームワーク、ライブラリなど

- PythonとMySQLはDocker Composeで動かす。
- PythonのパッケージはPoetryで管理する。
- APIサーバーはFastAPI + uvicornで動かす。
- 認可の方式としてOAuth2.0を用いる。認可グラントのタイプはシンプルな[ROPC](https://openid-foundation-japan.github.io/rfc6749.ja.html#grant-password)。
  なぜこれを選んだのかというと、単純に[FastAPIのドキュメント](https://fastapi.tiangolo.com/tutorial/security/oauth2-jwt/)に書かれていたのがこれだったため。いつかほかのタイプも実装してみたい。
- DBのマイグレーションは[albemic](https://github.com/sqlalchemy/alembic)を使用してみる。今回はユーザ情報しか作らないので、alembicの使用は間違いなくオーバーなのだが、勉強のため使ってみる。

### プロジェクト構成

プロジェクトディレクトリは次のようにする。

- DBに関するCRUDs処理は`cruds`モジュールに書く。
- DBと対応するモデルは`model`モジュールに書く。
- APIのリクエストボディ、レスポンスボディの形式は`schemas.py`に書く。
- DBのセッションの作成は`db.py`に書く。

```sh
.
├── api
│   ├── cruds
│   │   ├── __init__.py
│   │   └── user.py
│   ├── models
│   │   ├── __init__.py
│   │   └── user.py
│   ├── routers
│   │   ├── __init__.py
│   │   └── auth.py
│   ├── schemas
│   │   ├── __init__.py
│   │   └── user.py
│   ├── db.py
│   ├── main.py
│   └── migrate_db.py
├── Dockerfile
├── docker-compose.yaml
├── poetry.lock
└── pyproject.toml
```

ちなみにこの図は`tree -I __pycache__ --dirsfirs`で生成。

サービス名は以下の通り。
- `app`：アプリケーションサーバー。FastAPI、albemicが動いている。
- `db`：DBサーバー。MySQLが動いている。

## 開発環境作成

最低限の環境を作る。本質的なところではないのであまり解説はしない。

`docker-compose.yaml`は次のようにする。

```yaml
version: '3'
services:
  app:
    build: .
    volumes:
      - .:/src
    ports:
      - 8000:8000

  db:
    image: mysql:8
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: 'yes'
      MYSQL_DATABASE: 'app-db'
      TZ: 'Asia/Tokyo'
    volumes:
      - mysql_data:/var/lib/mysq
    command: --default-authentication-plugin=mysql_native_password

volumes:
  mysql_data:
```

`Dockerfile`は次のようにする。

```Dockerfile
FROM python:3.11-buster
ENV PYTHONUNBUFFERED=1

WORKDIR /src

RUN pip install poetry
RUN poetry config virtualenvs.in-project true

ENTRYPOINT ["poetry", "run", "uvicorn", "api.main:app", "--host", "0.0.0.0", "--reload"]
```

ちなみに、`virtualenvs.in-project ture`をやっておかないと、プロジェクトディレクトリに各種ライブラリが展開されないので注意。

以下の3つのコマンドを実行する。この時点で必要なパッケージを`--dependency`で指定している。

```sh
$ docker-compose build
$ docker-compose run --entrypoint=poetry app init --name app \
    --dependency fastapi \
    --dependency uvicorn[standard] \
    --dependency alembic \
    --dependency aiomysql \
$ docker-compose run --entrypoint=poetry app install --no-root
```

簡単に`api/main.py`を作成しておく。

```python3
from fastapi import FastAPI

app = FastAPI()

@app.get('/api/hello')
def hello():
    return 'Hello'
```

最後に`docker-compose up`すれば、FastAPI（on uvicorn）とMySQLのサーバーが起動する。

## マイグレーションスクリプト作成

alembicを初期化。

```sh
$ docker-compose run --entrypoint=poetry app run alembic init alembic
```

`alembic.ini`にMySQLコンテナへのアドレスを指定する。ついでにここにasync版のURLを書いておく。

```ini
sqlalchemy.url = mysql+pymysql://root@db:3306/app-db?charset=utf8
sqlalchemy.async_url = mysql+aiomysql://root@db:3306/app-db?charset=utf8
```

DBとの疎通確認も兼ねて、空のマイグレーションをしておく。

```sh
$ docker-compose run --entrypoint=poetry app run alembic revision --autogenerate -m "empty migration"
$ docker-compose run --entrypoint=poetry app run alembic upgrade head
```

## ユーザのテーブル作成

今回はメールアドレスとパスワードで認証するような仕組みを作るので、ユーザのエンティティにはその2つを持たせる。

まず`api/db.py`を編集する。

```python
from sqlalchemy.orm import declarative_base

Base = declarative_base()
```

`api/models/user.py`でユーザのエンティティを作成。

```python
from sqlalchemy import Column, Integer, String
from api.db import Base

class User(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    email = Column(String(256), unique=True)
    password = Column(String(256))
```

`alembic/env.py`に`metadata`を指定。

```python
from api.db import Base
from api.models import user

target_metadata = Base.metadata
```

マイグレーションをして、ユーザテーブルを作成。

```sh
$ docker-compose run --entrypoint=poetry app run alembic revision --autogenerate -m "user"
$ docker-compose run --entrypoint=poetry app run alembic upgrade head
```

## DBのセッション作成

後々ユーザ登録とかログインで使うので、DBのセッションを作っておく。今回はDBのasync版のURLが`alembic.ini`に書かれているため、それを使わせてもらう。

`api/db.py`に追記。

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
h
from sqlalchemy.orm import sessionmaker, declarative_base
from alembic.config import Config

config = Config('alembic.ini')

async_engine = create_async_engine(config.get_main_option('sqlalchemy.async_url'), echo=True)
async_session = sessionmaker(
        autocommit=False,
        autoflush=False,
        bind=async_engine,
        class_=AsyncSession
)

async def get_db():
    async with async_session() as session:
        yield session
```

## ユーザ登録処理を作成

やることは、パスワードをハッシュ化してDBに保存すること。

1. メールとパスワードをスキーマの形で受け取る。
2. パスワードハッシュ化する。
3. DBに追加する。すでに存在するメールアドレスがあるなら例外を投げるはずなので、ちゃんとキャッチする。
4. ユーザ情報を返す。

ハッシュのためにpasslibが必要なので、このタイミングで入れておく。

```sh
docker-compose run --entrypoint=poetry app add passlib[bcrypt]
```

### 準備

`api/routers/user.py`でひな形を作っておく。

```python
from fastapi import APIRouter

from api.schema import user as user_schema

router = APIRouter()

@router.post('/api/register', response_model=user_schema.User)
async def register(user_create: user_schema.UserCreate):
    pass
```

リクエストとレスポンスのスキーマが必要なのでそれをつくる。`api/schema/user.py`を編集する。

```python
from pydantic import BaseModel


class UserBase(BaseModel):
    email: str


class UserCreate(UserBase):
    password: str


class User(UserBase):
    id: int

    class Config:
        orm_mode=True
```

`api/main.py`にルーターの記述を追加する。

```python
from api.routers import user

app.include_router(user.router)
```

この時点でSwagger UIを開いて、`/api/register`のエンドポイントが開かれていればOK。

### 中身の作成

`api/routers/user.py`を編集する。UNIQUE制約に関する例外をキャッチする事情で、少し煩雑にはなっている。しかし、それ以外のところを見てみると、単にユーザを作って返しているだけだと分かる。
ちなみに、`api.schema.user`の`User`クラスで`orm_mode=True`にしているおかげで、`api.models.user.User`が自動的に`api.schema.user.User`に変換されて出力される。

```python
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Annotated
from pymysql.err import IntegrityError
from pymysql.constants import ER

from api.db import get_db
from api.schema import user as user_schema
from api.cruds import user as user_cruds

@router.post('/api/register', response_model=user_schema.User)
async def register(user_create: user_schema.UserCreate, db: Annotated[AsyncSession, Depends(get_db)]):
    try:
        user = await user_cruds.register_user(db, user_create)
        return user
    except IntegrityError as e:
        errcode, _ = e.args
        if errcode == ER.DUP_ENTRY:
            raise HTTPException(
                    status_code=status.HTTP_409_CONFLICT,
                    detail='already used email address'
                  )
        else:
            raise
```

`api/cruds/user.py`を編集する。

パスワードをハッシュ化してDBに登録する。例外はSQLAlchemyがラップして返すので、それを引きはがして呼び出し元に任せる。

```python
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError
from passlib.context import CryptContext
from pymysql.constants import ER

from api.models import user as user_model
from api.schema import user as user_schema


pwd_context = CryptContext(schemes=['bcrypt'], deprecated='auto')


async def register_user(
    db: AsyncSession,
    user_create: user_schema.UserCreate
) -> user_model.User: 

    try:
        user = user_model.User(**user_create.dict())
        user.password = pwd_context.hash(user.password)

        db.add(user)
        await db.commit()
        await db.refresh(user)

        return user
    except IntegrityError as e:
        db.rollback()
        raise e.orig
```


## トークン取得処理を作成

やることは、

1. [ROPCのフォーム形式](https://openid-foundation-japan.github.io/rfc6749.ja.html#password-tok-req)に従い、`username`、`password`を取得。
2. `username`に合致するユーザをDBから検索する。OAuth2の使用上`username`という名前で受け取るが、ここでは`email`と同じ意味。
3. ユーザが見つかったらパスワードを照合。
4. 2、3が成功したらトークンを生成して返す。

の4つ。それぞれについての実装方法は、

1. `fastapi.security`モジュールで`OAuth2PasswordReqeustForm`が提供されているのでそれを使う。
2. `api.cruds`モジュールに`get_user_by_email`という関数を作成し、そこでDBとの通信を行う。
3. `passlib`の`CryptContext.verify`関数を使う。
4. ユーザを判別できるようなサブ情報（ここでは`email`）とトークンの有効期限を入れた辞書を作り、JWTにする。JWTの変換は`jose`モジュールの`jwt.encode`を用いる。

となる。なお、`jwt.encode`の暗号化アルゴリズムとしてHS256を用いる。そのための鍵（シークレットキー）をあらかじめ生成しておく。

## ログインしているユーザ情報が見られるAPIを作成

やることは、

1. トークンを取得。
2. トークンの有効期限をチェック。
3. トークンの`sub`情報からユーザ情報をDBから検索し、返す。

の4つ。それぞれについての実装方法は、

1. `fastapi.security`モジュールで`OAuth2PasswordBearer`が提供されているのでそれを使う。
2. `jose`モジュールの`jwt.decode`でJWTをデコードする。このとき有効期限情報もチェックされる（[参考ソースコード](https://github.com/mpdavis/python-jose/blob/master/jose/jwt.py)）。
3. デコードされた辞書から`sub`情報を取り出す。ここには`email`の情報を入れたので、これをもとに`gt_user_by_email`を使ってユーザを取得する。

となる。

## ログインしているかどうかを判定するAPIを作成

やることは`OAuth2PasswordBearer`のインスタンス作成時に`auto_err=False`を設定する以外はまったく同じ。
