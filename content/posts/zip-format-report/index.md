---
title: "zipファイルの構造を少しだけ理解する"
date: 2020-03-04T13:50:16+09:00
tags: ["zip"]
categories: ["zip", "unix", "linux"]
---

Unix系のコマンド(od、grep)だけを使って、zipファイルの中身をのぞく。

## zip形式の参考サイト

zipの仕様書は[ZIP File Format Specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)で確認できる。ページ内検索をかけながら必要なところをつまんでいく、という読み方が良さそう。

日本語なら<a href="https://ja.wikipedia.org/wiki/ZIP_(%E3%83%95%E3%82%A1%E3%82%A4%E3%83%AB%E3%83%95%E3%82%A9%E3%83%BC%E3%83%9E%E3%83%83%E3%83%88)#%E6%8A%80%E8%A1%93%E7%9A%84%E3%81%AA%E6%83%85%E5%A0%B1">Wikipedia</a>がある。こちらは図が書かれているし日本語なので分かりやすい。


## zipファイルの用意

まずはzipファイルを用意する。

`foo.txt`と`bar.txt`を用意する。

{{< cui >}}
$ echo "Hello, World." > foo.txt
$ echo "Good Bye." > bar.txt
{{< /cui >}}

これらをzipコマンドでまとめる。

{{< cui >}}
$ zip tmp.zip foo.txt bar.txt
{{< /cui >}}

## バイナリ形式で出力

zipファイルはテキストとして表示できるものではなく、バイナリとして表示しないとあまり意味を掴めない。バイナリ表示ができるテキストエディタを使ってもよいが、ここでは`od`コマンドを用いる。

{{< cui >}}
$ od -Ax -tx1z tmp.zip
{{< /cui >}}

引数の意味は以下の通り。`man od`でも確認できる。

- `-A`: アドレスの基数(**A**ddress-radix)。出力時、最も左の値がファイル先頭から何バイト目なのかを表示する。続けて`x`と書くと、16進数(he**x**)で出力する。
- `-t`: データの出力形式(おそらく**t**ypeの略)。
   - 続けて`x1`と書くと、1バイト区切りの16進数で出力する。
   - 続けて`z`と書くと、右側にテキストでの表示を添える。ただし表示されるのはASCIIコードで認識される文字のみ。


結果は以下のようになる。

{{< cui >}}
000000 50 4b 03 04 0a 00 00 00 00 00 28 70 64 50 4b 82  >PK........(pdPK.<
000010 70 33 0e 00 00 00 0e 00 00 00 07 00 1c 00 66 6f  >p3............fo<
000020 6f 2e 74 78 74 55 54 09 00 03 1b 36 5f 5e 1b 36  >o.txtUT....6_^.6<
000030 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00  >_^ux............<
000040 00 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 2e 0a 50  >.Hello, World..P<
000050 4b 03 04 0a 00 00 00 00 00 2b 70 64 50 cb e8 62  >K........+pdP..b<
000060 fc 0a 00 00 00 0a 00 00 00 07 00 1c 00 62 61 72  >.............bar<
000070 2e 74 78 74 55 54 09 00 03 21 36 5f 5e 21 36 5f  >.txtUT...!6_^!6_<
000080 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00  >^ux.............<
000090 47 6f 6f 64 20 42 79 65 2e 0a 50 4b 01 02 1e 03  >Good Bye..PK....<
0000a0 0a 00 00 00 00 00 28 70 64 50 4b 82 70 33 0e 00  >......(pdPK.p3..<
0000b0 00 00 0e 00 00 00 07 00 18 00 00 00 00 00 01 00  >................<
0000c0 00 00 a4 81 00 00 00 00 66 6f 6f 2e 74 78 74 55  >........foo.txtU<
0000d0 54 05 00 03 1b 36 5f 5e 75 78 0b 00 01 04 e8 03  >T....6_^ux......<
0000e0 00 00 04 e8 03 00 00 50 4b 01 02 1e 03 0a 00 00  >.......PK.......<
0000f0 00 00 00 2b 70 64 50 cb e8 62 fc 0a 00 00 00 0a  >...+pdP..b......<
000100 00 00 00 07 00 18 00 00 00 00 00 01 00 00 00 a4  >................<
000110 81 4f 00 00 00 62 61 72 2e 74 78 74 55 54 05 00  >.O...bar.txtUT..<
000120 03 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04  >.!6_^ux.........<
000130 e8 03 00 00 50 4b 05 06 00 00 00 00 02 00 02 00  >....PK..........<
000140 9a 00 00 00 9a 00 00 00 00 00                    >..........<
00014a
{{< /cui >}}

## シグネチャ

zipファイルは以下のような要素を持つ。

- local file header + file data : ファイルの補足情報 + ファイルの中身
- central directory header : 恐らくファイルの索引みたいなもの。zipファイルを解凍することなく、どんなファイルが入っているのかを確認したい場合に用いるのだと思う
- end of central directory : zipファイルの終端を表す情報

これらは次の順番で並んでいる(本当はdata descriptorというのもあるが今回は省略する)。


```txt
[local file header + file data]
[local file header + file data]
...
[local file header + file data]
[central directory header]
[central directory header]
...
[central directory header]
[end of central directory]
```

各ヘッダおよびend of central directoryは、固有の4バイト列(シグネチャ)から始める。zip解凍ソフトは、シグネチャから各要素を認識する。シグネチャは以下の通り。

- local file header: `0x504B0304`
- central directory header: `0x504B0102`
- end of central directory: `0x504B0506`

### シグネチャをハイライトする

上のシグネチャは3つとも`504B`で始まっている。これを用いて、バイナリからシグネチャを検索してみる。

文字列検索をかけたいときは`grep`コマンド。

{{< cui >}}
grep "50 4b"
{{< /cui >}}

しかし上のようにやると該当する行しか表示してもらえない。ちょっとした小技だが、「`50 4b`または行末`$`で検索をかける」ようにすると、すべての行が出力される。行末は文字ではないので、ハイライトされることはない。

{{< cui >}}
grep "50 4b\|$"
{{< /cui >}}

拡張正規表現を用いると、パイプのエスケープをしないで済む。

{{< cui >}}
grep -E "50 4b|$"
{{< /cui >}}

では早速、`od`と組み合わせる。

{{< cui >}}
$ od -Ax -tx1z tmp.zip | grep -E "50 4b|$"
{{< /cui >}}

次のようにハイライトされる。

{{< cui >}}
000000 <span class="orangered">50 4b</span> 03 04 0a 00 00 00 00 00 28 70 64 <span class="orangered">50 4b</span> 82  >PK........(pdPK.<
000010 70 33 0e 00 00 00 0e 00 00 00 07 00 1c 00 66 6f  >p3............fo<
000020 6f 2e 74 78 74 55 54 09 00 03 1b 36 5f 5e 1b 36  >o.txtUT....6_^.6<
000030 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00  >_^ux............<
000040 00 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 2e 0a 50  >.Hello, World..P<
0000<span class="orangered">50 4b</span> 03 04 0a 00 00 00 00 00 2b 70 64 50 cb e8 62  >K........+pdP..b<
000060 fc 0a 00 00 00 0a 00 00 00 07 00 1c 00 62 61 72  >.............bar<
000070 2e 74 78 74 55 54 09 00 03 21 36 5f 5e 21 36 5f  >.txtUT...!6_^!6_<
000080 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00  >^ux.............<
000090 47 6f 6f 64 20 42 79 65 2e 0a <span class="orangered">50 4b</span> 01 02 1e 03  >Good Bye..PK....<
0000a0 0a 00 00 00 00 00 28 70 64 <span class="orangered">50 4b</span> 82 70 33 0e 00  >......(pdPK.p3..<
0000b0 00 00 0e 00 00 00 07 00 18 00 00 00 00 00 01 00  >................<
0000c0 00 00 a4 81 00 00 00 00 66 6f 6f 2e 74 78 74 55  >........foo.txtU<
0000d0 54 05 00 03 1b 36 5f 5e 75 78 0b 00 01 04 e8 03  >T....6_^ux......<
0000e0 00 00 04 e8 03 00 00 <span class="orangered">50 4b</span> 01 02 1e 03 0a 00 00  >.......PK.......<
0000f0 00 00 00 2b 70 64 50 cb e8 62 fc 0a 00 00 00 0a  >...+pdP..b......<
000100 00 00 00 07 00 18 00 00 00 00 00 01 00 00 00 a4  >................<
000110 81 4f 00 00 00 62 61 72 2e 74 78 74 55 54 05 00  >.O...bar.txtUT..<
000120 03 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04  >.!6_^ux.........<
000130 e8 03 00 00 <span class="orangered">50 4b</span> 05 06 00 00 00 00 02 00 02 00  >....PK..........<
000140 9a 00 00 00 9a 00 00 00 00 00                    >..........<
00014a
{{< /cui >}}

余計なところまで検索がひっかかっていたり、行をまたがってしまって検索がひっかからなかったりしている部分があるので、そこは自力で確認する。するとシグネチャは以下の部分だとわかる。


{{< cui >}}
000000 <span class="orangered">50 4b 03 04</span> 0a 00 00 00 00 00 28 70 64 50 4b 82  >PK........(pdPK.<
000010 70 33 0e 00 00 00 0e 00 00 00 07 00 1c 00 66 6f  >p3............fo<
000020 6f 2e 74 78 74 55 54 09 00 03 1b 36 5f 5e 1b 36  >o.txtUT....6_^.6<
000030 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00  >_^ux............<
000040 00 48 65 6c 6c 6f 2c 20 57 6f 72 6c 64 2e 0a <span class="orangered">50</span>  >.Hello, World..P<
000050 <span class="orangered">4b 03 04</span> 0a 00 00 00 00 00 2b 70 64 50 cb e8 62  >K........+pdP..b<
000060 fc 0a 00 00 00 0a 00 00 00 07 00 1c 00 62 61 72  >.............bar<
000070 2e 74 78 74 55 54 09 00 03 21 36 5f 5e 21 36 5f  >.txtUT...!6_^!6_<
000080 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00  >^ux.............<
000090 47 6f 6f 64 20 42 79 65 2e 0a <span class="orangered">50 4b 01 02</span> 1e 03  >Good Bye..PK....<
0000a0 0a 00 00 00 00 00 28 70 64 50 4b 82 70 33 0e 00  >......(pdPK.p3..<
0000b0 00 00 0e 00 00 00 07 00 18 00 00 00 00 00 01 00  >................<
0000c0 00 00 a4 81 00 00 00 00 66 6f 6f 2e 74 78 74 55  >........foo.txtU<
0000d0 54 05 00 03 1b 36 5f 5e 75 78 0b 00 01 04 e8 03  >T....6_^ux......<
0000e0 00 00 04 e8 03 00 00 <span class="orangered">50 4b 01 02</span> 1e 03 0a 00 00  >.......PK.......<
0000f0 00 00 00 2b 70 64 50 cb e8 62 fc 0a 00 00 00 0a  >...+pdP..b......<
000100 00 00 00 07 00 18 00 00 00 00 00 01 00 00 00 a4  >................<
000110 81 4f 00 00 00 62 61 72 2e 74 78 74 55 54 05 00  >.O...bar.txtUT..<
000120 03 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04  >.!6_^ux.........<
000130 e8 03 00 00 <span class="orangered">50 4b 05 06</span> 00 00 00 00 02 00 02 00  >....PK..........<
000140 9a 00 00 00 9a 00 00 00 00 00                    >..........<
00014a
{{< /cui >}}

local file headerとcentral directory headerが2個ずつ、end of central directoryが1個確認できる。

## end of central directoryの確認

`50 4b 05 06`以降のバイナリだけ表示することを考える。`od`コマンドの出力結果は、以下のようにとらえるとよい。

{{< cui >}}
       +0 +1 +2 +3 +4 +5 +6 +7 +8 +9 +a +b +c +d +e +f
------------------------------------------------------
000130 e8 03 00 00 <span class="orangered">50 4b 05 06</span> 00 00 00 00 02 00 02 00
{{< /cui >}}

左`00130`で、上が`+4`の位置だから、「赤色の`50`の位置はファイル開始から`00130+4 = 00134`バイト目だ」と読める。ただし、ここでは`00134`は16進数である。

`od`コマンドで`-j[x] -N[y]`を指定すると、「`x`バイト目にジャンプ(**j**ump)して`y`バイト数(**N**umber)分だけ表示する」という処理が行える。なので、end of central directory以降のバイナリだけ表示したい場合は、以下のコマンドを実行すればよい。

{{< cui >}}
$ od -Ax -tx1z -j0x134 tmp.zip | grep -E "50 4b 05 06|$"
000134 <span class="orangered">50 4b 05 06</span> 00 00 00 00 02 00 02 00 9a 00 00 00  >PK..............<
000144 9a 00 00 00 00 00                                >......<
00014a
{{< /cui >}}

これらは次のような意味を持っている(説明はspecificationからの抜粋)。値はリトルエンディアンであることに注意。

```txt
50 4b 05 06 : end of central dir signature
00 00 : number of this disk 
00 00 : start of the central directory
02 00 :  total number of the disk with the start of the central directory
02 00 : total number of entries in the central directory
9a 00 00 00 : size of the central directory
9a 00 00 00 : offset of start of central directory with respect to the starting disk number 
00 00 : .ZIP file comment length 
```

ディスクって何のこと？調べてみたところ、恐らくzipファイルを分割するときに扱われる情報([specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)の「8.0  Splitting and Spanning ZIP files」参照)。zipファイルを分割して複数のフロッピーに保存する、みたいに使っていた名残りみたい。現代ではあまり使われない？ディスクというと円盤をイメージしてしまうが、物理的な円盤のことを指している分けではなさそう。ディスク=分割されたファイル、という理解で良いのだろうか。ちなみに、`zip`コマンドでファイル分割を行う場合は`-s`オプションを利用する。詳しくは`man  zip`を参照。

## central directoryの確認

end of central directoryによると、central directoryは`0x0000009a`バイト目から始まって`0x0000009a`バイト分あるらしい。試しに確認してみる。

{{< cui >}}
$ od -Ax -tx1z -j0x9a -N0x9a tmp.zip | grep -E "50 4b|$"
00009a <span class="orangered">50 4b</span> 01 02 1e 03 0a 00 00 00 00 00 28 70 64 50  >PK..........(pdP<
0000aa 4b 82 70 33 0e 00 00 00 0e 00 00 00 07 00 18 00  >K.p3............<
0000ba 00 00 00 00 01 00 00 00 a4 81 00 00 00 00 66 6f  >..............fo<
0000ca 6f 2e 74 78 74 55 54 05 00 03 1b 36 5f 5e 75 78  >o.txtUT....6_^ux<
0000da 0b 00 01 04 e8 03 00 00 04 e8 03 00 00 <span class="orangered">50 4b</span> 01  >.............PK.<
0000ea 02 1e 03 0a 00 00 00 00 00 2b 70 64 50 cb e8 62  >.........+pdP..b<
0000fa fc 0a 00 00 00 0a 00 00 00 07 00 18 00 00 00 00  >................<
00010a 00 01 00 00 00 a4 81 4f 00 00 00 62 61 72 2e 74  >.......O...bar.t<
00011a 78 74 55 54 05 00 03 21 36 5f 5e 75 78 0b 00 01  >xtUT...!6_^ux...<
00012a 04 e8 03 00 00 04 e8 03 00 00                    >..........<
000134
{{< /cui >}}

`50 4b 01 02`の列が2箇所見つかる。これがcentral directory headerのようだ。`foo.txt`や`bar.txt`の文字列が見つかることから、どうやらここにファイル名の情報が埋め込まれているらしいとわかる。

2つ目の`50 4b 01 02`以降の列に注目する。

```txt
50 4b 01 02 : central file header signature
1e 03 : version made by
0a 00 : version needed to extract
00 00 : general purpose bit flug
00 00 : compression method
2b 70 : last mod file time
64 50 : last mod file date 
cb e8 62 fc : crc32
0a 00 00 00 : compressed size
0a 00 00 00 : uncompressed size
07 00 : file name length
18 00 : extra field length
00 00 : file comment length
00 00 : disk number start
01 00 : internal file attribute
00 00 a4 81 : external file attribute
4f 00 00 00 : relative offset of local header
62 61 72 2e 74 78 74 : file name
55 54 05 00 03 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00 : extra field
```

要素数が多い上にまだ理解しきれていない部分もあるので、一部だけ確認する。

`62 61 72 2e 74 78 74`はASCIIコードで`bar.txt`だから、ちゃんとファイル名になっていることが分かる。ファイル名の長さも`0x0007`バイトである。

`version needed to extract`とは圧縮方式を指定するところで、これはspecificationの「4.4.3 version needed to extract」に詳細が載っている。`0x000a = 10`とはVersion1.0のことのようで、これは無圧縮を意味する。実際、`compressed size`と`uncompressed size`が一致していることから、圧縮が行われていないことが分かる。

`crc32`とは、CRC符号のための冗長ビットをここに付加する。CRC符号は誤りの検出によく用いられる。何に対してCRCを計算するのかについてはspecificationにはっきり記載されている箇所が見つからなかったが、おそらくファイル本体に対して計算する。

## local file header + file dataの確認

さてcentral directory headerによると、`bar.txt`のlocal file headerおよび本体は、ファイル先頭から`0x0000004f`バイト目にあるらしい。

{{< cui >}}
$ od -Ax -tx1z -j0x4f tmp.zip | grep -E "50 4b|$"
00004f <span class="orangered">50 4b</span> 03 04 0a 00 00 00 00 00 2b 70 64 50 cb e8  >PK........+pdP..<
00005f 62 fc 0a 00 00 00 0a 00 00 00 07 00 1c 00 62 61  >b.............ba<
00006f 72 2e 74 78 74 55 54 09 00 03 21 36 5f 5e 21 36  >r.txtUT...!6_^!6<
00007f 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00  >_^ux............<
00008f 00 47 6f 6f 64 20 42 79 65 2e 0a <span class="orangered">50 4b</span> 01 02 1e  >.Good Bye..PK...<
00009f 03 0a 00 00 00 00 00 28 70 64 <span class="orangered">50 4b</span> 82 70 33 0e  >.......(pdPK.p3.<
0000af 00 00 00 0e 00 00 00 07 00 18 00 00 00 00 00 01  >................<
0000bf 00 00 00 a4 81 00 00 00 00 66 6f 6f 2e 74 78 74  >.........foo.txt<
0000cf 55 54 05 00 03 1b 36 5f 5e 75 78 0b 00 01 04 e8  >UT....6_^ux.....<
0000df 03 00 00 04 e8 03 00 00 <span class="orangered">50 4b</span> 01 02 1e 03 0a 00  >........PK......<
0000ef 00 00 00 00 2b 70 64 50 cb e8 62 fc 0a 00 00 00  >....+pdP..b.....<
0000ff 0a 00 00 00 07 00 18 00 00 00 00 00 01 00 00 00  >................<
00010f a4 81 4f 00 00 00 62 61 72 2e 74 78 74 55 54 05  >..O...bar.txtUT.<
00011f 00 03 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00  >..!6_^ux........<
00012f 04 e8 03 00 00 <span class="orangered">50 4b</span> 05 06 00 00 00 00 02 00 02  >.....PK.........<
00013f 00 9a 00 00 00 9a 00 00 00 00 00                 >...........<
00014a
{{< /cui >}}

`50 4b 03 04`で始まる列がlocal file headerである。

```txt
50 4b 03 04 : local file header signature
0a 00 : version needed to extract
00 00 : general purpose bit flag
00 00 : compression method
2b 70 : last mod file time
64 50 : last mod file date
cb e8 62 fc : crc-32
0a 00 00 00 : compressed size
0a 00 00 00 : uncompressed size
07 00 : file name length
1c 00 : extra field length
62 61 72 2e 74 78 74 : filename
55 54 09 00 03 21 36 5f 5e 21 36 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00 : extra field
47 6f 6f 64 20 42 79 65 2e 0a : file data
```

central directoryのものと共通する要素があることが確認できる。このようにあえて冗長性を持たせることで、ヘッダの誤り訂正に利用するのだろうか。

`47 6f 6f 64 20 42 79 65 2e 0a`という列はASCIIコードで`Good Bye.\n`である。ファイルデータが埋め込まれていることが分かる。

## (おまけ)ディレクトリの取り扱い

圧縮したい対象にディレクトリを含む場合、zipファイルの中身はどうなるのだろうか。

ディレクトリを含むzipファイルを作ってみる。

{{< cui >}}
$ mkdir hoge
$ echo "Hello, World" > hoge/foo.txt
$ echo "Good bye." > bar.txt
$ zip -r tmp.zip hoge bar.txt
{{< /cui >}}

以下のコマンドで、シグネチャの位置をある程度把握する。

{{< cui >}}
$ od -Ax -tx1z tmp.zip | grep -E "50 4b|$"
{{< /cui >}}

シグネチャを手動でハイライトすると次のようになる。
{{< cui >}}
000000 <span class="orangered">50 4b 03 04</span> 0a 00 00 00 00 00 59 ad 64 50 00 00  >PK........Y.dP..<
000010 00 00 00 00 00 00 00 00 00 00 05 00 1c 00 68 6f  >..............ho<
000020 67 65 2f 55 54 09 00 03 4a a2 5f 5e 62 a2 5f 5e  >ge/UT...J._^b._^<
000030 75 78 0b 00 01 04 e8 03 00 00 04 e8 03 00 00 <span class="orangered">50</span>  >ux.............P<
000040 <span class="orangered">4b 03 04</span> 0a 00 00 00 00 00 59 ad 64 50 90 3a f6  >K........Y.dP.:.<
000050 40 0d 00 00 00 0d 00 00 00 0c 00 1c 00 68 6f 67  >@............hog<
000060 65 2f 66 6f 6f 2e 74 78 74 55 54 09 00 03 4a a2  >e/foo.txtUT...J.<
000070 5f 5e 4a a2 5f 5e 75 78 0b 00 01 04 e8 03 00 00  >_^J._^ux........<
000080 04 e8 03 00 00 48 65 6c 6c 6f 2c 20 57 6f 72 6c  >.....Hello, Worl<
000090 64 0a <span class="orangered">50 4b 03 04</span> 0a 00 00 00 00 00 61 ad 64 50  >d.PK........a.dP<
0000a0 cf c7 a3 3d 0a 00 00 00 0a 00 00 00 07 00 1c 00  >...=............<
0000b0 62 61 72 2e 74 78 74 55 54 09 00 03 55 a2 5f 5e  >bar.txtUT...U._^<
0000c0 55 a2 5f 5e 75 78 0b 00 01 04 e8 03 00 00 04 e8  >U._^ux..........<
0000d0 03 00 00 47 6f 6f 64 20 62 79 65 2e 0a <span class="orangered">50 4b 01</span>  >...Good bye..PK.<
0000e0 <span class="orangered">02</span> 1e 03 0a 00 00 00 00 00 59 ad 64 50 00 00 00  >.........Y.dP...<
0000f0 00 00 00 00 00 00 00 00 00 05 00 18 00 00 00 00  >................<
000100 00 00 00 10 00 ed 41 00 00 00 00 68 6f 67 65 2f  >......A....hoge/<
000110 55 54 05 00 03 4a a2 5f 5e 75 78 0b 00 01 04 e8  >UT...J._^ux.....<
000120 03 00 00 04 e8 03 00 00 <span class="orangered">50 4b 01 02</span> 1e 03 0a 00  >........PK......<
000130 00 00 00 00 59 ad 64 50 90 3a f6 40 0d 00 00 00  >....Y.dP.:.@....<
000140 0d 00 00 00 0c 00 18 00 00 00 00 00 01 00 00 00  >................<
000150 a4 81 3f 00 00 00 68 6f 67 65 2f 66 6f 6f 2e 74  >..?...hoge/foo.t<
000160 78 74 55 54 05 00 03 4a a2 5f 5e 75 78 0b 00 01  >xtUT...J._^ux...<
000170 04 e8 03 00 00 04 e8 03 00 00 <span class="orangered">50 4b 01 02</span> 1e 03  >..........PK....<
000180 0a 00 00 00 00 00 61 ad 64 50 cf c7 a3 3d 0a 00  >......a.dP...=..<
000190 00 00 0a 00 00 00 07 00 18 00 00 00 00 00 01 00  >................<
0001a0 00 00 a4 81 92 00 00 00 62 61 72 2e 74 78 74 55  >........bar.txtU<
0001b0 54 05 00 03 55 a2 5f 5e 75 78 0b 00 01 04 e8 03  >T...U._^ux......<
0001c0 00 00 04 e8 03 00 00 <span class="orangered">50 4b 05 06</span> 00 00 00 00 03  >.......PK.......<
0001d0 00 03 00 ea 00 00 00 dd 00 00 00 00 00           >.............<
0001dd
{{< /cui >}}

1つ目のlocal file headerのfile name部分に注目すると、`hoge`ディレクトリは、あたかも`hoge/`というファイルかのように記録されている。compressed sizeもuncompressed sizeも勿論0。
また、2つ目のlocal file headerのfile name部分に注目すると、`hoge`ディレクトリにある`foo.txt`は、あたかも`hoge/foo.txt`というファイルかのように記録されている。このように、zipファイルではディレクトリの階層構造を平坦にするようだ。


## まとめ

不完全ではあるが、zipファイルの構造を学んだ。

ここまで学ぶと、無圧縮のzipファイルを作るプログラムくらいは書けそう。
