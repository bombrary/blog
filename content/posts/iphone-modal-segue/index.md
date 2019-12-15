---
title: "iPhoneアプリ開発メモ - セミモーダルビューからの遷移"
date: 2019-12-14T11:00:24+09:00
tags: ["Swift", "iPhone", "UIKit"]
categories: ["Swift", "iPhone"]
---

## 目標

- セミモーダルビューを作成する
- セミモーダルビュー上のボタンを押すと、それを閉じた後に別ビューに遷移する。

## 登場物

- `Main.storyboard`と`ViewController`
- `Menu.storyboard`と`MenuViewController`
- `Dest1.storyboard`
- `Dest2.storyboard`

## 前提

- 今後Viewが増えていく状況を想定して、Storyboardを分割することを考える。Storyboard同士はStoryboard Referenceで結びつける。

## セミモーダルビューの作成

検索して良く出てくるのは`UIPresentationController`を利用する方法。ただ今回はなるべくStoryboardで完結させたい。

そこで、以下のページを参考して作ることを考える。

[ハンバーガーメニューを作成するには？ - Swift Life](http://swift.hiros-dot.net/?p=377)

### ファイル作成

`Menu.storyboard`、`MenuViewController`、 `Menu.storyboard`、`Dest1.storyboard`、 `Dest2.storyboard`の5つをあらかじめ作成しておく。

### Menu.storyboard

classには`MenuViewController`を指定する。部品配置は以下のようにする。

全体を包むViewを親View、その中に作ったViewを子Viewと呼ぶことにすると、

- Constraintは適当に設定する。子Viewが画面下に配置されるようにする。
- StackViewにはFill Equallyの設定を行っておく。
- 親Viewの背景色を、黒の半透明に設定する。設定手順は以下の通り。
  1. BackgroundをBlackに設定
  2. BackgroundをCustomに設定し直すと、カラーピッカーが現れる。そこで透明度を50%に設定する。

また、"Initial View Controller"にチェックをつける。

親Viewのtagを1に設定しておく。これはタッチイベントを捕捉する際に必要になる。

{{< figure src="./storyboard_menu.png" width="50%">}}

### Dest1.storyboard、Dest2.storyboard

`Dest1.storyboard`の部品配置は以下のようにする。

"Is initial View Controller"にチェックをつける。

{{< figure src="./storyboard_dest1.png" width="50%">}}

`Dest2.storyboard`の部品配置は以下のようにする。

"Is initial View Controller"にチェックをつける。

{{< figure src="./storyboard_dest2.png" width="50%">}}

### Main.storyboard

部品配置は以下のようにする。

{{< figure src="./storyboard_main.png" >}}

OpenButtonからStoryboard ReferenceへのSegueのActionは"Present Modally"を選択。Segueの設定は以下のようにする。

{{< figure src="./segue01.png" width="50%">}}

Storyboard Referenceにて、"Storyboard"をMenuに、"Referenced ID"を未記入にする。

"Referenced ID"が未記入の場合、Storyboard上のInitial View Controllerへの参照にしてくれる。もしInitial View ControllerでないViewControllerに遷移したいなら、ここに記入する。ただし、遷移先のView ControllerにてIdentifierを設定しておくことを忘れずに。

### MenuViewController.swift

`Menu.storyboard`の小ViewのOutletを作成する。名前は`menuView`とする。

その上で以下の文を追記する。

{{< highlight swift >}}
class MenuViewController: UIViewController {
    ...

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let menuPosY = menuView.layer.position.y
        menuView.layer.position.y += menuView.layer.frame.height
        UIView.animate(
            withDuration: 0.5,
            delay: 0,
            options: .curveEaseOut,
            animations: {
                self.menuView.layer.position.y = menuPosY
        },
            completion: nil)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if touch.view?.tag == 1 {
                UIView.animate(
                    withDuration: 0.2,
                    delay: 0,
                    options: .curveEaseOut,
                    animations: {
                        self.menuView.layer.position.y += self.menuView.layer.frame.height
                }) { bool in
                    self.dismiss(animated: bool, completion: nil)
                }
            }
        }
    }
}
{{< /highlight >}}

`dismiss`メソッドを使うと自身のビューを閉じることができる。

{{< figure src="./mov01.gif" width="25%">}}

## モーダルビューを閉じてから遷移する処理

モーダルビュー上で直接Segueを作りたいところだが、そうするとモーダルビューの上にDestinationのViewが乗ってしまう。モーダルビューを閉じてから、Mainの方で遷移するように処理を書かなくてはいけない。

`MenuViewController.kt`にて、`Menu.storyboard`にあるボタン"To Destination1"と"To Destination2"のActionを設定する。それぞれの関数の実装を以下のようにする。

{{< highlight kotlin >}}
    @IBAction func dstOneTapped(_ sender: Any) {
        let navController = presentingViewController as! UINavigationController
        dismiss(animated: true) {
            let sb = UIStoryboard(name: "Dest1", bundle: nil)
            guard let vc = sb.instantiateInitialViewController() else {
                print("View Controller is not found.")
                return
            }
            navController.pushViewController(vc, animated: true)
        }
    }
    @IBAction func dstTwoTapped(_ sender: Any) {
        let navController = presentingViewController as! UINavigationController
        dismiss(animated: true) {
            let sb = UIStoryboard(name: "Dest2", bundle: nil)
            guard let vc = sb.instantiateInitialViewController() else {
                print("View Controller is not found.")
                return
            }
            navController.pushViewController(vc, animated: true)
        }
    }
{{< /highlight >}}

`MenuViewController`を表示しているのは、`Main.storyboard`で定義されたNavigation Controllerである。これは試しに`print(presentingViewController)`してみると分かる。従って、`presentingViewController`は`UINavigationController`にダウンキャストしている。

こうして得られた`navController`について、`pushViewController`メソッドを利用して遷移する。ビューを閉じた後に遷移したいから、`dismiss`メソッドの`completion`引数にこの処理を書いている。ちなみに、`dismiss`の`completion`内に`navController`の宣言を書くと実行時エラーを起こすことに注意。なぜなら`completion`の中では、`presentingViewController`は`nil`を返すから。`completion`はViewが破棄された後に呼ばれる関数。

`instantiateInitialViewController`で、Storyboard上のInitial View Controllerを作る(Storyboardで"Is initial view controller"にチェックをつけた理由はこれ)。InitialじゃないView Controllerを作りたいなら、`instantiateViewController`を利用する。このとき、遷移先のView Controllerにidentifierを設定しておくことを忘れないように。

## 遷移先のStoryboardににNavigation Controllerを持たせたい場合

遷移先がNavigation Controllerの場合、Navigation Controllerのルートに遷移するように書くだけ。Navigation ControllerをNavigation Controllerにpushしようとすると実行時エラーを吐かれるので注意。

### Dest1.storyboardの変更

部品構成を以下のようにする。

- NavigationItemのtitleをHelloに変更すると、上部にHelloが表示されるようになる。

ルートのView Controller(ラベル`Distination1`が書かれているもの)のidentifierを`dest1`に設定する。

{{< figure src="./storyboard_dest1_2.png" >}}

### MenuViewController.swiftの変更

メソッド`dstOneTapped`を以下のように変更する。

{{< highlight kotlin >}}
    @IBAction func dstOneTapped(_ sender: Any) {
        let navController = presentingViewController as! UINavigationController
        dismiss(animated: true) {
            let sb = UIStoryboard(name: "Dest1", bundle: nil)
            let vc = sb.instantiateViewController(withIdentifier: "dest1") 
            navController.pushViewController(vc, animated: true)
        }
    }
{{< /highlight >}}

ここで、`let vc = sb.instantiateViewController(withIdentifier: "navigation controllerのID")`と書いてはいけない。Navigation Controllerの中にNavigation Contollerをpushすることはできないため、`pushViewController`の呼び出し時にエラーになる。

{{< figure src="./mov02.gif" width="25%">}}


## その他の知見

この記事では利用しなかったが、大事そうな知見をここにまとめておく

### Segueにおける値渡し

遷移元のViewControllerにて、`prepare(for segue: UIStoryboradSegue, sender: Any?)`関数をoverrideする。特定のSegueに対して値を渡したい場合は、`segue.identifier`でif文を書けば良い。

{{< highlight swift >}}
override func prepare(for segue: UIStoryboradSegue, sender: Any?) {
  if segue.identifier == "Storyboard上で設定したSegueのidentifier" {
    let vc = segue.destination
    // vcに何か値を渡す処理
  }
}
{{< /highlight >}}

## 参考文献

[ハンバーガーメニューを作成するには？ - Swift Life](http://swift.hiros-dot.net/?p=377)
