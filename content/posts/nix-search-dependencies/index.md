---
title: "Nixのパッケージ・derivationの探り方まとめ"
date: 2024-04-04T09:00:00+09:00
tags: ["derivation", "package", "nix-index", "nix-tree", "nixos"]
categories: ["Nix"]
toc: true
---

Nixで、あるパッケージがどのパッケージに依存しているのかを調べたくなったのを発端に、パッケージやその依存関係の調べ方についていろいろ調べた。

## 前置き

### 用語解説

いろいろとNix固有（？）の言葉が出てくるため、ここでまとめて解説しておく。

[Glossary](https://nixos.org/manual/nix/stable/glossary.html)と[Nix Pills Chapter9](https://nixos.org/guides/nix-pills/automatic-runtime-dependencies)を参考にする。
* [パッケージ](https://nixos.org/manual/nix/stable/glossary.html#package)：ファイルやデータの集まり。
* [derivation](https://nixos.org/manual/nix/stable/glossary.html#gloss-derivation)：何らかのビルドタスクを行うための記述書。端的にはパッケージを作るための仕様書である。次の節で詳しく述べる
  * [output](https://nixos.org/manual/nix/stable/glossary#gloss-output)：derivationから生成されたもの
* [store object](https://nixos.org/manual/nix/stable/glossary#gloss-store-object)：Nixによって管理されているあらゆるオブジェクトをさす。通常は`/nix/store/`に保管されているはず
* [store path](https://nixos.org/manual/nix/stable/glossary#gloss-store-path)：store objectが置かれている場所。通常は`/nix/store/`にあるはず
* [build depencencies](https://nixos.org/guides/nix-pills/automatic-runtime-dependencies#id1399)：ビルドの時点で必要になる依存関係。ビルドに必要なソースコードや、derivationの中で参照されている別のderivationを指す。これはderivationに記載されている
* [runtime dependencies](https://nixos.org/guides/nix-pills/automatic-runtime-dependencies#id1401)：実行時に必要になる依存関係。動的ライブラリや、ほかのパッケージの実行ファイルなどを指す
  * これを検出する方法は素朴で、生成したパッケージをNAR形式で固め、そこに埋め込まれているoutputのパスがruntime dependenciesと判定するだけである
* [NAR (Nix Archive)](https://nixos.org/manual/nix/stable/glossary#gloss-nar)：tarのように複数ファイルを1つのファイルに固めた形式。ただし、同じアーカイブ対象であればまったく同じNARファイルができるように、tarに比べてシンプルなつくりになっている。例えば、tarだとアーカイブする度にタイムスタンプ（`mtime`フィールド）が埋め込まれるが、NARにはそれがない（[参考](https://nixos.org/guides/nix-pills/automatic-runtime-dependencies#id1400)）
  * NARが作られた背景について、[edolstra氏のPh.D論文](https://edolstra.github.io/pubs/phd-thesis.pdf)のp.91が詳しい
  * `nix nar dump-path <ファイル・ディレクトリ名>`で、NAR形式がどんなものか見ることが可能（バイナリなので、odやhexdumpコマンドを嚙ませたほうが見やすいかも）
* [closure](https://nixos.org/manual/nix/stable/glossary#gloss-closure)：あるstore pathに直接または間接的に依存するstore pathの集合
  * 閉包（closure）という名の通り、closureの任意のstore pathについて、それに依存するstore pathは必ずそのclosureの要素になっている（言い換えると、ある要素に対して「その依存関係を列挙する」という操作を定義したとき、closureはその操作について閉じている）

### パッケージのビルドとderivationについて

NixOSを使うとなるとたいていは`configuration.nix`や`home.nix`を設定するだけなので、derivationに触れない場合が多いかもしれないので、一応ここで少し詳細な解説をはさむ。

derivationは、（一つの使い道としては）ビルドの仕様書である。原義としては、[公式doc](https://nixos.org/manual/nix/stable/language/derivations.html)を引用すると、
> a specification for running an executable on precisely defined input files to repeatably produce output files at uniquely determined file system paths

である。「正確に定義された入力ファイルをもとに繰り返し出力ファイルを生成し、一意に定められたシステムパスにそれを配置するための実行ファイルを動かすための仕様書」ということになる。つまり、derivationには、
* 入力
* （何らかの出力を生成する）実行ファイル

を書くことができる。

この特徴はプログラムのビルドに使える。例えば何らかのプログラムをビルドしたいという場合、ライブラリを持ってきて、それをコンパイルして、適当な所に生成物を配置する、という過程を踏むことになる。この情報をderivationに書くことができる。
Nixではあらゆるツールやアプリケーションのビルド方法をderivationで記述する。

もちろん、derivationの定義としては別にビルドに限らず使える。例えば[buildEnv](https://nixos.org/manual/nixpkgs/stable/#sec-building-environment)は、アプリケーションをビルドするのではなく、アプリケーションを集めたディレクトリ構造を生成する。

## あるアプリ・ツールがどのパッケージに収録されているのかを知る

### パッケージ名を推測して調べる場合

* [NixOS Search](https://search.nixos.org/packages)を用いる
* CLI上で調べたいなら、`nix search`コマンドを用いる。例えば`nix search nixpkgs <正規表現>`で、nixpkgsの中から`<正規表現>`に合致するパッケージを検索してくれる。

### インストール済みのバイナリ・ファイルから調べたい場合

すでにアプリ・ツールが自分の環境に入っており、それがどのパッケージに収録されていたのかを特定したい場合。

`which`と`realpath`を組み合わせて、アプリケーションが`/nix/store`のどのディレクトリに配置されているのかを確認する。
```console
bombrary@nixos:~$ realpath `which ls`
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3/bin/coreutils
```

### インストール済みでないバイナリ・ファイルから調べたい場合

まだアプリが自分の環境にインストールされておらず、どのパッケージを入れれば目的のアプリが手に入るのか分からない場合。

その場合は[nix-index](https://github.com/nix-community/nix-index)を使う。

nix-indexを使うためには一度データベースを作成する必要があるが、生成には時間がかかるため、代わりにすでに作成済みのnix-indexである[nix-index-database](https://github.com/nix-community/nix-index-database)を使うとよい。

以下は、lsコマンドの入っているパッケージを検索する例。`-r` 引数をつければ正規表現で検索できる。
```console
bombrary@nixos:~$ nix run github:nix-community/nix-index-database -- -r 'bin/ls$' | head
(zulip.out)                                           0 s /nix/store/lq69lvdricnhah5drlw3114rfc81pwr8-zulip-5.11.0-fhs/usr/bin/ls
(zulip.out)                                           0 s /nix/store/cyadcn0rq5q59ysqvs212y0rhyvf0i7p-zulip-5.11.0-usr-target/bin/ls
(zsnes2.out)                                          0 s /nix/store/997sgfzlfi3794d3b3qgprbkrzh6w7g1-coreutils-9.4/bin/ls
(zettlr.out)                                          0 s /nix/store/c4j1a63mwzb96xym5ncbrvl4nk3wvrgl-zettlr-3.0.2-fhs/usr/bin/ls
...
```

## パッケージがどのderivationでビルドされたのかを知る

`niq-store --query --deriver`を用いる。以下はlsコマンドがどのパッケージに収録されているのかを見る例。
```console
bombrary@nixos:~/deps$ nix-store --query --deriver `which ls`
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
```

derivationファイルの内容を確認したい場合、[nix derivation showコマンド](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-derivation-show)を使う。

以下はlsコマンドが収録されているパッケージのderivationの情報を出力する例。
```console
bombrary@nixos:~$ nix derivation show `which ls`
{
  "/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv": {
    "args": [
      "-e",
      "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"
    ],
    "builder": "/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash",
    "env": {
      ...
    },
    "inputDrvs": {
      "/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "bin"
        ]
      },
      "/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      },
      "/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "out"
        ]
      },
      "/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv": {
        "dynamicOutputs": {},
        "outputs": [
          "dev"
        ]
      }
    },
    "inputSrcs": [
      "/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh",
      "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"
    ],
    "name": "coreutils-full-9.3",
    "outputs": {
      "debug": {
        "path": "/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug"
      },
      "info": {
        "path": "/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info"
      },
      "out": {
        "path": "/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3"
      }
    },
    "system": "x86_64-linux"
  }
}
```

ちなみに、アプリケーションの実行ファイルそのものではなく、直接drvファイルを指定することも可能（その場合は、末尾に `^*` をつけたほうがよいっぽい）。
```sh
nix derivation show /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv^*
```

なお、`nix derivation show` コマンドは `/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv` をJSONで分かりやすく出力しているに過ぎず、drvファイル自体はATermという形式で書かれている（[参考](https://nixos.org/manual/nix/stable/protocols/derivation-aterm)）。これをJSONに変換して出力している。生のデータを見てみたいなら直接 `cat` で見てみるとよい。以下はcoreutilsの結果（分かりやすく改行している）。
```console
bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].key'
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv

bombrary@nixos:~$ nix derivation show `which ls` | jq -r 'to_entries[].key' | xargs cat
Derive(
 [("debug","/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug","",""),
  ("info","/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info","",""),
  ("out","/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3","","")],
 [("/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv",["out"]),
  ("/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv",["dev"]),
  ("/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv",["dev"]),
  ("/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv",["bin"]),
  ("/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv",["dev"]),
  ("/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv",["out"]),
  ("/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv",["out"]),
  ("/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv",["out"]),
  ("/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv",["out"]),
  ("/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv",["dev"])],
 ["/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh",
  "/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"],
 "x86_64-linux",
 "/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash",
 ["-e","/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh"],
 [("FORCE_UNSAFE_CONFIGURE",""),
  ("NIX_CFLAGS_COMPILE",""),
  ("NIX_LDFLAGS",""),
  ("__structuredAttrs",""),
  ("buildInputs","/nix/store/hwb08pf2byl2a1rnmaxq56f389h6b6yn-acl-2.3.1-dev /nix/store/djciacxl96yr2wd02lcxyn8z046fzrqr-attr-2.5.1-dev /nix/store/1fszsmhmlhbi4yzl2wgi08cfw0dng7pq-gmp-with-cxx-6.3.0-dev /nix/store/2d8yhfx7f2crn8scyzdk6dg3lw7y1ifh-openssl-3.0.12-dev"),
  ("builder","/nix/store/7dpxg7ki7g8ynkdwcqf493p2x8divb4i-bash-5.2-p15/bin/bash"),
  ("cmakeFlags",""),
  ("configureFlags","--with-packager=https://nixos.org --enable-single-binary=symlinks --with-openssl gl_cv_have_proc_uptime=yes"),
  ("debug","/nix/store/b073nwng2fy24zaqbdx6zbimxkad7dyk-coreutils-full-9.3-debug"),
  ("depsBuildBuild",""),
  ("depsBuildBuildPropagated",""),
  ("depsBuildTarget",""),
  ("depsBuildTargetPropagated",""),
  ("depsHostHost",""),
  ("depsHostHostPropagated",""),
  ("depsTargetTarget",""),
  ("depsTargetTargetPropagated",""),
  ("doCheck","1"),
  ("doInstallCheck",""),
  ("enableParallelBuilding","1"),
  ("enableParallelChecking","1"),
  ("enableParallelInstalling","1"),
  ("info","/nix/store/1pd076gkjwh0wdv8cnxy6p7kl141jnk2-coreutils-full-9.3-info"),
  ("mesonFlags",""),
  ("name","coreutils-full-9.3"),
  ("nativeBuildInputs","/nix/store/nsl35d8x8jp0vy8n4xy8sx9v68gdh444-autoreconf-hook /nix/store/rza0ib08brnkwx75n7rncyjq97j76ris-perl-5.38.2 /nix/store/3q6fnwcm677l1q60vkhcf9m1gxhv83jm-xz-5.4.4-bin /nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh"),
  ("out","/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3"),
  ("outputs","out info debug"),
  ("patches",""),
  ("pname","coreutils-full"),
  ("postInstall",""),
  ("postPatch","# The test tends to fail on btrfs, f2fs and maybe other unusual filesystems.\nsed '2i echo Skipping dd sparse test && exit 77' -i ./tests/dd/sparse.sh\nsed '2i echo Skipping du threshold test && exit 77' -i ./tests/du/threshold.sh\nsed '2i echo Skipping cp reflink-auto test && exit 77' -i ./tests/cp/reflink-auto.sh\nsed '2i echo Skipping cp sparse test && exit 77' -i ./tests/cp/sparse.sh\nsed '2i echo Skipping rm deep-2 test && exit 77' -i ./tests/rm/deep-2.sh\nsed '2i echo Skipping du long-from-unreadable test && exit 77' -i ./tests/du/long-from-unreadable.sh\n\n# Some target platforms, especially when building inside a container have\n# issues with the inotify test.\nsed '2i echo Skipping tail inotify dir recreate test && exit 77' -i ./tests/tail-2/inotify-dir-recreate.sh\n\n# sandbox does not allow setgid\nsed '2i echo Skipping chmod setgid test && exit 77' -i ./tests/chmod/setgid.sh\nsubstituteInPlace ./tests/install/install-C.sh \\\n  --replace 'mode3=2755' 'mode3=1755'\n\n# Fails on systems with a rootfs. Looks like a bug in the test, see\n# https://lists.gnu.org/archive/html/bug-coreutils/2019-12/msg00000.html\nsed '2i print \"Skipping df skip-rootfs test\"; exit 77' -i ./tests/df/skip-rootfs.sh\n\n# these tests fail in the unprivileged nix sandbox (without nix-daemon) as we break posix assumptions\nfor f in ./tests/chgrp/{basic.sh,recurse.sh,default-no-deref.sh,no-x.sh,posix-H.sh}; do\n  sed '2i echo Skipping chgrp && exit 77' -i \"$f\"\ndone\nfor f in gnulib-tests/{test-chown.c,test-fchownat.c,test-lchown.c}; do\n  echo \"int main() { return 77; }\" > \"$f\"\ndone\n\n# intermittent failures on builders, unknown reason\nsed '2i echo Skipping du basic test && exit 77' -i ./tests/du/basic.sh\n"),
  ("preInstall",""),
  ("propagatedBuildInputs",""),
  ("propagatedNativeBuildInputs",""),
  ("separateDebugInfo","1"),
  ("src","/nix/store/8f1x5yr083sjbdkv33gxwiybywf560nz-coreutils-9.3.tar.xz"),
  ("stdenv","/nix/store/kv5wkk7xgc8paw9azshzlmxraffqcg0i-stdenv-linux"),
  ("strictDeps",""),
  ("system","x86_64-linux"),
  ("version","9.3")]
)
```

## derivationのbuild dependenciesを知る

`nix derivation show` コマンドで出力されたJSON結果のうち、`inputDrvs`と`inputSrcs`に書かれているものがそれである。

```console
bombrary@nixos:~/deps$ nix derivation show `which ls` | jq -r 'to_entries[].value | (.inputDrvs | to_entries[].key),(.inputSrcs[])' | sort
/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv
/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv
/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv
/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv
/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv
/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv
/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv
/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv
/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv
```

上記のように調べてもよいが、`nix-store --query --references`のほうがシンプルな解決策かもしれない。`--references`オプションを用いることで、derivationに直接依存する入力を検索する。

```console
bombrary@nixos:~/deps$ nix-store --query --references /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | sort
/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv
/nix/store/9jcfzyyb0h86mvc31s9qmxs6lncqrwhc-acl-2.3.1.drv
/nix/store/akpwym6q116hivciyq2vqj9n5jk9f5i6-xz-5.4.4.drv
/nix/store/d1qldhg6iix84bqncbzml2a1nw8p95bg-gmp-with-cxx-6.3.0.drv
/nix/store/ks5ivc59k57kwii93qlsfgcx2a7xma1k-autoreconf-hook.drv
/nix/store/mnrjvk62d35v8514kc5w31fg3py0smr8-coreutils-9.3.tar.xz.drv
/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv
/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv
/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
/nix/store/wd100hlzyh5w9zkfljkaagp87b7h7733-openssl-3.0.12.drv
```

さらに深い階層をインタラクティブに確認したい、という場合には、[nix-tree](https://github.com/utdemir/nix-tree)を使うとよい。

## derivationの間接的なbuild dependenciesもすべて知る

`nix-store --query --requisites`で可能。`--requisites`をつけることで、依存関係の[閉包（closure）](https://nixos.org/manual/nix/stable/glossary#gloss-closure)を求めることができる。
閉包という名のとおり、このコマンドで出力されたdrvの集合に対して、どのdrvもそれに依存するdrvが集合の中に存在する（つまり集合の中で「閉じている」という状態）。

```console
bombrary@nixos:~/deps$ nix-store --query --requisites /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | sort
/nix/store/001gp43bjqzx60cg345n2slzg7131za8-nix-nss-open-files.patch
/nix/store/00qr10y7z2fcvrp9b2m46710nkjvj55z-update-autotools-gnu-config-scripts.sh
/nix/store/03glsh6vz72mzrwf22w4p7a6aasa3f8n-python-setup-hook.sh.drv
/nix/store/0b8qs04dfrc3ni8b1xkzsvb0rj85ji4j-libssh2-1.11.0.drv
/nix/store/0bmmg6xn0jnicvp7jk099k6356n32m0k-lambda-ICE-PR109241.patch
/nix/store/0df8rz15sp4ai6md99q5qy9lf0srji5z-0001-Revert-libtool.m4-fix-nm-BSD-flag-detection.patch
/nix/store/0fakyqwlvwjpqshals88ax5f6n2lff3p-locales-setup-hook.sh.drv
/nix/store/0khd36ikc7fqqkdzk5fjrnrmanlsq7rv-python-setup-hook.sh.drv
/nix/store/0x1r5kahv0xjkqa7n3v862dc8b2n25q6-python3-minimal-3.11.6.drv
/nix/store/0y5flakfvnf813cwrr8rygf1jnk0gfnc-CVE-2019-13636.patch
...
```

ツリー形式で出力したいなら、`nix-store --query --tree`で可能。 `[...]` で省略されているものはおそらく、同じ出力が出ないようにキャッシュされているもの（いわゆる枝狩り）。

```console
bombrary@nixos:~/deps$ nix-store --query --tree /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | head
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
├───/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
├───/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
├───/nix/store/98sv0g544bqmks49d6vgylbkh9sccdvm-attr-2.5.1.drv
│   ├───/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
│   │   ├───/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
│   │   ├───/nix/store/bzq60ip2z5xgi7jk6jgdw8cngfiwjrcm-bootstrap-tools.tar.xz.drv
│   │   └───/nix/store/i9nx0dp1khrgikqr95ryy2jkigr4c5yv-unpack-bootstrap-tools.sh
│   ├───/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh [...]
│   ├───/nix/store/5w8l933if7cnsw59hjq6iyhl1xshcs84-gettext-0.21.1.drv
...
```

## パッケージのruntime dependenciesを知る

これも`nix-store --query --references`で可能。drvではなくバイナリのパスを指定すれば、それに依存するruntime dependenciesを知ることができる。

```console
bombrary@nixos:~/deps$ nix-store --query --references `which ls`
/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27
/nix/store/9vv53vzx4k988d51xfiq2p46fqrjshv0-gmp-with-cxx-6.3.0
/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1
/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12
/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
```

## パッケージの間接的なruntime dependenciesもすべて知る

これも`nix-store --query --requisites`で可能。drvではなくバイナリのパスを指定すれば、それに依存するruntime dependenciesを知ることができる。

```console
bombrary@nixos:~/deps$ nix-store --query --requisites `which ls`
/nix/store/iyw6mm7a75i49h9szc0m08ynay1p7kka-gcc-12.3.0-libgcc
/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1
/nix/store/4h5isrbr87jjw69rgdnhi8psi7hhk5im-libidn2-2.3.4
/nix/store/fhws3x2s9j5932r6ah660nsh41bkrq27-xgcc-12.3.0-libgcc
/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27
/nix/store/giyri337jb6sa1qyff6qp771qfq10yhf-gcc-12.3.0-lib
/nix/store/9vv53vzx4k988d51xfiq2p46fqrjshv0-gmp-with-cxx-6.3.0
/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1
/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12
/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
```
