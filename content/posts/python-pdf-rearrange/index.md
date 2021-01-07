---
title: "PythonでPDFの順序並び替えと空白ページ挿入(2種類の方法)"
date: 2021-01-07T11:50:37+09:00
tags: ["PDF", "PyPDF4"]
categories: ["Python"]
toc: true
---

平綴じ印刷ができるように、PDFの順序を入れ替えたり、空白ページを挿入するプログラムを書いた。
方法1はPython + いろんなコマンドで、方法2はPythonのPDFライブラリである`PyPDF4`を利用した方法。
実装してみた結果、後者が圧倒的に簡単だった。

## 動機

[平綴じ](http://zokeifile.musabi.ac.jp/平綴じ/)がしたい場面が出てきたが、印刷機に専用の設定が見つからなかった。
なので平綴じになるようにPDFのページ順を1,2,3,4,5,6,7,8,...から4,1,2,3,8,5,6,7,..に変え、それをプリンタで両面刷り(短辺綴じ)・2ページ割付で印刷することを考えた。

平綴じの場合、紙に両面4ページずつ印刷されることになる。するとPDFのページ数は4の倍数でなくてはならない。よって、4の倍数でなかった場合はその分を空白ページで埋めなければならない。

### PDFファイルの準備

テスト用にPDFファイルを作っておく。ここはなんでも良いのだが、とりあえず以下のLaTeXのコードから10ページのPDFファイルを作る。名前は`input.pdf`としておく。

```latex
\documentclass{jsarticle}
\begin{document}
\centering \Huge
1 Page
\newpage
2 Page
\newpage
3 Page
\newpage
4 Page
\newpage
5 Page
\newpage
6 Page
\newpage
7 Page
\newpage
8 Page
\newpage
9 Page
\newpage
10 Page
\end{document}
```

## 方法1：Python + 諸々のコマンドの利用

### 方針

PDFのページ順を変えるためには、`pdftk`コマンドを利用すれば良い。`pdftk`は、Homebrewなら`brew install pdftk-java`で使えるようになる)。例えば8ページのPDFファイル`input.pdf`を並び替えるなら次のコマンドで可能。

{{< cui >}}
$ pdftk A=input.pdf cat A4 A1 A2 A3 A8 A5 A6 A7 output output.pdf
{{< /cui >}}

例えば空白ページを1ページ持つファイルを`blank.pdf`とすると、6ページのPDFファイルを並び替え、7、8ページを空白ページとするコマンドは次のように書ける。`A7`と`A8`が`B1`に置き換わっていることに注目。

{{< cui >}}
$ pdftk A=input.pdf B=blank.pdf cat A4 A1 A2 A3 B1 A5 A6 B1 output output.pdf
{{< /cui >}}

空白ページは次のように作成すればよい([参考](https://unix.stackexchange.com/questions/277892/how-do-i-create-a-blank-pdf-from-the-command-line))。
`convert`は、Homebrewなら`brew install imagemagick`で使えるようになる。

{{< cui >}}
$ convert xc:none -page 842x595 blank.pdf
{{< /cui >}}

`842x595`の部分はPDFのサイズを表すが、このサイズはPDFによって異なるので、`input.pdf`からページサイズを知る必要がある。これは`pdfinfo`で可能。`pdfinfo`は、Homebrewなら`brew install poppler`で使えるようになる。また、`Pages`からページ数を取得できる。

{{< cui >}}
$ pdfinfo input.pdf
...
Pages:          10
...
Page size:      595.28 x 841.89 pts (A4)
...
{{< /cui >}}

実際には、`A4 A1 A2 A3 ...`を手で書くわけには行かないし、`input.pdf`のページサイズも勝手に取得して欲しいので、この辺りの処理をプログラムに任せることにする。プログラミング言語はなんでも良いが、今回はPythonを選択する。


### 実装

まずはPDFの情報を取得する関数を作る。Pythonでコマンドを実行するために`subprocess`モジュールを使う。
`pdftk`コマンドの出力結果は`key: val`の形で与えられるので、正規表現で`key`と`val`を取り出す。
`Pages`はそのまま`int`に変換すれば良いが、`Page size`は`[float] x [float]`の形で書かれているので、それを正規表現で取り出す。

```python
import subprocess
import re

def get_pdfinfo(path):
    proc = subprocess.Popen(["pdfinfo", path], encoding='utf-8', stdout=subprocess.PIPE)

    p = re.compile('(.+): +(.+)\n')
    info_dict = dict([p.match(line).groups() for line in proc.stdout])

    pages = int(info_dict['Pages'])
    (width, height) = re.match(r'(\d+(?:\.\d+)?) x (\d+(?:\.\d+)?)', info_dict['Page size']).groups()

    class PDFInfo:
        def __init__(self, pages, width, height):
            self.pages = pages
            self.width = width
            self.height = height

    return PDFInfo(pages, width, height)
```

空白ページを1ページ持つのPDFファイルを作成する関数は次のようにする。

```python
def create_blank_page(filename, width, height):
    subprocess.run(['convert', 'xc:none', '-page', f'{width}x{height}', filename])
```

平綴じ用の順序を作る関数を定義する。

```python
def new_page_index(pages):
    page_index = []
    new_pages = (pages + 3) // 4 * 4
    for i in range(0, new_pages):
        if i % 4 == 0:
            page_index.append(i + 4)
        else:
            page_index.append(i)
    return page_index
```

最後に、実際に入れ替える処理を`rearrange_pdf`関数としてまとめる。ヘルパー関数として、ページ順序を`pdftk`の引数用のフォーマットに変換する関数`make_cat_args`を作る。

```python
import os
import tmpfile
import shutil

...

def make_cat_args(pages, page_index):
    cat_args = []
    for i in page_index:
        if i <= pages:
            cat_args.append('A' + str(i))
        else:
            cat_args.append('B1')
    return cat_args


def rearrange_pdf(src, dst):
    tmp_path = tempfile.mkdtemp()
    blank_path = os.path.join(tmp_path, 'blank.pdf')
    print(blank_path)

    info = get_pdfinfo(src)
    create_blank_page(blank_path, info.width, info.height)
    page_index = new_page_index(info.pages)
    cat_args = make_cat_args(info.pages, page_index)

    arg1 = f'A={src}'
    arg2 = f'B={blank_path}'
    subprocess.run(['pdftk', arg1, arg2, 'cat'] + cat_args + ['output', dst])

    shutil.rmtree(tmp_path)
```

例えば、`rearrange_pdf('input.pdf', 'output.pdf')`のように用いる。

```python
if __name__ == '__main__':
    rearrange_pdf('input.pdf', 'output.pdf')
```


## 方法2：Python + PyPDF4の利用

実は、以前Python + [PyPDF2](https://github.com/mstamy2/PyPDF2)という組み合わせで、目的のプログラムを書いたことがある。PDFの並び替えも、空白ページを作成する関数もあるので、今回やりたいことはこれだけで事足りる。

調べてみるとそのforkである[PyPDF4](https://github.com/claird/PyPDF4)があるらしいので、今回はこちらを使ってみる。Web上にドキュメントが見つからないので、`pydoc PyPDF4`コマンドで読むのが良さそう。また、PyPDF2と基本的なインターフェースは変わっていないと予想されるので、[PyPDF2のドキュメント](https://pythonhosted.org/PyPDF2/)も一部参考になるだろう。

### 実装

方法1と比べると驚くほどシンプルに書ける。

- `PdfFileReader`でPDF読み込み、`PdfFileWriter`で書き込みを担う。
- `PdfFileReader`クラスの`getNumPages`メソッドでページ数を取得する。`getPage`メソッドでページを取得する。
- `PdfFileWriter`クラスの`addBlankPage`メソッドで空白ページを追加する(ページサイズを引数に指定しなかった場合、1つ前のページサイズと同じになる)。`addPage`でページを追加する。`write`メソッドで書き出しをする。

`getPage`メソッドに指定するページ番号は0-indexedなので、`new_page_index`の実装が方法1と少し異なっていることに注意。

```python
import PyPDF4

def new_page_index(pages):
    page_index = []
    new_pages = (pages + 3) // 4 * 4
    for i in range(0, new_pages):
        if i % 4 == 0:
            page_index.append(i + 3)
        else:
            page_index.append(i - 1)
    return page_index


def rearrange_pdf(src, dst):
    pdf_src = PyPDF4.PdfFileReader(src)
    num_pages = pdf_src.getNumPages()
    page_index = new_page_index(num_pages)

    pdf_dst = PyPDF4.PdfFileWriter()
    for i in page_index:
        if i < num_pages:
            pdf_dst.addPage(pdf_src.getPage(i))
        else:
            pdf_dst.addBlankPage()

    with open(dst, mode='wb') as f:
        pdf_dst.write(f)
```
