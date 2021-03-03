---
title: "Socket通信の勉強(1) - ディスクリプタ/TCPによる通信"
date: 2019-11-24T17:08:19+09:00
tags: ["TCP", "C", "C++", "Socket"]
categories: ["C", "C++", "Network"]
---

Socket通信を勉強する。

## 前提

- プログラムはMac(Mojave)で動かす。
- ネットワークに関する知識はほんの少しある。
- 使うプログラミング言語はC++だが、ここではbetter Cの意味でしか用いない。

## (寄り道) ファイル入出力

Socket通信を学んでいると、ファイルディスクリプタが出てきたので、まずはそこから勉強する。

関数定義については[JM Project](https://linuxjm.osdn.jp/index.html)から引用したものを用いる。これはLinuxマニュアルと同じらしいので、恐らくmanコマンドで出力されるものと同じである(ただし英語であるが)。

### ファイルディスクリプタとは

ファイルディスクリプタとは、ファイルと結びつけられた単なる整数値である。データの読み書きを行う場合は、この整数値を指定してアクセスする。例えばファイル`test.txt`のファイルディスクリプタが4だった場合、読み書きをする関数read/writeには引数4を指定する。

個人的には、ファイルとプロセスのやりとりはあるケーブルを介して行なっているイメージがある。例えば番号4の端子にはすでに`test.txt`が繋がっているとしよう。このとき、プロセスが`text.txt`にアクセスしたいなら、番号4の端子にアクセスすれば良い。

{{< figure src="fd01.svg" >}}

### ファイルの読み込み

ファイルディスクリプタを用いてファイルを読み込む例を以下に示す。以下は、`test.txt`を読み込んで、そのファイルディスクリプタとファイルの内容を出力するプログラムである。

{{< highlight cpp >}}
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

int main() {
  int fd = open("test.txt", O_RDONLY);
  char buf[64];

  read(fd, buf, sizeof(buf));
  printf("fd: %d\n", fd);
  printf("%s\n", buf);
  close(fd);

  return 0;
}
{{< /highlight >}}

`test.txt`の内容は以下のようにする。

{{< highlight txt >}}
Hello, World
{{< /highlight >}}

実行すると、以下のように出力される。`fd`の値は実行環境によって異なる。

{{< highlight txt >}}
fd: 3
Hello, World

{{< /highlight >}}

以下説明するopen/read/closeは関数ではなく、全てシステムコールである。

### openでファイルを開く

開きたいファイルのパスと、読み書きの方法を引数に指定する。成功するとファイルディスクリプタを返す。

{{< highlight cpp >}}
#include <fcntl.h>

int open(const char *pathname, int flags);
{{< /highlight >}}

### readで読み込む

ファイルディスクリプタと、読み取った値を保持しておくためのバッファ、また読み取るデータの長さを指定する。

{{< highlight cpp >}}
#include <unistd.h>

ssize_t read(int fd, void *buf, size_t count);
{{< /highlight >}}

### closeでディスクリプタを解放する

openで結びつけられたファイルディスクリプタはcloseで解放しなければならないことに注意。低級寄りの処理なだけあって、自動では解放してくれない。

### 注意

今回はファイルディスクリプタを直接取得してファイルの読み取りを行なったが、普通は代わりに`FILE`構造体を用いてやりとりをすることに注意。その際、`open`ではなく`fopen`を使うなどの異なる点がある。

## ソケット通信の考え方

前項ではファイルとプロセスの通信を、ファイルディスクリプタを介して行なった。ソケット通信もほとんど同じである。異なるプロセス間で通信を行うため、データやりとりの前段階でやることが結構ある。しかしデータのやりとりの際にディスクリプタを用いる点は同じである。

結局、ソケットとは通信用の特別な「ファイル」のようなもの。「通信用」なだけであって、ファイル同様ディスクリプタを介してデータをやりとりする。

### 通信方式

ソケット通信では、いくつかの通信方式が選べる。今回はTCP/IPプロトコルに沿って話を進めていく

### サーバーとクライアント

TCP通信には必ず「サーバー」と「クライアント」が存在する。

- サーバー: その名の通り何かを「与える」役割を担う。クライアントが何か要求してきたら、それに対して適切な返答をする。
- クライアント: その名の通り何かを「依頼する」役割を担う。サーバーに何かを要求して、サーバーからの返答を受ける。

ソケット通信においても同じようにサーバーとクライアントが存在するが、通信は双方向にやりとりできるため、必ず上の定義に当てはまるとは限らない。例えば「サーバーとクライアントでチャットするプログラム」は作成可能であるが、上の定義に反する。

例えば「大人数でチャットするプログラム」を作りたい場合、例えば1つのサーバーに大人数が接続して、サーバを介してデータをやりとりする方法が考えられる。このような仕組みはマルチクライアントと呼ばれる。

### 通信の手順(粗)

いきなりマルチクライアント通信を考えるのは大変なので(というよりも僕がまだそのやり方を知らないので)、とりあえずサーバーとクライアントが1対1で通信する状況を考える。その場合、大雑把には以下の流れで通信が行われる。ハイフンの後に書かれている単語は、手順に対応するCの関数(またはシステムコール)である。

1. **サーバー**: クライアントの通信が来るのを待つ - listen
2. **クライアント**: サーバーに接続する - connect
3. **サーバー**: 接続を受け入れる - accept
4. **両方**: データのやりとりを行う - read/writeもしくはsend/recv

上に示した手順だとまだ情報が足りない。例えば、「サーバーが受け入れ状態になるときとはどんな状態か」「クライアントがどのサーバーに接続するのかを記した宛先はどうするのか」「データのやりとりはどう行うのか」など。

### 通信の手順(細)

全体像を上で掴んだところで、少し細かい手順を記す。

サーバーは以下の手順を踏む。

1. listen(待ち受け)用のソケット作成 - socket
2. 「どこからの接続を待つのか」「どのポートにて待ち受けするのか」を決める - sockaddr_in構造体
3. ソケットにその情報を紐つける - bind
4. 実際に待ち受けする - listen
5. 接続要求が来たら受け入れる - accept
6. 4によって通信用のソケットが得られるので、それを用いてデータのやりとりをする- read/write

ここで、1で作ったソケットと4で作ったソケットは異なることに注意。

クライアントは以下の手順を踏む。
 
1. サーバーとの通信用のソケット作成 - socket
2. サーバが待ち受けている宛先を設定 - sockaddr_in構造体
3. 2で設定した宛先に対して接続する - connect
4. 1で作ったソケットを用いてデータのやりとりをする。 - read/write

どんなプロトコルを使って通信するかは、socket関数の引数およびsockaddr_inのメンバとして設定する。

## 実際に書いてみる

`server.cpp`と`client.cpp`を用意する。

### server.cpp

{{< highlight cpp >}}
#include <iostream>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
  // 1.
  int sock_listen = socket(AF_INET, SOCK_STREAM, 0);

  // 2.
  struct sockaddr_in server_addr = {0};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
  server_addr.sin_port = htons(8000);

  // 3.
  bind(sock_listen, (struct sockaddr*)&server_addr, sizeof(server_addr));

  // 4.
  listen(sock_listen, 5);

  struct sockaddr_in client_addr;
  socklen_t len = sizeof(struct sockaddr_in);
  // 5.
  int sock = accept(sock_listen, (struct sockaddr*)&client_addr, &len);
  printf("accepted.\n");

  // 6.
  char msg[] = "Hello, World";
  write(sock, msg, sizeof(msg));

  close(sock);
  close(sock_listen);

  return 0;
}
{{< /highlight >}}

### client.cpp

{{< highlight cpp >}}
#include <iostream>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
  // 1.
  int sock = socket(AF_INET, SOCK_STREAM, 0);

  // 2.
  struct sockaddr_in server_addr = {0};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
  server_addr.sin_port = htons(8000);

  // 3.
  connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr));

  // 4.
  char buf[64];
  read(sock, buf, sizeof(buf));
  printf("%s\n", buf);

  close(sock);
  return 0;
}
{{< /highlight >}}

### 実行

とりあえずコンパイルする。

{{< highlight txt >}}
$ gcc server.c -o server
$ gcc client.c -o client
{{< /highlight >}}

先にserverを起動しておき、その後clientを起動する。すると、clientにて`Hello, World`が出力される。

連続でプログラムを実行すると、何も反応せず終了することがる。きちんとエラー処理をしていないので、なぜこうなっているのかが分からない。後でエラー処理をちゃんとつけることにする。

### server.cppの説明

#### socket

ソケットを作成する。

- `AF_INET`: 通信を行うドメインをIPv4に設定する
- `SOCK_STREAM`: 信頼性のある双方向通信を行う設定。恐らくTCP通信のことをここで設定しているのだと思う。
- 第3引数: とりあえず0でいいっぽい。複数プロトコルに対応させる場合はここをいじるっぽい？

{{< highlight cpp >}}
  // 1.
  int sock_listen = socket(AF_INET, SOCK_STREAM, 0);
{{< /highlight >}}

#### sockaddr_in構造体

クライアントから通信を受け入れるためのアドレス、ポートの設定をする。`sockaddr_in`構造体はIPv4のための構造体らしい。

- `server_addr = {0}`: これはC言語の文法で、0初期化できる。`memset`を使っても良い。
- `sin_family = AF_INET`: これで通信方法がIPv4に設定される
- `sin_addr.s_addr = htonl(INADDR_ANY)`: これで「どんなクライアントからも通信を受け付ける」ようになる。
- `sin_port = htons(8000)`: ポートを設定する。`htons`は整数値の表現方法を変える関数。PCによって値の表現方法が異なるのを解決するための手段。

{{< highlight cpp >}}
  // 2.
  struct sockaddr_in server_addr = {0};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
  server_addr.sin_port = htons(8000);
{{< /highlight >}}

#### bind

ソケットにアドレス、ポートの情報を結びつける。

- `sock_listen`: 結びつけるソケット。
- `(struct sockaddr*)&server_addr`: 結びつけるアドレス
- `sizeof(server_addr)`: `server_addr`のサイズ。`sizeof(struct sockaddr_in)`と同義。

{{< highlight cpp >}}
  // 3.
  bind(sock_listen, (struct sockaddr*)&server_addr, sizeof(server_addr));
{{< /highlight >}}

#### listen

待ち受けを開始する

- `sock_listen`: 待ち受けするためのソケット
- `5`: これは複数クライアントからの接続に対応するものらしい。

{{< highlight cpp >}}
  // 4.
  listen(sock_listen, 5);
{{< /highlight >}}

#### accept

クライアントからの要求を受け入れ、通信を確立する

追記(2019/12/8): 受け入れが来るまで待つ処理はここで行なっている。

- `sock_listen`: 待ち受けしていたソケット
- `(struct sockaddr*)&client_addr`: このようにしてクライアントのアドレス諸々の情報を取得できる。使用しない場合は`NULL`を指定する。
- `&len`: `client_addr`のサイズがここに格納されてくる。

{{< highlight cpp >}}
  // 5.
  int sock = accept(sock_listen, (struct sockaddr*)&client_addr, &len);
  printf("accepted.\n");
{{< /highlight >}}

#### write

ここではメッセージを送るために利用している。

- `sock`: 通信用のソケット
- `msg`: 書き出すメッセージ
- `sizeof(msg)`: メッセージのサイズ

{{< highlight cpp >}}
  // 6.
  char msg[] = "Hello, World";
  write(sock, msg, sizeof(msg));
{{< /highlight >}}

#### close

作ったソケットは`close`を用いて破棄しなければならない。

{{< highlight cpp >}}
  close(sock);
  close(sock_listen);
{{< /highlight >}}

### client.cppの説明


#### sockaddr_in構造体

接続先のサーバーのアドレスとポートを指定する。

- `server_addr.sin_addr.s_addr = inet_addr("127.0.0.1")`: 今回はローカルホスト(自身のPC)と接続するため、`127.0.0.1`をIPアドレスとしている。

{{< highlight cpp >}}
  struct sockaddr_in server_addr = {0};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
  server_addr.sin_port = htons(8000);
{{< /highlight >}}

#### connect

サーバーに接続する

- `sock`: 通信を行うためのソケット。
- `(struct sockaddr *)&server_addr`: サーバーのアドレス。
- `sizeof(server_addr)`: `server_addr`のサイズ。`sizeof(sturct sockaddr_in)`と同義

{{< highlight cpp >}}
  connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr));
{{< /highlight >}}

#### read

ここでは、サーバーからのメッセージを受信する意味で用いる。

{{< highlight cpp >}}
  char buf[64];
  read(sock, buf, sizeof(buf));
{{< /highlight >}}

`read`は返り値として「実際に受け取ったデータのバイト数」を返す。`buf`一杯にデータを受け取っているとは限らないことに注意。


## エラーをつける

今回出てきたすべての関数/システムコールは、失敗すると-1を返す。

`perror`は、何かしらの失敗のメッセージのうち最新のものを出力する関数。`perror("name")`で、`name: エラーメッセージ`と出力される。

### server.cppの内容

{{< highlight cpp >}}
#include <iostream>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {
  int sock_listen = socket(AF_INET, SOCK_STREAM, 0);
  if (sock_listen < 0) {
    perror("socket");
    exit(1);
  }

  struct sockaddr_in server_addr = {0};
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = htonl(INADDR_ANY);
  server_addr.sin_port = htons(8000);

  if (bind(sock_listen, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
    perror("bind");
    exit(1);
  }

  if (listen(sock_listen, 5) < 0) {
    perror("listen");
    exit(1);
  }

  struct sockaddr_in client_addr;
  socklen_t len = sizeof(struct sockaddr_in);
  int sock = accept(sock_listen, (struct sockaddr*)&client_addr, &len);
  if (sock < 0) {
    perror("accept");
    exit(1);
  }

  char msg[] = "Hello, World";
  if (write(sock, msg, sizeof(msg)) < 0) {
    perror("write");
    exit(1);
  }

  close(sock);
  close(sock_listen);

  return 0;
}
{{< /highlight >}}

### client.cppの内容

{{< highlight cpp >}}
#include <iostream>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>

int main() {

  // 1.
  struct sockaddr_in server_addr;
  server_addr.sin_family = AF_INET;
  server_addr.sin_addr.s_addr = inet_addr("127.0.0.1");
  server_addr.sin_port = htons(8000);

  // 2.
  int sock = socket(AF_INET, SOCK_STREAM, 0);
  if (sock < 0) {
    perror("socket");
    exit(1);
  }

  // 3.
  if (connect(sock, (struct sockaddr *)&server_addr, sizeof(server_addr)) < 0) {
    perror("connect");
    exit(1);
  }

  // 4.
  char buf[64];
  if (read(sock, buf, sizeof(buf)) < 0) {
    perror("read");
    exit(1);
  }
  printf("%s\n", buf);

  close(sock);
  return 0;
}
{{< /highlight >}}

## ソケットが閉じられていない

あまり間隔を空けずに`server`を起動しようとすると、以下のメッセージが出力されサーバーが起動しない。

{{< highlight txt >}}
bind: Address already in use
{{< /highlight >}}

理由はTCPプロトコルの仕様による。TCPプロトコルは接続終了後、そのソケットをTIME_WAIT状態にする。このため、ソケットは接続終了後しばらく使えない。TIME_WAITにする理由は、遅れて来たパケットのためらしい。TCPは「信頼性のある通信」だから、このような工夫がされているのだろう。

### SO_REUSEADDR

TIME_WAIT状態でもソケットを利用するための方法がある。`setsockopt`関数でソケットの設定を変更すれば良い。`SO_REUSEADDR`というオプションを1に設定する。

- `sock_listen`: 変更対象のソケット。
- `SOK_SOCKET`: これを指定するとソケットレベルのオプションを指定するらしい。他のプロトコルについての設定も可能らしい。
- `SO_REUSEADDR`: 変更したいオプション。
- `&optval`: オプションの値。オプションの値の型は、変更するオプションによって異なる。そこでこの引数は`(const void*)`型(汎用ポインタと呼ばれているもの)となっている。ただし実装によって個々の型は違うようで、[Linuxマニュアル](https://linuxjm.osdn.jp/html/LDP_man-pages/man2/getsockopt.2.html)では`(const void*)`だが、[IBM](https://www.ibm.com/support/knowledgecenter/ja/SSLTBW_2.3.0/com.ibm.zos.v2r3.hala001/setopt.htm)では`char *`、[Microsoft](https://docs.microsoft.com/en-us/windows/win32/api/winsock/nf-winsock-setsockopt)では`(const char*)`だったりする。[こちらのページを参考に](https://teratail.com/questions/194720)定義を調べたら`(const void*)`だった。
- `sizeof(optval)`: `optval`が汎用ポインタとして定義されているからだろうか、ここにそのサイズを指定しなければならない。

{{< highlight cpp >}}
// これより上でソケットを定義しておく
int optval = 1;
setsockopt(sock_listen, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
// これより下でbind関数を呼び出す。
{{< /highlight >}}

setsockoptはエラーを出すと-1を返すので、エラー処理をちゃんと書こうとすると次のようになる。
{{< highlight cpp >}}
// これより上でソケットを定義しておく
int optval = 1;
if (setsockopt(sock_listen, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)) < 0) {
  perror("setsockopt");
  exit(1);
}
// これより下でbind関数を呼び出す。
{{< /highlight >}}

## ブロッキング

実はサーバー側がwriteするまで、クライアントはreadを待ってくれる。このような仕組みをブロッキングという。いわゆる同期通信である。

例えば、次のように`server`で、`write`の前に5秒待つとしよう。

{{< highlight cpp >}}
  printf("Wait for 5 seconds.\n");
  sleep(5);
  char msg[] = "Hello, World";
  if (write(sock, msg, sizeof(msg)) < 0) {
    perror("write");
    exit(1);
  }
{{< /highlight >}}

すると、`client`と通信が確立した後、`server`は`Hello, World`を送る前に5秒間待機する。この時、`client`はそれを待ってくれる。

`ioctl`関数を用いるとノンブロッキングにすることができるらしいが、詳しい話は割愛。

## recv/send

`read/write`を用いる代わりに、`recv/send`を用いる、という選択肢がある。これはソケットのために作られた関数だ。

`server`の`write`に関するコードは以下のように置き換えられる。
{{< highlight cpp >}}
  char msg[] = "Hello, World";
  if (write(sock, msg, sizeof(msg), 0) < 0) {
    perror("write");
    exit(1);
  }
{{< /highlight >}}

`client`の`read`に関するコードは以下のように置き換えられる
{{< highlight cpp>}}
  char buf[64];
  if (recv(sock, buf, sizeof(buf), 0) < 0) {
    perror("read");
    exit(1);
  }
{{< /highlight >}}

第4引数に0が加わっただけのように見える。第4引数には通信に関するオプションが指定できる。何もなければ0を指定し、この場合は`read/write`関数と全く同じ動作をする。

今回はここまで。
