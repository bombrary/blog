---
title: "iPhoneアプリ開発メモ - addTarget/SegmentedControl"
date: 2019-12-14T19:44:49+09:00
tags: ["iPhone", "Swift", "Selector", "SegmentedControl"]
categories: ["iPhone", "Swift"]
---

## 目標

- 降順、昇順の切り替えができるTableViewを作成する。

## 準備

### Main.storyborad

部品を以下のように配置する。

{{< figure src="./storyboard_main.png" width="60%" >}}

Segmented Controlのラベルの設定は以下で行える。

{{< figure src="./segmentedctl_prop.png" width="50%" >}}

TableViewCellのindentifierは`testCell`とする。

### ViewController.swift

後々の処理のため、TableViewに表示するデータを`items`、その元データを`itemsSource`と分けることにする。

{{< highlight swift >}}
class ViewController: UIViewController {
    
    let itemsSource = ["items1", "items2", "items3", "items4", "items5", "items6", "items7", "items8"]
    var items: [String] = []


    @IBOutlet weak var segmentedControl: UISegmentedControl!
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        tableView.dataSource = self
        items = itemsSource
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "testCell")!
        cell.textLabel?.text = items[indexPath.row]
        return cell
    }
}
{{< /highlight >}}

## Segmented Controlのイベント設定

`ViewController.swift`に追記する。

{{< highlight swift >}}
   override func viewDidLoad() {
        ...
        segmentedControl.addTarget(self, action: #selector(segmentedCtlValueChanged(_:)), for: .valueChanged)
    }
    @objc func segmentedCtlValueChanged(_ sender: UISegmentedControl) {
        let index = sender.selectedSegmentIndex
        if index == 0 {
            items = itemsSource
        } else {
            items = itemsSource.reversed()
        }
        tableView.reloadData()
    }
{{< /highlight >}}

{{< figure src="./mov01.gif" width="50%" >}}

### addTarget

UI部品に対して何かイベントが発生した時の処理を設定する。JSでいう`addEventListener`みたいなものだと思う。

処理する関数名はSelectorの書式で書く。

以下の場合、ボタンが押されたときに`self.buttonTapped`メソッドが呼ばれる。ボタンの場合はStoryboardからAction接続する方が簡単だが、例のため書いている。

{{< highlight swift >}}
// addTarget(処理する関数の場所, 処理する関数名, イベントの種類)
button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
{{< /highlight >}}

Selectorで指定した関数`buttonTapped`は次のような引数で定義する。先頭に`@objc`をつける。

{{< highlight swift >}}
@objc func buttonTapped(_ sender: UIButton) {
    print("Tapped!")
}
{{< /highlight >}}

`for`で指定できるイベントはたくさんある。詳しくは[ドキュメント](https://developer.apple.com/documentation/uikit/uicontrol/event)参照。

### segmentedControl.selectedSegmentIndex

これでどのセグメントが選択されているのかが番号として分かる。`Ascending`が0、`Descending`が1として割り振れらている。おそらく左から右へ番号が振られていると思う。

## その他の知見

`addTarget`に指定できるSelectorとその実装は以下の3種類。[ドキュメント](https://developer.apple.com/documentation/uikit/uicontrol#1943645)は若干古いので、引数が少し異なる。また`sender`の型は呼び出し元の型だから、`UIButton`とは限らないことにも注意。

{{< highlight swift >}}
#selector(doSomething) 
@IBAction func doSomething()

#selector(doSomething(_:))
@IBAction func doSomething(_ sender: UIButton)

#selector(doSomething(_:for:))
@IBAction func doSomething(_ sender: UIButton, for event: UIEvent)
{{< /highlight >}}

## 追記: addTargetを使わない方法

Storyboardからコードへ普通にAction接続したらできることが判明した。Actionの種類を"Value Changed"にして接続すれば、上の`addTarget`と全く同じ処理が書ける。どんな種類のActionが指定できるのかは接続時のプルダウンから見られるし、また以下のように右サイドバーから見ることも可能。

{{< figure src="./actions.png" width="30%" >}}

`addTarget`はAction接続のコード版という立ち位置で、同じ機能が実現できるのかも。

## 参考

- [UISegmentedControl - Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uisegmentedcontrol)
- [UIControl - Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uicontrol#1943645)
- [addTarget - Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uicontrol/1618259-addtarget)
- [UIControl.Event - Apple Developer Documentation](https://developer.apple.com/documentation/uikit/uicontrol/event)

