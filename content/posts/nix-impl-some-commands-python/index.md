---
title: "Nixのいくつかの処理をPythonで実装してみる"
date: 2024-04-04T00:05:01Z
draft: true
tags: ["Python", "derivation"]
categories: ["Nix"]
toc: true
---



## derivationをパースする

drvファイルをぐっとにらむと、データ型としては以下のパターンしかなさそうだとわかる。
* 文字列：`"` でくくられている
* リスト：`[`と`]`でくくられている
* タプル：`(`と`)`でくくられている

最初の`Derive(...)`もタプルとして解釈することにすると、drvの形式をパースする関数`parse_drv`は次のように実装できる。ほとんどの`parse_*`関数は、返り値を`(パースした値, 残りの文字列)`のタプルで返すように実装している。

```python
def parse_drv(s: str) -> tuple:
    s = s[len("Derive("):]
    r, _ = parse_tuple(s)
    return r

def parse_ch(s: str) -> tuple[str, str]:
    return s[0], s[1:]

def parse_prim(head: str, s: str) -> tuple[tuple|list|str, str]:
    match head:
        case "(":
            return parse_tuple(s)
        case "[":
            return parse_list(s)
        case "\"":
            return parse_str(s)
        case _:
            raise ValueError("Invalid token")

def parse_tuple(s: str) -> tuple[tuple, str]:
    res = []
    while True:
        c, s = parse_ch(s)
        match c:
            case ")":
                break
            case ",":
               pass
            case _:
                r, s = parse_prim(c, s)
                res.append(r)
    return tuple(res), s

def parse_list(s: str) -> tuple[list, str]:
    res = []
    while True:
        c, s = parse_ch(s)
        match c:
            case "]":
                break
            case ",":
                pass
            case _:
                r, s = parse_prim(c, s)
                res.append(r)
    return res, s

def parse_str(s: str) -> tuple[str, str]:
    res = ""
    while True:
        match s[0]:
            case "\"":
                c, s = parse_ch(s)
                if res and res[-1] == "\\":
                    res += c
                else:
                    break
            case _:
                c, s = parse_ch(s)
                res += c
    return res, s
```

## derivationの直接的・間接的なbuild dependenciesもすべて出力する

上記の関数をもとに、再帰的に依存関係を探る関数`show_deps`を実装する
* `nix derivation show`コマンドでのinputDrvsは、drvファイルでは`Derive(...)`の2番目の要素に入っているので、そこから取り出す
* ある依存関係がほかのderivationの依存関係になっていることがあるが、同じものが出てきた場合は省略する。省略のためのメモとして`DRV_CACHE`を用意している
* ツリー構造として読み込んだ後、`show_tree`で出力する

```python
import sys

DRV_CACHE = {}

Tree = str | dict[str, "Tree"]

def load_drv(path: str) -> tuple:
    with open(path) as f:
        return parse_drv(f.read())

def dump_deps(path: str) -> Tree:
      if path not in DRV_CACHE:
          DRV_CACHE[path] = load_drv(path)
          input_drvs = DRV_CACHE[path][1]
          input_srcs = DRV_CACHE[path][2]
          res = { input_drv_path: dump_deps(input_drv_path) for input_drv_path, _ in input_drvs }
          res |= { src: "" for src in input_srcs }
          return res
      else:
          return ": cached"

def show_tree(tree: Tree, last: bool, header=""):
    if isinstance(tree, str):
        return

    for i, (k, v) in enumerate(tree.items()):
        last = i == len(tree) - 1
        print(header, end="")
        if last:
            print("└──", end="")
        else:
            print("├──", end="")

        if isinstance(v, str):
            print(f'{k}{v}')
        else:
            print(k)

            if last:
                header_children = header + "   "
            else:
                header_children = header + "│  "
            show_tree(v, last, header_children)


if __name__ == "__main__":
    tree = dump_deps(sys.argv[1])
    show_tree(tree, True, "")
```

実行例。

```console
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
├──/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
│  ├──/nix/store/1vzpfyxn64qx5my47kc0hjys37404hls-gcc-12.3.0.drv
│  │  ├──/nix/store/1032as2ph6j8pwan8dijl60jmfnzfi6b-perl-5.38.2.drv
│  │  │  ├──/nix/store/2zsw6v5l9zzhslrrdqpljnb425njg1pf-perl-5.38.2.tar.gz.drv
│  │  │  ├──/nix/store/9xhbdxvc93v7hc4vplng07z3y3lmfwvq-bootstrap-stage1-stdenv-linux.drv
│  │  │  │  ├──/nix/store/271ydjn02v2r49l5nn6yw5lr3nc5ydbi-update-autotools-gnu-config-scripts-hook.drv
│  │  │  │  │  ├──/nix/store/303sqdqr3x78jlgs00pixbdwv7hqizq1-gnu-config-2023-09-19.drv
│  │  │  │  │  │  ├──/nix/store/h11pn2l5rszzgjrl84qw2ifr33rdkjcq-config.sub-28ea239.drv
│  │  │  │  │  │  ├──/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
│  │  │  │  │  │  │  ├──/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
...
│  ├──/nix/store/jm8hin39q3ms3gffpa2w3xk8bxmychm3-make-shell-wrapper-hook.drv: cached
│  ├──/nix/store/mvvhw7jrrr8wnjihpalw4s3y3g7jihgw-stdenv-linux.drv: cached
│  ├──/nix/store/szciaprmwb7kdj7zv1b56midf7jfkjnw-bash-5.2-p15.drv: cached
│  ├──/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
│  ├──/nix/store/cklrwbwi889pp2fdsswdjvn12sdy5i5j-openssl-disable-kernel-detection.patch
│  ├──/nix/store/lzmcfv2m4ripknpvbsv8wcg1ik1kif4h-use-etc-ssl-certs.patch
│  ├──/nix/store/sq4h6bqjx12v9whvm65pjss25hg1538q-nix-ssl-cert-file.patch
│  └──/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
├──/nix/store/1cwqp9msvi5z8517czfl88dd42yhrdwg-separate-debug-info.sh
└──/nix/store/v6x3cs394jgqfbi0a42pam708flxaphh-default-builder.sh
```

ツリー構造ではなくただ一覧で表示したい & cachedの行はいらない場合は、適当にsedやgrepで整形すればよい。
```
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv | sed 's/.*\(\/nix\/store\/.*\)/\1/' | grep -v cached
/nix/store/5q67fxm276bdp87jpmckvz3n81akw6a5-perl-5.38.2.drv
/nix/store/1vzpfyxn64qx5my47kc0hjys37404hls-gcc-12.3.0.drv
/nix/store/1032as2ph6j8pwan8dijl60jmfnzfi6b-perl-5.38.2.drv
/nix/store/2zsw6v5l9zzhslrrdqpljnb425njg1pf-perl-5.38.2.tar.gz.drv
/nix/store/9xhbdxvc93v7hc4vplng07z3y3lmfwvq-bootstrap-stage1-stdenv-linux.drv
/nix/store/271ydjn02v2r49l5nn6yw5lr3nc5ydbi-update-autotools-gnu-config-scripts-hook.drv
/nix/store/303sqdqr3x78jlgs00pixbdwv7hqizq1-gnu-config-2023-09-19.drv
/nix/store/h11pn2l5rszzgjrl84qw2ifr33rdkjcq-config.sub-28ea239.drv
/nix/store/ks6kir3vky8mb8zqpfhchwasn0rv1ix6-bootstrap-tools.drv
/nix/store/b7irlwi2wjlx5aj1dghx4c8k3ax6m56q-busybox.drv
...
```

## ファイル・ディレクトリをNAR形式に変換する

同様のことは`nix nar dump-path`コマンドでも行えるが、勉強のためPythonで同様の処理を実装した。

[edolstra氏のPh.D論文](https://edolstra.github.io/pubs/phd-thesis.pdf)のp.93のFigure 5.2をもとに作成。

```python3
import io
import os
import stat

def archiveNAR(out_path: str) -> bytes:
    out = io.BytesIO()
    serialize(out, out_path)
    return out.getvalue()

def serialize(out: io.BytesIO, path: str):
    write_string(out, "nix-archive-1")
    serialize1(out, path)

def serialize1(out: io.BytesIO, path: str):
    write_string(out, "(")
    serialize2(out, path)
    write_string(out, ")")

def serialize_entry(out: io.BytesIO, name: str, path: str):
    write_strings(out, "entry", "(", "name", name, "node")
    serialize1(out, path);
    write_string(out, ")")

def serialize2(out: io.BytesIO, path: str):
    def dump_contents(path):
        with open(path, 'rb') as f:
            bs = f.read()
            write_bytes(out, bs);

    st = os.lstat(path)

    if stat.S_ISREG(st.st_mode):
        write_strings(out, "type", "regular")
        if is_executable(st.st_mode):
            write_strings(out, "executable", "")
        write_string(out, "contents")
        dump_contents(path);
    elif stat.S_ISDIR(st.st_mode):
        write_strings(out, "type", "directory")

        entries = read_directory(path)
        for relpath, _ in sorted(entries.items(), key=lambda e: e[0]):
            abspath = os.path.join(path, relpath)
            serialize_entry(out, relpath, abspath)

    elif stat.S_ISLNK(st.st_mode):
        write_strings(out, "type", "symlink", "target", os.readlink(path))

    else:
        raise ValueError("Invalid filetype")

def read_directory(dirpath: str):
    with os.scandir(dirpath) as it:
        return { e.name: os.lstat(e) for e in it }

def is_executable(mode: int) -> bool:
    return (mode & 0o111) != 0

def write_string(out: io.BytesIO, s: str):
    bs = s.encode(encoding='ascii')
    write_bytes(out, bs)

def write_strings(out: io.BytesIO, *ss: str):
    for s in ss:
        write_string(out, s)

def write_bytes(out: io.BytesIO, bs: bytes):
    out.write(len(bs).to_bytes(8, byteorder='little'))
    out.write(bs)

    m = len(bs) % 8
    if m:
        pad = b"\x00" * (8 - (len(bs) % 8))
        out.write(pad)
```

mainの部分。
```python
import sys

if __name__ == "__main__":
    sys.stdout.buffer.write(archiveNAR(sys.argv[1]))
```

`nix nar dump-path` コマンドの結果と一致していることが分かる。
```console
bombrary@nixos:~/deps$ echo "Hello, World" > hello.txt
bombrary@nixos:~/deps$ paste <(nix nar dump-path hello.txt | od -w8 -tx1z) <(nix run nixpkgs#python3 -- dump.py hello.txt | od -w8 -tx1z)
0000000 0d 00 00 00 00 00 00 00  >........<     0000000 0d 00 00 00 00 00 00 00  >........<
0000010 6e 69 78 2d 61 72 63 68  >nix-arch<     0000010 6e 69 78 2d 61 72 63 68  >nix-arch<
0000020 69 76 65 2d 31 00 00 00  >ive-1...<     0000020 69 76 65 2d 31 00 00 00  >ive-1...<
0000030 01 00 00 00 00 00 00 00  >........<     0000030 01 00 00 00 00 00 00 00  >........<
0000040 28 00 00 00 00 00 00 00  >(.......<     0000040 28 00 00 00 00 00 00 00  >(.......<
0000050 04 00 00 00 00 00 00 00  >........<     0000050 04 00 00 00 00 00 00 00  >........<
0000060 74 79 70 65 00 00 00 00  >type....<     0000060 74 79 70 65 00 00 00 00  >type....<
0000070 07 00 00 00 00 00 00 00  >........<     0000070 07 00 00 00 00 00 00 00  >........<
0000100 72 65 67 75 6c 61 72 00  >regular.<     0000100 72 65 67 75 6c 61 72 00  >regular.<
0000110 08 00 00 00 00 00 00 00  >........<     0000110 08 00 00 00 00 00 00 00  >........<
0000120 63 6f 6e 74 65 6e 74 73  >contents<     0000120 63 6f 6e 74 65 6e 74 73  >contents<
0000130 0d 00 00 00 00 00 00 00  >........<     0000130 0d 00 00 00 00 00 00 00  >........<
0000140 48 65 6c 6c 6f 2c 20 57  >Hello, W<     0000140 48 65 6c 6c 6f 2c 20 57  >Hello, W<
0000150 6f 72 6c 64 0a 00 00 00  >orld....<     0000150 6f 72 6c 64 0a 00 00 00  >orld....<
0000160 01 00 00 00 00 00 00 00  >........<     0000160 01 00 00 00 00 00 00 00  >........<
0000170 29 00 00 00 00 00 00 00  >).......<     0000170 29 00 00 00 00 00 00 00  >).......<
0000200 0000200
```

## output pathからderivationを引く

output pathからderivationを引く方法として、公式的には`nix-store --query --deriver`コマンドを用いる方法がある。

しかし、そもそもoutput pathはderivationの諸々の情報を使いハッシュ化して作成されたものである。ハッシュの不可逆性により、逆にoutput pathから直接導出することは不可能のはずである。

ではNixではどうやってこれを行っているのかというと、別に`/nix/store/`を全探索とかしている訳ではない。実は`/nix/var/nix/db/db.sqlite`にSQLiteのDBがあり、そこにいろいろな情報を保管している。このDBはNix内部で用いるものであり、情報がほとんどないのだが、一応[Glossaly](https://nixos.org/manual/nix/stable/glossary#gloss-nix-database)や[Local Store](https://nixos.org/manual/nix/stable/store/types/local-store)の説明から、その存在だけは確認できる。

そこからどうやってSQL文を叩けばoutput pathからderivationが引けるのかというと、少なくともNix 2.21.1の状況では
* [nix-store --query --deriverの呼び出し場所](https://github.com/NixOS/nix/blob/2.21.1/src/nix-store/nix-store.cc#L381)：queryPathInfoで返ってきた値からderiverを取り出している
* [QueryPathInfoのSQL文](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/local-store.cc#L384)

から分かる。要するに、`ValidPaths`というテーブルを`path`で引いて、`deriver`のカラムを取り出せばよい。SQL文的には
```sql
select deriver from ValidPaths where path = '<output path>';
```

となる。

実際にPythonコードにすると、mainも含め以下のようになる。

```python
import sqlite3
import sys

def get_deriver(conn: sqlite3.Connection, out_path: str):
    cur = conn.cursor()
    cur.execute('select deriver from ValidPaths where path = ?', (out_path, ))
    for row in cur:
        return row[0]
    raise ValueError("Deriver is not found")

if __name__ == "__main__":
    with sqlite3.connect("file:///nix/var/nix/db/db.sqlite?immutable=1", uri=True) as conn:
        print(get_deriver(conn, sys.argv[1]))
```


実行例。symlink先のパスの判定とかは特にやってないため、`which ls`を`dump.py`の引数に埋め込んでも動作しないことに注意。
```console
bombrary@nixos:~/deps$ realpath `which ls`
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3/bin/coreutils

bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py /nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
/nix/store/g0kqr7b99b70kb10vmqg10vkj9nfk7zm-coreutils-full-9.3.drv
```

## パッケージの直接的・間接的なruntime dependenciesをすべて知る

今まで書いたコードを総動員して、あるパッケージのruntime dependenciesを再帰的に探索するコードが書ける。

```python
from typing import Any

OUT_CACHE = set()

def search_runtime_deps(nar_bytes: bytes, output_map: dict[str, Any]) -> list[str]:
    res = []
    for drv in output_map.values():
        for _, out_path, _, _ in drv[0]:
            if (out_path.encode('ascii') in nar_bytes) and (out_path not in OUT_CACHE):
                res.append(out_path)
                OUT_CACHE.add(out_path)
                res.extend(search_runtime_deps(archiveNAR(out_path), output_map))
    return res

if __name__ == "__main__":
    with sqlite3.connect("file:///nix/var/nix/db/db.sqlite?immutable=1", uri=True) as conn:
        out_path = sys.argv[1]
        drv = get_deriver(conn, out_path)
        _ = dump_deps(drv) # DRV_CACHEを生成するために事前に呼び出しておく

        nar = archiveNAR(out_path)
        outputs = search_runtime_deps(nar, DRV_CACHE)
        for output in outputs:
            print(output)
```

実行結果は、`nix-store --query --requisites`のものと同じである。

```console
bombrary@nixos:~/deps$ OUT_PATH=/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
bombrary@nixos:~/deps$ nix run nixpkgs#python3 -- dump.py $OUT_PATH | sort
/nix/store/03167shkax5dxclnv6r3sd8waa6lq7ny-coreutils-full-9.3
/nix/store/4h5isrbr87jjw69rgdnhi8psi7hhk5im-libidn2-2.3.4
/nix/store/80dld61hbpvy1ay1sdwaqyy4jzhm48xx-libunistring-1.1
/nix/store/9vv53vzx4k988d51xfiq2p46fqrjshv0-gmp-with-cxx-6.3.0
/nix/store/fhws3x2s9j5932r6ah660nsh41bkrq27-xgcc-12.3.0-libgcc
/nix/store/giyri337jb6sa1qyff6qp771qfq10yhf-gcc-12.3.0-lib
/nix/store/idwlqkj1z2cgjcijgnnxgyp0zgzpv7c5-attr-2.5.1
/nix/store/iyw6mm7a75i49h9szc0m08ynay1p7kka-gcc-12.3.0-libgcc
/nix/store/j6mwswpa6zqhdm1lm2lv9iix3arn774g-glibc-2.38-27
/nix/store/l0rxwrg41k3lsdiybf8q0rf3nk430zr8-openssl-3.0.12
/nix/store/wmsmw09x6l3kcl4ng3qs3ircj8h73si3-acl-2.3.1
```
