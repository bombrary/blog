---
title: "OpenAPI定義から特定の要素だけ取り出すスクリプト"
date: 2026-04-26T15:05:00+09:00
tags: [ "OpenAPI", "Swagger" ]
categories: [ "Python" ]
---

## 前置き

OpenAPIスキーマからAPIクライアントを作りたい。そういう場合 [OpenAPITools/openapi-generator](https://github.com/OpenAPITools/openapi-generator) を使って生成することになるが、スキーマがあまりにもでかすぎると困る。
* yamlだとファイルがでかすぎるとうまく読めない
* Pythonのようなインタプリタ型のクライアントだとモジュールのロードに時間がかかる

一例として、以下のAPIスキーマを見てほしい。以下はネットワーク仮想化製品であるVMware NSX-TのAPIスキーマであるが、`nsx_policy_api.yml` を見ると、テキストファイルなのに12MGもある。jsonファイルですら8.6MBである。

[NSX-T Data Center REST API](https://developer.broadcom.com/xapis/nsx-t-data-center-rest-api/latest/x-references/)

こういった外部製品のAPIクライアントを作ることを考えたとき、実際には特定のAPIしか叩かないだろう。もしその特定のAPIのスキーマと関連リソースだけを抽出したスキーマを作れば、軽量なAPIクライアントが作成できることが期待される。

というわけで本記事では、OpenAPIのスキーマから必要なリソースと関連リソースだけを抽出した新しいスキーマを生成するスクリプトを作成する。

## 設計

今回の目的は「特定のAPIと関連リソースのみを抽出する」ことである。

### 入出力

そのため、入力と出力はそれぞれ次のようになる。
* 入力：
    * OpenAPI定義ファイル
    * OpenAPI定義ファイルに含まれるAPIパスのリスト
* 出力： OpenAPIスキーマ
    * 最もファイルサイズを占めているであろう以下の属性には必要最低限のものが入っている状態となっている
        * `paths`
        * `definitions` (v2.0のみ)
        * `parameters` (v2.0のみ)
        * `responses` (v2.0のみ)
        * `components` (v3.0のみ)
    * OpenAPI には2.0と3.0があるが、特に取り決めない
        * [OpenAPI Specification - Version 2.0 | Swagger](https://swagger.io/specification/v2/)
        * [OpenAPI Specification - Version 3.0 | Swagger](https://swagger.io/specification/v3/)

### インターフェース

APIパスのリストは、改行区切りで標準入力から受け取るものとする。
```sh
python3 main.py -i input.yml -o output.yml
```

### API関連リソースを抽出するロジック

OpenAPIでは、`$ref: "#/{attr...}"` のような構文で、別の場所で定義されている要素を参照できる。

```yml
/pets:
  get:
    description: Returns all pets from the system that the user has access to
    produces:
    - application/json
    responses:
      '200':
        description: A list of pets.
        schema:
          type: array
          items:
            $ref: '#/definitions/pet'
```

このような `$ref: ...` があるため、完全なAPIスキーマとして抽出するためには、`$ref` が参照する先のリソースも漏らさずスキーマとして抽出する必要がある。

`$ref: "#/key1/key2/...` という構文自体は [JSON Reference](https://datatracker.ietf.org/doc/html/draft-pbryan-zyp-json-ref-03)、 [JSON Pointer](https://datatracker.ietf.org/doc/html/rfc6901) で定義されている仕様らしい。しかし今回はそこまで頑張って規格どおりにパースする必要はないので、単に、
* `$ref: "#/key1/key2/...` が見つかった場合、`d[key1][key2][...]...` を参照する

という処理を入れて取り込んでいく。処理のイメージとしては以下である。

1. APIパスの要素を走査していく
1. `$ref` をキーとする要素が見つかった場合、それが参照している要素を走査
1. さらにその中で `$ref` をキーとする要素が見つかった場合、さらに参照している要素を走査…

返却値としては、APIパスから到達可能なオブジェクト、またはJSON Pointerの集合を返せばよい。これはいわゆる [NixでいうClosure（閉包）](https://nix.dev/manual/nix/2.28/glossary#gloss-closure) を求める問題に帰着される。

なんだか面白くなってきたので、もう少しちゃんと定式化してみる。

```markdown
* r がreferenceであるとは、 "#/key1/key2/..." の形式で書かれた文字列である
* dict D と reference r = "#/key1/key2/..." を用いて、Dのrによる参照先を次のように定義する
    * deref(D, r) := D[key1][key2]...
* dict D について、D が持つreferenceの集合を ref_set(D) で表す。 ref_set(D) は次のように定義される
    * e = deref(D) が dict の場合、以下の集合の和集合である
        * { v for k, v in e.items() if k == "$ref" and (vがreferenceである) }
        * ref_set(v) for v in e.values()
    * e = deref(D) が list の場合、以下の集合の和集合である
        * ref_set(v) for v in e
    * e = deref(D) が上記いずれでもない場合、空集合である
* dict D0 ⊆ D について、以下のように満たすreferenceの集合を ref_closure(D0) で表す。これを D0 の閉包と呼ぶ
    * 任意の要素 r ∈ ref_closure(D0) に対して、ref_closure(deref(D, r)) ⊆ ref_closure(D0)
        * すなわち、ref_closure(D0) は deref(D, *) に対して閉じている
    * 具体的には、以下で構成可能である
        1. R := ref_set(D) とする
        2. r in R に対して、再帰的にderef(D, r)の閉包ref_closure(deref(D, r))を求める
           循環参照がない限りはいずれRが空集合になるため、この再帰は有限回で停止する
        3. 1と2の和集合を返す
```

ここまでいくとあとはほとんど実装するだけとなる。

## 実装

### API関連リソースを抽出するロジックの実装

まず閉包を求めるロジックは以下のように書ける。

```python
from typing import Any

def is_ref(ref: str) -> bool:
    return ref.startswith("#/")

def deref(d: dict, ref: str) -> Any:
    if not is_ref(ref):
        raise ValueError(f"Invalid JSON pointer format: {ref}")

    cur = d
    for key in  ref[2:].split("/"):
        cur = cur[key]
    return cur

def set_ref_value(d: dict, ref: str, value: Any):
    if not is_ref(ref):
        raise ValueError(f"Invalid JSON pointer format: {ref}")

    cur = d
    keys = ref[2:].split("/")
    for key in keys[:-1]:
        cur = cur[key]
    cur[keys[-1]] = value

def ref_set(obj: Any) -> set[str]:
    if isinstance(obj, dict):
        result = { v for k, v in obj.items() if k == "$ref" and is_ref(v) }
        for v in obj.values():
           result |= ref_set(v) 
        return result
    elif isinstance(obj, list):
        result = set()
        for v in obj:
            result |= ref_set(v)
        return result
    else:
        return set()

def ref_closure(whole: dict, obj: Any) -> set[str]:
    R = { r for r in ref_set(obj) }
    if len(R) == 0:
        return R
    else:
        return R | set.union(*[ref_closure(whole, deref(whole, r)) for r in R ])
```

<details><summary>テストコード</summary>

```python
import unittest
from dataclasses import dataclass
from typing import Any
from openapi_extract import *

class TestMain(unittest.TestCase):
    def test_deref(self):
        @dataclass
        class Case:
            case_name: str
            d: dict
            ref: str
            expect: Any
            is_success: bool
            expect_error: type[Exception] | None

        test_cases = [
            Case("normal-str", { "a": { "b": "foo" }}, "#/a/b", "foo", True, None),
            Case("normal-int", { "a": { "b": 0 }}, "#/a/b", 0, True, None),
            Case("normal-more-nested", { "a": { "b": {"c": { "d": { "e": 0 }}}}}, "#/a/b/c/d/e", 0, True, None),
            Case("error-invalid-input-1", { "a": { "b": "foo" }}, "/a/b", "foo", False, ValueError),
            Case("error-invalid-input-2", { "a": { "b": "foo" }}, "a/b", "foo", False, ValueError)
        ]

        for e in test_cases:
            with self.subTest(e.case_name):
                if e.is_success:
                    actual = deref(e.d, e.ref)
                    self.assertEqual(e.expect, actual)
                else:
                    assert(e.expect_error is not None)
                    with self.assertRaises(e.expect_error):
                        _ = deref(e.d, e.ref)

    def test_set_ref_value(self):
        @dataclass
        class Case:
            case_name: str
            d: dict
            ref: str
            value: Any
            is_success: bool
            expect_error: type[Exception] | None

        test_cases = [
            Case("normal-str", { "a": { "b": "foo" }}, "#/a/b", "bar", True, None),
            Case("normal-int", { "a": { "b": 0 }}, "#/a/b", 1, True, None),
            Case("normal-more-nested", { "a": { "b": {"c": { "d": { "e": 0 }}}}}, "#/a/b/c/d/e", 1, True, None),
            Case("error-invalid-input-1", { "a": { "b": "foo" }}, "/a/b", "bar", False, ValueError),
            Case("error-invalid-input-2", { "a": { "b": "foo" }}, "a/b", "bar", False, ValueError)
        ]

        for e in test_cases:
            with self.subTest(e.case_name):
                if e.is_success:
                    set_ref_value(e.d, e.ref, e.value)
                    actual = deref(e.d, e.ref)
                    expect = e.value
                    self.assertEqual(expect, actual)
                else:
                    assert(e.expect_error is not None)
                    with self.assertRaises(e.expect_error):
                        _ = deref(e.d, e.ref)

    def test_ref_set(self):
        @dataclass
        class Case:
            case_name: str
            d: dict
            ref: str
            expect: set[str]

        D0 = {
            "a0": {
                "b0": { "$ref": "#/a1/b1" },
                "c0": { "$ref": "#/a2" },
                "d0": { "$ref": "#/a3" },
                "e0": "foo",
                "f0": { "g0": { "$ref": "#/a4" } },
            },
            "a1": {
                "b1": {
                    "c1": [
                        { "$ref": "#/a3" },
                        "foo",
                        { "g0": { "$ref": "#/a4" } },
                    ]
                },
            },
            "a2": 0,
            "a3": 1,
        }
        test_cases = [
            Case("dict1", D0, "#/a0/b0", { "#/a1/b1" }),
            Case("dict2", D0, "#/a0", { "#/a1/b1", "#/a2", "#/a3", "#/a4" }),
            Case("empty", D0, "#/a2", set()),
        ]
        for e in test_cases:
            with self.subTest(e.case_name):
                actual = ref_set(deref(e.d, e.ref))
                self.assertEqual(e.expect, actual)

    def test_ref_closure(self):
        @dataclass
        class Case:
            case_name: str
            d: dict
            ref: str
            expect: set[str]

        D0 = {
            "a0": {
                "b0": { "$ref": "#/a1/b1" },
                "c0": { "$ref": "#/a2" },
                "d0": { "$ref": "#/a3" },
                "e0": "foo",
                "f0": { "g0": { "$ref": "#/a4" } },
            },
            "a1": {
                "b1": {
                    "c1": [
                        { "$ref": "#/a5" },
                        "foo",
                        { "g0": { "$ref": "#/a6" } },
                    ]
                },
            },
            "a2": { "$ref": "#/a7" },
            "a3": 1,
            "a4": "foo",
            "a5": [],
            "a6": { "foo": "bar" },
            "a7": "foo",
        }
        test_cases = [
            Case("dict1", D0, "#/a0/b0", { "#/a1/b1", "#/a5", "#/a6" }),
            Case("dict2", D0, "#/a0", { "#/a1/b1", "#/a2", "#/a3", "#/a4", "#/a5", "#/a6", "#/a7" }),
            Case("dict3", D0, "#/a2", { "#/a7" }),
            Case("dict4", D0, "#/a7", set() ),
        ]
        for e in test_cases:
            with self.subTest(e.case_name):
                actual = ref_closure(D0, deref(e.d, e.ref))
                self.assertEqual(e.expect, actual)

if __name__ == "__main__":
    unittest.main()
```

</details>

### CLIの実装

閉包を求める関数を用いて、実際にOpenAPIスキーマを抽出するCLIを書いてみよう。

```python
import sys
import json
import click
from pathlib import Path
from openapi_extract import ref_closure, deref, set_ref_value
from logging import getLogger, DEBUG, StreamHandler, Formatter


logger = getLogger(__name__)
logger.setLevel(DEBUG)

formatter = Formatter('%(asctime)s: %(message)s')

handler = StreamHandler(sys.stderr)
handler.setFormatter(formatter)
handler.setLevel(DEBUG)
logger.addHandler(handler)


@click.group()
def cli():
    pass


def extract_schema(input_schema_data: dict, output_schema_data: dict, api_path_list: list[str]):
    # refの取得
    refs = set()
    for path in api_path_list:
        logger.info(f"extracting path: {path}")
        path_dict = input_schema_data["paths"][path]
        output_schema_data["paths"][path] = path_dict
        refs |= ref_closure(input_schema_data, path_dict)

    # refの指す値の抽出
    for ref in refs:
        logger.debug(f"extracting ref: {ref}")
        set_ref_value(output_schema_data, ref, deref(input_schema_data, ref))


@click.option("-i", "input_schema_path", required=True, help="input schema path")
@click.option("-o", "output_schema_path", required=True, help="output schema path")
@cli.command("convert")
def convert(
    input_schema_path: str,
    output_schema_path: str,
):
    api_path_list = [ line.strip() for line in sys.stdin.readlines() ]
    logger.info(f"api_path: {len(api_path_list)}")

    logger.info(f"loading: {input_schema_path}")
    with Path(input_schema_path).open("r") as f:
        input_schema_data = json.load(f)
    logger.info(f"loaded: {input_schema_path}")

    # 初期化
    EXCLUDE_KEYS = [ "paths", "definitions", "parameters", "responses", "components" ]
    output_schema_data = {}
    for k, v in input_schema_data.items():
        if k in EXCLUDE_KEYS:
            output_schema_data[k] = {}
        else:
            output_schema_data[k] = v

    # 抽出
    extract_schema(input_schema_data, output_schema_data, api_path_list)

    # 書き出し
    with Path(output_schema_path).open("w") as f:
        json.dump(output_schema_data, f)
    logger.info(f"saved: {output_schema_path}")


def print_tabular(rows: list[list[str]]):
    fixed_length = [ 0 ] * len(rows[0])
    for row in rows:
        for i in range(len(fixed_length)):
            fixed_length[i] = max(fixed_length[i], len(row[i]))
    fixed_length[-1] = 0

    for row in rows:
        print(" ".join([ c.ljust(fl) for c, fl in zip(row, fixed_length) ]))


if __name__ == "__main__":
    cli()
```

## 動作確認

### 抽出スクリプトの実行

APIのパスのリストをファイルに書いておいて、それを食わせて生成する。

```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths.txt
/infra/segments
/infra/segments/{segment-id}
/infra/segments/{segment-id}/ports
/infra/segments/{segment-id}/ports/{port-id}
/infra/domains/{domain-id}/groups
/infra/domains/{domain-id}/groups/{group-id}

[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths.txt | uv run python main.py convert -i nsx_policy_api.json -o out.json
2026-04-26 05:36:54,022: api_path: 6
2026-04-26 05:36:54,022: loading: nsx_policy_api.json
2026-04-26 05:36:54,087: loaded: nsx_policy_api.json
2026-04-26 05:36:54,087: extracting path: /infra/segments
2026-04-26 05:36:54,087: extracting path: /infra/segments/{segment-id}
2026-04-26 05:36:54,088: extracting path: /infra/segments/{segment-id}/ports
2026-04-26 05:36:54,088: extracting path: /infra/segments/{segment-id}/ports/{port-id}
2026-04-26 05:36:54,088: extracting path: /infra/domains/{domain-id}/groups
2026-04-26 05:36:54,088: extracting path: /infra/domains/{domain-id}/groups/{group-id}
2026-04-26 05:36:54,089: extracting ref: #/definitions/PortAttachment
2026-04-26 05:36:54,089: extracting ref: #/definitions/UnboundedKeyValuePair
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentExtraConfig
2026-04-26 05:36:54,089: extracting ref: #/definitions/LocalEgress
2026-04-26 05:36:54,089: extracting ref: #/responses/InternalServerError
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentPortListResult
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentSubnet
2026-04-26 05:36:54,089: extracting ref: #/definitions/RevisionedResource
2026-04-26 05:36:54,089: extracting ref: #/responses/BadRequest
2026-04-26 05:36:54,089: extracting ref: #/definitions/ChildPolicyConfigResource
2026-04-26 05:36:54,089: extracting ref: #/definitions/ResourceLink
2026-04-26 05:36:54,089: extracting ref: #/definitions/AttachedInterfaceEntry
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentListResult
2026-04-26 05:36:54,089: extracting ref: #/definitions/SelfResourceLink
2026-04-26 05:36:54,089: extracting ref: #/responses/ServiceUnavailable
2026-04-26 05:36:54,089: extracting ref: #/definitions/ApiError
2026-04-26 05:36:54,089: extracting ref: #/definitions/BridgeProfileConfig
2026-04-26 05:36:54,089: extracting ref: #/definitions/PolicyResource
2026-04-26 05:36:54,089: extracting ref: #/definitions/Group
2026-04-26 05:36:54,089: extracting ref: #/definitions/GroupListResult
2026-04-26 05:36:54,089: extracting ref: #/definitions/ConnectivityAdvancedConfig
2026-04-26 05:36:54,089: extracting ref: #/definitions/RelatedApiError
2026-04-26 05:36:54,089: extracting ref: #/definitions/PolicyRequestParameter
2026-04-26 05:36:54,089: extracting ref: #/responses/Forbidden
2026-04-26 05:36:54,089: extracting ref: #/responses/PreconditionFailed
2026-04-26 05:36:54,089: extracting ref: #/definitions/Expression
2026-04-26 05:36:54,089: extracting ref: #/definitions/Tag
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentPort
2026-04-26 05:36:54,089: extracting ref: #/definitions/ListResult
2026-04-26 05:36:54,089: extracting ref: #/responses/NotFound
2026-04-26 05:36:54,089: extracting ref: #/definitions/Segment
2026-04-26 05:36:54,089: extracting ref: #/definitions/PolicyConfigResource
2026-04-26 05:36:54,089: extracting ref: #/definitions/FederationConnectivityConfig
2026-04-26 05:36:54,089: extracting ref: #/definitions/L2Extension
2026-04-26 05:36:54,089: extracting ref: #/definitions/PortAddressBindingEntry
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentDhcpConfig
2026-04-26 05:36:54,089: extracting ref: #/definitions/ManagedResource
2026-04-26 05:36:54,089: extracting ref: #/definitions/Resource
2026-04-26 05:36:54,089: extracting ref: #/definitions/LocalEgressRoutingEntry
2026-04-26 05:36:54,089: extracting ref: #/definitions/SegmentAdvancedConfig
2026-04-26 05:36:54,092: saved: out.json
```

8.5Mのjsonが89Kまで小さくなった。またjqで中身をのぞいてみても、関連のAPIとそのリソースしか無さそう。
```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ ls -lah nsx_policy_api.json out.json
-rwxrwxrwx 1 bombrary users 8.5M Apr 26 03:17 nsx_policy_api.json
-rw-r--r-- 1 bombrary users  89K Apr 26 05:36 out.json

[bombrary@nixos:~/pworks/python-openapi-extract]$ jq '.paths | keys' out.json
[
  "/infra/domains/{domain-id}/groups",
  "/infra/domains/{domain-id}/groups/{group-id}",
  "/infra/segments",
  "/infra/segments/{segment-id}",
  "/infra/segments/{segment-id}/ports",
  "/infra/segments/{segment-id}/ports/{port-id}"
]

[bombrary@nixos:~/pworks/python-openapi-extract]$ jq '.definitions | keys' out.json
[
  "ApiError",
  "AttachedInterfaceEntry",
  "BridgeProfileConfig",
  "ChildPolicyConfigResource",
  "ConnectivityAdvancedConfig",
  "Expression",
  "FederationConnectivityConfig",
  "Group",
  "GroupListResult",
  "L2Extension",
  "ListResult",
  "LocalEgress",
  "LocalEgressRoutingEntry",
  "ManagedResource",
  "PolicyConfigResource",
  "PolicyRequestParameter",
  "PolicyResource",
  "PortAddressBindingEntry",
  "PortAttachment",
  "RelatedApiError",
  "Resource",
  "ResourceLink",
  "RevisionedResource",
  "Segment",
  "SegmentAdvancedConfig",
  "SegmentDhcpConfig",
  "SegmentExtraConfig",
  "SegmentListResult",
  "SegmentPort",
  "SegmentPortListResult",
  "SegmentSubnet",
  "SelfResourceLink",
  "Tag",
  "UnboundedKeyValuePair"
]
```

### openapi-generator-cliを用いたpythonクライアントの生成

試しに [openapi-generator-cli](https://github.com/openapitools/openapi-generator-cli) でクライアントを生成できるか試してみる。
```sh
docker run --rm \
    -v "${PWD}:/local" \
    -u "$(id -u $(whoami)):$(id -g $(whoami))" \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    openapitools/openapi-generator-cli generate \
    -i /local/out.json \
    -g python \
    -o /local/out/
```

```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ docker run --rm \
    -v "${PWD}:/local" \
    -u "$(id -u $(whoami)):$(id -g $(whoami))" \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    openapitools/openapi-generator-cli generate \
    -i /local/out.json \
    -g python \
    -o /local/out/
[main] INFO  o.o.codegen.DefaultGenerator - Generating with dryRun=false
[main] INFO  o.o.codegen.DefaultGenerator - OpenAPI Generator: python (client)
[main] INFO  o.o.codegen.DefaultGenerator - Generator 'python' is considered stable.
[main] INFO  o.o.c.l.AbstractPythonCodegen - Environment variable PYTHON_POST_PROCESS_FILE not defined so the Python code may not be properly formatted. To define it, try 'export PYTHON_POST_PROCESS_FILE="/usr/local/bin/yapf -i"' (Linux/Mac)
[main] INFO  o.o.c.l.AbstractPythonCodegen - NOTE: To enable file post-processing, 'enablePostProcessFile' must be set to `true` (--enable-post-process-file for CLI).
[main] WARN  o.o.codegen.utils.ModelUtils - Failed to get the schema name: null
[main] WARN  o.o.c.l.AbstractPythonCodegen - Codegen property is null (e.g. map/dict of undefined type). Default to typing.Any.
[main] WARN  o.o.c.l.AbstractPythonCodegen - Codegen property is null (e.g. map/dict of undefined type). Default to typing.Any.
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/models/api_error.py
[main] INFO  o.o.codegen.TemplateManager - Skipped /local/out/test/test_api_error.py (Test files never overwrite an existing file of the same name.)
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/docs/ApiError.md
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/models/attached_interface_entry.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/test/test_attached_interface_entry.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/configuration.py
....
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/__init__.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/models/__init__.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/api/__init__.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/exceptions.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/test/__init__.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/api_client.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/api_response.py
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/openapi_client/rest.py
[main] INFO  o.o.codegen.TemplateManager - Skipped /local/out/.openapi-generator-ignore (Skipped by supportingFiles options supplied by user.)
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/.openapi-generator/VERSION
[main] INFO  o.o.codegen.TemplateManager - writing file /local/out/.openapi-generator/FILES
############################################################################################
# Thanks for using OpenAPI Generator.                                                      #
# We appreciate your support! Please consider donation to help us maintain this project.   #
# https://opencollective.com/openapi_generator/donate                                      #
############################################################################################
```

READMEを見ると、ちゃんと指定したAPIパスに関するメソッドだけが定義されていることがわかる。  
※ 見やすさのため [glow](https://github.com/charmbracelet/glow) で出力している

```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ nix run 'nixpkgs#glow' -- out/README.md

   openapi-client

  VMware NSX Policy REST API

  This Python package is automatically generated by the OpenAPI Generator https://openapi-generator.tech project:

  • API version: 4.1.2.0.0
  • Package version: 1.0.0
  • Generator version: 7.22.0-SNAPSHOT
  • Build package: org.openapitools.codegen.languages.PythonClientCodegen

  ## Requirements.

  Python 3.10+

  ## Installation & Usage

  （中略）


  ## Documentation for API Endpoints

  All URIs are relative to https://nsxmanager.your.domain/policy/api/v1 https://nsxmanager.your.domain/policy/api/v1

  Class       │Method                                 │HTTP request                            │Description
  ────────────┼───────────────────────────────────────┼────────────────────────────────────────┼──────────────────────────
  Connectivit…│create_or_replace_infra_segment /home/…│PUT /infra/segments/{segment-id}        │Create or update a infra …
  Connectivit…│create_or_replace_infra_segment_port /…│PUT /infra/segments/{segment-id}/ports/…│Create or update an infra…
  Connectivit…│delete_infra_segment /home/bombrary/pw…│DELETE /infra/segments/{segment-id}     │Delete infra segment
  Connectivit…│delete_infra_segment_port /home/bombra…│DELETE /infra/segments/{segment-id}/por…│Delete an infra segment p…
  Connectivit…│get_infra_segment_port /home/bombrary/…│GET /infra/segments/{segment-id}/ports/…│Get infra segment port by…
  Connectivit…│list_all_infra_segments /home/bombrary…│GET /infra/segments                     │List all segments under i…
  Connectivit…│list_infra_segment_ports /home/bombrar…│GET /infra/segments/{segment-id}/ports  │List infra segment ports
  Connectivit…│patch_infra_segment /home/bombrary/pwo…│PATCH /infra/segments/{segment-id}      │Create or update a segment
  Connectivit…│patch_infra_segment_port /home/bombrar…│PATCH /infra/segments/{segment-id}/port…│Patch an infra segment po…
  Connectivit…│read_infra_segment /home/bombrary/pwor…│GET /infra/segments/{segment-id}        │Read infra segment
  GroupsApi   │delete_group /home/bombrary/pworks/pyt…│DELETE /infra/domains/{domain-id}/group…│Delete Group
  GroupsApi   │delete_group_0 /home/bombrary/pworks/p…│DELETE /infra/domains/{domain-id}/group…│Delete Group
  GroupsApi   │list_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups   │List Groups for a domain
  GroupsApi   │list_group_for_domain_0 /home/bombrary…│GET /infra/domains/{domain-id}/groups   │List Groups for a domain
  GroupsApi   │patch_group_for_domain /home/bombrary/…│PATCH /infra/domains/{domain-id}/groups…│Patch a group
  GroupsApi   │patch_group_for_domain_0 /home/bombrar…│PATCH /infra/domains/{domain-id}/groups…│Patch a group
  GroupsApi   │read_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups/{…│Read group
  GroupsApi   │read_group_for_domain_0 /home/bombrary…│GET /infra/domains/{domain-id}/groups/{…│Read group
  GroupsApi   │update_group_for_domain /home/bombrary…│PUT /infra/domains/{domain-id}/groups/{…│Create or update a group
  GroupsApi   │update_group_for_domain_0 /home/bombra…│PUT /infra/domains/{domain-id}/groups/{…│Create or update a group
  InventoryApi│delete_group /home/bombrary/pworks/pyt…│DELETE /infra/domains/{domain-id}/group…│Delete Group
  InventoryApi│list_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups   │List Groups for a domain
  InventoryApi│patch_group_for_domain /home/bombrary/…│PATCH /infra/domains/{domain-id}/groups…│Patch a group
  InventoryApi│read_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups/{…│Read group
  InventoryApi│update_group_for_domain /home/bombrary…│PUT /infra/domains/{domain-id}/groups/{…│Create or update a group
  NetworkingA…│create_or_replace_infra_segment /home/…│PUT /infra/segments/{segment-id}        │Create or update a infra …
  NetworkingA…│create_or_replace_infra_segment_port /…│PUT /infra/segments/{segment-id}/ports/…│Create or update an infra…
  NetworkingA…│delete_infra_segment /home/bombrary/pw…│DELETE /infra/segments/{segment-id}     │Delete infra segment
  NetworkingA…│delete_infra_segment_port /home/bombra…│DELETE /infra/segments/{segment-id}/por…│Delete an infra segment p…
  NetworkingA…│get_infra_segment_port /home/bombrary/…│GET /infra/segments/{segment-id}/ports/…│Get infra segment port by…
  NetworkingA…│list_all_infra_segments /home/bombrary…│GET /infra/segments                     │List all segments under i…
  NetworkingA…│list_infra_segment_ports /home/bombrar…│GET /infra/segments/{segment-id}/ports  │List infra segment ports
  NetworkingA…│patch_infra_segment /home/bombrary/pwo…│PATCH /infra/segments/{segment-id}      │Create or update a segment
  NetworkingA…│patch_infra_segment_port /home/bombrar…│PATCH /infra/segments/{segment-id}/port…│Patch an infra segment po…
  NetworkingA…│read_infra_segment /home/bombrary/pwor…│GET /infra/segments/{segment-id}        │Read infra segment
  PolicyApi   │create_or_replace_infra_segment /home/…│PUT /infra/segments/{segment-id}        │Create or update a infra …
  PolicyApi   │create_or_replace_infra_segment_port /…│PUT /infra/segments/{segment-id}/ports/…│Create or update an infra…
  PolicyApi   │delete_group /home/bombrary/pworks/pyt…│DELETE /infra/domains/{domain-id}/group…│Delete Group
  PolicyApi   │delete_infra_segment /home/bombrary/pw…│DELETE /infra/segments/{segment-id}     │Delete infra segment
  PolicyApi   │delete_infra_segment_port /home/bombra…│DELETE /infra/segments/{segment-id}/por…│Delete an infra segment p…
  PolicyApi   │get_infra_segment_port /home/bombrary/…│GET /infra/segments/{segment-id}/ports/…│Get infra segment port by…
  PolicyApi   │list_all_infra_segments /home/bombrary…│GET /infra/segments                     │List all segments under i…
  PolicyApi   │list_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups   │List Groups for a domain
  PolicyApi   │list_infra_segment_ports /home/bombrar…│GET /infra/segments/{segment-id}/ports  │List infra segment ports
  PolicyApi   │patch_group_for_domain /home/bombrary/…│PATCH /infra/domains/{domain-id}/groups…│Patch a group
  PolicyApi   │patch_infra_segment /home/bombrary/pwo…│PATCH /infra/segments/{segment-id}      │Create or update a segment
  PolicyApi   │patch_infra_segment_port /home/bombrar…│PATCH /infra/segments/{segment-id}/port…│Patch an infra segment po…
  PolicyApi   │read_group_for_domain /home/bombrary/p…│GET /infra/domains/{domain-id}/groups/{…│Read group
  PolicyApi   │read_infra_segment /home/bombrary/pwor…│GET /infra/segments/{segment-id}        │Read infra segment
  PolicyApi   │update_group_for_domain /home/bombrary…│PUT /infra/domains/{domain-id}/groups/{…│Create or update a group
  PortsApi    │create_or_replace_infra_segment_port /…│PUT /infra/segments/{segment-id}/ports/…│Create or update an infra…
  PortsApi    │delete_infra_segment_port /home/bombra…│DELETE /infra/segments/{segment-id}/por…│Delete an infra segment p…
  PortsApi    │get_infra_segment_port /home/bombrary/…│GET /infra/segments/{segment-id}/ports/…│Get infra segment port by…
  PortsApi    │list_infra_segment_ports /home/bombrar…│GET /infra/segments/{segment-id}/ports  │List infra segment ports
  PortsApi    │patch_infra_segment_port /home/bombrar…│PATCH /infra/segments/{segment-id}/port…│Patch an infra segment po…
  SegmentsApi │create_or_replace_infra_segment /home/…│PUT /infra/segments/{segment-id}        │Create or update a infra …
  SegmentsApi │create_or_replace_infra_segment_0 /hom…│PUT /infra/segments/{segment-id}        │Create or update a infra …
  SegmentsApi │create_or_replace_infra_segment_port /…│PUT /infra/segments/{segment-id}/ports/…│Create or update an infra…
  SegmentsApi │delete_infra_segment /home/bombrary/pw…│DELETE /infra/segments/{segment-id}     │Delete infra segment
  SegmentsApi │delete_infra_segment_0 /home/bombrary/…│DELETE /infra/segments/{segment-id}     │Delete infra segment
  SegmentsApi │delete_infra_segment_port /home/bombra…│DELETE /infra/segments/{segment-id}/por…│Delete an infra segment p…
  SegmentsApi │get_infra_segment_port /home/bombrary/…│GET /infra/segments/{segment-id}/ports/…│Get infra segment port by…
  SegmentsApi │list_all_infra_segments /home/bombrary…│GET /infra/segments                     │List all segments under i…
  SegmentsApi │list_all_infra_segments_0 /home/bombra…│GET /infra/segments                     │List all segments under i…
  SegmentsApi │list_infra_segment_ports /home/bombrar…│GET /infra/segments/{segment-id}/ports  │List infra segment ports
  SegmentsApi │patch_infra_segment /home/bombrary/pwo…│PATCH /infra/segments/{segment-id}      │Create or update a segment
  SegmentsApi │patch_infra_segment_0 /home/bombrary/p…│PATCH /infra/segments/{segment-id}      │Create or update a segment
  SegmentsApi │patch_infra_segment_port /home/bombrar…│PATCH /infra/segments/{segment-id}/port…│Patch an infra segment po…
  SegmentsApi │read_infra_segment /home/bombrary/pwor…│GET /infra/segments/{segment-id}        │Read infra segment
  SegmentsApi │read_infra_segment_0 /home/bombrary/pw…│GET /infra/segments/{segment-id}        │Read infra segment

  ## Documentation For Models

  • ApiError /home/bombrary/pworks/python-openapi-extract/out/docs/ApiError.md
  • AttachedInterfaceEntry /home/bombrary/pworks/python-openapi-extract/out/docs/AttachedInterfaceEntry.md
  • BridgeProfileConfig /home/bombrary/pworks/python-openapi-extract/out/docs/BridgeProfileConfig.md
  • ChildPolicyConfigResource /home/bombrary/pworks/python-openapi-extract/out/docs/ChildPolicyConfigResource.md
  • ConnectivityAdvancedConfig /home/bombrary/pworks/python-openapi-extract/out/docs/ConnectivityAdvancedConfig.md
  • Expression /home/bombrary/pworks/python-openapi-extract/out/docs/Expression.md
  • FederationConnectivityConfig /home/bombrary/pworks/python-openapi-extract/out/docs/FederationConnectivityConfig.md
  • Group /home/bombrary/pworks/python-openapi-extract/out/docs/Group.md
  • GroupListResult /home/bombrary/pworks/python-openapi-extract/out/docs/GroupListResult.md
  • L2Extension /home/bombrary/pworks/python-openapi-extract/out/docs/L2Extension.md
  • ListResult /home/bombrary/pworks/python-openapi-extract/out/docs/ListResult.md
  • LocalEgress /home/bombrary/pworks/python-openapi-extract/out/docs/LocalEgress.md
  • LocalEgressRoutingEntry /home/bombrary/pworks/python-openapi-extract/out/docs/LocalEgressRoutingEntry.md
  • ManagedResource /home/bombrary/pworks/python-openapi-extract/out/docs/ManagedResource.md
  • PolicyConfigResource /home/bombrary/pworks/python-openapi-extract/out/docs/PolicyConfigResource.md
  • PolicyRequestParameter /home/bombrary/pworks/python-openapi-extract/out/docs/PolicyRequestParameter.md
  • PolicyResource /home/bombrary/pworks/python-openapi-extract/out/docs/PolicyResource.md
  • PortAddressBindingEntry /home/bombrary/pworks/python-openapi-extract/out/docs/PortAddressBindingEntry.md
  • PortAttachment /home/bombrary/pworks/python-openapi-extract/out/docs/PortAttachment.md
  • RelatedApiError /home/bombrary/pworks/python-openapi-extract/out/docs/RelatedApiError.md
  • Resource /home/bombrary/pworks/python-openapi-extract/out/docs/Resource.md
  • ResourceLink /home/bombrary/pworks/python-openapi-extract/out/docs/ResourceLink.md
  • RevisionedResource /home/bombrary/pworks/python-openapi-extract/out/docs/RevisionedResource.md
  • Segment /home/bombrary/pworks/python-openapi-extract/out/docs/Segment.md
  • SegmentAdvancedConfig /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentAdvancedConfig.md
  • SegmentDhcpConfig /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentDhcpConfig.md
  • SegmentExtraConfig /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentExtraConfig.md
  • SegmentListResult /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentListResult.md
  • SegmentPort /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentPort.md
  • SegmentPortListResult /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentPortListResult.md
  • SegmentSubnet /home/bombrary/pworks/python-openapi-extract/out/docs/SegmentSubnet.md
  • SelfResourceLink /home/bombrary/pworks/python-openapi-extract/out/docs/SelfResourceLink.md
  • Tag /home/bombrary/pworks/python-openapi-extract/out/docs/Tag.md
  • UnboundedKeyValuePair /home/bombrary/pworks/python-openapi-extract/out/docs/UnboundedKeyValuePair.md


  ## Documentation For Authorization

  Authentication schemes defined for the API:


  ### BasicAuth

  • Type: HTTP basic authentication

  ## Author
```

## （おまけ）便利CLIの実装

本筋とは関係ない便利CLIコマンドの実装。

### APIメソッドの一覧を出力

APIメソッドの量が多すぎてdocsから探すの大変、という場合に使えそう。

```python
def print_tabular(rows: list[list[str]]):
    fixed_length = [ 0 ] * len(rows[0])
    for row in rows:
        for i in range(len(fixed_length)):
            fixed_length[i] = max(fixed_length[i], len(row[i]))
    fixed_length[-1] = 0

    for row in rows:
        print(" ".join([ c.ljust(fl) for c, fl in zip(row, fixed_length) ]))


@click.option("-i", "input_schema_path", required=True, help="input schema path")
@cli.command("list")
def list_api_paths(
    input_schema_path: str,
):
    logger.info(f"loading: {input_schema_path}")

    with Path(input_schema_path).open("r") as f:
        input_schema_data = json.load(f)

    rows = []
    for path, path_dict in input_schema_data["paths"].items():
        for method, details in path_dict.items():
            rows.append([ path, method.upper(), repr(details["summary"]) ])
    rows.sort()
    print_tabular(rows)
```

実行例。
```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ uv run python main.py list -i nsx_policy_api.json | grep /infra/segments/ | head -10
2026-04-26 06:13:07,301: loading: nsx_policy_api.json
/infra/segments/service-segments                                                                                                                                                   GET    'List Service Segments'
/infra/segments/service-segments/{service-segment-id}                                                                                                                              DELETE 'Delete Service Segment'
/infra/segments/service-segments/{service-segment-id}                                                                                                                              GET    'Read Service Segment'
/infra/segments/service-segments/{service-segment-id}                                                                                                                              PATCH  'Create a service segment'
/infra/segments/service-segments/{service-segment-id}                                                                                                                              PUT    'Create service segment'
/infra/segments/state                                                                                                                                                              GET    'Get infra segments by configuration state'
/infra/segments/{infra-segment-id}/ports/{infra-port-id}/port-discovery-profile-binding-maps                                                                                       GET    'List Infra Port Discovery Profile Binding Maps'
/infra/segments/{infra-segment-id}/ports/{infra-port-id}/port-discovery-profile-binding-maps/{port-discovery-profile-binding-map-id}                                               DELETE 'Delete Infra Port Discovery Profile Binding Profile'
/infra/segments/{infra-segment-id}/ports/{infra-port-id}/port-discovery-profile-binding-maps/{port-discovery-profile-binding-map-id}                                               GET    'Get Infra Port Discovery Profile Binding Map'
/infra/segments/{infra-segment-id}/ports/{infra-port-id}/port-discovery-profile-binding-maps/{port-discovery-profile-binding-map-id}                                               PATCH  'Create Infra Port Discovery Profile Binding Map'
```

### 複数のAPIをマージする

同じエンドポイントだが、basePathによって利用するAPIが分かれており、かつOpenAPI定義も別々のファイルに分かれている。でも同じAPIクライアントとして作りたいから、それらをマージして1つのOpenAPI定義として作りたい。

例えばNSX-Tの例でいうと、
* `/api/v1` でコールするAPIは `nsx_api.json`
* `/policy/api/v1` でコールするAPIは `nsx_policy_api.json`

と分かれている。これをまとめたOpenAPIスキーマを作成して1つのクライアントを作りたい。

そこで、以下の方針でマージするコマンドを作ってみる。

* basePathを `paths` のほうに寄せる
* dictやlistの場合は要素をマージする。そうでない場合は上書き
    * 同名のリソースが存在した場合、同じ構造かどうかのチェックをする
    * ただし `info` は例外的に上書きしてしまう

```python
def merge_with_dup_check(d1: dict[str, Any], d2: dict[str, Any]) -> dict[str, Any]:
    dup_keys = d1.keys() & d2.keys()
    if len(dup_keys) > 0:
        for k in dup_keys:
            if d1[k] == d2[k]:
                pass
            else:
                raise ValueError(f"Duplicate key, but structure is inconsistent. d1[{repr(k)}]={d1[k]}, d2[{repr(k)}]={d2[k]}")
    return d1 | d2


@click.option("-i", "input_schema_path_list", required=True, multiple=True, help="input schema path (multiple)")
@click.option("-o", "output_schema_path", required=True, help="output schema path")
@cli.command("merge")
def merge_schamas(
    input_schema_path_list: list[str],
    output_schema_path: str,
):
    logger.info(f"loading: {input_schema_path_list}")

    input_schema_data_list = []
    for input_schema_path in input_schema_path_list:
        with Path(input_schema_path).open("r") as f:
            input_schema_data_list.append(json.load(f))

    # basePathの変換
    for input_schema_data in input_schema_data_list:
        base_path = input_schema_data["basePath"]
        input_schema_data["paths"] = { base_path + k: v for k, v in input_schema_data["paths"].items() }

    # 初期化
    input_schema_data_first = input_schema_data_list[0]
    output_schema_data = {}
    for k, v in input_schema_data_first.items():
        output_schema_data[k] = v

    # マージ
    OVEREIDE_KEYS = [ "info" ]
    for input_schema_data in input_schema_data_list[1:]:
        for k, v in input_schema_data.items():
            if k in OVEREIDE_KEYS:
                output_schema_data[k] = v
            elif isinstance(v, dict):
                output_schema_data[k] = merge_with_dup_check(output_schema_data[k], v)
            elif isinstance(v, list):
                output_schema_data[k] += v
            else:
                output_schema_data[k] = v
    output_schema_data["basePath"] = ""

    # 書き出し
    with Path(output_schema_path).open("w") as f:
        json.dump(output_schema_data, f)
    logger.info(f"saved: {output_schema_path}")
```

これで実行してみると、 `/api/v1` 付きのものと `/policy/api/v1` 付きのものが混合して出力されていることがわかる。

```console
[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths_policy.txt
/infra/segments
/infra/segments/{segment-id}
/infra/segments/{segment-id}/ports
/infra/segments/{segment-id}/ports/{port-id}
/infra/domains/{domain-id}/groups
/infra/domains/{domain-id}/groups/{group-id}
/infra/realized-state/enforcement-points/{enforcement-point-name}/vifs
/infra/realized-state/enforcement-points/{enforcement-point-name}/virtual-machines

[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths_default.txt
/fabric/vifs
/fabric/virtual-machines
/trust-management/certificates
/trust-management/csrs
/trust-management/csrs-extended

[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths_policy.txt | uv run python main.py convert -i nsx_policy_api.json -o out_policy.json
2026-04-26 07:37:27,863: api_path: 8
2026-04-26 07:37:27,863: loading: nsx_policy_api.json
2026-04-26 07:37:27,952: loaded: nsx_policy_api.json
2026-04-26 07:37:27,952: extracting path: /infra/segments
2026-04-26 07:37:27,953: extracting path: /infra/segments/{segment-id}
2026-04-26 07:37:27,953: extracting path: /infra/segments/{segment-id}/ports
2026-04-26 07:37:27,953: extracting path: /infra/segments/{segment-id}/ports/{port-id}
2026-04-26 07:37:27,953: extracting path: /infra/domains/{domain-id}/groups
2026-04-26 07:37:27,954: extracting path: /infra/domains/{domain-id}/groups/{group-id}
2026-04-26 07:37:27,954: extracting path: /infra/realized-state/enforcement-points/{enforcement-point-name}/vifs
2026-04-26 07:37:27,954: extracting path: /infra/realized-state/enforcement-points/{enforcement-point-name}/virtual-machines
2026-04-26 07:37:27,954: extracting ref: #/definitions/ListResult
2026-04-26 07:37:27,954: extracting ref: #/definitions/Resource
...
2026-04-26 07:37:27,955: extracting ref: #/definitions/RevisionedResource
2026-04-26 07:37:27,955: extracting ref: #/definitions/ResourceLink
2026-04-26 07:37:27,955: extracting ref: #/definitions/PortAttachment
2026-04-26 07:37:27,955: extracting ref: #/definitions/PortAddressBindingEntry
2026-04-26 07:37:27,955: extracting ref: #/definitions/L2Extension
2026-04-26 07:37:27,955: extracting ref: #/definitions/SegmentAdvancedConfig
2026-04-26 07:37:27,955: extracting ref: #/definitions/ManagedResource
2026-04-26 07:37:27,955: extracting ref: #/definitions/ChildPolicyConfigResource
2026-04-26 07:37:27,955: extracting ref: #/definitions/PolicyResource
2026-04-26 07:37:27,955: extracting ref: #/responses/NotFound
2026-04-26 07:37:27,955: extracting ref: #/definitions/LocalEgress
2026-04-26 07:37:27,958: saved: out_policy.json

[bombrary@nixos:~/pworks/python-openapi-extract]$ cat target_paths_default.txt | uv run python main.py convert -i nsx_api.json -o out_default.json
2026-04-26 07:37:42,865: api_path: 5
2026-04-26 07:37:42,865: loading: nsx_api.json
2026-04-26 07:37:42,910: loaded: nsx_api.json
2026-04-26 07:37:42,910: extracting path: /fabric/vifs
2026-04-26 07:37:42,911: extracting path: /fabric/virtual-machines
2026-04-26 07:37:42,911: extracting path: /trust-management/certificates
2026-04-26 07:37:42,911: extracting path: /trust-management/csrs
2026-04-26 07:37:42,911: extracting path: /trust-management/csrs-extended
2026-04-26 07:37:42,911: extracting ref: #/definitions/CsrList
2026-04-26 07:37:42,911: extracting ref: #/responses/BadRequest
2026-04-26 07:37:42,912: extracting ref: #/definitions/VirtualNetworkInterface
...
2026-04-26 07:37:42,912: extracting ref: #/definitions/Resource
2026-04-26 07:37:42,912: extracting ref: #/definitions/DiscoveredResource
2026-04-26 07:37:42,912: extracting ref: #/definitions/VirtualMachineListResult
2026-04-26 07:37:42,912: extracting ref: #/responses/PreconditionFailed
2026-04-26 07:37:42,912: extracting ref: #/definitions/X509Certificate
2026-04-26 07:37:42,912: extracting ref: #/responses/NotFound
2026-04-26 07:37:42,912: extracting ref: #/definitions/SelfResourceLink
2026-04-26 07:37:42,912: extracting ref: #/definitions/VirtualNetworkInterfaceListResult
2026-04-26 07:37:42,913: extracting ref: #/definitions/Tag
2026-04-26 07:37:42,914: saved: out_default.json

[bombrary@nixos:~/pworks/python-openapi-extract]$ uv run python main.py merge -i out_policy.json -i out_default.json -o out.json
2026-04-26 07:36:20,479: loading: ('out_policy.json', 'out_default.json')
2026-04-26 07:36:20,484: saved: out.json

[bombrary@nixos:~/pworks/python-openapi-extract]$ cat out.json | jq '.paths | keys'
[
  "/api/v1/fabric/vifs",
  "/api/v1/fabric/virtual-machines",
  "/api/v1/trust-management/certificates",
  "/api/v1/trust-management/csrs",
  "/api/v1/trust-management/csrs-extended",
  "/policy/api/v1/infra/domains/{domain-id}/groups",
  "/policy/api/v1/infra/domains/{domain-id}/groups/{group-id}",
  "/policy/api/v1/infra/realized-state/enforcement-points/{enforcement-point-name}/vifs",
  "/policy/api/v1/infra/realized-state/enforcement-points/{enforcement-point-name}/virtual-machines",
  "/policy/api/v1/infra/segments",
  "/policy/api/v1/infra/segments/{segment-id}",
  "/policy/api/v1/infra/segments/{segment-id}/ports",
  "/policy/api/v1/infra/segments/{segment-id}/ports/{port-id}"
]
```

## おわりに

OpenAPIスキーマをこねて必要最低限だけ取り出すスクリプトを実装した。

正直こんなの最近なら生成AIで一瞬で生成してもらえるが、今回みたいな「閉じた構造を生成する」という観点は別にOpenAPIの話に限らず、知的な面白さがあったので自分で考えて手で実装した。
