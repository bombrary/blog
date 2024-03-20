---
title: "Nixの外でビルドされた実行バイナリを動かすメモ"
date: 2024-02-18T21:10:00+09:00
tags: ["Rye"]
categories: ["NixOS"]
toc: true
---

## 前置き

NixOSはNixOSの内側で生活するには十分快適だが、その外で作成されたソフトウェアを持ってこようとすると、途端にめんどくさくなる。その例として
* 動的リンカのパスが解決できず実行バイナリが動かない
* shebangのパスが解決できずシェルスクリプトが実行できない

が挙げられるが、今回は前者の話をする。その解決方法としてpatchelfとnix-ldがあるのでそれを紹介する（後者は[envfs](https://github.com/Mic92/envfs)で解決可能だが、もしかしたら後日記事にまとめるかも）

この件についてはすでにZennでまとめてくださっている人がいる（参考：[NixOS に関する小ネタ集](https://zenn.dev/link/comments/8b1875820711d7)）し、なんなら[nix-ldの製作者のブログ](https://blog.thalheim.io/2022/12/31/nix-ld-a-clean-solution-for-issues-with-pre-compiled-executables-on-nixos/)でほぼ同じ内容の記事を書かれていた。が、今一度自分も整理のため、具体的にぶち当たった事例も含めて書いておこうと思う。

## 要約

* [nix-ld](https://github.com/Mic92/nix-ld)を導入すれば、NixOS外の実行バイナリが動くようになる
* 共有ライブラリが足りないなどのエラーが出た場合は、`LD_LIBRARY_PATH`を指定する
  * `nix develop`で上記環境変数が設定されるようにnixファイルを書いたほうが良い

## 経緯

Pythonのプロジェクト管理ツールである[Rye](https://github.com/mitsuhiko/rye)を使いたくなった（もちろんNixOSを使っているんだからRyeを使わず全部nixファイルで管理しろ、と言われればその通りなのだが、それはおいおい勉強しようと思う…）

Ryeはまだ盛んに開発されており、まだまだ今後変わりうる可能性があるが、現バージョン（0.24.0）で試しに使ってみよう。nixの場合、以下のコマンドで一時的にRyeを入れて実行可能だ。
```sh
nix run nixpkgs#rye
```

プロンプトに従って進めていく。
```console
[bombrary@nixos:~/python/bin]$ nix run nixpkgs#rye
Welcome to Rye!

Rye has detected that it's not installed on this computer yet and
automatically started the installer for you.  For more information
read https://rye-up.com/guide/installation/

This installer will install rye to /home/bombrary/.rye
This path can be changed by exporting the RYE_HOME environment variable.

Details:
  Rye Version: 0.24.0
  Platform: linux (x86_64)

✔ Continue? · yes
✔ Select the preferred package installer · pip-tools (slow but stable)
✔ Determine Rye's python Shim behavior outside of Rye managed projects · Make Rye's own Python distribution available
✔ Which version of Python should be used as default toolchain? · cpython@3.12
```

ところが、最後のcpython@3.12.1のダウンロード後、No such file or directory という一見謎のエラーで終了する。
```console
Installed binary to /home/bombrary/.rye/shims/rye
Bootstrapping rye internals
Downloading cpython@3.12.1
Checking checksum
success: Downloaded cpython@3.12.1
error: unable to create self venv using /home/bombrary/.rye/py/cpython@3.12.1/install/bin/python3. It might be that the used Python build is incompatible with this machine. For more information see https://rye-up.com/guide/installation/

Caused by:
    No such file or directory (os error 2)
```

このエラーの原因を確かめ、解決するために、今回いろいろ調査を行った。

## エラーの原因の調査

まず次のエラー文に注目する。`~/.rye/py/cpython@3.12.1/install/bin/python3`を実行してエラーが出たように見える。

```
error: unable to create self venv using /home/bombrary/.rye/py/cpython@3.12.1/install/bin/python3. 
```

このcpython@3.12.1は、Ryeが外部からDLしてきたstandalone版のpythonビルドである。これについて、[Philosophy and Vision - Rye](https://rye-up.com/philosophy/)を見ると、次のようにある。
> **No System Python**: I can't deal with any more linux distribution weird Python installations or whatever mess there is on macOS. I used to build my own Pythons that are the same everywhere, now I use indygreg's Python builds. Rye will automatically download and manage Python builds from there. No compiling, no divergence.

実は以前のRye古いバージョン（少なくとも、2023年の4月頃？）は、ユーザの環境でPythonのビルドを行っていたはずだが、最近のバージョンではビルド済みのバイナリ[python-build-standalone](https://github.com/indygreg/python-build-standalone)を持ってきているようだ。その実行バイナリをNixOS上で実行するとエラーが出るようだ。

ここからはRyeの話とは離れて、「なぜstandalone版のpythonが実行できないのか、どうすれば実行できるようになるのか」を調べていく。そのために、pythonのstandaloneをDLしてくる。
```console
[bombrary@nixos:~]$ curl -LO https://github.com/indygreg/python-build-standalone/releases/download/20240107/cpython-3.12.1+20240107-x86_64-unknown-linux-gnu-install_only.tar.gz
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
  0     0    0     0    0     0      0      0 --:--:-- --:--:-- --:--:--     0
100 64.6M  100 64.6M    0     0  17.0M      0  0:00:03  0:00:03 --:--:-- 24.5M

[bombrary@nixos:~]$ tar -xzf cpython-3.12.1+20240107-x86_64-unknown-linux-gnu-install_only.tar.gz
[bombrary@nixos:~]$ cd python/bin

[bombrary@nixos:~/python/bin]$ ls
2to3  2to3-3.12  idle3  idle3.12  pip  pip3  pip3.12  pydoc3  pydoc3.12  python3  python3-config  python3.12  python3.12-config
```

実行してみると、`required file not found` という、先ほどの`No such file or directory`と同じようなエラーが出てくる。
```console
[bombrary@nixos:~/python/bin]$ ./python3.12
-bash: ./python3.12: cannot execute: required file not found
```

straceを実行して、どんなシステムコールが呼び出されているのかを確認する。しかし、一番初めの `execve` の時点で `ENOENT` が出ている。
```console
[bombrary@nixos:~/python/bin]$ strace -f ./python3.12
execve("./python3.12", ["./python3.12"], 0x7ffe18d43b58 /* 45 vars */) = -1 ENOENT (No such file or directory)
strace: exec: No such file or directory
+++ exited with 1 +++
```

結局、`python3.12` をそのまま実行しても、`strace` で確認しても、結局「ファイルが無い」と言われるだけで、具体的に何のファイルが足りないのか教えてくれない。
ここまで来るともう`execve`のコードを読みに行くしかない。読みに行ってもよいのだが、「execve NOENT」とかでググるとピンポイントの記事が見つかる。

[ENOENT on a file that exists. Why? - StackExchange](https://superuser.com/questions/507022/enoent-on-a-file-that-exists-why)

要するに、これが出る場合は、本当に実行ファイルが無いか、**interpreterが無いか** のどちらかである。

interpreterというのは何だろうか。`file`コマンドを実行すると、以下の情報がわかる。
* ELFという実行ファイル形式である
* interpreterは`/lib64/ld-linux-x86-64.so.2`である（後述）
```console
[bombrary@nixos:~/python/bin]$ nix run nixpkgs#file -- python3.12
python3.12: ELF 64-bit LSB executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, for GNU/Linux 2.6.32, with debug_info, not stripped
```

ELF（Executable and Linkable Format）というのはLinuxで現在標準的に使われている実行ファイルの形式である。ELFの細かい仕様についてはほかの文献を参照してもらうことにして、その中身を確認してみよう。NixOSの場合、`binutils`パッケージに`readelf`があるので、それを使う。`-a`引数ですべての要素を出力する。
```console
[bombrary@nixos:~/python/bin]$ nix shell nixpkgs#binutils --command readelf -a ./python3.12
```

`readelf`は、ELFファイルに関する様々な情報を出力してくれる。なにやらいろいろと情報が出てきたが、ここでは以下の部分に注目する。

```console
Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x00000000003ff040 0x00000000003ff040
                 0x00000000000002a0 0x00000000000002a0  R      0x8
  LOAD           0x0000000000000000 0x00000000003ff000 0x00000000003ff000
                 0x0000000000001000 0x0000000000001000  RW     0x1000
  INTERP         0x0000000000000560 0x00000000003ff560 0x00000000003ff560
                 0x000000000000001c 0x000000000000001c  R      0x1
      [Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]
  NOTE           0x0000000000000580 0x00000000003ff580 0x00000000003ff580
                 0x0000000000000020 0x0000000000000020  R      0x4
```

Program Headersという項目のINTERPのところで、`/lib64/ld-linux-x86-64.so.2` というinterpreterを要求していることがわかる。

で、`ld-linux-x86-64.so.2`とは何なのかというと、動的リンカと呼ばれるプログラムを指す。プログラムはそれ単体で実行できるとは限らず、外部から共有ライブラリとしてプログラムを読み込んで動作をするものがある。その共有ライブラリを読み込むためのプログラムが動的リンカ（Dynamic Linker）、ないしDynamic Loaderと呼ばれるものである。

今回の問題は、その動的リンカ `/lib64/ld-linux-x86-64.so.2` が無いのが問題である。実際、以下のように `/lib`や `/lib64` ディレクトリすらない。

```console
[bombrary@nixos:~/python/bin]$ ls /
bin  boot  dev  etc  home  lost+found  nix  opt  proc  root  run  srv  sys  tmp  usr  var
```

多くのLinuxディストリビューションはFHS（Filesystem Hierarchy Standard）に準拠しており、それによると`/lib`ディレクトリ下には[libc.so.\*またはld\*](https://www.pathname.com/fhs/pub/fhs-2.3.html#REQUIREMENTS5)のどちらかが要求されている。これが無いということは、NixOSがFHSに準拠していないOSであることを意味する。なぜそうなっているのかというと、NixOSないしNixの設計上の理由である。Nixでは実行ファイル、ライブラリ、設定ファイルなど、ビルドに関連するあらゆるファイルを `/nix/store/` 下で管理する。それらは依存関係に関する情報のハッシュ（厳密には、derivationのハッシュか？）で管理される。詳細は[How Nix works](https://nixos.org/guides/how-nix-works)参照してもらうことにして、このようにすることでNixOSないしNixでは、複数バージョンの共存や、ビルドの再現性を実現する。

実際、nixpkgsで管理されたpython3を見てみると、`ld-linux-x86-64.so.2`は`glibc`パッケージの一部として`/nix/store/`下で管理されていることがわかる（glibcというのは、[標準Cライブラリ](https://ja.wikipedia.org/wiki/%E6%A8%99%E6%BA%96C%E3%83%A9%E3%82%A4%E3%83%96%E3%83%A9%E3%83%AA)の実装の1つ）。これは、glibcのバージョンによって`ld-linux-x86-64.so.2`も変わりうることを意味する。
```console
[bombrary@nixos:~]$ nix shell nixpkgs#binutils nixpkgs#python3 --command bash -c 'readelf -a `which python3`'
...
Program Headers:
  Type           Offset             VirtAddr           PhysAddr
                 FileSiz            MemSiz              Flags  Align
  PHDR           0x0000000000000040 0x0000000000400040 0x0000000000400040
                 0x00000000000002d8 0x00000000000002d8  R      0x8
  INTERP         0x0000000000000318 0x0000000000400318 0x0000000000400318
                 0x0000000000000053 0x0000000000000053  R      0x1
      [Requesting program interpreter: /nix/store/cyrrf49i2hm1w7vn2j945ic3rrzgxbqs-glibc-2.38-44/lib/ld-linux-x86-64.so.2]
  LOAD           0x0000000000000000 0x0000000000400000 0x0000000000400000
                 0x0000000000000770 0x0000000000000770  R      0x1000
...
```

このように`ld-linux-x86-64.so.2`を`/nix/store/`下で管理することで複数バージョンのglibcが使えるようになるが、代わりに`/lib64/ld-linux-x86-64.so.2`があることを前提とした実行バイナリをそのまま動かすことができなくなってしまう。

## 実行バイナリを動かすための緩和策

Nixはあらゆるファイルを`/nix/store/`で管理するため、そもそもNixの外部で作られたプログラムを動作させることは想定されていない。とはいえ、このままではNix外でビルドされた多くのプログラムが使えないことになり、ユーザとしては不便である。

そこで、Nixの再現性を失うことになるが、利用できるようにするための緩和策が4つ考えられる。
* 外部で作られた実行バイナリを動かすのをあきらめ、Nixでビルドされたものを使う
* 外部で作られた実行バイナリをNixOS上で動かすのをあきらめ、コンテナを使う。
* patchelfでinterpreterのパスを `/lib64/ld-linux-x86-64.so.2` から `/nix/store/***-glibc-*-*/lib/ld-linux-x86-64.so.2` に書き換える
* nix-ldを使って、`/lib/ld-linux-x86-64.so.2` を自動生成する

### （推奨）解決策1 外部で作られた実行バイナリを動かすのをあきらめ、Nixでビルドされたものを使う

本末転倒感があるが、そもそも外部から持ってきた実行バイナリを使わず、Nixの世界だけで完結するよう頑張るのも一つの手である。実際そのほうが、余計なトラブル無く動作する可能性が高い。例えば後述の解決策4でも、[うまく動かないケース](#sol4-not-working)が存在する。

Ryeの利用に限って言うと、Ryeを使うのをあきらめ、Nix + Pythonでプロジェクト管理する、ということになる。[NixOS Wiki](https://nixos.wiki/wiki/Python)に詳しいことが乗っているが、`python.withPackages`を使うことでプロジェクトが作成可能だ。

とはいえ、Rye自体はnixpkgsに収録されているわけだし、ここでの「外部から持ってきた実行バイナリ」というのはRyeではなくRyeがDLしてくるpython-build-standaloneである。なのでこれを使わないよう工夫する、という手段もとれる。現バージョンのRyeでは、python-build-standaloneをDLしてきて`~/.rye/py/cpython@[ver]`に展開する。そこで、あらかじめ、`/nix/store/`下にあるpython3.12.1をsymlinkとして`~/.rye/cpython\@3.12.1/install`に配置してしまえば、Nixでビルドされたpythonを使うことが可能だ。これはHome Managerだと以下のように記載すればいける。
```nix
{ config, pkgs, ... }:
{
  ...
  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    "rye-python" = {
      source = "${pkgs.python312}";
      target = ".rye/py/cpython@3.12.1/install";
    };
  };
}
```

今回はPythonのパッケージがnixpkgsにあったからよかったが、nixpkgsに無いプログラムは自分でderivationを作成してビルドする必要がある。自分でビルドする作業は（少なくとも自分は）試行錯誤の連続でかなり骨の折れる作業である。ましてやソースコードが公開されていない場合はそれすら不可能になってしまう。

### 解決策2 外部で作られた実行バイナリをNixOS上で動かすのをあきらめ、コンテナを使う

NixOS上で直接動かすのはあきらめ、Dockerコンテナを立てる。UbuntuなりDebianなり、よくあるLinuxディストリビューションをイメージとしたコンテナであれば、すでに `/lib64/ld-linux-x86-64.so.2` は用意されているので、それをベースイメージとしてDockerfileを書いて開発環境を整えればよい。

NixOSユーザでない人を含む、複数人で開発する環境を整えるのであれば、この方法がベストだと思う。しかしNixOSユーザとしては、個人でいろいろ触ったりする際に、普段のNixOSの世界から離れて作業することになるのは、ちょっと悔しい。

### 解決策3 patchelfでinterpreterを書き換える

なぜpython-standaloneが実行できないのかというと、それはinterpreterのパスが解決できないのが問題であった。ELFのヘッダ情報を色々と書き換えるツールとして[patchelf](https://github.com/NixOS/patchelf)がある。これを使えばinterpreterを `/nix/store/`にある`ld-linux-x86-64.so.2`に書き換えることが可能だ。

しかしここで、どの`ld-linux-x86-64.so.2`に書き換えるべきか、という疑問が生じる。実際、`/nix/store`下にある`ld-linux-x86-64.so.2`には以下の種類がある。
```console
[bombrary@nixos:~/dotfiles]$ find /nix/store/ -mindepth 3 -maxdepth 3 -type f -name '*ld-linux-x86-64.so.2'
/nix/store/dr1k5pfb3yfvm2d3viifv8vpzygc24w5-extra-utils/lib/ld-linux-x86-64.so.2
/nix/store/cyrrf49i2hm1w7vn2j945ic3rrzgxbqs-glibc-2.38-44/lib/ld-linux-x86-64.so.2
/nix/store/l44s1c8agi82zwb8gmp0p8f5vjpgclha-extra-utils/lib/ld-linux-x86-64.so.2
/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/ld-linux-x86-64.so.2
/nix/store/7jiqcrg061xi5clniy7z5pvkc4jiaqav-glibc-2.38-27/lib/ld-linux-x86-64.so.2
```

ここでは、現在のNixOSのシステムで使われているglibcを選ぶことにする。以下のように`nix-store -q --references`で依存関係を調べる。
```console
[bombrary@nixos:~/dotfiles]$ nix-store -q --references /run/current-system/sw | grep glibc
/nix/store/c3gw5qskwbyq711s79vs9z7dfr7613cm-getent-glibc-2.38-27
/nix/store/6xkb4i81jbchphvcdhjb6yy6xxa4sjqs-glibc-locales-2.38-27
/nix/store/vksrk76p5cfbjxb0n95vdkxy7fl2cbcm-glibc-2.38-27-bin

[bombrary@nixos:~/dotfiles]$ nix-store -q --references /nix/store/vksrk76p5cfbjxb0n95vdkxy7fl2cbcm-glibc-2.38-27-bin | grep glibc
/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27
/nix/store/vksrk76p5cfbjxb0n95vdkxy7fl2cbcm-glibc-2.38-27-bin
```

現在のシステムで使われているglibcは`/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27`らしいので、これをpatchelfでセットしてみよう。

```console
[bombrary@nixos:~/python/bin]$ nix run nixpkgs#patchelf -- --set-interpreter /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2 python3.12
```

すると、pythonが起動するようになった。
```console
[bombrary@nixos:~/python/bin]$ ./python3.12
Python 3.12.1 (main, Jan  8 2024, 05:57:25) [Clang 17.0.6 ] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> print("Hello", 1 + 2 + 3)
Hello 6
>>>
```

これのデメリットは、一つずつ外部から持ってきたバイナリについてpatchelfコマンドを実行しなくてはいけない点。またシステムの使うglibcが変わり、`nixos-collect-garbage`で不要なglibcが削除されると、patchelfをやり直す必要が出てくる。

### 解決策4 nix-ldを使って /lib/ld-linux-x86-64.so.2 を自動生成する

これがおそらく現時点で最もシンプルな解決策。シンプルではあるものの、特定の条件ではプログラムが正常に動かない場合があるため注意。これについては[後述](#sol4-not-working)。

[nix-ld](https://github.com/Mic92/nix-ld)というプログラムを導入することで、`/lib/ld-linux-x86-64.so.2`を自動生成する（なお[FAQ](https://github.com/Mic92/nix-ld?tab=readme-ov-file#does-this-work-on-non-nixos-system)で言及されているが、NixOS以外のシステムでこれをやってはいけない）。

やり方としては、`configuration.nix`に以下の一文を追加し、`nixos-rebuild switch`するだけである。
```nix
{
  programs.nix-ld.enable = true;
}
```

NixOSを再ビルドすると、`lib64`が増えていることがわかる。
```console
[bombrary@nixos:~/dotfiles]$ ls /
bin  boot  dev  etc  home  lost+found  nix  opt  proc  root  run  srv  sys  tmp  usr  var

[bombrary@nixos:~/dotfiles]$ sudo nixos-rebuild switch --flake .#minimal
[sudo] password for bombrary:
warning: Git tree '/home/bombrary/dotfiles' is dirty
building the system configuration...
warning: Git tree '/home/bombrary/dotfiles' is dirty
activating the configuration...
setting up /etc...
reloading user units for bombrary...
setting up tmpfiles
reloading the following units: dbus.service

[bombrary@nixos:~/dotfiles]$ ls /
bin  boot  dev  etc  home  lib64  lost+found  nix  opt  proc  root  run  srv  sys  tmp  usr  var
```

その実体は`nix-ld`というプログラムになっている。このプログラムがinterpreterの役割を担ってくれる（[ソースコード](https://github.com/Mic92/nix-ld/blob/main/nix-ld.nix)的に、実際には`stdenv.cc.bintools.dynamicLinker`にあるinterpreterを持ってきているっぽい？）。
```console
[bombrary@nixos:~/dotfiles]$ ls -la /lib64
lrwxrwxrwx - root 18 Feb 13:22 ld-linux-x86-64.so.2 -> /nix/store/nfxfy71ldi0wwr9lklbp5bp143aivaxg-nix-ld-1.2.2/libexec/nix-ld

[bombrary@nixos:~/dotfiles]$ nix run nixpkgs#file /nix/store/nfxfy71ldi0wwr9lklbp5bp143aivaxg-nix-ld-1.2.2/libexec/nix-ld
/nix/store/nfxfy71ldi0wwr9lklbp5bp143aivaxg-nix-ld-1.2.2/libexec/nix-ld: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), static-pie linked, not stripped
```

以下のように、前項で変えたinterpreterを戻したとしても、python3.12が動作することが確認できる（注意：`NIX_LD`環境変数を反映させるために、NixOSのビルド後はshellへの再ログインが必要）。
```console
[bombrary@nixos:~/python/bin]$ nix run nixpkgs#patchelf -- --set-interpreter /lib64/ld-linux-x86-64.so.2 python3.12

[bombrary@nixos:~/python/bin]$ ./python3.12
Python 3.12.1 (main, Jan  8 2024, 05:57:25) [Clang 17.0.6 ] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
```

このnix-ldを導入するだけで多くのプログラムが動くという手軽さと、glibcのバージョンはnix-ldが隠してくれているという利点から、おそらくこれが現状の推奨された方法だと思う。Ryeのセットアップもエラーなく完了する。
```console
[bombrary@nixos:~]$ nix run nixpkgs#rye
Welcome to Rye!

Rye has detected that it's not installed on this computer yet and
automatically started the installer for you.  For more information
read https://rye-up.com/guide/installation/

This installer will install rye to /home/bombrary/.rye
This path can be changed by exporting the RYE_HOME environment variable.

Details:
  Rye Version: 0.24.0
  Platform: linux (x86_64)

✔ Continue? · yes
✔ Select the preferred package installer · pip-tools (slow but stable)
✔ Determine Rye's python Shim behavior outside of Rye managed projects · Make Rye's own Python distribution available
✔ Which version of Python should be used as default toolchain? · cpython@3.12
Installed binary to /home/bombrary/.rye/shims/rye
Bootstrapping rye internals
Downloading cpython@3.12.1
Checking checksum
success: Downloaded cpython@3.12.1
Upgrading pip
Installing internal dependencies
Updated self-python installation at /home/bombrary/.rye/self

The rye directory /home/bombrary/.rye/shims was not detected on PATH.
It is highly recommended that you add it.
✔ Should the installer add Rye to PATH via .profile? · no
note: did not manipulate the path. To make it work, add this to your .profile manually:

    source "$HOME/.rye/env"

For more information read https://mitsuhiko.github.io/rye/guide/installation

All done!
```


## 足りない共有ライブラリを補う

Ryeではバージョンを`pin`サブコマンドで指定できるが、古いバージョンであるpython3.11を持ってこようとするとエラーになる。
```
[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#rye -- pin 3.11.1
pinned 3.11.1 in /home/bombrary/tmp/rye-test/.python-version

[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#rye -- sync
Python version mismatch (found cpython@3.11.4, expected cpython@3.11.1), recreating.
Initializing new virtualenv in /home/bombrary/tmp/rye-test/.venv
Python version: cpython@3.11.1
RuntimeError: failed to query /home/bombrary/.rye/py/cpython@3.11.1/install/bin/python3 with code 127 err: '/home/bombrary/.rye/py/cpython@3.11.1/install/bin/python3: error while loading shared libraries: libcrypt.so.1: cannot open shared object file: No such file or directory\n'
error: failed creating virtualenv ahead of sync

Caused by:
    failed to initialize virtualenv
```

エラーの内容として有力な情報は`libcrypt.so.1: cannot open shared object file: No such file or directory`である。どうやら共有ライブラリのファイルである`libcrypt.so.1`が足りないらしい。実際、`ldd`コマンドで確認してみると、`libcrypt.so.1`がnot foundになっている。
```console
[bombrary@nixos:~/tmp/rye-test]$ ldd ~/.rye/py/cpython\@3.11.1/install/bin/python3.11
        linux-vdso.so.1 (0x00007fff0b8bd000)
        /home/bombrary/.rye/py/cpython@3.11.1/install/bin/../lib/libpython3.11.so.1.0 (0x00007f012c600000)
        libpthread.so.0 => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/libpthread.so.0 (0x00007f012dc68000)
        libdl.so.2      => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/libdl.so.2 (0x00007f012dc63000)
        libutil.so.1    => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/libutil.so.1 (0x00007f012dc5e000)
        libcrypt.so.1   => not found
        libm.so.6       => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/libm.so.6 (0x00007f012c520000)
        librt.so.1      => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/librt.so.1 (0x00007f012dc57000)
        libc.so.6       => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/libc.so.6 (0x00007f012c338000)
        /lib64/ld-linux-x86-64.so.2 => /nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2 (0x00007f012dc75000)
        libcrypt.so.1 => not found
```

ほかの共有ライブラリに関しては、`ld-linux-x86-64.so.2`と同じパッケージにあるせいか、パスが解決できている。しかし`libcrypt.so.1`はglibcには入っていないため、パスの解決ができない。ちなみに、もしNixでビルドされているのであれば、以下のようにRUNPATHに`/nix/store/`下のパッケージのパスが指定されている（以下は`exa`の例）。

```console
[bombrary@nixos:~/tmp/rye-test]$ nix shell nixpkgs#binutils --command readelf -d `which exa`

Dynamic section at offset 0x1a27c0 contains 32 entries:
  Tag        Type                         Name/Value
 0x0000000000000001 (NEEDED)             Shared library: [libz.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libgcc_s.so.1]
 0x0000000000000001 (NEEDED)             Shared library: [libm.so.6]
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
 0x000000000000001d (RUNPATH)            Library runpath: [/nix/store/ilr7br1ck7i6wcgfkynwpnjp7n964h38-zlib-1.3.1/lib:/nix/store/cyrrf49i2hm1w7vn2j945ic3rrzgxbqs-glibc-2.38-44/lib:/nix/store/1s98ricsglmfjjqkfnpvywnip5z7gp9q-gcc-13.2.0-lib/lib]
 0x000000000000000c (INIT)               0x15000
 ...
```

ところがpython-standaloneではそのようなRUNPATHが指定されていないため、どこを参照すれば`libcrypt.so.1`があるのかわからず、エラーとなる。このように、実行バイナリが必要としている共有ライブラリが無い or パスが解決できない場合に、何か手を加える必要がある。

解決方法として以下の2つが考えられる。
* RUNPATHを設定する
* LD_LIBRARY_PATHを設定する

### 解決策1 RUNPATHを設定する

RUNPATHが設定されていないのであればそれを設定すればよいではないか、という解決策。RUNPATHの設定は[patchelf](https://github.com/NixOS/patchelf)の`--set-rpath`でできる。

まず`libcrypt.so.1`が入っているパッケージを探す。これに関してはググったりして予想したりして頑張ると、`libxcrypt-legacy`というパッケージにあることが分かる （あとは[nix-index](https://github.com/nix-community/nix-index)を使うのがよいのかもしれないが、最初のindexを作るところでかなり時間がかかるのが悩ましい）。
```console
# libxcrypt-legacyを入れた上で新しいシェルに入る
[bombrary@nixos:~]$ nix shell nixpkgs#libxcrypt-legacy

# libxcrypt-legacyのパスを見つける
[bombrary@nixos:~]$ nix eval --raw nixpkgs#libxcrypt-legacy
/nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36

# libcrypt.so.1があることを確認
[bombrary@nixos:~]$ ls /nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib
libcrypt.la  libcrypt.so  libcrypt.so.1  libcrypt.so.1.1.0  libxcrypt.so  pkgconfig
```

`/nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib`に`libcrypt.so.1`があることが分かったので、patchelfでそれをRUNPATHに設定する。

```console
[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#patchelf -- --set-rpath /nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib ~/.rye/py/cpython\@3.11.1/install/bin/python3.11

[bombrary@nixos:~/tmp/rye-test]$ nix shell nixpkgs#binutils --command readelf -d ~/.rye/py/cpython\@3.11.1/install/bin/python3.11

Dynamic section at offset 0x7000 contains 35 entries:
  Tag        Type                         Name/Value
 0x000000000000001d (RUNPATH)            Library runpath: [/nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib]
 0x0000000000000001 (NEEDED)             Shared library: [$ORIGIN/../lib/libpython3.11.so.1.0]
 ...
```

これでpython3.11が起動するようになる。
```console
# 試しに.venvを消してsyncを再実行
[bombrary@nixos:~/tmp/rye-test]$ rm -rf .venv

[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#rye -- sync
Initializing new virtualenv in /home/bombrary/tmp/rye-test/.venv
Python version: cpython@3.11.1
Generating production lockfile: /home/bombrary/tmp/rye-test/requirements.lock
Generating dev lockfile: /home/bombrary/tmp/rye-test/requirements-dev.lock
Installing dependencies
...
Successfully built rye-test
Installing collected packages: rye-test, numpy
Successfully installed numpy-1.26.1 rye-test-0.1.0
Done!
```

これのデメリットは、一つずつ外部から持ってきた実行バイナリについてpatchelfコマンドを実行しなくてはいけない点。また今回入れた`libxcrypt`は、`nix shell nixpkgs#libxcrypt-legacy`で一時的に導入しただけであり、`nixos-collect-garbage`すると消えてしまう。

### 解決策2-1 LD_LIBRARY_PATHに設定する

動的リンカは`LD_LIBRARY_PATH`環境変数を見て、共有ライブラリの検索パスを増やせる（参考：[ld-linux.so.\*](https://manpages.ubuntu.com/manpages/focal/ja/man8/ld-linux.so.8.html)）。これを用いると、`libcrypt.so.1`へのパスが解決できるようになる。

これを踏まえると、次のように一時的に`LD_LIBRARY_PATH`を設定すれば、python3.11.1が動く。
```console
# 前項の追加分を消す
[bombrary@nixos:~/tmp/rye-test]$ rm -rf ~/.rye/py/cpython\@3.11.1

[bombrary@nixos:~/tmp/rye-test]$ LD_LIBRARY_PATH=/nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib nix run nixpkgs#rye -- sync
Reusing already existing virtualenv
Generating production lockfile: /home/bombrary/tmp/rye-test/requirements.lock
Generating dev lockfile: /home/bombrary/tmp/rye-test/requirements-dev.lock
Installing dependencies
...
Successfully built rye-test
Installing collected packages: rye-test
Successfully installed rye-test-0.1.0
Done!
```

### 解決策2-2 Nixファイルにまとめる

とはいえ実用上、いちいちライブラリのパスを探して`LD_LIBRARY_PATH`に指定するのは大変なので、`nix develop`で環境変数込みのシェルが起動できるように設定するのがよい。例えば、`flake.nix`に以下のように書く。
* `devShells.<system>.default`に`pkgs.mkShell{...}`を書く
* `pkgs.mkShell`の中に環境変数を指定する
  * `pkgs.lib.makeLibraryPath`でいい感じにライブラリのパスのリストを作成してくれる
* `pkgs.mkShell{ packages = [...]; }` で、利用するパッケージを指定する
  * ここでは`rye`を指定しているので、今後は長いコマンド`nix run nixpkgs#rye`を打たなくて良くなる

※  `nix-shell`でシェルを動かしたい場合の例は、[nix-ldのUsage](https://github.com/Mic92/nix-ld?tab=readme-ov-file#usage)を参照。
```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let
    pkgs = import nixpkgs { system = "x86_64-linux"; };
  in
  {
    devShells."x86_64-linux".default = pkgs.mkShell {
      packages = with pkgs; [
        rye
      ];
      LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath (with pkgs; [
        libxcrypt-legacy
      ]);
    };
  };
}
```

これで`nix develop`コマンドを入力すれば、上記の設定を入れてシェルに入れる。

```console
# 前項の追加分を消す
[bombrary@nixos:~/tmp/rye-test]$ rm -rf ~/.rye/py/cpython\@3.11.1

[bombrary@nixos:~/tmp/rye-test]$ nix develop

[bombrary@nixos:~/tmp/rye-test]$ echo $LD_LIBRARY_PATH
/nix/store/vrg3cdryjqqxkxj5jqy5b445fv8mnwap-libxcrypt-4.4.36/lib

# 試しに.venvを消してsyncを再実行
[bombrary@nixos:~/tmp/rye-test]$ rm -rf .venv

[bombrary@nixos:~/tmp/rye-test]$ rye sync
Initializing new virtualenv in /home/bombrary/tmp/rye-test/.venv
Python version: cpython@3.11.1
Generating production lockfile: /home/bombrary/tmp/rye-test/requirements.lock
Generating dev lockfile: /home/bombrary/tmp/rye-test/requirements-dev.lock
Installing dependencies
...
Successfully built rye-test
Installing collected packages: rye-test, numpy
Successfully installed numpy-1.26.1 rye-test-0.1.0
Done!
```

## まとめ

ごちゃごちゃと書いたが、言いたいことは大体[nix-ldのREADME](https://github.com/Mic92/nix-ld)に集約されており、外部から持ってきた実行バイナリを動かすためには、
* nix-ldを導入する
* 環境変数`LD_LIBRARY_PATH`を指定したシェルが動作するようにnixファイルを書く

をすればよい。

関連するツールとして他にも[nix-alien](https://github.com/thiagokokada/nix-alien)とか[nix-autobahn](https://github.com/Lassulus/nix-autobahn)があるらしいが、これらは今後調べてみようと思う。


## （追記：解決策4 補足） nix-ldでも正しく動かないケース {#sol4-not-working}

### Ryeのバージョンアップで動かなくなった件

Ryeのバージョンアップによる追記。0.29.0で確認した事象。
```console
[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#rye -- --version
rye 0.29.0
commit: 0.29.0 (1980-01-01)
platform: linux (x86_64)
self-python: not bootstrapped (target: cpython@3.12)
symlink support: true
uv enabled: false
```

いつからかのバージョンから、syncが正しく動作しなくなった。venvの実行に失敗しているようである。
```console
[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#rye -- sync
Bootstrapping rye internals
Found a compatible Python version: cpython@3.12.2
  × Failed to detect the operating system version: could not detect either glibc version nor musl libc version, at least one of which is required
error: could not sync because bootstrap failed

Caused by:
    Failed to create self venv using /home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3. uv exited with status: exit status: 1
```

straceでexecveを見てみよう

```console
[bombrary@nixos:~/tmp/rye-test]$ strace -s 10000 -f nix run nixpkgs#rye -- sync 2>&1 | grep execve
execve("/run/current-system/sw/bin/nix", ["nix", "run", "nixpkgs#rye", "--", "sync"], 0x7ffeab00aaa8 /* 47 vars */) = 0
[pid 140768] execve("/nix/store/8hp47i45bd3pl3v541314zsqmray88a3-rye-0.29.0/bin/rye", ["/nix/store/8hp47i45bd3pl3v541314zsqmray88a3-rye-0.29.0/bin/rye", "sync"], 0x7ffea9b00408 /* 47 vars */ <unfinished ...>
<... execve resumed>)                   = 0
[pid 140774] execve("/run/wrappers/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/home/bombrary/.nix-profile/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/nix/profile/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/home/bombrary/.local/state/nix/profile/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/etc/profiles/per-user/bombrary/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/nix/var/nix/profiles/default/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */) = -1 ENOENT (No such file or directory)
[pid 140774] execve("/run/current-system/sw/bin/ldd", ["ldd", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x7ffd0636e2d0 /* 47 vars */ <unfinished ...>
[pid 140774] <... execve resumed>)      = 0
[pid 140775] execve("/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2", ["/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2", "--verify", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x14ccd70 /* 47 vars */) = 0
[pid 140778] execve("/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2", ["/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib64/ld-linux-x86-64.so.2", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3"], 0x14dac30 /* 51 vars */) = 0

[pid 140779] execve("/home/bombrary/.rye/uv/0.1.17/uv", ["/home/bombrary/.rye/uv/0.1.17/uv", "--quiet", "venv", "--python", "/home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3", "/home/bombrary/.rye/self"], 0x560d660ff200 /* 48 vars */ <unfinished ...>
[pid 140779] <... execve resumed>)      = 0
[pid 140784] execve("/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/ld-linux-x86-64.so.2", ["/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27/lib/ld-linux-x86-64.so.2"], 0x7ffe7a9405c0 /* 48 vars */ <unfinished ...>
[pid 140784] <... execve resumed>)      = 0
[pid 140785] execve("nixpkgxpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
[pid 140785] execve("nixos-config=/etc/nixos/configuration.nix/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
[pid 140785] execve("/nix/var/nix/profiles/per-user/root/channels/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
```

どうやら、コマンド
```sh
/home/bombrary/.rye/uv/0.1.17/uv --quiet venv --python /home/bombrary/.rye/py/cpython@3.12.2/install/bin/python3 /home/bombrary/.rye/self
```
が実行され、`~/.rye/self` にvenvを作ろうとしているが、それに失敗しているようである。最後のlddの呼び出しを見るに、glibcかmuslの判定を`ldd --version`で行おうとしているが、なぜかlddのパスが解決できない。

いくつかのパスについてexecveが通るか試みているように見えるが、これはexecvpの挙動である。execvpを使っていることは、
* [0.1.17のplatform-host/src/linux.rs](https://github.com/astral-sh/uv/blob/0.1.17/crates/platform-host/src/linux.rs#L44)では、`std::process::Command`を使ってlddを呼び出している
* `std::process`は`sys::process`のラッパーで、そこで[execvpの呼び出しの記述](https://doc.rust-lang.org/1.73.0/src/std/sys/unix/process/process_unix.rs.html#405)がある

と辿ることで分かる。でexecvpはなんの情報をもとにいくつかのパスを試しているのかというと、それは環境変数`PATH`である（[実際のソースコード](https://elixir.bootlin.com/glibc/latest/source/posix/execvpe.c#L71)）。`PATH`に書かれているディレクトリについて、末尾に`ldd`をつけた上で片っ端からexecveすることで試している。

ところがよく見ると、その調べるディレクトリがなにかおかしいことに気づく。
```
execve("nixpkgxpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
execve("nixos-config=/etc/nixos/configuration.nix/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
execve("/nix/var/nix/profiles/per-user/root/channels/ldd", ["ldd", "--version"], 0x7ffe7a9405c0 /* 48 vars */) = -1 ENOENT (No such file or directory)
```
ここに書かれている3種類は、 **PATHではなくNIX_PATHにかかれているもの** のはずである。試しに `strace` に `-v` をつけることで、どんな環境変数が付けられているのか見てみる

```
[bombrary@nixos:~/tmp/rye-test]$ echo $NIX_PATH
nixpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels

[bombrary@nixos:~/tmp/rye-test]$ echo $PATH
/run/wrappers/bin:/home/bombrary/.nix-profile/bin:/nix/profile/bin:/home/bombrary/.local/state/nix/profile/bin:/etc/profiles/per-user/bombrary/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin

[bombrary@nixos:~/tmp/rye-test]$ strace -v -s 10000 -f nix run nixpkgs#rye -- sync 2>&1 | grep execve | tail -1 | tr "," "\n" | grep "\"NIX_PATH="

[bombrary@nixos:~/tmp/rye-test]$ strace -v -s 10000 -f nix run nixpkgs#rye -- sync 2>&1 | grep execve | tail -1 | tr "," "\n" | grep "\"PATH="
 "PATH=nixpkgxpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels"
 "PATH=/run/wrappers/bin:/home/bombrary/.nix-profile/bin:/nix/profile/bin:/home/bombrary/.local/state/nix/profile/bin:/etc/profiles/per-user/bombrary/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
```

なぜか、`NIX_PATH`が`PATH`に書き換わっている。しかもそれが最初に現れるから、execvpのパス検索に使われてしまう。

### 手軽な事象の再現方法

次の手順を踏むと、`NIX_PATH`が`PATH`に書き換わる事象が再現できる

まず以下のように、`env`を入れた上でprocessを実行するRustコードを書く。
```rust
use std::process::Command;

fn main() {
    let mut cmd = Command::new("./program");
    cmd.env("FOO", "BAR");

    let output = cmd.output()
        .expect("Failed to execute command");
    println!("{}", std::str::from_utf8(&output.stdout).unwrap());
}
```

Nix外（例：Ubuntuのコンテナ）で以下のCコードをコンパイルする。プログラム名は`program`にする。内容は、環境変数`PATH`が見つかればそれを出力するだけである。

```c
#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[], char *envp[]) {
  int i;
  for (i = 0; envp[i]; i++){
    char key[5] = "";
    strncpy(key, envp[i], 4);
    if (strcmp(key, "PATH") == 0) {
      printf("%s\n", envp[i]);
    }
  }
  return 0;
}
```

Docker上での場合のコンパイル例。

```console
[bombrary@nixos:~/tmp/cargo-test]$ docker run --rm -it -v`pwd`:/app/ -w/app gcc:13.2.0
root@a6ca8112f5c8:/app# gcc -o program program.c
```

これで、Rustのプログラムをビルドしたうえで実行すると、意図しない`PATH`が現れることが確認できる。
```console
[bombrary@nixos:~/tmp/cargo-test]$ cargo build
    Finished dev [unoptimized + debuginfo] target(s) in 0.03s

[bombrary@nixos:~/tmp/cargo-test]$ ./target/debug/cargo-test
PATH=nixpkgxpkgs=/nix/var/nix/profiles/per-user/root/channels/nixos:nixos-config=/etc/nixos/configuration.nix:/nix/var/nix/profiles/per-user/root/channels
PATH=/nix/store/nhcidacc2bad8jaq965i3bwwnf777b6r-cargo-1.76.0/bin:/nix/store/yp1f9ya9r4qjssxavfnpqv28ryf3ibfh-rustc-wrapper-1.76.0/bin:/nix/store/qhpw32pz39y6i30b3vrbw5fw6zv5549f-gcc-wrapper-13.2.0/bin:/nix/store/7vc88ixc6yca2hwgszjk51dh23j3g2nr-gcc-13.2.0/bin:/nix/store/m9b4wcy4yyn5xcy394h74x7klb28nm2c-glibc-2.38-44-bin/bin:/nix/store/mb488rr560vq1xnl10hinnyfflcrd51n-coreutils-9.4/bin:/nix/store/7hhd9smnjspppk4k6n47bkw64fdbgbrz-binutils-wrapper-2.41/bin:/nix/store/bczmlm8brs93gp4lscwvc1dnn2ipymnc-binutils-2.41/bin:/nix/store/avlyab878080nxxwy386vwx99js7w4l7-gdb-14.1/bin:/nix/store/3125ahv429pk8sxnfhj5l3f2ph7jllrk-patchelf-0.15.0/bin:/nix/store/mb488rr560vq1xnl10hinnyfflcrd51n-coreutils-9.4/bin:/nix/store/rr5pqqck5f6fjkv7agwjyhaljvh27ncn-findutils-4.9.0/bin:/nix/store/n6i46dn14q3iq82gqgb5qkl74aqhwr77-diffutils-3.10/bin:/nix/store/q7kq0naays5251ihghw0ccsz39id7kk5-gnused-4.9/bin:/nix/store/320v66ili0mwnyrxj3dwbxm0z8ndkbw7-gnugrep-3.11/bin:/nix/store/sgpv5hm93gzkcm4s536nmkpag3q5d22s-gawk-5.2.2/bin:/nix/store/zq7c5lha3pzixhs8vgy0c0k2sn9s6kq9-gnutar-1.35/bin:/nix/store/p27jyrx9ghhxbl5j82114fdy50lr33z3-gzip-1.13/bin:/nix/store/f7i053lqqbppa3nx3nbmk6y46wy06shj-bzip2-1.0.8-bin/bin:/nix/store/3wwka0sn2h96cmqxyclj2vba26a5sk1s-gnumake-4.4.1/bin:/nix/store/4vzal97iq3dmrgycj8r0gflrh51p8w1s-bash-5.2p26/bin:/nix/store/yb3vxdqkdx672wl4hg92xf1zhykjjppr-patch-2.7.6/bin:/nix/store/p6iz6wa3lqwzf5nbihpv52zpp1ji9243-xz-5.6.0-bin/bin:/nix/store/pqraddz55s3qlsjxs71zwjchj0c4csfw-file-5.45/bin:/run/wrappers/bin:/home/bombrary/.nix-profile/bin:/nix/profile/bin:/home/bombrary/.local/state/nix/profile/bin:/etc/profiles/per-user/bombrary/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin
```

### どこに問題があるのか

いくつか試した限りだと、
* Rustコードの中の`cmd.env("FOO", "BAR")`を取り除くと、正常に動く
* `cmd.env(...)`があったとしても、`cargo build`ではなく`cargo run`なら正常に動く
* `patchelf --set-interpreter ... ./program` で `program` のldをちゃんと設定してあげると、`cargo build`でも正常に動く

という事実が確認できた。このことから、事象の再現条件は
* プログラムが、Nix外部でビルドされたプログラムを呼び出すこと
* `cmd.env(...)` で環境変数に手を入れること
* `cargo build`でビルドすること

という複雑なものになっている。`env`を入れるというだけで意図しない環境変数の書き換えが起こるので、明らかに万人が期待する動作になっていない。とても興味深く厄介な挙動であるが、なぜこんなことが起こるのかの解析は（少なくとも自分の実力では）困難だった（どこで環境変数の書き換えが起こっているのかを特定するためにはデバッガをうまく使えばできるのかもしれないが、未勉強）。

ここから得られる教訓の一つとしては、Nix外部でビルドされたバイナリは、100%動くとは限らないということ…。
