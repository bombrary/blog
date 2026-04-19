---
title: "Nixで作るdocker image - buildEnvについて"
date: 2026-04-19T14:55:00+09:00
tags: ["docker", "buildEnv"]
categories: ["Nix"]
---

## 要約

この記事では、Nixでdocker imageを作成する例を通して、NixのbuildEnvとは何か、それを使ってどのようにdocker imageが作成されるのか、について述べる。

要約としては以下の通り。
* buidEnvは、[directoryであるようなfile system object](https://nix.dev/manual/nix/2.24/store/file-system-object)を統合した新しいパッケージを作成する
  * binとかlibとかのディレクトリにいろんなパッケージが入ることになる
* dockerTools.buildImageは、buildEnvでまとめたパッケージをルートディレクトリに配置してdocker imageを作成する


## Nixを用いたdocker imageの作り方

Nixでは、docker imageをDockerfileではなくNix言語を使って書ける。具体的には、[dockerTools.buildImage](https://nixos.org/manual/nixpkgs/stable/#ssec-pkgs-dockerTools-buildImage)という関数を用いてパッケージを作成する。Dockerfileを使う場合との違いは、もちろんNix言語で宣言的にパッケージ構成が書ける点と、image内に入れるツールとしてnixpkgsに登録されているものが使える点である。

まずは例として、Pythonが入ったdocker imageを作ってみよう。ただし、Pythonだけでなくbashや、lsコマンドも使えるようにする。

ベースとして `flake.nix` を次のようにする。今回は docker image を `docker-example` というパッケージとしてビルドする。実際の定義は `docker-example.nix` に記載する。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in
  {
    packages.x86_64-linux.docker-example = import ./docker-example.nix { inherit pkgs; };
  };
}
```

そして `docker-example.nix` では以下のようにする。
* `name` と `tag` に、docker imageの名前とタグを指定する
* `copyToRoot` に、docker imageに配置すべきパッケージを設定する。これには `buildEnv` を用いる
* `config` に、コンテナとして動作させた場合のコマンドの設定やworking directoryの設定をする
```nix
{ pkgs }:
  pkgs.dockerTools.buildImage {
    name = "docker-example";
    tag = "latest";
    created = "now";
    copyToRoot = pkgs.buildEnv {
      name = "my-env";
      paths = with pkgs; [
        python3
        bash
        coreutils
      ];
    };
    config = {
      Cmd = [ "/bin/python" ];
      WorkingDir = "/";
    };
  }
```

その他有用なコマンドとして以下がある。引数はたくさんあるので、詳しくはdockerTools.buildImageの[Inputs](https://nixos.org/manual/nixpkgs/stable/#ssec-pkgs-dockerTools-buildImage-inputs)や[dockerTools](https://nixos.org/manual/nixpkgs/stable/#sec-pkgs-dockerTools)で定義されている関数の各種Examplesを参照。
* `fromImage`： Dockerfileの`FROM`文と同じで、ベースイメージを指定する。これが未指定の場合は `FROM scratch` と同じ状態になる
  * [dockerTools.pullImage](https://nixos.org/manual/nixpkgs/stable/#ssec-pkgs-dockerTools-pullImage)をここに指定するケースがほとんどかも
* `extraCommands`： ビルド終了時に実行するbashスクリプトを書く。何かファイルやディレクトリを作っておきたい場合とかに使えるかも

docker imageのビルドは以下のようにする（これが `docker build` に対応するコマンド）。
```sh
nix build '.#docker-example'
```

すると、ビルド生成物として `.tar.gz` （へのsymbolic link）が出来上がる。
```console
[bombrary@nixos:~/docker-example]$ ls -la ./result
lrwxrwxrwx - bombrary 23 Sep 17:33  ./result -> /nix/store/d8z33ww71hq81rax0dkg9s2zdsxks63i-docker-image-docker-example.tar.gz
```

これを `docker load` で読み込ませれば、docker imageとして使えるようになる。
```console
[bombrary@nixos:~/docker-example]$ docker load < result
55cb75bf2c49: Loading layer [==================================================>]  319.5MB/319.5MB
Loaded image: docker-example:latest

[bombrary@nixos:~/docker-example]$ docker run --rm -it docker-example:latest
Python 3.12.5 (main, Aug  6 2024, 19:08:49) [GCC 13.3.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
```

試しにbashでどんなファイルが生成されてるのか見てみよう。
```console
[bombrary@nixos:~/docker-example]$ docker run --rm -it docker-example:latest bash

bash-5.2# ls
bin  dev  etc  include  lib  libexec  nix  proc  share  sys

bash-5.2# ls -la bin
total 500
dr-xr-xr-x 2 0 0 4096 Jan  1  1980  .
drwxr-xr-x 1 0 0 4096 Sep 23 08:36  ..
lrwxrwxrwx 1 0 0   67 Jan  1  1980  2to3 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/2to3
lrwxrwxrwx 1 0 0   72 Jan  1  1980  2to3-3.12 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/2to3-3.12
lrwxrwxrwx 1 0 0   63 Jan  1  1980 '[' -> '/nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/['
lrwxrwxrwx 1 0 0   67 Jan  1  1980  b2sum -> /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/b2sum
lrwxrwxrwx 1 0 0   68 Jan  1  1980  base32 -> /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/base32
...

[bombrary@nixos:~/docker-example]$ docker run --rm -it docker-example:latest bash
bash-5.2# ls -la /nix/store
total 116
dr-xr-xr-x 29 0 0 4096 Jan  1  1980 .
dr-xr-xr-x  3 0 0 4096 Jan  1  1980 ..
dr-xr-xr-x  4 0 0 4096 Jan  1  1980 0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5
dr-xr-xr-x  4 0 0 4096 Jan  1  1980 1w90l4fm5lzhlybipfilyjij2das6w98-openssl-3.0.14
dr-xr-xr-x  4 0 0 4096 Jan  1  1980 22nxhmsfcv2q2rpkmfvzwg2w5z1l231z-gcc-13.3.0-lib
dr-xr-xr-x  6 0 0 4096 Jan  1  1980 3dyw8dzj9ab4m8hv5dpyx7zii8d0w6fi-glibc-2.39-52
dr-xr-xr-x  4 0 0 4096 Jan  1  1980 3hxxbbjc8r66nravvjind6ixhz7cpij1-mpdecimal-4.0.0
```

どうやら、docker imageのファイルたちも `/nix/store` で管理されているようだ。

## buildEnvの仕組みと役割

`dockerTools.buildImage` への引数として `copyToRoot = pkgs.buildEnv { ... }` を指定したが、この `buildEnv` は複数のパッケージをまとめて1つのパッケージにするために用いられる。

試しに、`buildEnv`の生成物と生成元を調べてみよう。まずその定義は以下のようなものであった。
* パッケージ名は `my-env` である
* python3とbashとcoreutilsを混ぜて1つのパッケージを作成する
```nix
pkgs.buildEnv {
  name = "my-env";
  paths = with pkgs; [
    python3
    bash
    coreutils
  ];
};
```

まずは生成物から調べる。`my-env`がパッケージ名なのだから、これが`/nix/store`下に生成されているはずである。調べよう。以下のように、`dockerTools.buildImage` の生成物からそのderivationを特定し、そこからbuild dependenciesを調べ、`my-env`のderivationを探す。
```console
[bombrary@nixos:~/docker-example]$ nix-store --query --deriver ./result
/nix/store/j10avwx9ns3pjcdzkyncyxig21r0l3xh-docker-image-docker-example.tar.gz.drv

[bombrary@nixos:~/docker-example]$ nix-store --query --requisites /nix/store/j10avwx9ns3pjcdzkyncyxig21r0l3xh-docker-image-docker-example.tar.gz.drv | grep my-env
/nix/store/r7ykbl49lmzp8rfzdnqw30vi9gnp81yq-my-env.drv
```

そしてそのderivationの生成物を見つける。これが`my-env`の実体である。
```console
[bombrary@nixos:~/docker-example]$ nix-store --query --outputs /nix/store/r7ykbl49lmzp8rfzdnqw30vi9gnp81yq-my-env.drv
/nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env
```

lsで中身を覗いてみると、dockerのコンテナの中で見たものと同じものが見えるはずだ。
```console
[bombrary@nixos:~/docker-example]$ ls /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env
 bin   include   lib   libexec   share

[bombrary@nixos:~/docker-example]$ ls /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env/bin -la
lrwxrwxrwx - root  1 Jan  1970  2to3 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/2to3
lrwxrwxrwx - root  1 Jan  1970  2to3-3.12 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/2to3-3.12
lrwxrwxrwx - root  1 Jan  1970  [ -> /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/[
lrwxrwxrwx - root  1 Jan  1970  b2sum -> /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/b2sum
...
```

続いて生成元となるパッケージを調べよう。今度は`my-env`のruntime dependenciesを調べる。
```console
[bombrary@nixos:~/docker-example]$ nix-store --query --references /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env
/nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5
/nix/store/8806c307rqnjcaqk9xfi8c9yzr05xs75-bash-5.2p32-man
/nix/store/izpf49b74i15pcr9708s3xdwyqs4jxwl-bash-5.2p32
/nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5
```

これらをlsで調べてみると、各パッケージの中で `/bin` や `/lib` が作成されていることが確認できる。
```console
[bombrary@nixos:~/docker-example]$ ls /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5
 bin   include   lib   nix-support   share

[bombrary@nixos:~/docker-example]$ ls /nix/store/izpf49b74i15pcr9708s3xdwyqs4jxwl-bash-5.2p32
 bin   lib

[bombrary@nixos:~/docker-example]$ ls /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5
 bin   libexec


[bombrary@nixos:~/docker-example]$ ls /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin
 2to3   2to3-3.12   idle   idle3   idle3.12   pydoc   pydoc3   pydoc3.12   python   python-config   python3   python3-config   python3.12   python3.12-config

[bombrary@nixos:~/docker-example]$ ls /nix/store/izpf49b74i15pcr9708s3xdwyqs4jxwl-bash-5.2p32/bin
 bash   sh

[bombrary@nixos:~/docker-example]$ ls /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin
 [          basenc   chown       cp       df          echo     false    hostid    link      mkdir    nice     od        printenv   realpath   sha1sum     shred   stat     tac       touch      tty        uptime   whoami
 b2sum      cat      chroot      csplit   dir         env      fmt      id        ln        mkfifo   nl       paste     printf     rm         sha224sum   shuf    stdbuf   tail      tr         uname      users    yes
 base32     chcon    cksum       cut      dircolors   expand   fold     install   logname   mknod    nohup    pathchk   ptx        rmdir      sha256sum   sleep   stty     tee       true       unexpand   vdir
 base64     chgrp    comm        date     dirname     expr     groups   join      ls        mktemp   nproc    pinky     pwd        runcon     sha384sum   sort    sum      test      truncate   uniq       wc
 basename   chmod    coreutils   dd       du          factor   head     kill      md5sum    mv       numfmt   pr        readlink   seq        sha512sum   split   sync     timeout   tsort      unlink     who
```

そして`my-env`に戻ると、上記で調べたファイルたちが`my-env`にも存在し、symbolic linkとして作成されていることが分かる。
```console
[bombrary@nixos:~/docker-example]$ ls /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env/bin -la | grep /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3
lrwxrwxrwx - root  1 Jan  1970 python3 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3
lrwxrwxrwx - root  1 Jan  1970 python3-config -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3-config
lrwxrwxrwx - root  1 Jan  1970 python3.12 -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3.12
lrwxrwxrwx - root  1 Jan  1970 python3.12-config -> /nix/store/h3i0acpmr8mrjx07519xxmidv8mpax4y-python3-3.12.5/bin/python3.12-config

[bombrary@nixos:~/docker-example]$ ls /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env/bin -la | grep /nix/store/izpf49b74i15pcr9708s3xdwyqs4jxwl-bash-5.2p32/bin/bash
lrwxrwxrwx - root  1 Jan  1970 bash -> /nix/store/izpf49b74i15pcr9708s3xdwyqs4jxwl-bash-5.2p32/bin/bash

[bombrary@nixos:~/docker-example]$ ls /nix/store/v6bnvh23256rnpppg8zqvhrp4dxis498-my-env/bin -la | grep /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/ls
lrwxrwxrwx - root  1 Jan  1970 ls -> /nix/store/0kg70swgpg45ipcz3pr2siidq9fn6d77-coreutils-9.5/bin/ls
```

このことから、`buildEnv`は、複数のパッケージの`/bin`や`/lib`などを1つの統合してパッケージを作成するための関数といえる。


## docker imageの作成過程でやっていること

ここまでの調査から、`dockerTools.buildImage` で行っていることは以下であると思われる。
1. buildEnvで作成されたファイルやディレクトリをimageのルートディレクトリにコピーする
2. 1で存在するsymbolic linkが機能するように、image内に `/nix/store` を作り、必要なruntime dependenciesをそこにコピーする

2の過程があるので、`dockerTools.buildImage`はその生成物だけで完結するようにできており、runtime dependenciesは存在しない。実際`nix-store --query`で調べてみると、runtime dependenciesは自分自身しかいないことが分かる。
```console
[bombrary@nixos:~/docker-example]$ nix-store --query --requisites result
/nix/store/d8z33ww71hq81rax0dkg9s2zdsxks63i-docker-image-docker-example.tar.gz
```

## baseイメージを指定した場合はどうか

baseImageとしてalpineを使ってビルドしてみる。これには[dockerTools.pullImage](https://nixos.org/manual/nixpkgs/stable/#ex-dockerTools-pullImage-nixprefetchdocker)を使う。
* `fromImage = pkgs.dockerTools.pullImage { ... }` のところで設定
    * 必須要素として、image名、imageのハッシュ（`imageDigest`）、nix/storeにfetchしてきたときのoutputHash（`sha256`）を指定する
    * `sha256` についてはわからないので、初回は `lib.fakeHash` としておく

```nix
{ pkgs }:
  pkgs.dockerTools.buildImage {
    name = "docker-example";
    tag = "latest";
    created = "now";
    fromImage = pkgs.dockerTools.pullImage {
      imageName = "alpine";
      imageDigest = "sha256:9b9ebaba5ccb78ee301bec0b365d4d014973b05bd77a7bf59cb18f8b160a09c4";
      sha256 = pkgs.lib.fakeHash;
    };
    copyToRoot = pkgs.buildEnv {
      name = "my-env";
      paths = with pkgs; [
        python3
        bash
        coreutils
      ];
    };
    config = {
      Cmd = [ "/bin/python" ];
      WorkingDir = "/";
    };
  }
```

初回はビルドすると `sha256` に設定するべきhashが設定できていないとエラーになる。 `got: ...` に記載のものを `sha256` に設定しなおし再ビルドする。
```console
bombrary@nixos:~/docker-example% nix build '.#docker-example'
error: hash mismatch in fixed-output derivation '/nix/store/vak90icvcmlr0mwajhpkg6dg9yz3qj0j-docker-image-alpine-latest.tar.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    sha256-87nEajeTggC4AkkpkpLTm8+qfWS6oG6sDZvPCVIUG8c=
error: 1 dependencies of derivation '/nix/store/8l0alnwzdj8rjfzv87mzp5b8si4vmqwx-docker-image-docker-example.tar.gz.drv' failed to build
```

これでビルド・ロードしてみると、Loading layerにて2つのlayerが読まれていることがわかる。おそらく1つ目がbaseイメージで、そのあとがnix buildで同封したパッケージ分のイメージだと思われる。
```console
bombrary@nixos:~/docker-example% nix build '.#docker-example'
bombrary@nixos:~/docker-example% docker load < result
71c8e6069532: Loading layer [==================================================>]  7.495MB/7.495MB
55cb75bf2c49: Loading layer [==================================================>]  319.5MB/319.5MB
Loaded image: docker-example:latest
bombrary@nixos:~/docker-example%
```

そして、alpineイメージに同封されていたバイナリとnixファイルで設定したパッケージのバイナリが混在して配置されていることがわかる。
```console
bash-5.3# ls /bin/ -la
total 1300
dr-xr-xr-x 1 root root   4096 Jan  1  1980  .
drwxr-xr-x 1 root root   4096 Apr 19 05:30  ..
lrwxrwxrwx 1 root root     64 Jan  1  1980 '[' -> '/nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/['
lrwxrwxrwx 1 root root     12 Apr 15 04:51  arch -> /bin/busybox
lrwxrwxrwx 1 root root     12 Apr 15 04:51  ash -> /bin/busybox
lrwxrwxrwx 1 root root     68 Jan  1  1980  b2sum -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/b2sum
lrwxrwxrwx 1 root root     69 Jan  1  1980  base32 -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/base32
lrwxrwxrwx 1 root root     69 Jan  1  1980  base64 -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/base64
lrwxrwxrwx 1 root root     71 Jan  1  1980  basename -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/basename
lrwxrwxrwx 1 root root     69 Jan  1  1980  basenc -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/basenc
lrwxrwxrwx 1 root root     75 Jan  1  1980  bash -> /nix/store/sfvyavxai6qvzmv9p9x6mp4wwdz4v41m-bash-interactive-5.3p9/bin/bash
lrwxrwxrwx 1 root root     78 Jan  1  1980  bashbug -> /nix/store/sfvyavxai6qvzmv9p9x6mp4wwdz4v41m-bash-interactive-5.3p9/bin/bashbug
lrwxrwxrwx 1 root root     12 Apr 15 04:51  bbconfig -> /bin/busybox
-rwxr-xr-x 1 root root 820500 Dec 16 14:19  busybox
lrwxrwxrwx 1 root root     66 Jan  1  1980  cat -> /nix/store/74sind1d6vf2bfwd7yklg8chsvzqxmmq-coreutils-9.10/bin/cat
lrwxrwxrwx 1 root root     12 Apr 15 04:51  chattr -> /bin/busybox
```

## arionについて

## まとめ

NixのbuildEnvとは何か、それを使ってどのようにdocker imageが作成されるのかについて調べた。

ほかに面白そうな話題として [arion](https://docs.hercules-ci.com/arion/) というのがあるが、これはまた気が向いたら触ってみて別の記事にする。
