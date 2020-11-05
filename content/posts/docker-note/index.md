---
title: "Docker 備忘録"
date: 2020-09-21T08:49:00+09:00
draft: true
tags: []
categories: ["Docker"]
---

Dockerを久々に使ったら全然覚えていなかった。`docker --help`でも分かるし何なら[ドキュメント](https://docs.docker.com/reference/)を見れば良いのだが、一応備忘録として残しておく。

## イメージの操作

### イメージの一覧

{{< cui >}}
$ docker images
{{< /cui >}}

### イメージをDocker Hubからダウンロード

[Docker Hub](https://hub.docker.com)にて適当なイメージを探してくる。

{{< cui >}}
$ docker pull <em>repositry_name</em>:<em>tag_name</em>
{{< /cui >}}

もし`tag_name`を省略した場合、デフォルトで`latest`というタグが付く。

例えば[nginx](https://hub.docker.com/_/nginx)の最新版をダウンロードしたい場合は、次のコマンドを実行する。

{{< cui >}}
$ docker pull nginx
{{< /cui >}}



### イメージの削除

{{< cui >}}
$ docker rmi 
{{< /cui >}}

## コンテナの操作

### コンテナの一覧

{{< cui >}}
$ docker ps
{{< /cui >}}

`-a`オプションを付けると、停止したコンテナを含めて確認できる。

もしコンテナを再開・停止・削除したい場合は、このコマンドでコンテナIDまたはコンテナ名を確認する。

### コンテナを作成 & 起動

基本はこれ。

{{< cui >}}
$ docker run <em>image_name</em>
{{< /cui >}}

ただし、nginxなどのサーバーを動かす場合、例えば以下のようなオプションを付ける。

{{< cui >}}
$ docker run -d -p 8080:80 -v <em>path_host</em>:<em>/usr/share/nginx/html:ro</em> nginx
{{< /cui >}}

- `-d`: コンテナをバックグラウンドで実行する
- `-p`: ホストにおける8080番ポートの通信をコンテナの80番ポートに流す。これにより、`http://loaclhost:8080`に接続すれば、コンテナ内のWebサーバ(nginx)に接続される。
- `-v path_host:path_container`: *path_host*で指定したパスを*path_container*へマウントする（絶対パスで指定）。これにより、例えばコンテナ外でhtmlを作成して、それをコンテナ内のWebサーバに読ませられる。

ちなみに、`--name container_name`オプションを付けると、コンテナの名前を*container_name*にしてくれる。付けなかった場合、ランダムな名前が付けられる。

### コンテナの停止・再起動

{{< cui >}}
$ docker stop <em>container_name</em>
{{< /cui >}}

{{< cui >}}
$ docker start <em>container_name</em>
{{< /cui >}}

### コンテナの削除

{{< cui >}}
$ docker rm <em>container_name</em>
{{< /cui >}}

コンテナが停止した状態でないと（`-f`をつけない限りは）削除できないので注意。

### コンテナ内のシェルに入る場合

{{< cui >}}
$ docker exec -it <em>container_name</em> bash
{{< /cui >}}

`docker exec`はコンテナ内でコマンドを実行するためのコマンドなのだが、上のように使うことでコンテナ内のbashに入れる（[ドキュメントの例にも載ってた](https://docs.docker.com/engine/reference/commandline/exec/#run-docker-exec-on-a-running-container)）。引数の意味がいまいちわかっていない。気が向いたら調べる。

## 参考

- [Reference documentation - docker docs](https://docs.docker.com/reference/)
