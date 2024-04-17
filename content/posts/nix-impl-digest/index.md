---
title: "Nixでハッシュ関係の処理のPython実装"
date: 2024-04-17T21:32:10Z
draft: true
tags: []
categories: []
---

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
  * 20B=160bitは、Nix32表現では160bit/5(bit/文字)=32文字である
* `compressHash`の実装は[libutil/hash.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libutil/hash.cc#L379-L386)にある。20バイトを超えた分の情報を失わせないように、20で割った余りに対応するindexにXORで足しこんでいる

Pythonで実装すると以下のようになる。
```python
HASH_TRUNC_BYTES = 20

def compress_hash(hash: bytes) -> bytes:
    bytes_list = [0] * HASH_TRUNC_BYTES
    for i in range(0, len(hash)):
        bytes_list[i % HASH_TRUNC_BYTES] ^= hash[i]
    return bytes(bytes_list)
```


## derivation hashの計算

## source hashの計算

## output hashの計算

そのあたりの実装は[libstore/derivations.cc](https://github.com/NixOS/nix/blob/2.21.1/src/libstore/derivations.cc)が参考になる。具体的には、
* `DrvHash hashDerivationModulo()`関数
* `DrvHash pathDerivationModulo()`関数
* `unparse()`関数

あたりが参考になる。

```python
import hashlib


def load_drv(path: str) -> Derivation:
    with open(path) as f:
        return parse_drv(f.read())

HASH_CACHE = {}
def replace_input_drv_path(drv: Derivation) -> set[InputDrv]:
    return {
        InputDrv(
            path=hash_derivation_modulo(i.path),
            ids=i.ids,
        )
        for i in drv.input_drvs
    }

def hash_derivation_modulo(path: str) -> str:
    if path not in HASH_CACHE:
        drv = load_drv(path)
        # outputsの第1要素のhashが空でない場合、fixed outputのはず
        out = drv.outputs[0]
        if out.hash:
            fingerprint = f"fixed:out:{out.hash_algo}:{out.hash}:{out.path}"
            HASH_CACHE[path] = hashlib.sha256(fingerprint.encode()).hexdigest()
        else:
            drv.input_drvs = replace_input_drv_path(drv)
            HASH_CACHE[path] = hashlib.sha256(unparse_drv(drv).encode()).hexdigest()

    return HASH_CACHE[path]

def calc_out_hash(path: str) -> bytes:
    drv = load_drv(path)

    drv.outputs = [ Output(o.id, "", o.hash_algo, o.hash) for o in drv.outputs ]
    for output in drv.outputs:
        drv.envs[output.id] = ""

    drv.input_drvs = replace_input_drv_path(drv)
    digest =  hashlib.sha256(unparse_drv(drv).encode()).hexdigest()
    fingerprint = f"output:out:sha256:{digest}:/nix/store:{drv.envs["name"]}"
    return hashlib.sha256(fingerprint.encode()).digest()


import sys

if __name__ == "__main__":
    hash = calc_out_hash(sys.argv[1])
    print(to_nix32(compress_hash(hash)))
```
