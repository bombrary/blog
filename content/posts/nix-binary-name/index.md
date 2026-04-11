---
title: "Nixで既存パッケージのバイナリ名を別名に変える方法"
date: 2026-04-11T15:48:59+09:00
tags: []
categories: [ "Nix" ]
---


## はじめに

Macに対しhome-manager経由でGNU版のsedを導入したかった。

nixpkgsだとgnusedから導入可能。
```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gnused
  ];
}
```

ところが、環境変数`PATH`の順番のせいで、通常通り`gnused`を入れてもBSD版sedが先に読まれてしまう。
nixないしhome-managerでPATHの順序を入れ替える方法がわからなかったので、次のようにして無理やりGNU版sedを読ませるようにする。

* `sed` コマンドを `gnused` として使えるようにラップする
* それを `shellAliases` に設定

```nix
{ ... }:
{
  home.packages = with pkgs; [
      # (sedコマンドをgnusedとして使えるようにwrapしたもの)
  ];

  # ...

  programs.zsh = {
    shellAliases = {
      sed = "gnused";
    };
  }
}
```

> * `sed` コマンドを `gnused` として使えるようにラップする

これをどうやるのかがこの記事の話題。

## 既存パッケージのバイナリ名を別名にする

すでにビルドされ `sed` として作成したバイナリを、どうにかして `gnused` バイナリとして使えるようにしたい。

### TD;LR

下記でやり方を色々考えているが、結論以下のように runCommand を使うのが好み。

```nix
runCommand "my-gnused" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.gnused}/bin/sed $out/bin/gnused
'';
```

### やりかた1 writeShellScriptBinを使う

* [writeShellScriptBin](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-writeShellScriptBin) を使い、`gnused` というシェルスクリプトが `sed` を呼び出すようにする
* それを `sed` のaliasとして設定

```nix
writeShellScriptBin "gnused" ''
   exec "${gnused}/bin/sed" "$@"
''
```

これを `home.packages` の中に入れたうえでビルドすると、以下のような `gnused` ができている。
```console
bombrary@bombrary-macbookair:~/dotfiles% cat `which gnused`
#!/nix/store/3zrx6av2d1141igkcn8477cvbfqpcmcf-bash-5.3p9/bin/bash
exec "/nix/store/xzsihjm86aqgqarrzifrzr4sfchw4225-gnused-4.9/bin/sed" "$@"
```

ただUsageのところに/nix/storeへの絶対パスが載ってしまうのがちょっと微妙。
```console
bombrary@bombrary-macbookair:~/dotfiles% gnused --help
Usage: /nix/store/xzsihjm86aqgqarrzifrzr4sfchw4225-gnused-4.9/bin/sed [OPTION]... {script-only-if-no-other-script} [input-file]...
```

### やりかた2 mkDerivationを使う

* mkDerivationで新しいパッケージとして作成
  * ただ既存のgnusedへのsymlinkを作成するだけ
* それを `sed` のaliasとして設定

```nix
stdenv.mkDerivation {
  name = "my-gnused";
  version = pkgs.gnused.version;
  buildCommand = ''
    mkdir -p $out/bin
    ln -s ${pkgs.gnused}/bin/sed $out/bin/gnused
  '';
}
```

これでビルドすると、確かに
* my-gnusedが作成されている
* my-gnusedのbinがオリジナルのgnusedのsedへのsymlinkとなっている

ことがわかる。
```console
bombrary@bombrary-macbookair:~/dotfiles% ls -la `readlink $(which gnused)`
lrwxr-xr-x - root  1 Jan  1970 /nix/store/8s9ir0drraknphjsxkw1bdmpm49i1rah-my-gnused/bin/gnused -> /nix/store/xzsihjm86aqgqarrzifrzr4sfchw4225-gnused-4.9/bin/sed
```

で実行してみるとgnusedコマンドとしてUsageが出力される。
```console
bombrary@bombrary-macbookair:~/dotfiles% gnused --help
Usage: gnused [OPTION]... {script-only-if-no-other-script} [input-file]...
...
```

### やりかた3 runCommand を使う

[runCommand](https://nixos.org/manual/nixpkgs/stable/#trivial-builder-runCommand) を使うと、mkDerivationの記述を簡略化できる。

```nix
runCommand "my-gnused" {} ''
    mkdir -p $out/bin
    ln -s ${pkgs.gnused}/bin/sed $out/bin/gnused
'';
```

結果はmkDerivationを使う場合と同じ。

記述量も比較的短いしこれが一番コスパの良い方法かも。

## 終わりに：応用例

今回は単に既存のバイナリと名前が被ってるから別名として扱いたいというケースで使った。

他の応用例としては、複数バージョンのパッケージを同時に扱うことができるようになりそう。

例えば、
* goの1.15のコンパイラを `go1.15`
* goの1.18のコンパイラを `go1.18`
* goの1.26のコンパイラを `go1.26`

として実行できるようにする、などができそう。
