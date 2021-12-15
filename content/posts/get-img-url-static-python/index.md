---
title: "Pythonを使った(静的)ページの画像のURL取得"
date: 2021-12-09T11:08:15+09:00
toc: true
tag: ["CLI", "Flask", "Web"]
category: ["Python"]
---

Webページの画像だけを手っ取り早く取得したい場合にどうすれば良いのかを考えた。
これを行うプログラムをPythonで取得する。

この記事で作成したプログラムは[GitHubのRepository](https://github.com/bombrary/get-img-python)に公開した。

## 前提

- Pythonのバージョンは3.10を想定。
- この記事では外部ライブラリとして
  - [Requests](https://requests.readthedocs.io/en/master/) 2.26.0
  - [Beautiful Soup](https://www.crummy.com/software/BeautifulSoup/bs4/doc/) 4.10.0
  - [tqdm](https://github.com/tqdm/tqdm) 4.62.3
  - [w3lib](https://w3lib.readthedocs.io/en/latest/) 1.22.0

  を使う。この記事のコードを動かす場合は`pip`コマンドなどでインストールしておく。

## 方針

やることは案外単純である。

1. WebページのHTMLデータを取ってくる。
2. `img`要素を探して、その`src`属性を取ってくる。
3. scheme、netlocが無かったらそれを付加して、完全なURLにする。

1は[Requests](https://requests.readthedocs.io/en/master/)、2は[Beautiful Soup](https://www.crummy.com/software/BeautifulSoup/bs4/doc/)を使えば良いだろう。
3は思ったより複雑である。`src`属性に入っているパスには、

- URL: `http://foo.org/bar/hoge.png`
- スキームが省略されている: `//foo.org/bar/hoge.png`
- 絶対パス: `/bar/hoge.png`
- 相対パス: `../bar/hoge.png`
- データURL: `data:image/png;base64,...`

など色々ある。
これらのフォーマットを統一して完全なURLにするのは面倒であるが、幸運にも[urllib.parse.urljoin](https://docs.python.org/ja/3/library/urllib.parse.html#urllib.parse.urljoin)という関数があったのでこれを使う
(余談: 初め、`urljoin`の存在を知らずに自前でURLの変換機能を実装してしまった。学びにはなったが時間を費やした…)。

ついでの機能として、「特定の要素の中に含まれている`img`要素のURLを取得する」ことも考える。
これはCSSセレクタとして指定できるようにする。

まとめると、画像のURLを取得する関数は以下のようなインターフェースとなる。
```python
def get_img_urls(url: str, selector: Optional[str]=None) -> list[str]:
  pass # これから実装する
```
URLとセレクタを引数にとり、`img`要素のURLのリストを返す関数である。

ついでに画像ダウンロードのためのCLIや、画像を閲覧するWebアプリなどが作れたら良い。

## プロジェクトの構造

Pythonでモジュールを作ったことがないため、正しい作り方が分からないが、とりあえず以下のような構成にしてみる。
細かいディレクトリの構成は各節で述べる。

```
/project
|
+--+ getimg/
|
+--+ commandline/
|
+--+ viewer/
|
+--+ tests/
     +-- __init__.py
     +-- test_getimg.py
     +-- test_commandline.py
```

### CLI

CLIの書式は以下のようにする。取得したい画像のあるページのURL、及び画像のダウンロード先を指定する。

{{< cui >}}
> python -m commandline "http://foo.com/bar/" output/
{{< /cui >}}

CLIのコマンドライン引数の取扱いには[argparse](https://docs.python.org/ja/3/library/argparse.html?highlight=add_argument#module-argparse)が便利なのでそれを使う。


### 画像ビューワー

Webアプリについては、[Flask](https://flask.palletsprojects.com/en/2.0.x/)が一番手軽かなと思ったのでこれを使う。

以下のコマンドでWebサーバーが起動するようにする。

{{< cui >}}
> python -m viewer
{{< /cui >}}

ここではとりあえず一番手軽な`Flask.run`関数でサーバーを動かす。`Flask.run`で動作するのは開発用サーバーなのだが、個人的に利用することしか考えていないのでこれで良い。

### 補足: pyrightを使った開発

LSPにpyrightを使うとき、例えば`commandline/__init__.py`から`getimg`モジュールを参照しようとすると、「モジュールが無い」と怒られる。
これはプロジェクトの場所をpyrightが認識していないのが原因(多分)。なのでプロジェクトの位置をpyrightに教えてあげる必要がある。
そのために、`pyrightconfig.json`を作成し、内容を以下のようにする。

```json
{
  "executionEnvironments":[
    {
      "root": "."
    }
  ]
}
```

## 画像のURLを取得する関数の作成

`getimg`ディレクトリの構成。

```
/project
|
+-- getimg/
    +-- __init__.py
```

`getimg/__init__.py`を編集。必要モジュールは以下の通り。

```python
from typing import Optional, TypeGuard
from bs4 import BeautifulSoup
import requests
import urllib.parse
```


### 大まかな処理

まず、画像の取得は`requests`モジュールの`get`関数を使う。

```python
response = requests.get(url)
```

手に入れたHTML文書から`img`要素を探し、そのパスを取得する処理は`get_img_srcs`という関数に任せる。

```python
paths = get_img_srcs(response.text, selector)
```

`get_img_srcs`は次のようなシグネチャとし，後で実装する。
```python
def get_img_srcs(html_text: str, selector: Optional[str]=None) -> list[str]:
  pass
```

取得したパスに対し、`urllib.parse.urljoin`関数を使ってURLに変換する。
引数に指定しているのは`url`ではなく`response.url`である。このようにすれば、リダイレクトされたケースに対応できる。

```python
[urllib.parse.urljoin(response.url, path) for path in paths]
```

これらをまとめると、以下のようになる。

```python
def get_img_urls(url: str, selector: Optional[str]=None) -> list[str]:
    response = requests.get(url)
    paths = get_img_srcs(response.text, selector)
    return [urllib.parse.urljoin(response.url, path) for path in paths]
```

### img要素を探し、そのパスを取得する処理

まずは`BeautifulSoup`でHTML文書をパースする。

```python
soup = BeautifulSoup(html_text, 'html.parser')
```

`soup.select`を使って`img`要素を探す。その際、引数`selector`が指定されていれば`soup.select('[selector] img')`
とし、指定されていなければ`soup.select('img')`とする。

```python
new_selector = f'{selector} img' if selector is not None else 'img'
imgs = soup.select(new_selector)
```

`get`メソッドで`src`要素を読み取り、パスを取得する。

```python
paths = [img.get('src') for img in imgs]
```

型を気にしないのであればこのまま`return paths`しても良いが、pyrightなりmypyなりの型チェックをした際に怒られる。
これはなぜかというと、`bs4`モジュールの`Tag.get`関数の返り値が`str | list[str] | None`であるから。
これはコード中の`img.get('src')`に対応している。`img`要素なのに属性値が無かったり複数値とったりすることなんで普通は無いのだが、`Tag`の実装上こうなってしまっている。

解決策は、以下のように`TypeGuard`を使って、リストの中に`str`型のものしかないことを保証してやる。

```python
def is_attr_str(obj: str | list[str] | None) -> TypeGuard[str]:
    return isinstance(obj, str)

[path for path in paths if is_attr_str(path)]
```

ここまでをまとめると、関数は以下のようになる。

```python
def is_attr_str(obj: str | list[str] | None) -> TypeGuard[str]:
    return isinstance(obj, str)

def get_img_srcs(html_text: str, selector: Optional[str]=None) -> list[str]:
    soup = BeautifulSoup(html_text, 'html.parser')
    new_selector = f'{selector} img' if selector is not None else 'img'
    imgs = soup.select(new_selector)
    paths = [img.get('src') for img in imgs]
    return [path for path in paths if is_attr_str(path)]
```

### テスト

`tests/test_getimg.py`を編集。pytestを使ってテストを書く

`getimg/tests/test_getimg.py`の内容を以下のようにする。
`get_img_srcs`関数と`get_img_urls`関数のテストをここで行う。

まずはテストの対象であるHTML文書を書いておく。

```python
from getimg import get_img_srcs, get_img_urls
from typing import Final
from pytest import MonkeyPatch

html_text: Final = """
<html>
    <body>
        <div class="container1">
            <img src="http://loc1.com/foo/img1.png">
            <img src="/img2.png">
        </div>
        <div class="container2">
            <img src="../img3.png">
            <img src="//loc2.com/img4.png">
            <img src="data:image/png;base64,BINIMAGE">
        </div>
    </body>
</html>
"""
```

`get_src`関数がうまくいくかどうかのテスト。

```python
def test_get_src():
    expect = [
        "http://loc1.com/foo/img1.png",
        "/img2.png",
        "../img3.png",
        "//loc2.com/img4.png",
        "data:image/png;base64,BINIMAGE"
    ]

    assert get_img_srcs(html_text) == expect
```

`get_img_urls`関数がうまくいくかどうかのテスト。pytestの`monkeypatch` fixtureを使い、`requests.get`の処理を`fake_get`に挿げ替えているところがポイント。
CSSセレクタが機能しているかどうかのテストも行う。

```python
class Result:
    def __init__(self, url: str):
        self.text = html_text
        self.url = url

def fake_get(url: str) -> Result:
    return Result(url)


def test_get_url(monkeypatch: MonkeyPatch):
    monkeypatch.setattr('requests.get', fake_get)


    url = "http://loc.com/foo/"
    expect = [
        "http://loc1.com/foo/img1.png",
        "http://loc.com/img2.png",
        "http://loc.com/img3.png",
        "http://loc2.com/img4.png",
        "data:image/png;base64,BINIMAGE",
    ]

    assert get_img_urls(url) == expect


def test_get_url_with_selector(monkeypatch: MonkeyPatch):
    monkeypatch.setattr('requests.get', fake_get)

    url = "http://loc.com/foo/"
    expect = [
        "http://loc.com/img3.png",
        "http://loc2.com/img4.png",
        "data:image/png;base64,BINIMAGE",
    ]

    assert get_img_urls(url, ".container2") == expect
```

これで`pytest`を実行すると、テストに成功することが確かめられる。

## CLIの作成

### 仕様

`commandline`ディレクトリの構成。

```
/project
|
+-- commandline/
    +-- __init__.py
    +-- __main__.py
```

CLIの機能及び実装上の注意については以下の通り。

- 重複している名前があれば、ファイル名の末尾に`_1`、`_2`などと数字をつける。
- 画像のダウンロードに失敗した場合、そのURLと失敗の原因を出力する。
- プログレスバーを出力する。
- クエリ文字列に注意する。`http://foo.com/img.png?foobar`みたいにクエリ文字列がついていることがある。
- Data URLの場合で処理を分ける必要がある。URLの中に画像データが含まれているため、以下の3つの事項に注意する。
  - Data URLをパースして、画像データ、画像の形式のデータを取得する必要がある。
  - 画像データをデコードする場合、エンコーディング形式に気をつける必要がある。`png`などのバイナリ形式の画像なら`base64`であるが、`svg`形式の場合は`utf-8`の可能性がある。
  - 画像ファイル名が存在しないため、適当に`data_url.png`という名前をつけることにする。

  パース処理、デコード処理が結構面倒。しかし幸運にも[w3lib](https://w3lib.readthedocs.io/en/latest/)というライブラリの`w3lib.url.parse_data_uri`と言う関数があったので使わせてもらう。
- テストがしやすいように、処理を細かく関数に分ける。

また、実行するときは以下のような書式にする。

{{< cui >}}
> python -m commandline "http://foo.com/bar/" output/
{{< /cui >}}

また、コマンドライン引数を指定できるようにする。

- `-v`オプションをつけると、ダウンロードした画像URLとその出力先のログを出力。
- `-s`オプションをつけると、CSSセレクターを指定できる。

### 準備

`commandline/__init__.py`を編集。まず、必要モジュールをインポート。

```python
from getimg import get_img_urls
from typing import Optional
import requests
from requests.exceptions import RequestException
import urllib.parse
import os.path
from tqdm import tqdm
```

ログを出力する関数を作っておく。

```python
def print_log(text: str, need_log: bool):
    if need_log:
        print(text)
```

### メインとなる処理

URLからHTML文書を取得し、そこから`img`タグの`src`を読み取り、そのダウンロードを行う関数は`download_imgs_from_page`とする。
返り値は画像のダウンロードの失敗情報のリストである。これは`(URL, 例外)`のタプルのリストとする。

`download_imgs_from_urls`は次の項で実装する。

```python
FailInfo = tuple[str, RequestException | ValueError]


def download_imgs_from_page(url: str, output_dir: str, selector: Optional[str]=None, need_log: bool=False) -> list[FailInfo]:
    urls = get_img_urls(url, selector)
    return download_imgs_from_urls(urls, output_dir, need_log)
```


### 画像をダウンロードする処理

1つの画像をダウンロードする処理、複数の画像をダウンロードする処理を別々の関数に分ける。
例外が発生した場合は、その結果を`failInfo`に入れる。Data URLか否かの分岐はここで行っている。

プログレスバーを出力するのには[tqdm](https://github.com/tqdm/tqdm)を使う。

```python
def is_dataurl(url: str) -> bool:
    return url.startswith('data:')


def download_imgs_from_urls(urls: list[str], output_dir: str, need_log: bool=False) -> list[FailInfo]:
    failInfo = []
    for url in tqdm(urls):
        if is_dataurl(url):
            e = save_img_from_data_url(url, output_dir, need_log)
            if e is not None:
                failInfo.append((url[0:100] + '...', e)) # 長すぎる場合が多いので100文字までで切る
        else:
            e = download_img_from_url(url, output_dir, need_log)
            if e is not None:
                failInfo.append((url, e))
    return failInfo
```

データURLでないURLについては、普通に`requests.get`関数でダウンロードする。
`make_path`関数と`save_img`関数はこの後実装する。

```python
def download_img_from_url(url: str, output_dir: str, need_log: bool=False) -> Optional[RequestException]:
    path = make_path(url, output_dir)

    try:
        res = requests.get(url)
    except RequestException as e:
        return e

    save_img(path, res.content)

    print_log(f'{url} -> {path}', need_log)
```

続いてデータURL形式の処理。主なパース処理は`w3lib.url.parse_data_uri`に任せ、拡張子は`extract_ext_from_mime`という関数を作って処理している。
`svg`形式の画像についてはMIMEタイプが`image/svg+xml`となるため、例外的に扱っている。

```python
def extract_ext_from_mime(mime: str) -> str:
    [_, type] = mime.split('/')
    if type == 'svg+xml':
        return 'svg'
    else:
        return type


def save_img_from_data_url(url: str, output_dir: str, need_log: bool=False) -> Optional[ValueError]:
    try:
        result = w3lib.url.parse_data_uri(url)
    except ValueError as e:
        return e

    ext = extract_ext_from_mime(result.media_type)

    path = f'{output_dir}/dara_url.{ext}'
    save_img(path, result.data)

    print_log(f'(Data URL) -> {path}', need_log)
```


### パスの解決処理

与えられた画像のURLからファイル名を取り出して、画像を出力するディレクトリ`output_dir`と組み合わせて保存先パスを作成。

`output_dir`について、`dir/`と`dir`は同じものとみなす。そのために`rstrip`関数を用いている。
別にこれをしなくても保存自体はできるのだが、ログに`http://foo.com/img.png -> output_dir//img.png`と二重の`//`が現れてしまい、少し汚い。

`urllib.parse.urlparse`をわざわざ呼び出しているのは、クエリ文字列を省くため。

```python
def make_path(url: str, output_dir: str) -> str:
    output_dir = output_dir.rstrip('/')
    path = f'{output_dir}/{extract_filename(url)}'
    return path


def extract_filename(url: str) -> str:
    urlinfo = urllib.parse.urlparse(url)
    return os.path.basename(urlinfo.path)
```

### 画像の保存処理

`rename_if_exists`関数で行っている処理は、出力先パスに同名のファイルが無いかどうか調べ、存在した場合は`name_1.png`や`name_2.png`のように数字をつけること。

```python
def save_img(path: str, content: bytes):
    path = rename_if_exists(path)
    with open(path, 'wb') as f:
        f.write(content)


def rename_if_exists(path) -> str:
    if not os.path.exists(path):
        return path
    else:
        root, ext = os.path.splitext(path)
        i = 1
        while True:
            new_path = f'{root}_{i}{ext}'
            if not os.path.exists(new_path):
                return new_path
            i += 1
```

### テスト

`tests/test_commandline.py`を編集。使う関数を読み込んでおく。

```python
from commandline import extract_filename, make_path, rename_if_exists, download_imgs_from_urls
import pytest
from pytest import MonkeyPatch
from typing import Final
from requests.exceptions import HTTPError
```

関数`extract_filename`のテスト。クエリ文字列がちゃんと省かれるかどうか見ている。

```python
test_cases_extract_filename: Final = [
    ("http://foo.com/img.png", "img.png"),
    ("http://foo.com/bar/img.png", "img.png"),
    ("http://foo.com/bar/img.png?q=123", "img.png"),
]

@pytest.mark.parametrize("url, expect", test_cases_extract_filename)
def test_extract_filename(url: str, expect: str):
    assert extract_filename(url) == expect
```

関数`make_path`のテスト。

```python
test_cases_make_path: Final = [
    ("http://foo.com/img.png", "imgout", "imgout/img.png"),
    ("http://foo.com/img.png", "imgout/", "imgout/img.png"),
    ("http://foo.com/bar/fuga/img.png", "imgout", "imgout/img.png"),
]

@pytest.mark.parametrize("url, output_dir, expect", test_cases_make_path)
def test_make_path(url: str, output_dir: str, expect: str):
    assert make_path(url, output_dir) == expect
```

関数`rename_if_exists`のテスト。

```python
test_cases_rename_if_exists: Final = [
    (["output/img.png"], "output/img.png", "output/img_1.png"),
    (["output/img.png", "output/img_1.png"], "output/img.png", "output/img_2.png"),
    (["output/img_1.png"], "output/img.png", "output/img.png"),
    (["output/img_1.png"], "output/img_1.png", "output/img_1_1.png"),
    (["output/img.png", "output/img_2.png"], "output/img.png", "output/img_1.png"),
]

@pytest.mark.parametrize("paths_exist, target, expect", test_cases_rename_if_exists)
def test_rename_if_exists(paths_exist: list[str], target: str, expect: str, monkeypatch: MonkeyPatch):
    def fake_exists(path: str):
        return path in paths_exist

    monkeypatch.setattr('os.path.exists', fake_exists)

    assert rename_if_exists(target) == expect
```

関数`download_imgs_from_urls`のテスト。失敗した場合にその情報を返すかどうかを見ている。

```python
def test_download_imgs_from_urls(monkeypatch: MonkeyPatch):
    def fake_save_img(*_):
        pass

    class Response:
        def __init__(self):
            self.content = b'succeed'

    def fake_get(url: str) -> Response:
        if url == 'fail':
            raise HTTPError
        else:
            return Response()

    monkeypatch.setattr('commandline.save_img', fake_save_img)
    monkeypatch.setattr('requests.get', fake_get)

    urls = ["fail", "success", "fail", "fail"]
    failInfo = download_imgs_from_urls(urls, '.')
    assert len(failInfo) == 3
```

これで`pytest`が通ることを確認する。

### インターフェースの作成

`__main__.py`を編集。`argparse`モジュールを使って、コマンドライン引数のパースを行う。

```python
from . import download_imgs_from_page
import argparse

parser = argparse.ArgumentParser(prog="commandline")
parser.add_argument('url', type=str)
parser.add_argument('path', type=str)
parser.add_argument('-v', nargs='?', default=False, const=True, help="print log verbosely")
parser.add_argument('-s', type=str, help="CSS selector")

args = parser.parse_args()

failInfo = download_imgs_from_page(args.url, args.path, args.s, args.v)
for info in failInfo:
    print(info[0], info[1])
```

これで`python -m commandline URL 出力先ディレクトリ`とすると画像がダウンロードされるはず。
`python -m commandline -h`とするとコマンドの説明が出力される。

## 画像ビューワーWebアプリの作成

### 仕様

`viewer`ディレクトリの構成。

```
/project
|
+-- viewer/
    +-- __init__.py
    +-- __main__.py
    +-- templates/
    |   +-- index.html
    +-- static/
        +-- style.css
```

以下のような仕様を持つアプリを作る。

- `/`にアクセスすると、URLとCSSセレクタを入力するフォームが現れる。URLは必須入力。
- 送信ボタンを押すと、入力したURLにある画像をそのページに表示する。

### 雛形作成

`__init__.py`を以下のようにする。

```python
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello'
```

`__main__.py`を以下のようにする。一応、`-p [port]`でポートを指定できるようにしておく。

デバックのしやすさのため、`app.config['ENV'] = 'development'`を指定しておく
(本番環境の場合は使ってはいけないので注意。[参考](https://msiz07-flask-docs-ja.readthedocs.io/ja/latest/config.html#ENV))。

```python
from viewer import app
import argparse

parser = argparse.ArgumentParser(prog="viewer")
parser.add_argument('-p', type=str, default="8000")

args = parser.parse_args()

app.config['ENV'] = 'development'
app.run(debug=True, port=args.p)
```

これで`python -m viewer`とすると、開発用サーバーが起動する。ポートを変えたい場合は`python -m viewer -p ポート番号`とする。以下、ポートはデフォルトの`8000`で話を進める。[http://localhost:8000](http://localhost:8000)にアクセスすると、現時点では`Hello`とだけ表示されたページが出力される。

### templateの作成

仕様的に、作るWebページは1ページだけでよい。それを`viewer/templates/index.html`とし、以下のようにする。

CSSを後で書くので、適当にクラスを付与しておく。
`.get-img-form`の中にあるのが入力フォーム、`.received-images`の中にあるのが、表示された画像を表す。

```html
<html>
  <head>
    <meta charset="utf-8">
    <title>Image Viewer</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='style.css') }}">
  </head>
  <body>
    <div class="get-img-form">
      <form method="POST">
        <div>
          <label for="url">URL</label>
          <input name="url" required>
        </div>
        <div>
          <label for="selector">Selector</label>
          <input name="selector">
        </div>
        <div>
          <input type="submit" value="submit">
        </div>
      </form>
    </div>
    <div class="received-images">
      {% for url in urls %}
        <img src="{{ url }}">
      {% endfor %}
    </div>
  </body>
</html>
```

### ビューの作成

`viewer/__init__.py`を編集。今回作るFlaskアプリはこれだけでよい。

`POST`メソッドが来たとき、フォームからURLとセレクタの情報を取得。
それを使って`get_img_urls`を呼び出し、画像URLを取得。
それを`render_template`の引数に指定すればよい。

```python
from flask import Flask, render_template, request
from getimg import get_img_urls

app = Flask(__name__)

@app.route('/', methods=('GET', 'POST'))
def index():
    if request.method == 'POST':
        url = request.form['url']
        selector = request.form['selector']

        if url is not None:
            urls = get_img_urls(url, selector)
            return render_template('index.html', urls = urls)

    return render_template('index.html')
```

こんな感じのページが表示される。ここにURLとセレクタ(任意)を入力しsubmitボタンを押すと、URL先の画像が下に表示される。

{{< figure src="img/sc0.png" >}}

### 画像の並びの調整

このままだと画像の並びがやや汚いため、`getimg/viewer/static/style.css`を編集。`columns`プロパティを利用。

```css
.received-images {
  columns: 4;
}

.received-images img {
  width: 100%;
}
```

これで最低限のWebアプリができた。

## 今後の課題

- Webアプリのデザインを最低限しかやっていないので、もう少しCSSを書くべき。
- JSなどを使っている動的なページの画像取得ができない。そのため割と多くのWebサイトにおいて、画像が取得できない。これは`request.get`の代わりにSeleniumを使えば対応できるかも。その場合、「画像が読み込まれるまで数秒待つ」「特定の要素が現れるまで待つ」などといった処理が必要になるため、今回作った`getimg`モジュールよりは複雑になる。
