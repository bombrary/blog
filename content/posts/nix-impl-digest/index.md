---
title: "Nixでハッシュ関係の処理をPythonで実装してみる"
date: 2024-04-21T11:30:00+09:00
draft: true
tags: ["Python", "hash", "Nix32", "derivation"]
categories: ["Nix"]
toc: true
---

[前回の記事]({{< ref "/posts/nix-calc-digest">}})でstore pathを手で計算する方法を見てきたが、output hashの計算については手で計算するのが無理だった。これをPythonスクリプトで実装するとどうなるかをやってみた。

ゴールとしてはoutput hashを計算するコードを実装することであるが、
* Nix32表現の計算とtruncateオプションの計算はそれにあたって必要なので実装した
* おまけでderivation hashとsource hashの計算も実装した

なお、今回のコードについて
* [Nix 2.21.1](https://github.com/NixOS/nix/blob/2.21.1/)を参考に作っている
* すべてのパターンは網羅できていない可能性が高い（特にoutput hashの計算方法）
* [Nixのいくつかの処理をPythonで実装してみる]({{< ref "/posts/nix-impl-some-commands-python" >}})のコードを一部使って実装する

である。また、コードの実行例にあたって、[前回の記事のderivationの準備]({{< ref "/posts/nix-calc-digest">}}#prepare-derivation)にしたがって`sample`のderivationが準備されているものとする。

## Nix32表現の計算

Nix32の計算は[libutil/hash.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libutil/hash.cc#L90-L110)で行われている。

以下の並びのビット列があるとする（見やすさのため8bitごとに縦棒で区切ってある）。
```
b07 b06 b05 b04 b03 b02 b01 b00 | b15 b14 b13 b12 b11 b10 b09 b08 | b23 b22 b21 b20 b19 b18 b17 b16 | ...
```

Nix32表現では、以下のように5bitずつ取り出していく。
```
b04   b03   b02   b01   b00
b09   b08 | b07   b06   b05
b14   b13   b12   b11   b10
b19   b18   b17   b16 | b15
...
```

その5bitに文字を対応させる。具体的には、5bit値`idx`に対して、以下の文字列の`chars[idx]`を対応させる。
```
chars = "0123456789abcdfghijklmnpqrsvwxyz"
```

上記の処理を、下位のビット（160bit目）から最上位ビット（0bit目）まで上って行って、文字列を順に連結したら完成である。これをPythonコードで実装すると次のようになる。
```python
import sys

chars = "0123456789abcdfghijklmnpqrsvwxyz"

def to_nix32(hash: bytes) -> str:
    hash_bits = 8 * len(hash)
    nix32_len = (hash_bits - 1) // 5 + 1; # bit数を5で割って切り上げ
    s = ""
    for n in range(nix32_len - 1, -1, -1):
        b = n * 5
        i = b // 8
        j = b % 8
        c = (hash[i] >> j) | (hash[i + 1] << (8 - j) if i + 1 < len(hash) else 0)
        s = s + chars[c & 0x1f]

    return s
```

## truncateオプションの計算方法 {#truncate-option}

`nix-hash` コマンドには `--truncate` オプションがあり、これを行うとハッシュのNix32表現が32文字になる。ただし、これは別に単純に32文字に切り取っているわけではない。

* [nix/hash.cc](https://github.com/NixOS/nix/blob/2.21.1/src/nix/hash.cc#L118)の`compressHash`にて、ハッシュサイズを20バイトにする処理が行われている
  * 20バイト=160bitは、Nix32表現では160bit/5(bit/文字)=32文字である
* `compressHash`の実装は[libutil/hash.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libutil/hash.cc#L379-L386)にある。20バイトを超えた分の情報を失わせないように、20で割った余りに対応するindexにXORで足しこんでいる

実装は以下の通り。
```python
HASH_TRUNC_BYTES = 20

def compress_hash(hash: bytes) -> bytes:
    bytes_list = [0] * HASH_TRUNC_BYTES
    for i in range(0, len(hash)):
        bytes_list[i % HASH_TRUNC_BYTES] ^= hash[i]
    return bytes(bytes_list)
```


## derivation hashの計算

* inner digestについてはdrvファイルを単にハッシュ化するだけ
* build dependencies(input derivation + input sources)を連結させてfingerprintを作成する
  * derivationのパースについては[Nixのいくつかの処理をPythonで実装してみる]({{< ref "/posts/nix-impl-some-commands-python" >}})の`load_drv`関数を用いる。

```python
import hashlib
import os
import sys

def calc_drv_hash(path: str) -> bytes:
    drv = load_drv(path)
    name = drv.envs["name"]

    input_drvs = [ i.path for i in drv.input_drvs ]
    input_srcs = list(drv.input_srcs)
    inputs = sorted(input_drvs + input_srcs)

    inner_digest = hashlib.sha256(unparse_drv(drv).encode()).hexdigest()
    fingerprint = f"text:{":".join(inputs)}:sha256:{inner_digest}:/nix/store:{name}.drv"

    return hashlib.sha256(fingerprint.encode()).digest()

if __name__ == "__main__":
    hash = calc_drv_hash(sys.argv[1])
    print(to_nix32(compress_hash(hash)))
```

実行すると、drvファイルのパスに載っているハッシュと一致していることがわかる。
```console
bombrary@nixos:~/drv-test$ nix run nixpkgs#python312 -- dump.py  /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv
rj4yv464wz8n055r8d3z8iag33f1mgg4
```

## source hashの計算

inner digestをNARのハッシュから作って、それをもとにfingerprintを作成する。NARの処理については[Nixのいくつかの処理をPythonで実装してみる]({{< ref "/posts/nix-impl-some-commands-python" >}})の`archiveNAR`関数を用いる。

```python
import hashlib
import os

def calc_source_hash(path: str) -> bytes:
    name = os.path.basename(path)

    nar = archiveNAR(path)

    inner_digest = hashlib.sha256(nar).hexdigest()
    fingerprint = f"source:sha256:{inner_digest}:/nix/store:{name}"

    return hashlib.sha256(fingerprint.encode()).digest()

if __name__ == "__main__":
    hash = calc_source_hash(sys.argv[1])
    print(to_nix32(compress_hash(hash)))
```

`nix derivation show`に載っているsource hashと一致していることが確認できる。
```console
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv^* | jq -r 'to_entries[].value.inputSrcs[]'
/nix/store/cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd-hello.c
/nix/store/in7cqd3v1mg9f8jkvlm4d0h002h1697j-mybuilder.sh

bombrary@nixos:~/drv-test$ nix run nixpkgs#python312 -- dump.py ./hello.c
cap4mlkfwzh7l2f2x5zy5lvgy8xb5ywd

bombrary@nixos:~/drv-test$ nix run nixpkgs#python312 -- dump.py ./mybuilder.sh
in7cqd3v1mg9f8jkvlm4d0h002h1697j
```

## output hashの計算

この実装は[libstore/derivations.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/derivations.cc)を参考にした。関数としては
* `DrvHash hashDerivationModulo()`
* `DrvHash pathDerivationModulo()`
* `unparse()`

あたり。

やっていることとしては、
* `calc_out_hash()` がoutput hash計算のためののentry point
* `calc_out_hash()` では以下のことを行う
  1. outputのリスト`drv.outputs` に記載されているパスを空文字にする
  2. 環境変数の辞書`drv.envs` にもoutputのパスが記載されているはずなので空文字にする
  3. `input_drvs` に書かれているパスを `hash_derivation_modulo()` の結果に置換する
  4. drvをSHA256ハッシュ化してNix32表現で返す
* `hash_derivation_modulo()` では以下のことを行う。
  * fixed outputの場合、そのfingerprintをSHA256ハッシュ化してBase16表現で返す
  * そうでない場合、`input_drvs` に書かれているパスを `hash_derivation_modulo()` の結果に置換し、そのdrvをSHA256ハッシュ化してBase16表現で返す

となっている。`hash_derivation_modulo` という命名については、[libstore/derivations.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/derivations.cc)に`hashDerivationModulo()`や`pathDerivationModulo()`といった関数があることから（しかしmoduloのニュアンスがあまり良くわかっていない…）。

```python
import hashlib
import sys
import functools


def replace_input_drv_path(input_drvs: set[InputDrv]) -> set[InputDrv]:
    return {
        InputDrv(
            path=hash_derivation_modulo(i.path),
            ids=i.ids,
        )
        for i in input_drvs
    }


def is_fixed_output(drv: Derivation) -> bool:
    # outputsの第1要素のhashが空でない場合、fixed outputのはず
    return drv.outputs[0].hash != ""


@functools.lru_cache()
def hash_derivation_modulo(path: str) -> str:
    drv = load_drv(path)
    if is_fixed_output(drv):
        out = drv.outputs[0]
        fingerprint = f"fixed:out:{out.hash_algo}:{out.hash}:{out.path}"
        return hashlib.sha256(fingerprint.encode()).hexdigest()
    else:
        drv.input_drvs = replace_input_drv_path(drv.input_drvs)
        return hashlib.sha256(unparse_drv(drv).encode()).hexdigest()


def calc_out_hash(path: str) -> bytes:
    drv = load_drv(path)

    drv.outputs = [ Output(o.id, "", o.hash_algo, o.hash) for o in drv.outputs ]
    for output in drv.outputs:
        drv.envs[output.id] = ""

    drv.input_drvs = replace_input_drv_path(drv.input_drvs)

    inner_digest =  hashlib.sha256(unparse_drv(drv).encode()).hexdigest()
    fingerprint = f"output:out:sha256:{inner_digest}:/nix/store:{drv.envs["name"]}"

    return hashlib.sha256(fingerprint.encode()).digest()


if __name__ == "__main__":
    hash = calc_out_hash(sys.argv[1])
    print(to_nix32(compress_hash(hash)))
```

`nix derivation show`に載っているoutput hashと、スクリプトの実行結果が一致していることが確認できる。
```console
bombrary@nixos:~/drv-test$ nix derivation show /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv^* | jq -r 'to_entries[].value.outputs.out.path'
/nix/store/2l1a42rcz7jm1mspka2n8ivgdds8jlql-sample

bombrary@nixos:~/drv-test$ nix run nixpkgs#python312 -- dump.py /nix/store/rj4yv464wz8n055r8d3z8iag33f1mgg4-sample.drv
2l1a42rcz7jm1mspka2n8ivgdds8jlql
```
