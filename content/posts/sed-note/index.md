---
title: "sedコマンド備忘録"
date: 2026-04-09T19:10:00+09:00
tags: []
categories: [ "sed" ]
---

sedを使ったメモ。

## 前提

* GNU sed 4.9

## GNU版sedをMac + home-managerで導入する

nixpkgsだとgnusedから導入可能。ただMacに標準で入っているBSD版sedと被る & PATHの順序を変える方法がわからないので、別名でsedが実行できるようにしてaliasを作る。

詳細は [Nixで既存パッケージのバイナリ名を別名に変える方法]({{< ref "posts/nix-binary-name" >}}) を参照。

```nix
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    (runCommand "my-gnused" {} ''
        mkdir -p $out/bin
        ln -s ${pkgs.gnused}/bin/sed $out/bin/gnused
    '')
  ];

  programs.zsh = {
    shellAliases = {
      sed = "gnused";
    };
  };
}
```

```console
bombrary@bombrary-macbookair:~/dotfiles% sed
Usage: gnused [OPTION]... {script-only-if-no-other-script} [input-file]...

  -n, --quiet, --silent
                 suppress automatic printing of pattern space
      --debug
                 annotate program execution
  -e script, --expression=script
                 add the script to the commands to be executed

```

## BSD版とGNU版の違い

あまり詳しいことは知らないが微妙に違う。

* GNU版 [sed, a stream editor](https://www.gnu.org/software/sed/manual/sed.html)
* BSD版 [FreeBSD Manual Pages](https://man.freebsd.org/cgi/man.cgi?sed)

自分が見つけたのは以下の点。

### BSD版は、 i コマンドで改行する必要がある

下記は2行目にhiを挿入する例だが、GNU版だと `i text` でできるが、BSD版だと "": command i expects \ followed by text" というエラーが出る。
```console
bombrary@bombrary-macbookair:~/dotfiles% echo "aaa\nbbb\nccc" | sed '2i hi'
aaa
hi
bbb
ccc

bombrary@bombrary-macbookair:~/dotfiles% echo "aaa\nbbb\nccc" | /usr/bin/sed '2i hi'
sed: 1: "2i hi
": command i expects \ followed by text
```

これはそもそも、
```
i text
```

という文法がGNU版のみで定義された代替のsyntaxであり、本来は
```
i \
text
```

のようにバックスラッシュ+改行で入れる必要があるため。

[3.2 sed commands summary](https://www.gnu.org/software/sed/manual/sed.html)

> i\  
> text  
> insert text before a line.
> 
> i text  
> insert text before a line (alternative syntax).

実際、その通りにやるとBSD版でも動く。

```sh
echo "aaa\nbbb\nccc" | /usr/bin/sed '2i \
hi'
```

```console
bombrary@bombrary-macbookair:~/dotfiles% echo "aaa\nbbb\nccc" | sed '2i \
hi'

aaa
hi
bbb
ccc

bombrary@bombrary-macbookair:~/dotfiles% echo "aaa\nbbb\nccc" | /usr/bin/sed '2i \
hi'

aaa
hi
bbb
ccc
```


## セクションで区切られたテキストの編集例

以下のような、セクションを `[...]` で区切ったファイル `input.txt` があるとする。
```ini
[section1]
elem1
elem2
elem3
elem4

[section2]
elem1
elem2

[section3]
elem1
elem2
```

### 範囲を絞った操作

「section2」たけ表示したい場合。
* `/aaa/,/bbb/` で aaa でマッチしたところから bbbでマッチしたところまでを処理範囲にする
* それに対し p コマンドで出力
* `-n` オプションは p コマンドでの出力結果のみを出す

```sh
cat input.txt | sed '/^\[section2\]/,/^$/p' -n
```

```console
bombrary@bombrary-macbookair:~% cat input.txt | sed '/^\[section2\]/,/^$/p' -n
[section2]
elem1
elem2
```


### 末尾に要素を追加する

例えば、「section2の末尾にelem3を追記したい」というケース。

* `/^\[section2\]/,/^$/` で範囲を絞る
* さらに以下で、hiを `/^$/` がマッチした行に挿入
  ```
  /^$/i \
  text
  ```
* `{ ... }` はコマンドをグルーピングするためのブロック
```sh
cat input.txt | sed -e '/^\[section2\]/,/^$/{/^$/i \
hi
}'
```

一行で `/^\[section2\]/,/^$/{/^i/i hi}` と書きたいところだが、これだと `hi}` までが文字列と解釈されてしまう。 `-e` で分けることでそれが回避できるみたい。

```sh
cat input.txt | sed -e '/^\[section2\]/,/^$/{/^$/i hi' -e '}'
```

```console
bombrary@bombrary-macbookair:~% cat input.txt | sed -e '/^\[section2\]/,/^$/{/^$/i hi' -e '}'

[section1]
elem1
elem2
elem3
elem4

[section2]
elem1
elem2
hi


[section3]
elem1
elem2
```

ただこの条件だと末尾の `[section3]` には対応できない。 `[section3]` の場合は a コマンドで追記すると言う条件分岐が必要になる。

ここまで考え出すと、sedでわざわざやるか？と言う気もしてくる。

## 終わりに

ちょっとした整形には便利と言うイメージがあるので使いこなせるようにはなりたい。
