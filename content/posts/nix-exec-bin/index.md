---
title: "Nixの外でビルドされた実行バイナリをNixOSで動かす"
date: 2024-02-18T21:10:00+09:00
tags: ["Python"]
categories: ["NixOS"]
toc: true
---

## 更新内容

### 2024/09/14

記事の内容を整理した。もともとRyeを使う際に詰まった記録を記事にしたものだったが、あまりにRye依存になる記述が多かったので、python-build-standaloneを例とした内容に置き換えた。
Ryeのときの話は[RyeをNixOS上で動かそうとしたときの記録（2024年2月）]({{< ref "posts/rye-nix-202402" >}})に移動した。

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

## python-build-standaloneがNixOS上で動かせないことの確認

ここでは、外部でビルドされたpythonである[python-build-standalone](https://github.com/indygreg/python-build-standalone)をNixOS上で動かそうとしてみよう。なおpythonはnixpkgsから入手可能であり、通常利用の場合はわざわざ外部からビルド済みのpythonを持ってくる必要はないのだが、今回は例のためにこれを実行することを考える。

pythonのstandaloneをDLしてくる。
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

> When execve() returns the error ENOENT, it can mean more than one thing:
> 
> * the program doesn't exist;
> * the program itself exists, but it requires an "interpreter" that doesn't exist.

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

本末転倒感があるが、そもそも外部から持ってきた実行バイナリを使わず、Nixの世界だけで完結するよう頑張るのも一つの手である。実際そのほうが、余計なトラブル無く動作する可能性が高い。

例えばpythonでは、NixOSだけでパッケージを管理する仕組みが作られている。詳しくは[NixOS Wiki](https://nixos.wiki/wiki/Python)にに書かれているが、`python.withPackages`を使うことでプロジェクトが作成可能だ。

今回はpythonのパッケージがnixpkgsにあったからよかったが、nixpkgsに無いプログラムは自分でderivationを作成してビルドする必要がある。自分でビルドする作業は（少なくとも自分は）試行錯誤の連続でかなり骨の折れる作業である。ましてやソースコードが公開されていない場合はそれすら不可能になってしまう。

### 解決策2 外部で作られた実行バイナリをNixOS上で動かすのをあきらめ、コンテナを使う

NixOS上で直接動かすのはあきらめ、Dockerコンテナを立てる。UbuntuなりDebianなり、よくあるLinuxディストリビューションをイメージとしたコンテナであれば、すでに `/lib64/ld-linux-x86-64.so.2` は用意されているので、それをベースイメージとしてDockerfileを書いて開発環境を整えればよい。

NixOSユーザでない人を含む、複数人で開発する環境を整えるのであれば、この方法がベストだと思う。しかしNixOSユーザとしては、個人でいろいろ触ったりする際に、普段のNixOSの世界から離れて作業することになるのは、ちょっと悔しい。

### 解決策3 patchelfでinterpreterを書き換える

なぜpython-standaloneが実行できないのかというと、それはinterpreterのパスが解決できないのが問題であった。ELFのヘッダ情報を色々と書き換えるツールとして[patchelf](https://github.com/NixOS/patchelf)がある。これを使えばinterpreterを `/nix/store/`にある`ld-linux-x86-64.so.2`に書き換えることが可能だ。

しかしここで、どの`ld-linux-x86-64.so.2`に書き換えるべきだろうか。実際、`/nix/store`下にある`ld-linux-x86-64.so.2`には以下の種類がある。
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

このnix-ldを導入するだけで多くのプログラムが動くという手軽さと、glibcのバージョンはnix-ldが隠してくれているという利点から、おそらくこれが現状最もよさそう。

## 足りない共有ライブラリを補う

古いバージョンであるpython3.11を持ってこようとするとエラーになる。
```console
[bombrary@nixos:~]$ curl -LO https://github.com/indygreg/python-build-standalone/releases/download/20230116/cpython-3.11.1+20230116-x86_64-unknown-linux-gnu-install_only.tar.gz

[bombrary@nixos:~]$ tar -xzf cpython-3.11.1+20240107-x86_64-unknown-linux-gnu-install_only.tar.gz

[bombrary@nixos:~]$ ./python/bin/python3.11
./python/bin/python3.11: error while loading shared libraries: libcrypt.so.1: cannot open shared object file: No such file or directory
```

どうやら共有ライブラリのファイルである`libcrypt.so.1`が足りないらしい。実際、`ldd`コマンドで確認してみると、`libcrypt.so.1`がnot foundになっている。
```console
[bombrary@nixos:~]$ ldd ./python/bin/python3.11
        linux-vdso.so.1 (0x00007ffdda91c000)
        /home/bombrary/./python/bin/../lib/libpython3.11.so.1.0 (0x00007fb172a00000)
        libpthread.so.0 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libpthread.so.0 (0x00007fb174136000)
        libdl.so.2 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libdl.so.2 (0x00007fb174131000)
        libutil.so.1 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libutil.so.1 (0x00007fb17412c000)
        libcrypt.so.1 => not found
        libm.so.6 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libm.so.6 (0x00007fb17291d000)
        librt.so.1 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/librt.so.1 (0x00007fb174125000)
        libc.so.6 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib/libc.so.6 (0x00007fb172730000)
        /lib64/ld-linux-x86-64.so.2 => /nix/store/r8qsxm85rlxzdac7988psm7gimg4dl3q-glibc-2.39-52/lib64/ld-linux-x86-64.so.2 (0x00007fb174143000)
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

まず`libcrypt.so.1`が入っているパッケージを探す。nixpkgsのどのパッケージにどのファイルがあるのかを調べるには[nix-index](https://github.com/nix-community/nix-index)使えばよい。ただしこれを直接使うとindexの生成に時間がかかるので、代わりにindexが事前生成された[nix-index-database](https://github.com/nix-community/nix-index-database)を使う。
```console
[bombrary@nixos:~]$ nix run github:nix-community/nix-index-database libcrypt.so.1
(wineWowPackages.stagingFull.out)                     0 s /nix/store/p6kwnhrwpbyh1zk0l0vy19fzaw7933cc-libxcrypt-4.4.36/lib/libcrypt.so.1
(wineWowPackages.stagingFull.out)               235,676 x /nix/store/p6kwnhrwpbyh1zk0l0vy19fzaw7933cc-libxcrypt-4.4.36/lib/libcrypt.so.1.1.0
(status-im.out)                                 206,584 r /nix/store/3gjzcl4m28nsgc07q1s6r1dw911p5cs8-status-desktop-2.29.0-extracted/usr/lib/libcrypt.so.1
(simplex-chat-desktop.out)                       42,336 r /nix/store/a1399c4g96889j0f5sdq37452xa2a07y-simplex-chat-desktop-6.0.3-extracted/usr/lib/app/resources/vlc/libcrypt.so.1
(protonup-qt.out)                                     0 s /nix/store/4va86cbvckkjcmnrnh03gnalbv5jcxxk-protonup-qt-2.10.2-extracted/runtime/compat/lib/x86_64-linux-gnu/libcrypt.so.1
(protonup-qt.out)                               198,664 r /nix/store/4va86cbvckkjcmnrnh03gnalbv5jcxxk-protonup-qt-2.10.2-extracted/runtime/compat/lib/x86_64-linux-gnu/libcrypt.so.1.1.0
libxcrypt-legacy.out                                  0 s /nix/store/5lm3jdvg6flhjrckvbhiv9209sr782p6-libxcrypt-4.4.36/lib/libcrypt.so.1
libxcrypt-legacy.out                            217,528 x /nix/store/5lm3jdvg6flhjrckvbhiv9209sr782p6-libxcrypt-4.4.36/lib/libcrypt.so.1.1.0
```

ここから、 `libxcrypt-legacy` というパッケージに入っていそうなことがわかった。
```console
# libxcrypt-legacyを入れた上で新しいシェルに入る
[bombrary@nixos:~]$ nix shell nixpkgs#libxcrypt-legacy

# libxcrypt-legacyのパスを見つける
[bombrary@nixos:~]$ nix eval --raw nixpkgs#libxcrypt-legacy
/nix/store/18m36haf5csgj5fllfnb6njhrhpnjvgz-libxcrypt-4.4.36

# libcrypt.so.1があることを確認
[bombrary@nixos:~]$ ls $(nix eval --raw nixpkgs#libxcrypt-legacy)/lib
libcrypt.la  libcrypt.so  libcrypt.so.1  libcrypt.so.1.1.0  libxcrypt.so  pkgconfig
```

`/nix/store/18m36haf5csgj5fllfnb6njhrhpnjvgz-libxcrypt-4.4.36/lib`に`libcrypt.so.1`があることが分かったので、patchelfでそれをRUNPATHに設定する。

```console
[bombrary@nixos:~/tmp/rye-test]$ nix run nixpkgs#patchelf -- --set-rpath $(nix eval --raw nixpkgs#libxcrypt-legacy)/lib ~/python/bin/python3.11

[bombrary@nixos:~/tmp/rye-test]$ nix shell nixpkgs#binutils --command readelf -d ~/python/bin/python3.11

Dynamic section at offset 0x6000 contains 35 entries:
  Tag        Type                         Name/Value
 0x000000000000001d (RUNPATH)            Library runpath: [/nix/store/18m36haf5csgj5fllfnb6njhrhpnjvgz-libxcrypt-4.4.36/lib]
 0x0000000000000001 (NEEDED)             Shared library: [$ORIGIN/../lib/libpython3.11.so.1.0]
...
```

これでpython3.11が起動するようになる。
```console
[bombrary@nixos:~]$ ./python/bin/python3.11
Python 3.11.1 (main, Jan 16 2023, 22:41:20) [Clang 15.0.7 ] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
```

これのデメリットは、一つずつ外部から持ってきた実行バイナリについてpatchelfコマンドを実行しなくてはいけない点。また今回入れた`libxcrypt`は、`nix shell nixpkgs#libxcrypt-legacy`で一時的に導入しただけであり、`nixos-collect-garbage`すると消えてしまう。

### 解決策2-1 LD_LIBRARY_PATHに設定する

動的リンカは`LD_LIBRARY_PATH`環境変数を見て、共有ライブラリの検索パスを増やせる（参考：[ld-linux.so.\*](https://manpages.ubuntu.com/manpages/focal/ja/man8/ld-linux.so.8.html)）。これを用いると、`libcrypt.so.1`へのパスが解決できるようになる。

これを踏まえると、次のように一時的に`LD_LIBRARY_PATH`を設定すれば、python3.11.1が動く。
```console
# 前項の追加分を消す
[bombrary@nixos:~]$ nix run nixpkgs#patchelf -- --remove-rpath ./python/bin/python3.11

[bombrary@nixos:~]$ ./python/bin/python3.11
./python/bin/python3.11: error while loading shared libraries: libcrypt.so.1: cannot open shared object file: No such file or directory

# LD_LIBRARY_PATHの設定したうえでpythonを起動
[bombrary@nixos:~]$ LD_LIBRARY_PATH=$(nix eval --raw nixpkgs#libxcrypt-legacy)/lib ./python/bin/python3.11
Python 3.11.1 (main, Jan 16 2023, 22:41:20) [Clang 15.0.7 ] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
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
[bombrary@nixos:~/tmp/rye-test]$ nix develop

[bombrary@nixos:~]$ echo $LD_LIBRARY_PATH
/nix/store/18m36haf5csgj5fllfnb6njhrhpnjvgz-libxcrypt-4.4.36/lib

[bombrary@nixos:~]$ ./python/bin/python3.11
Python 3.11.1 (main, Jan 16 2023, 22:41:20) [Clang 15.0.7 ] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
```

## まとめ

ごちゃごちゃと書いたが、言いたいことは大体[nix-ldのREADME](https://github.com/Mic92/nix-ld)に集約されており、外部から持ってきた実行バイナリを動かすためには、
* nix-ldを導入する
* 環境変数`LD_LIBRARY_PATH`を指定したシェルが動作するようにnixファイルを書く

をすればよい。しかしうまく動かないケースもあるので、できれば外部バイナリを使わずNixのパッケージを使うようにしたい。

関連するツールとして他にも[nix-alien](https://github.com/thiagokokada/nix-alien)とか[nix-autobahn](https://github.com/Lassulus/nix-autobahn)があるらしいが、これらは今後調べてみようと思う。
