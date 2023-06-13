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
- DBのマイグレーションは[albemic](https://github.com/sqlalchemy/alembic)を使用してみる。

### プロジェクト構成

プロジェクトディレクトリは次のようにする。

- DBに関するCRUDs処理は`cruds`モジュールに任せる。
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

## マイグレーションスクリプト作成

## ユーザ登録処理を作成

やることは、パスワードをハッシュ化してDBに保存すること。

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
