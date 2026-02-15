---
title: "Jenkinsをちょっと触ってみる"
date: 2026-02-15T15:20:00Z
tags: []
categories: [ "Jenkins" ]
---

## 前置き

社内でJenkinsが使われていことは知っているが、いままで触れる機会が全然なかった。
そんな中突然Jenkinsに触れる機会があったのだが、あれこれ情報源をつまみ食いして試行錯誤した結果「なんかよくわかんないけどこうすれば動くんだろうなー」程度の理解になってしまっており気持ち悪い。
もう少し基本的なところを理解したいと思ったので勉強した。ついでに記事にした。

## 環境

* [NixOS on WSL](https://github.com/nix-community/NixOS-WSL)
* Jenkins Version 2.516.2

## 参考資料

* [JenkinsでCI環境構築チュートリアル （Linux編・macOS編） - ICS MEDIA](https://ics.media/entry/14273/#5.-jenkins%E3%81%AE%E3%82%BB%E3%83%83%E3%83%88%E3%82%A2%E3%83%83%E3%83%97)：導入時にこんなGUIセットアップするのか、という参考にした。ただ自分の環境はNixなので具体的な導入手順は別ページを参照する必要があった
* [Jenkins - NixOS Wiki](https://nixos.wiki/wiki/Jenkins)：NixOSでJenkinsをどうセットアップするかの解説ページだが、ただ `services.jenkins.enable = true` にしろとしか書いてない（でもそのシンプルさがNixの良いところ）
    * 他に設定できるオプションは [search.nixos.org](https://search.nixos.org/options?channel=25.11&query=jenkins) を見るとよい
* [Jenkins Pipelineを試す - とことんDevOps | 日本仮想化技術のDevOps技術情報メディア](https://devops-blog.virtualtech.jp/entry/20230609/1686278733)：とりあえずどうやってpipeline作って実行すればよいんだという観点で参考にした
* [Pipeline（公式ドキュメント）](https://www.jenkins.io/doc/book/pipeline/)：pipelineってどうやって書くんだろうなという参考にした
* [[Jenkins]パイプラインジョブがshでハングする問題 #Pipeline - Qiita](https://qiita.com/xishan/items/881f1e02628170801f4a)：ジョブの実行がいつまでたっても終わらなかったり変なエラーで落ちたりしたときに、こちらの記事あるとおりに環境変数設定したら治った。原理はよくわかってない…
* [JenkinsにGitHub認証情報を登録してJenkinsfileからジョブを作成できるようにする #GitHub - Qiita](https://qiita.com/karaage578tech/items/e6d6f53baf977cf4556b)：クレデンシャルってどこで設定するのという観点で参考にした
* [Declarative Pipeline で Jenkins に保存された認証情報を利用する #JenkinsPipeline - Qiita](https://qiita.com/kobanyan/items/7f6416714774d9b625d2)：作成したクレデンシャルをどうやってpipelineで使うのという観点で参考にした

## Jenkinsのインストール

まずはJenkinsが動く環境を整える必要がある。

セットアップは環境次第だが、自分の場合WSL上でNixOSを動かしているので、その上にJenkinsサーバーを動かす。

NixOSの場合は、以下を `configuration.nix` に追記して `nixos-rebuild switch` するだけ。
```nix
{
  # ...

  services.jenkins = {
    enable = true;
  };

  # ...
}
```

そのほかのオプションの詳細は [jenkinsのnixファイル](https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/services/continuous-integration/jenkins/default.nix) を見てもよいが、[公式docのAppendix A. Configuration Options 
](https://nixos.org/manual/nixos/stable/options#opt-services.jenkins.enable) または [search.nixos.org](https://search.nixos.org/options?channel=25.11&query=jenkins) からだと視覚的に見やすい。
例えばデフォルトでは `http://localhost:8080` でアクセスできるのだが、以下のように `port` でポートを変えることも可能。
```nix
{
  # ...

  services.jenkins = {
    enable = true;
    port = 7080;
  };

  # ...
}
```

## セットアップ

### 初回設定

`https://localhost:8080` にアクセスすると Unlock Jenkins ページに飛ぶので、指示通り `/var/lib/jenkins/secrets/initialAdminPassword` ファイルに記載の初期パスワードを入力。

{{< figure link="./img/setup-01.png" src="./img/setup-01.png" width="70%" >}}

次にプラグインを入れるかどうかが出る。取捨選択するものもよくわからないので、とりあえずInstall suggested pluginを選択する。

{{< figure link="./img/setup-02.png" src="./img/setup-02.png" width="70%" >}}

プラグインのインストール状況画面が出るので待つ。

{{< figure link="./img/setup-03.png" src="./img/setup-03.png" width="70%" >}}

続いて初回のAdminユーザを作れといわれる。今回はお試しなので、Skip and continue as adminを選択。

{{< figure link="./img/setup-04.png" src="./img/setup-04.png" width="70%" >}}

JenkinsのURLを設定する画面が出るが、今回はNot nowを押す。

{{< figure link="./img/setup-05.png" src="./img/setup-05.png" width="70%" >}}

準備ができましたと言われる。またスキップしたオプションはどこから設定できるのかも表示してくれている。そのままStart using Jekinsを押す。

{{< figure link="./img/setup-06.png" src="./img/setup-06.png" width="70%" >}}

### 環境変数の設定

ジョブがシェルコマンドを実行するのに必要なため、環境変数を設定する。

右上からJenkinsの管理を押す。

{{< figure link="./img/setting-01.png" src="./img/setting-01.png" width="70%" >}}

Systemを押す。

{{< figure link="./img/setting-02.png" src="./img/setting-02.png" width="70%" >}}

グローバルプロパティ → 環境変数のところで、 `PATH+EXTRA: /bin/` を追加して、Saveを押す。

{{< figure link="./img/setting-03.png" src="./img/setting-03.png" width="70%" >}}


## パイプラインに触ってみる

Jenkinsにはジョブの種類がいくつかあるが、本記事ではパイプラインを使ったジョブのみを扱う。  
※ 簡易的なジョブの作成にはfreestyleという種類が使えそうだが、[Best Practice](https://www.jenkins.io/doc/book/using/best-practices/#use-pipeline) でもパイプライン使えと言ってるし、そもそも [Working with projects](https://www.jenkins.io/doc/book/using/working-with-projects/) にもfreestyleの解説リンクだけ無い

### パイプラインの作成

新規ジョブを作成。

{{< figure link="./img/pipeline-01.png" src="./img/pipeline-01.png" width="70%" >}}

適当なジョブ名を入力し、パイプラインを選択し、OKを押す。

{{< figure link="./img/pipeline-02.png" src="./img/pipeline-02.png" width="70%" >}}

以下のようなpipeline定義を書き、Saveを押す。

```groovy
pipeline {
    agent any

    stages {
        stage('state-1') {
            steps {
                sh 'echo "Hello"'
                sh 'echo "World"'
            } 
        }
        stage('state-2') {
            steps {
                sh 'echo "Hello"'
                sh 'echo "World"'
            }
        }
    }
}
```

{{< figure link="./img/pipeline-03.png" src="./img/pipeline-03.png" width="70%" >}}

### パイプラインの実行

ビルド実行を押す。

{{< figure link="./img/pipeline-04.png" src="./img/pipeline-04.png" width="70%" >}}

ビルド成功すると緑マーク、失敗すると赤マークが出る。成功したビルドの番号を押す。

{{< figure link="./img/pipeline-05.png" src="./img/pipeline-05.png" width="70%" >}}

Console log画面からビルドのログが見える。

{{< figure link="./img/pipeline-06.png" src="./img/pipeline-06.png" width="70%" >}}

このログを見ると、なんとなくpipeline定義とビルドの実行ログが対応しているなとわかる。
* `Running on Jenkins ... ` で、Jenkinsサーバー上でビルドが実行されているのかがわかる
* 1つのビルドは複数のステージに分かれる
* 1つのステージは複数のステップに分かれる

## ノードを1台追加してみる

Jenkinsにはノードという概念があり、ジョブをどのノードが実行するかといったものを制御できるみたい。

試しにノードを1つ追加してみる。

### ノードの追加

まず Jenkinsの管理 → Node の画面に行き、New Node を押す。

{{< figure link="./img/add-node-01.png" src="./img/add-node-01.png" width="70%" >}}

ノード名を入力し、Permanent Agentのラジオボタンを選択し、Createを押す。

{{< figure link="./img/add-node-02.png" src="./img/add-node-02.png" width="70%" >}}

必要事項を入力
* リモートFSルート： ノードの作業ディレクトリのようなもの。お試しで作って動かしてみるだけなので、とりあえずホームディレクトリに適当なディレクトリ `/home/bombrary/jenkins-node-works` を切って設定しておく
* ラベル：ノードに設定するラベルを設定する。後でpipeline実行するときに、このノードを選択するための条件に使う
* 起動方法：「Launch agent by connecting it to the controller」 または 「SSH経由でUnixマシンのスレーブエージェントを起動」が選べるようだ
    * 今回はとりあえずノードが稼働しているということがわかればよいので、前者にする

{{< figure link="./img/add-node-03.png" src="./img/add-node-03.png" width="70%" >}}

保存を押すと元の画面に戻る。作成したnode-01を押す。

{{< figure link="./img/add-node-04.png" src="./img/add-node-04.png" width="70%" >}}

このコマンド入力すればagentが起動できるよ、という案内がある。

{{< figure link="./img/add-node-05.png" src="./img/add-node-05.png" width="70%" >}}

### ノードの稼働

ノードを追加をJenkinsから実施したが、実体となるエージェントがまだいないので起動する。

Nixの場合、まず `java` コマンドが動作するシェル環境を準備する。お試しであれば、 `flake.nix` を次のようにして `nix develop` コマンドを実行すればよい。
```nix
{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let
    pkgs = nixpkgs.legacyPackages.x86_64-linux;
  in
  {

    devShells.x86_64-linux.default = pkgs.mkShell {
      packages = with pkgs; [
        openjdk
      ];
    };
  };
}
```

javaが起動する作業環境を準備。
```console
bombrary@nixos:~% mkdir /home/bombrary/jenkins-node-works
bombrary@nixos:~% cd jenkins-node-works
bombrary@nixos:~/jenkins-node-works% nvim flake.nix
# flake.nixを作成

bombrary@nixos:~/jenkins-node-works% nix develop
warning: creating lock file '"/home/bombrary/jenkins-node-works/flake.lock"':
• Added input 'nixpkgs':
    'github:nixos/nixpkgs/ec7c70d12ce2fc37cb92aff673dcdca89d187bae?narHash=sha256-9xejG0KoqsoKEGp2kVbXRlEYtFFcDTHjidiuX8hGO44%3D' (2026-02-11)

[bombrary@nixos:~/jenkins-node-works]$ pwd
/home/bombrary/jenkins-node-works

[bombrary@nixos:~/jenkins-node-works]$
```

JenkinsのUIで案内されていたコマンドを実行すると、agentが稼働状態になる。
```console
[bombrary@nixos:~/jenkins-node-works]$ echo ********** > secret-file;curl -sO http://localhost:7080/jnlpJars/agent.jar;java -jar agent.jar -url http://localhost:7080/ -secret @secret-file -name "node-01" -webSocket -workDir "/home/bombrary/jenkins-node-works"
Feb 14, 2026 6:37:27 AM org.jenkinsci.remoting.engine.WorkDirManager initializeWorkDir
INFO: Using /home/bombrary/jenkins-node-works/remoting as a remoting work directory
Feb 14, 2026 6:37:27 AM org.jenkinsci.remoting.engine.WorkDirManager setupLogging
INFO: Both error and output logs will be printed to /home/bombrary/jenkins-node-works/remoting
Feb 14, 2026 6:37:27 AM hudson.remoting.Launcher createEngine
INFO: Setting up agent: node-01
Feb 14, 2026 6:37:27 AM hudson.remoting.Engine startEngine
INFO: Using Remoting version: 3309.v27b_9314fd1a_4
Feb 14, 2026 6:37:27 AM org.jenkinsci.remoting.engine.WorkDirManager initializeWorkDir
INFO: Using /home/bombrary/jenkins-node-works/remoting as a remoting work directory
Feb 14, 2026 6:37:27 AM hudson.remoting.Launcher$CuiListener status
INFO: WebSocket connection open
Feb 14, 2026 6:37:27 AM hudson.remoting.Launcher$CuiListener status
INFO: Connected
```

JenkinsのUIからも、ノードが稼働状態になったことを確認。

{{< figure link="./img/add-node-06.png" src="./img/add-node-06.png" width="70%" >}}

これで、pipelineの定義を以下のようにしてビルドしてみる。違いは `agent` の部分で、「 ラベルが `mynode` であるようなノード上でビルドを実行する」という意味になる。

```groovy
pipeline {
    agent { label 'mynode' }

    stages {
        stage('state-1') {
            steps {
                sh 'echo "Hello"'
                sh 'echo "World"'
            } 
        }
        stage('state-2') {
            steps {
                sh 'echo "Hello"'
                sh 'echo "World"'
            }
        }
    }
}
```

これで実行してみると、`Running on node-01 ...` のように、ちゃんと `node-01` 上で実行したというログが見える。

{{< figure link="./img/add-node-07.png" src="./img/add-node-07.png" width="70%" >}}

## クレデンシャルを使ってみる

Jenkinsでは、秘匿したい認証情報を登録する機能があるので使ってみる。

### クレデンシャルの作成

まずJenkinsの管理から Credentials を押す。

{{< figure link="./img/credential-01.png" src="./img/credential-01.png" width="70%" >}}

Stores scoped to Jenkins の欄のSystemを押す。

{{< figure link="./img/credential-02.png" src="./img/credential-02.png" width="70%" >}}

グローバルドメインを押す。

{{< figure link="./img/credential-03.png" src="./img/credential-03.png" width="70%" >}}

Adding some credentials を押す。

{{< figure link="./img/credential-04.png" src="./img/credential-04.png" width="70%" >}}

今回は種類「ユーザ名とパスワード」として作成する。ユーザ名とパスワードを適当に入力し、Createを押す。

{{< figure link="./img/credential-05.png" src="./img/credential-05.png" width="70%" >}}

作成後、クレデンシャル一覧画面に戻る。作成したクレデンシャルの下にIDがあるのでそれを控えておく。

{{< figure link="./img/credential-06.png" src="./img/credential-06.png" width="70%" >}}

### クレデンシャルの利用

最初に作ったジョブのpipeline定義を以下のようにしてビルドしてみる。
* `environment { 変数名 = credentials('クレデンシャルのID') }` のように、クレデンシャルを環境変数として宣言する
* `変数名_USR` 、 `変数名_PWD` のように環境変数として参照ができる

```groovy
pipeline {
    agent { label 'mynode' }

    environment {
        CREDS = credentials('7a18c0d3-67e8-4bea-a085-601c53c2fcd8')
    }

    stages {
        stage('state-1') {
            steps {
                sh 'echo "user: ${CREDS_USR}"'
                sh 'echo "pass: ${CREDS_PWD}"'
            } 
        }
    }
}
```

ビルドしてみると、Console Outputにてパスワードがちゃんと出力されていないことがわかる。

{{< figure link="./img/credential-07.png" src="./img/credential-07.png" width="70%" >}}

## パラメータ付きビルド

続いて、ジョブのビルド時にパラメータが設定できるようにしてみる。

pipeline定義を以下のようにする。
```groovy
pipeline {
    agent any
    parameters {
        string(name: 'PARAM_A', defaultValue: 'foo', description: 'This is param A')
        text(name: 'PARAM_B', defaultValue: 'bar', description: 'This is param B')
    }
    stages {
        stage('Example') {
            steps {
                echo "PARAM_A: ${PARAM_A}"
                echo "PARAM_B: ${PARAM_B}"
            }
        }
    }
}
```

これでSaveする。このパラメータ設定はJobを一度ビルドしないとpipeline定義が読み込まれず反映されないらしいので、まずは適当にJobを再ビルドする。

[How to make sure list of parameters are updated before running a Jenkins pipeline? - Stack Overflow](https://stackoverflow.com/questions/46680573/how-to-make-sure-list-of-parameters-are-updated-before-running-a-jenkins-pipelin)

そのあとジョブの設定にもう一度移動してみると、「ビルドのパラメータ化」のところにチェックが入っており、pipelineで定義したパラメータが設定されていることが分かる。

{{< figure link="./img/parameter-build-01.png" src="./img/parameter-build-01.png" width="70%" >}}

そして、「ジョブのビルド」と書いてあったものが「パラメータ付きビルド」に代わっており、押すと次のようにパラメータを入力する画面に飛ぶ。

{{< figure link="./img/parameter-build-02.png" src="./img/parameter-build-02.png" width="70%" >}}

ビルドしてみると、ちゃんと入力したパラメータがログに出ていることがわかる。

{{< figure link="./img/parameter-build-03.png" src="./img/parameter-build-03.png" width="70%" >}}

## アンインストール & クリーンアップ

NixOSの場合、以下 `services.jenkins.enable = true` を消して再度 `nixos-rebuild switch` するだけ。

```diff
-  services.jenkins = {
-    enable = true;
-  };
```

データも全部消したいなら `/var/lib/jenkins` も消す。

```sh
sudo rm -rf /var/lib/jenkins
```

## 終わりに

Jenkinsを導入し、ジョブのビルド、クレデンシャルの設定、パラメータの設定などいくつか機能を試してみた。

pipelineの定義を実際に書いてみて、なるほどpipelineはstepやstageの集まりなんだなという学びを得られたので有意義だった。
