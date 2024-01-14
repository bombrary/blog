---
title: "NixOSをWSL2上で構築したときのメモ"
date: 2024-01-13T11:23:15+09:00
tags: ["WSL", "NixOS"]
categories: ["setup"]
---

年末からお正月の間帰省したときにWindowsのラップトップを持っていった。しかしWSL2にはUbuntuしか入っておらず、最近デスクトップで使っている[NixOS](https://nixos.org/)が入っていなかった。そこで試しに構築してみたときのメモ。最低限コーディングができる環境が整った。

（IT系あるあるだけれど）[NixOS-WSL](https://github.com/nix-community/NixOS-WSL)の開発はまあまあ早いため、ここに書いてある内容もすぐ陳腐化してしまいそう。

## インストール

[Repository](https://github.com/nix-community/NixOS-WSL)のReleasesから`nixos-wsl.tar.gz`をDLしてくる

コマンドプロンプト or PowerShell で以下のコマンドを実行
```ps
wsl --import NixOS .\NixOS\ nixos-wsl.tar.gz --version 2
wsl -d NixOS
nix-channel --update
```

## Flake化による初回セットアップ

今回はなるべくnix-channelを使わず、flake.nixからなるべく必要なファイルを入れるようにしたい。そのほうが、今後再セットアップするときにそのflakeファイルを指定するだけで環境が構築できることを期待しているため。

とはいえ、現状のNixOSにはVimもGitも入っておらず限界があるので、それはChannelから入手する。まず現時点での最新版のnixosのChannelを登録する。

```sh
sudo nix-channel --add https://nixos.org/channels/nixos-23.11 nixos
sudo nix-channel --update
```

次にVimとGitを入れる。Vimはテキスト編集のため、Gitはnix-flakeの動作のために必要。

```sh
nix-shell -p vim git
```

[NixOSで最強のLinuxデスクトップを作ろう](https://zenn.dev/asa1984/articles/nixos-is-the-best#flake%E5%8C%96)や[Using nix flakes with NixOS](https://nixos.wiki/wiki/Flakes#Using_nix_flakes_with_NixOS)に書かれている内容を参考に進めていく。

まずホームディレクトリに移動し、適当なディレクトリ`nixos-config`を作り、そこにNixOSの設定ファイル（`configuration.nix`）を持ってくる。

```sh
cd ~
mkdir nixos-config
cd nixos-config
cp /etc/nixos/* .
```

`flake.nix`を作成し以下のようにする。

- inputsにnixosのリポジトリと、NixOS-WSLのリポジトリを指定する
  - [inputs](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html#flake-references)の書き方はattribute setとurl-likeな書き方の2種類がある。url-likeな書き方だとtag指定の方法がわからなかったので、NixOS-WSLのinputに関してはattribute setで書いている
- nixosSystemの引数として`specialArgs`が指定でき、これで`configuration.nix`に引数を渡せる

```nix
{
  inputs = {
    nixos.url = "github:NixOS/nixpkgs/nixos-23.11";
    nixos-wsl = {
      type = "github";
      owner = "nix-community";
      repo = "NixOS-WSL";
      ref = "2311.5.3";
    };
  };

  outputs = inputs: {
    nixosConfigurations = {
      wsl = inputs.nixos.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
        ];
        specialArgs = {
          nixos-wsl = inputs.nixos-wsl;
        };
      };
    };
  };
}
```

現在、`configuration.nix`ではWSL用のモジュールを`nixos-wsl` Channelから取得するようになっている。

```sh
> sudo nix-channel --list
nixos https://nixos.org/channels/nixos-23.11
nixos-wsl https://github.com/nix-community/NixOS-WSL/archive/refs/heads/main.tar.gz
```

もしそのまま実行したいなら、以下のコマンドでビルドが可能。`--impore`引数をつける必要がある。
```sh
sudo nixos-rebuild switch --impure --flake .#wsl
```

しかしこのままだとローカルな環境のChannelに依存することになってしまう。flakeでビルドするときはflakeだけで完結させたいので、Channelを使わないような設定に書き換える。そのために、cpでコピーしてきた`configuration.nix`を編集する。

- 引数に`nixos-wsl`を追加。これは先ほど`flake.nix`で`specialArgs`として指定したattributeに当たる
- `<nixos-wsl/modules>`のところを`nixos-wsl.nixosModules`に変える

```nix
{ config, lib, pkgs, nixos-wsl, ... }:
{
  ...
  imports = [
    # include NixOS-WSL modules
    nixos-wsl.nixosModules.wsl
  ];
  ...
}
```

これで、次のように`--impure`無しでコマンドが実行可能になる。

```sh
sudo nixos-rebuild switch --flake .#wsl
```

## Flakeの有効化

`configuration.nix`に以下を追記。

```nix
{ config, lib, pkgs, nixos-wsl, ... }:
{
  ...
  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
    };
  };
  ...
}
```


## ユーザの追加

- `configuration.nix`で、自分ユーザの設定を追加しておく。
-  今ログインしている`nixos`ユーザの設定を変えるのは余計なトラブルの元になりそうなので避ける
- お好みでshellを設定する

```nix
{ config, lib, pkgs, nixos-wsl, ... }:
{
  ...
  wsl.defaultUser = "nixos";

  users.users.ユーザ名 = {
    shell = pkgs.fish;
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  programs.fish.enable = true;

  security.sudo = {
    enable = true;
  };
  ...
}
```

ビルド後、`sudo passwd ユーザ名` でユーザのパスワードを設定しておく。

ユーザを指定してログインしたい場合は、`-u`をつけてログインが可能。
```ps
（コマンドプロンプト or PowerShell内で）
wsl -d NixOS -u ユーザ名
```

何か設定を間違えてsudoできなくなってしまったという場合には、rootでログインするという手もあるので覚えておく。
```ps
（コマンドプロンプト or PowerShell内で）
wsl -d NixOS -u root
```

### 余談

`isNormalUser`の指定がなかった場合にビルドしたときのエラー。ありえないくらい親切にエラーを出してくれる。

```
error:
Failed assertions:
- Exactly one of users.users.bombrary.isSystemUser and users.users.bombrary.isNormalUser must be set.

- users.users.bombrary.group is unset. This used to default to
nogroup, but this is unsafe. For example you can create a group
for this user with:
users.users.bombrary.group = "bombrary";
users.groups.bombrary = {};

- users.users.bombrary.shell is set to fish, but
programs.fish.enable is not true. This will cause the fish
shell to lack the basic nix directories in its PATH and might make
logging in as that user impossible. You can fix it with:
programs.fish.enable = true;

If you know what you're doing and you are fine with the behavior,
set users.users.bombrary.ignoreShellProgramCheck = true;
instead.
```

## home-managerの設定

ユーザを作成したら、一応NixOSの再起動を行い、自分が作ったユーザでログインする。

```ps
wsl --shutdown NixOS
wsl -d NixOS -u ユーザ名
```

また設定ファイルを掻くので、gitをvimを入れておく。
```sh
nix-shell -p git vim
```

先程作った設定ファイルを持ってくる
```sh
sudo mv -r /home/nixos/nixos-config .
sudo chown ユーザ名 -R nixos-config
```

`flake.nix`にhome-managerの設定を追記する。

```nix
{
  inputs = {
    ...
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {
    ...
    homeConfigurations = {
      myHome = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = import inputs.nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        extraSpecialArgs = {
          inherit inputs;
        };
        modules = [
          ./home.nix
        ];
      };
    };
  };
}
```

`home.nix`をまず次のようにする。
```nix
{
  home = rec {
    username = "ユーザ名";
    homeDirectory = "/home/${username}";
    stateVersion = "23.11";
  };
  programs.home-manager.enable = true;
}
```

初回設定の適用
```sh
nix run home-manager -- switch --flake .#myHome
```

後は`home.nix`を書き換えて好きなパッケージを入れる。
