---
title: "iPhoneアプリ開発メモ - UIPresentationControllerの利用"
date: 2019-12-19T10:01:42+09:00
tags: ["iPhone", "Swift", "UIKit", "UIPresentationController"]
categories: ["iPhone", "Swift"]
---

UIPresentationControllerを利用すると、モーダル表示の方法をカスタマイズできる。これについて備忘録を残す。

## そもそもモーダル表示とは

そもそもモーダル表示って何？と思ったので調べる。モーダルと検索すると「モーダルウインドウ」の話がよく出てくる。これは「ある操作を終えるまで親ウインドウの操作ができない子ウインドウ」という意味で使われているようだ。これはモーダル表示と似たような意味なのだろうか。判然としないので一次資料を漁る。

[AppleのHuman Interface Guideline](https://developer.apple.com/design/human-interface-guidelines/ios/app-architecture/modality/)にModalityの意味が書いてあって、これを引用すると、

<blockquote>
Modality is a design technique that presents content in a temporary mode that’s separate from the user's previous current context and requires an explicit action to exit.
<br>
[意訳] Modalityとは、ユーザの以前の文脈から離れた一時的なモードでコンテンツを表示するデザインの手法。そのモードを終了するためには何か明示的なアクションを必要とする。
</blockquote>

ほとんど同じ意味っぽい。

例えば次のようなモーダル表示(Page Sheet)の場合，呼び出し元が下にあってその上に青いビューが載っている。ここでは、「上から下に引っ張る」というアクションを起こすことで、このビューを閉じることができる。

{{< figure src="./iphone-pagesheet.png" width="30%" >}}

## 用意するもの

- 表示**元**のViewController
- 表示**先**のViewController
- UIPresentationControllerのサブクラス - これが表示先のViewControllerの表示方法を規定する。

ここでは、表示先のViewControllerのStoryboard IDを`dest`とする．

## 準備

まずはボタンをクリックすると表示されるものだけ作る。

### Main.storyboard

表示元にはボタンを配置する。表示先はラベルを配置し、適切なConstraintを設定しておく。

{{< figure src="./storyboard_main01.png" width="75%" >}}

### ViewController.swift

ボタンのAction接続を作る。ボタンがタップされたら遷移するようにする。

{{< highlight swift >}}
class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func buttonTapped(_ sender: Any) {
        let vc = (storyboard?.instantiateViewController(identifier: "dest"))!
        present(vc, animated: true, completion: nil)
    }
}
{{< /highlight >}}

## 遷移前の設定
`buttonTapped`に追記して次のようにする。

{{< highlight swift >}}
@IBAction func buttonTapped(_ sender: Any) {
    let vc = (storyboard?.instantiateViewController(identifier: "dest"))!
    vc.modalPresentationStyle = .custom
    vc.transitioningDelegate = self
    present(vc, animated: true, completion: nil)
}
{{< /highlight >}}

さらに次のextensionを追加する。

{{< highlight swift >}}
extension ViewController: UIViewControllerTransitioningDelegate {
    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return CustomPresentationController(presentedViewController: presented, presenting: presenting)
    }
}
{{< /highlight >}}

### modalPresentationStyle

モーダル表示のスタイルを設定する。`.custom`を設定すると、そのスタイルは`UIPresentationController`によって設定されるようになる([ソース](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioningdelegate))。`UIPresentationController`は`UIViewControllerTransitioningDelegate`のプロトコルで定義されたメソッド`presentationController`で設定する。

今回は`ViewController`にこのDelegateを設定するが、例えば表示先のViewControllerのswiftファイルにDelegateを設定する、という書き方もあり。

### UIViewControllerTransitioningDelegate

このプロトコルには、ViewController間の遷移に関する設定をするメソッドが定義されている。ここではメソッド`presentationController`のみ定義する。これは`UIPresentationController`クラスのサブクラスを返す。ここでは`CustomPresentationController`とする。このクラスは次項で実装する。


## CustomPresentationController

遷移時の表示アニメーションとか、遷移後の表示方法を制御するController。overrideできるメソッドは[ドキュメント](https://developer.apple.com/documentation/uikit/uipresentationcontroller)に全て書かれているので、必要なものを実装する。

次のような内容を持つ`CustomPresentationController.swift`を作成する。

{{< highlight swift >}}
class CustomPresentationController: UIPresentationController {
  // いろいろ書く
}
{{< /highlight >}}

### 主要そうなプロパティ

- `presentingViewController`: 表示元のViewController
- `presentedViewController`: これから表示するViewController
- `presentedView`: これから表示するView。挙動を検証してみた限りだと、`presentedViewController.view`と同義っぽい？
- `containerView`: `presentedView`を包むView？ドキュメントだと<q>The view in which the presentation occurs.</q>とあるので、この中で実際のビューの表示が起こるみたい。
- `frameOfPresentedViewInContainerView`: 表示するビューの位置・サイズを決める。

### 主要そうなメソッド

- 遷移の開始、終了時の処理は`presentationTransitionWillBegin/DidEnd`および`dismissalTransitionWillBegin/DidEnd`で設定できる。前者はビューが表示される時、後者はビューが表示されなくなるときに呼ばれる。ここに表示や非表示時のアニメーションを記述する。
- `containerView`に実際に要素が置かれるときの処理は`containerViewWillLayoutSubviews/DidLayoutSubviews`で設定できる。ここにはビューの位置やサイズを記述する。
- 表示ビューのサイズを変更するためには`size`メソッドをオーバーライドする。この関数は`UIContentContainer`プロトコルで定義されている関数。

## ビューのサイズと位置の変更

以下のような配置のウインドウを作ることを考える。

{{< figure src="./layout01.svg" >}}

設定方法は[こちら](https://qiita.com/wai21/items/9b40192eb3ee07375016)を参考にした。変数名のいくつかはここと同じになっている。

## サイズを変更する


`CustomPresentationController`に以下の定義を追加する。

単に`size`メソッド内で`margin`込みのViewサイズを設定し、それを利用して`frameOfPresentedViewInContainerView`を設定している。コンテナの存在を確認するため、`containerView`の背景色を分かりやすくする。

{{< highlight swift >}}
override func presentationTransitionWillBegin() {
    containerView?.backgroundColor = .systemGreen
}

let margin = (x: CGFloat(40), y: CGFloat(100))
override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
    return CGSize(width: parentSize.width - 2*margin.x, height: parentSize.height - 2*margin.y)
}
override var frameOfPresentedViewInContainerView: CGRect {
    var presentedViewFrame = CGRect()
    let containerBounds = containerView!.bounds
    let childContentSize = size(forChildContentContainer: presentedViewController, withParentContainerSize: containerBounds.size)
    presentedViewFrame.size = childContentSize

    return presentedViewFrame
}
{{< /highlight >}}

`presentedView`にこの情報を教えておく必要があるので、`containerViewWillLayoutSubviews`にそれを書く。

{{< highlight swift >}}
override func containerViewWillLayoutSubviews() {
    presentedView?.frame = frameOfPresentedViewInContainerView
}
{{< /highlight >}}


ラベルが青Viewの中央に並んでいる。このことから、`size`や`frameOfPresentedViewInContainerView`で定義されたサイズは、単にトリミングしているわけでなく、Constraintを保ったままViewそのものを縮小したサイズだと分かる。

{{< figure src="./iphone02.png" width="30%" >}}

### 捕捉

実は、上の`containerViewWillLayoutSubviews`内のコードを書かなくても一見正常に動作しているように見える。しかし試しに次のようにprintデバッグしてみる。

{{< highlight swift >}}
override var frameOfPresentedViewInContainerView: CGRect {
  ...
  print("presentedViewInContainerView:\(presentedViewFrame)")
  print("presentedView?.frame:\(presentedView?.frame)")
  ...
}
{{< /highlight >}}

すると、画面遷移のときに次のログが出力される。

```
presentedViewInContainerView:(0.0, 0.0, 334.0, 696.0)
presentedView?.frame:Optional((0.0, 0.0, 414.0, 896.0))
```

このログだけでは画面遷移開始前なのか後なのかはわからないが、少なくとも`presentedView`の位置、サイズが`frameOfPresentedViewInContainerView`と異なる瞬間がある。具体例は思いつかないが、何か表示に関するバグを生みそう。なので`containerViewWillLayoutSubviews`に書いたコードは必要。


## 位置を変更

`presentedViewFrame`の原点位置を変更すれば良い。

{{< highlight swift >}}
override var frameOfPresentedViewInContainerView: CGRect {
    ...
    presentedViewFrame.origin.x += margin.x
    presentedViewFrame.origin.y += margin.y

    return presentedViewFrame
}
{{< /highlight >}}


{{< figure src="./iphone03.png" width="30%" >}}

## 背景を暗くするアニメーション

一応こうすることで背景色を半透明の黒にできる。遷移に関するアニメーションは`transitionCoordinator?.animate`を利用する。

{{< highlight swift >}}
override func presentationTransitionWillBegin() {
    containerView!.backgroundColor = UIColor(white: 0.0, alpha: 0.0)
    presentedViewController.transitionCoordinator?.animate(alongsideTransition: { [unowned self] _ in
        self.containerView?.backgroundColor = UIColor(white: 0.0, alpha: 0.5)
    })
}
{{< /highlight >}}

これでうまくいくのだが、いろいろ調べてみると、`containerView`の背景色を直接いじっている例が見当たらない。もしかしたら`containerView`はあくまでコンテナなので、レイアウトのためにこれをいじるのはあまり良くない？

次のように`overlay`という名のViewを作って、これを半透明の黒にする例しかなかった。この場合は色を変更するのではなく、Viewそのものの透明度をアニメーションさせる。こっちのほうが良いのかな？

`overlay`の`frame`は`containerViewWillLayoutSubviews`に記述しておく。

{{< highlight swift >}}
let overlay = UIView()
override func presentationTransitionWillBegin() {
    overlay.backgroundColor = .black
    overlay.alpha = 0.0
    containerView?.addSubview(overlay)
    presentedViewController.transitionCoordinator?.animate(alongsideTransition: { [unowned self] _ in
        self.overlay.alpha = 0.5
    })
}
override func containerViewWillLayoutSubviews() {
    ...
    overlay.frame = containerView!.bounds
}
{{< /highlight >}}

## タップされたら画面を閉じる

次のように、`overlay`に`UITapGestureRecognizer`を設定しておく。これは`presentationTransitionWillBegin`の中に定義する。

{{< highlight swift >}}
let recognizer = UITapGestureRecognizer(target: self, action: #selector(overlayTapped(_:)))
overlay.addGestureRecognizer(recognizer)
{{< /highlight >}}

`selector`に`overlayTapped`関数を指定したから、これを定義する。

{{< highlight swift >}}
@objc func overlayTapped(_ sender: UITapGestureRecognizer) {
    presentedViewController.dismiss(animated: true, completion: nil)
}
{{< /highlight >}}

画面の破棄が終了すると`dismissalTransitionDidEnd`が呼ばれるので、その処理を書く。

{{< highlight swift >}}
override func dismissalTransitionDidEnd(_ completed: Bool) {
    if completed {
        overlay.removeFromSuperview()
    }
}
{{< /highlight >}}

### 捕捉

`dismissalTransitionDidEnd`に処理を書かなくても一見動作は同じである。これを書かなかったからと言って`overlay`が破棄されないわけでもないようだ(これは`overlay`をカスタムビューにして、`deinit`内でprintを書いてみると分かる)。しかし、少なくとも僕が調べたサイトでは、すべて`overlay.removeFromSuperview()`を呼び出している。

現時点で考えられる理由は次の2点である。

- [ドキュメント](https://developer.apple.com/documentation/uikit/uipresentationcontroller/1618323-dismissaltransitiondidend)に、「このメソッドはpresentation controller内で追加されたViewを削除するために使う」と書かれているから、削除しておいた方が行儀が良い。
- もう少し凝ったコードを書くとき、何らかの理由でメモリリークが起こるのを防ぐため。


### overlayのアニメーション

overlayがゆっくりと透明になるようにする。`presentedView`が閉じられるときに行いたいので、`dismissalTransitionBegin`に記述する。

{{< highlight swift >}}
override func dismissalTransitionWillBegin() {
    presentedViewController.transitionCoordinator?.animate(alongsideTransition: { [unowned self] _ in
        self.overlay.alpha = 0.0
    })
}
{{< /highlight >}}

{{< figure src="./mov.gif" width="30%" >}}

## 捕捉: 遷移のアニメーションの向きを制御したいとき

例えば、「Viewを横からスライドして出現させたい」などの要求があるかもしれない。

まずは、次の2つのメソッドを`ViewController.swift`の`extension`部分に書く。`CustomAnimationController`はアニメーションを制御するためのオブジェクトで、後で定義する。

{{< highlight swift >}}
func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    return CustomAnimationController(isPresentation: true)
}
func animationController(forPresented presented: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    return CustomAnimationController(isPresentation: false)
}
{{< /highlight >}}

`UIViewControllerAnimatedTransitioning`プロトコルに準拠した`NSObject`を作っておく。[こちら](https://dev.classmethod.jp/smartphone/ios-custom-dialog-with-uipresentationcontroller/)では、次のように、`isPresented`で表示時と削除時でアニメーションを分けていた。

{{< highlight swift >}}
class CustomAnimationController: NSObject, UIViewControllerAnimatedTransitioning {
    let isPresented: Bool
    init(isPresented: Bool) {
        self.isPresented = isPresented
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.2
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isPresented {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }
    
    func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        // 表示時のアニメーションを書く
    }
    func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        // 削除時のアニメーションを書く
    }
}
{{< /highlight >}}

これについては興味があればまた勉強する。

## その他の知見

### Computed Property

変数xは例えばこんな感じで初期化できる。つまり初期化時に何かしらの処理を行いたい時にそれを`{}`でまとめて書ける。これは`frameOfPresentedViewInContainerView`のoverride時に使った。

{{< highlight swift >}}
let y = 10
var x: Int {
    var t = 0
    for i in 1...y {
        t += i
    }
    return t
}
{{< /highlight >}}

xにアクセスするたびに毎回計算が行われることに注意(中にprintを入れてみると分かる)。一回のみで良い場合は次のように、Computed Propertyではなくクロージャを使う。

{{< highlight swift >}}
let y = 10
var x: Int = {
    var t = 0
    for i in 1...y {
        t += i
    }
    return t
}()
{{< /highlight >}}

## 参考

- [Modality - Human Interface Guideline - Apple Developper](https://developer.apple.com/design/human-interface-guidelines/ios/app-architecture/modality/)
- [UIViewControllerTransitioningDelegate - Apple Developper](https://developer.apple.com/documentation/uikit/uiviewcontrollertransitioningdelegate)
- [UIPresentationController - Apple Developper](https://developer.apple.com/documentation/uikit/uipresentationcontroller)
- [【Swift】UIPresentationControllerを使ってモーダルビューを表示する - Qiita](https://qiita.com/wai21/items/9b40192eb3ee07375016)
- [iOS UIPresentationControllerを使用してカスタムダイアログを実装する - Developpers.IO](https://dev.classmethod.jp/smartphone/ios-custom-dialog-with-uipresentationcontroller/)
