---
title: "Nixを用いたツール実行環境・開発環境を作る方法メモ"
date: 2024-05-05T22:22:49Z
draft: true
toc: true
tags: [ "template", "direnv", "flake", "NixOS"]
categories: [ "Nix" ]
---

## 要約

この記事では、ツールを一時的に導入したり、ツールが実行可能な開発環境を整備したりする目的として、

* 各種コマンド
  * nix shell
  * nix run
  * nix develop
* direnv + nix-direnv
* nix flake init にtemplateを指定する方法

を扱う。

## はじめに

Nixではユーザ環境にパッケージを入れるために、以下の2つのどちらかを使うはず（宣言的に管理できる後者がよりデファクトになっている気がする）。
* [nix-env](https://nixos.org/manual/nix/stable/command-ref/nix-env)
* [home-manager](https://github.com/nix-community/home-manager)

これらは永続的にパッケージを導入する仕組みであるが、一時的に、パッケージを導入したいという場合があるだろう。そのようなケースとしては以下の2つである。
* あるツールを使いたいが、別に永続的にそれを使う必要はない。試しに使ってみたい場合は、ある瞬間にそれが使えれば十分な場合
* virtualenvみたいに、開発時のみに特定のバージョンの開発ツールが導入されている状態であってほしい場合

前者の場合、
* [nix shell](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-shell)
* [nix run](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run)

コマンドを用いる。後者の場合、[nix develop](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop)コマンドを用いる。

## nix shellコマンド

[nix shell](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-shell) コマンドを用いると、一時的にパッケージを導入して新しいshellに入ることができる。

以下のように使うと、パッケージを導入した状態で新しいshellに入る。パッケージは複数指定が可能。
```sh
nix shell (package name) (package name) ...
```

以下は、`nix shell` コマンドを用いてgccを使える状態にする例。
```console
~ $ nix shell nixpkgs#gcc
~ $ gcc --version
gcc (GCC) 13.2.0
Copyright (C) 2023 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

ちなみに、1パッケージ内の1コマンドだけ実行したい場合で、わざわざ新しいshellを作る必要もない場合は、以下のように `--command` 引数を指定する。
```console
~ $ nix shell nixpkgs#gcc --command gcc --version
gcc (GCC) 13.2.0
Copyright (C) 2023 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

## nix runコマンド {#nix-run-in-flake}

[nix run](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run)は上記の `--command` 付きの `nix-shell` の簡略版。

### 外部パッケージを手軽に実行する

```console
~ $ nix run nixpkgs#gcc -- --version
gcc (GCC) 13.2.0
Copyright (C) 2023 Free Software Foundation, Inc.
This is free software; see the source for copying conditions.  There is NO
warranty; not even for MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
```

上記では横棒 `--` が `--version` の前に挟まれているが、これは `nix run` コマンドの引数と `gcc` の引数を区別するためのもの。

内部動作は[Description](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-run#description)を見るとわかるが、パッケージの元となるderivationに特に何も設定されていなければ、そのパッケージ名と同じファイルを実行する。例えばパッケージ名が `gcc` の場合、 `$out/bin/gcc` を実行する。そのため、パッケージ名と実行ファイルが異なる場合はこのコマンドは使えない場合がある。

### 自分のflake.nixから使う

もちろん自分で書いた `flake.nix` に書いたパッケージについて `nix run` で実行することができるので、簡易的なシェルスクリプトを書いてコマンドとして定義したり、ある実行ファイルのエイリアスを作ったりできる。いわゆる `npm run` 的にコマンドが作れる。

やり方は、自分が作った `flake.nix` のoutputsの `packages` に指定する。以下の[writeShellScriptBin](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-writeText)は、shellスクリプトを作成しそれを `$out/bin/(第一引数で指定した名前)` として出力するderivation（を返す関数）である。
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
    packages.x86_64-linux.my-hello = pkgs.writeShellScriptBin "my-hello" ''
      echo "Hello!"
    '';
  };
}
```

実行例。
```console
~/t/nix-develop-test $ nix run .#my-hello
Hello!
```

ちなみに実行ファイル名がパッケージ名と異なる場合は、以下のように `apps` に指定する。以下は、 `my-hello` を別名 `hello-alias` として実行したい場合の例。 `program` に実行ファイルへのパスを設定する。
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
    packages.x86_64-linux.my-hello = pkgs.writeShellScriptBin "my-hello" ''
      echo "Hello!"
    '';
    apps.x86_64-linux.hello-alias = {
      type = "app";
      program = "${self.packages.x86_64-linux.my-hello}/bin/my-hello";
    };
  };
}
```

実行例。
```console
~/t/nix-develop-test $ nix run .#hello-alias
Hello!
```

## nix developコマンド {#nix-develop}

[nix develop](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop)は、ドキュメントを引用すると
> nix develop - run a bash shell that provides the build environment of a derivation

である。つまりderivationをビルドするためのbashを提供するコマンドである。そのため、自分が開発したいものがderivationとして扱われることが前提にあるが、単に開発ツールや依存関係ををひとまとめにした環境を作る使い方もできる。

### 使い方

[Flake output attributes](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop#flake-output-attributes)に書いてある通り、 `devShells` というoutputにderivationを記述する。derivationには[nixpkgsのmkShellNoCC](https://nixos.org/manual/nixpkgs/unstable/#sec-pkgs-mkShell-variants)を使おう。以下では、
* `packages = ...` でpythonを指定している
* 環境変数 `FOO` を設定している
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
    devShells.x86_64-linux.default = pkgs.mkShellNoCC {
      packages = with pkgs; [
        python312
      ];
      FOO = "BAR";
    };
  };
}
```

`nix develop` コマンドを実行すると、bashに入り、
* `flake.nix` に設定した `python` が実行できる
* `flake.nix` に設定した環境変数が設定されている
```console
~/t/nix-develop-test $ nix develop

[bombrary@nixos:~/tmp/nix-develop-test]$ python --version
Python 3.12.3

[bombrary@nixos:~/tmp/nix-develop-test]$ echo $FOO
BAR
```

#### 余談

`mkShell`ないし`mkShellNoCC`の動作について。

* `inputsFrom` にderivationやパッケージを指定すると、それを[stdenv.mkDerivation](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv)の各種buildInputsやnativeBuildInputsに波及させられる。詳細は[mkShell](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/build-support/mkshell/default.nix)のソースコードを読めばよい。例えばあるパッケージをビルドしたくて、その依存関係を全部備えた上でshellを作りたい場合に役立つかも
* [stdenv.mkDerivation](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv)ないしそれをラップした関数（ `mkShell` も含む）が前提で作られている模様。これは `nix develop -vvvv` や `nix derivation show` で探ってみるとわかるが、以下のように stdenv に依存する記述があるからである
  * `$name-env` をビルドするときに、 `get-env.sh` がbuilderの引数に指定される
  * [get-env.sh](https://github.com/NixOS/nix/blob/2.22.0/src/nix/get-env.sh)を見ると、 `$stdenv` がもしあったら `$stdenv/setup` を実行する記述がある


### bash起動までの内部動作

内部動作としては[Nix 2.22.0のdevelop.cc](https://github.com/NixOS/nix/blob/2.22.0/src/nix/develop.cc#L573)を読むと、
1. `$name-env` というderivationを作成、ビルドする
   * `$name` はderivation名で、`mkShell` の場合特に指定がなければ `name=nix-shell` となる（[該当ソース](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/build-support/mkshell/default.nix#L5)）。
   * `$name-env` のoutputはJSON形式で、環境変数やパッケージなどの情報が詰まっている。これがおそらく、[Example](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop#examples)で言及されている `profile` のこと。
2. `$name-env` のoutputからbashrcを生成する
3. 2を引数にしてbashを起動する

となっていることが分かる。

### （おまけ） nix-shell コマンドについて

[nix-shell](https://nixos.org/manual/nix/stable/command-ref/nix-shell)コマンドもまた、シェルを起動するが、こちらは`nix develop`とほぼ同機能のコマンドである。目的についても、[Description](https://nixos.org/manual/nix/stable/command-ref/nix-shell#description)に、
>  This is useful for reproducing the environment of a derivation for development.

と記載されている。

違いとしては、こちらはNix Flakeが開発される前に作成されたコマンドのため、`flake.nix` ではなく `shell.nix` にderivation定義を記述する点である。

## bash以外のshellを使った開発環境が作りたい場合

### nix developコマンドがbashしか対応していないのはなぜ？（考察）

`nix develop` コマンドのデフォルトのshellはbashである。ほかのshellをオプションで切り替えられるということはできない。理由として考えられるのは以下の2点。
* shellはたくさんあるので、`nix develop` に全部対応させるのは現実的でない
* ほとんどの場合bashがderivationをビルドするために使われている

まずNixは、あらゆるパッケージをderivaitonからビルドすることを前提として作られている。そして `nix develop` は、ビルドのインタラクティブなshellを提供するコマンドであった。

derivationを作るといった場合、[builtinのderivation](https://nixos.org/manual/nix/stable/language/derivations)を使うことはあまりなく、多くの場合[nixpkgsのstdenv.mkDerivation](https://nixos.org/manual/nixpkgs/stable/#sec-using-stdenv)ないしそれをラップしたものを用いることになる。そしてこの `mkDerivation` は、内部的にはbashスクリプトを実行してパッケージをビルドする。

derivationのほとんどがbashを用いる以上、 `nix develop` が用いるshellはbashが望ましい。実際、[nix developのExample](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-develop#examples)にある `configurePhase` 、 `buildPhase` 、 `installPhase` などのコマンドは `mkDerivation` に含まれているbash関数であり、bashでないと動作しない。

ビルドの動作確認として `nix develop` を使うならbashが良いことが分かった。しかしそれ以外の場合、例えば、別にderivationをビルドする目的で使わず、bashの関数を使う必要もない場合は、別のshellを使いたいときもある。その場合、以下のやり方が考えられる。
* `nix develop` コマンドを用いる
  * （その1）`shellHook` に `exec (shell名)` を記述する
    * 参考：[Using zsh/fish/... instead of bash](https://nixos-and-flakes.thiscute.world/development/intro#using-zsh-fish-instead-of-bash)
* `nix develop` コマンドをそもそも使わない
  * （その2）`nix shell`コマンドを用いる： `packages` に [runCommand](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-runCommand) を指定
    * 参考：[Creating a Development Environment with pkgs.runCommand](https://nixos-and-flakes.thiscute.world/development/intro#creating-a-development-environment-with-pkgs-runcommand)
  * （その3）direnvとnix-direnvを使う

### （その1）nix developを用いる方法

`nix develop` コマンドは `shellHook` を、shell起動時に実行するように作られている（ドキュメントに記載はないものの、ほぼ同機能の[nix-shell](https://nixos.org/manual/nix/stable/command-ref/nix-shell)のドキュメントには`shellHook`について記載されている）。そのため、 `shellHook` に `exec (shell名)` を指定すれば、好きなshellに入った状態にできる。

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
    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        python312
      ];
      shellHook = ''
        exec ${pkgs.fish}/bin/fish
      '';
    };
  };
}
```

実行例。
```console
~/t/nix-develop-test $ nix develop

[bombrary@nixos:~/tmp/nix-develop-test]$ python --version
Python 3.12.3
```

### （その2）nix shellを用いる方法

[nix runをflake.nixから使う](#nix-run-in-flake)の応用。お好みのshellの実行ファイルをラップしたパッケージを作成する。

[nixpkgsのrunCommand](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-runCommand)は、`stdenv.mkDerivation` よりもシンプルなderivaiton作成関数で、最後の引数に指定されたシェルスクリプトを実行することでoutputを作成するだけである。これを用いて、outputに`fish`へのsymlinkを張る。

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
    packages.x86_64-linux.dev-shell = pkgs.runCommand "dev-shell" {
      packages = with pkgs; [
        python312
      ];
    } ''
     mkdir -p $out/bin/
     ln -s ${pkgs.fish}/bin/fish $out/bin/dev-shell
    '';
  };
}
```

ところがこの状態だと、素のfishのsymlinkを張っただけで、環境変数 `PATH` が何も設定されていない。
```console
~/t/nix-develop-test $ nix run .#dev-shell
Welcome to fish, the friendly interactive shell
Type help for instructions on how to use fish

~/t/nix-develop-test $ python --version
DBI connect('dbname=/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite','',...) failed: unable to open database file at /run/current-system/sw/bin/command-not-found line 13.
cannot open database `/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite' at /run/current-system/sw/bin/command-not-found line 13.
```

そこで、以下のように、環境変数 `PATH` を付加したfishを作成する。
* [makeWrapper](https://nixos.org/manual/nixpkgs/stable/#chap-trivial-builders)パッケージの `wrapProgram` 関数を使い、環境変数を設定した実行ファイルを新たに作成できる。引数については[make-wrapper.shのソースコード](https://github.com/NixOS/nixpkgs/blob/nixos-23.11/pkgs/build-support/setup-hooks/make-wrapper.sh)のが詳しいのでそちらを参照
* `LD_LIBRARY_PATH` など、他に付けたい環境変数があれば、`wrapProgram` の引数に追加する
* `PATH`は`:`で実行ファイルのあるパスを文字列指定するが、そのような文字列を作成するユーティリティに[lib.strings.makeBinPath](https://nixos.org/manual/nixpkgs/stable/#sec-functions-library-strings)があるので、それを使っている
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
    packages.x86_64-linux.dev-shell =
    let
      packages = with pkgs; [
        python312
      ];
    in
    pkgs.runCommand "dev-shell" {
      packages = packages;
      nativeBuildInputs = [ pkgs.makeWrapper ];
    } ''
     mkdir -p $out/bin/
     ln -s ${pkgs.fish}/bin/fish $out/bin/dev-shell
     wrapProgram $out/bin/dev-shell --prefix PATH : ${pkgs.lib.strings.makeBinPath packages}
    '';
  };
}
```

実行例。
```console
~/t/nix-develop-test $ nix run .#dev-shell
Welcome to fish, the friendly interactive shell
Type help for instructions on how to use fish

~/t/nix-develop-test $ python --version
Python 3.12.3
```

`nix develop` を使った場合に比べ、環境変数の準備などやることが多いが、一からカスタマイズして開発環境を用意したい場合に有効かもしれない。

### （その3）direnvとnix-direnvの利用

[direnv](https://github.com/direnv/direnv)と[nix-community/nix-direnv](https://github.com/nix-community/nix-direnv)と組み合わせると、`flake.nix` に `devShells` が設定されたディレクトリに入ったときに、`nix develop` で実行された時と同じ環境変数が自動で設定される。別に `nix develop` を実行しているわけではないので、shellが切り替わることはない。

まずnix-direnvの[installation](https://github.com/nix-community/nix-direnv/tree/master?tab=readme-ov-file#installation)にはいくつか方法が書いてあるが、
* 今後継続的に使ってみるならhome-managerに指定する方法
* お試しで使ってみるなら `.envrc` にソースを書き込む方法

を試してみるのがよいかもしれない。もちろん、nix-direnvだけでなくその大元であるdirenvの導入も必要なので注意。

ここでは[home-manager](https://github.com/nix-community/nix-direnv?tab=readme-ov-file#via-home-manager)の導入を試す。以下は home-manager の設定ファイルの追記例。
```nix
{pkgs, ...}: {
  # ...
  programs.direnv = {
    enable = true;
    enableBashIntegration = true; # see note on other shells below
    nix-direnv.enable = true;
  };
  # ...
}
```

`flake.nix` は[nix developコマンド](#nix-develop)のときと同じにする。
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
    devShells.x86_64-linux.default = pkgs.mkShellNoCC {
      packages = with pkgs; [
        python312
      ];
      FOO = "BAR";
    };
  };
}
```

`use flake` と書かれた行を `.envrc` に追記して、 `direnv allow` コマンドを実行する。
```console
~/t/nix-develop-test $ echo "use flake" >> .envrc
direnv: error /home/bombrary/tmp/nix-develop-test/.envrc is blocked. Run `direnv allow` to approve its content

~/t/nix-develop-test $ direnv allow
direnv: loading ~/tmp/nix-develop-test/.envrc
direnv: using flake
direnv: nix-direnv: renewed cache
direnv: export +CONFIG_SHELL +DETERMINISTIC_BUILD +FOO +HOST_PATH +IN_NIX_SHELL +NIX_BUILD_CORES +NIX_CFLAGS_COMPILE +NIX_ENFORCE_NO_NATIVE +NIX_LDFLAGS +NIX_STORE +PYTHONHASHSEED +PYTHONNOUSERSITE +PYTHONPATH +SOURCE_DATE_EPOCH +_PYTHON_HOST_PLATFORM +_PYTHON_SYSCONFIGDATA_NAME +__structuredAttrs +buildInputs +buildPhase +builder +cmakeFlags +configureFlags +depsBuildBuild +depsBuildBuildPropagated +depsBuildTarget +depsBuildTargetPropagated +depsHostHost +depsHostHostPropagated +depsTargetTarget +depsTargetTargetPropagated +doCheck +doInstallCheck +dontAddDisableDepTrack +mesonFlags +name +nativeBuildInputs +out +outputs +patches +phases +preferLocalBuild +propagatedBuildInputs +propagatedNativeBuildInputs +shell +shellHook +stdenv +strictDeps +system ~PATH ~XDG_DATA_DIRS
```

環境変数が効いていることが分かる。
```console
~/t/nix-develop-test $ python --version
Python 3.12.3

~/t/nix-develop-test $ echo $FOO
BAR
```

ディレクトリを抜けると、環境変数が効かなくなったことが分かる。
```console
~/tmp $ python --version
DBI connect('dbname=/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite','',...) failed: unable to open database file at /run/current-system/sw/bin/command-not-found line 13.
cannot open database `/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite' at /run/current-system/sw/bin/command-not-found line 13.
~/tmp $ echo $FOO

```

## 開発環境のtemplate化

いままで開発環境を `flake.nix` に書いてきたが、毎度毎度これを書くのは面倒である。そこで、`flake.nix` に限らずファイルやディレクトリのひな形をtemplateとして残しておいて、`nix flake init`の時にそこからコピーしてくるようにする仕組みがある。

### 自分で作る方法

具体的には、flakeのoutputsに `templates` 属性があるのでそれを指定する。

試しにtemplateを作って、それを用いて開発環境を用意しよう。`~/flake-templates/` を作成し、以下のようにする。
```console
~/flake-templates $ nix run nixpkgs#tree
.
├── flake.lock
├── flake.nix
└── templates
    └── foo
        ├── flake.nix
        └── src
            └── main.py

4 directories, 4 files
```

`./flake-templates/flake.nix` を次のようにする。
* `templates.<name>` の `<name>` のところは適当なものにする。
* 他に、templateが展開されたときに時に文章を出力できる引数 `welcomeText` がある。詳細は [nix flake init](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake-init#template-definitions)を参照。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: {
    templates.foo = {
      path = ./templates/foo;
      description = "bar";
    };
  };
}
```

この状態で、適当なディレクトリから `nix flake init` を実行する。このとき、 `-t` でtemplateを指定する。 `<flake.nixへのパス>#<name>` の形式。
```console
~/t/foo $ nix flake init -t ~/flake-templates#foo .
warning: Git tree '/home/bombrary/flake-templates' is dirty
wrote: /home/bombrary/tmp/foo/flake.nix
wrote: /home/bombrary/tmp/foo/src/main.py
wrote: /home/bombrary/tmp/foo/src
```

ファイルやディレクトリが作成されていることがわかる。
```console
~/t/foo $ nix run nixpkgs#tree
.
├── flake.nix
└── src
    └── main.py

2 directories, 2 files
```

### 外部のtemplateを利用する方法

`nix flake init` コマンドの `-t` 引数にはflakeへのリポジトリも指定可能なので、誰かが作った外部のtemplateをとってくることもできる。実は[NixOS/templates](https://github.com/NixOS/templates)にはある程度の言語が揃っているので、ここからtemplateを引っ張ってきた後に、自分なりに整形すればよい。また、ほかのリポジトリを探したり、また自分でリポジトリを作って管理しても良し。

例えば、以下は[NixOS:templates#python](https://github.com/NixOS/templates/blob/1c160025a3137d9109f51939bd2473520040ff8f/flake.nix#L18)の例。どうやらpoetry向けのプロジェクトのようで、[pythonディレクトリ](https://github.com/NixOS/templates/tree/1c160025a3137d9109f51939bd2473520040ff8f/python)にあるものが展開されている。
```console
~/t/foo $ nix flake init -t github:NixOS/templates#python
wrote: /home/bombrary/tmp/foo/flake.nix
wrote: /home/bombrary/tmp/foo/poetry.lock
wrote: /home/bombrary/tmp/foo/pyproject.toml
wrote: /home/bombrary/tmp/foo/README.md
wrote: /home/bombrary/tmp/foo/sample_package/__init__.py
wrote: /home/bombrary/tmp/foo/sample_package/__main__.py
wrote: /home/bombrary/tmp/foo/sample_package


Getting started

      · Run nix develop
      · Run poetry run python -m sample_package

~/t/foo $ nix run nixpkgs#tree
.
├── flake.lock
├── flake.nix
├── poetry.lock
├── pyproject.toml
├── README.md
└── sample_package
    ├── __init__.py
    └── __main__.py

2 directories, 7 files
```

## （おまけ）その他トピック

### numtide/devshellを使ってみる

[numtide/devshell](https://github.com/numtide/devshell)は、`nix develop` での設定ファイルをNixではなくtomlで書くようにしたものっぽい。READMEによると、シンプルに開発環境を記述できることが目的のようだ。

READMEによるとまだunstable状態のようだが、試しに[docsのGetting started](https://numtide.github.io/devshell/getting_started.html)をやってみる。flakesの場合、templateがあるようなのでそれを引っ張ってくる。

```console
~/t/foo $ nix flake new -t "github:numtide/devshell" .
wrote: /home/bombrary/tmp/foo/flake.nix
wrote: /home/bombrary/tmp/foo/flake.lock
wrote: /home/bombrary/tmp/foo/devshell.toml
wrote: /home/bombrary/tmp/foo/shell.nix
wrote: /home/bombrary/tmp/foo/.gitignore
wrote: /home/bombrary/tmp/foo/.envrc
```

`devshell.toml` を次のようにする。
```toml
# https://numtide.github.io/devshell
[[commands]]
package = "python312"

[[env]]
name = "FOO"
value = "bar"

[[env]]
name = "BAZ"
value = "qux"
```

`nix develop` を起動すると、
* 親切なメニューが出力され、python3が使えることを教えてくれる
* 環境変数が設定されている

```console
~/t/foo $ nix develop
🔨 Welcome to devshell

[general commands]

  menu    - prints this menu
  python3 - A high-level dynamically-typed programming language

[devshell]$ echo $FOO $BAZ
bar qux
```

続いて、新しいコマンドを追加してみる。 `flake.nix` を編集する。
* `my-hello` を追加
* nixpkgsをimportするところで、`my-hello` パッケージを追加するようにoverlayを指定
  * [overlay](https://nixos.wiki/wiki/Overlays)をちゃんと説明しようとすると別記事が作れそうなので、ここでは省略する
```nix
{
  # ...
  outputs = { self, flake-utils, devshell, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      devShells.default =
        let
          my-hello = nixpkgs.legacyPackages.${system}.writeShellScriptBin "my-hello" ''
            echo Hello
          '';
          pkgs = import nixpkgs {
            inherit system;

            overlays = [
              devshell.overlays.default
              (final: prev: { my-hello = my-hello; })
            ];
          };
        in
        pkgs.devshell.mkShell {
          imports = [ (pkgs.devshell.importTOML ./devshell.toml) ];
        };
    });
}
```

これで、nixpkgsにあたかも `my-hello` が入っているようにできた。そのため、以下のように `devshells.toml` に指定できる。
```toml
[[commands]]
package = "my-hello"
help = "print hello"
```

実行例。
```console
~/t/foo $ nix develop
🔨 Welcome to devshell

[general commands]

  menu     - prints this menu
  my-hello - print hello
  python3  - A high-level dynamically-typed programming language

[devshell]$ my-hello
Hello
```

## 参考

* [Development Environments on NixOS](https://nixos-and-flakes.thiscute.world/development/intro)
  * 本記事を8割くらい書いたあとにこの記事を発見した。内容がかなりかぶってしまった…
* [Getting started with Nix Flakes and devshell](https://yuanwang.ca/posts/getting-started-with-flakes.html)
