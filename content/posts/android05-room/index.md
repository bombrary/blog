---
title: "Androidアプリ開発勉強(5) - Room"
date: 2019-12-01T12:48:52+09:00
draft: true
tags: []
categories: []
---

## Roomの基礎知識

Roomはデータベースの扱いを簡単にしてくれるライブラリ。

- entity: テーブルの情報。テーブル名およびレコードの列を定義する。
- DAO(Data Access Object): テーブルのアクセス方法を定義したオブジェクト。「この関数を呼んだらこのSQL文を実行する」という定義を書く。

## 書き方

### entity

{{< highlight kotlin >}}
@Entity(tableName = "table")
data class Record(
  @PrimaryKey(autoGenerate = true)
  var id: Int = 0
  @ColumnInfo(name = "name")
  var name: String
  @ColumnInfo(name = "age")
  var age: Int
)
{{< /highlight >}}

### DAO

INSERT文なら`@Insert`、UPDATE文なら`@Update`を関数の前にくっつける。

`SELECT * from table ORDER BY age`のようにより柔軟なSQL文を定義したいなら、`@Query("SQL文")`を関数の前にくっつける。SQL文の中に関数の引数を埋め込みたいなら、SQL文の中に`:引数`の形式で書く。

SQL文が複数のレコードを返す場合は`LiveData<List<Record>>`の形式で受け取る。

{{< highlight kotlin >}}
@Dao
interface MyDatabaseDao {
    @Insert
    fun insert(record: Record)
    @Update
    fun update(record: Record)
    @Query("SELECT * from table WHERE id = :key")
    fun get(key: Int): Record?
    @Query("SELECT * FROM table ORDER BY age")
    fun getAllRecord(): LiveData<List<Record>>
    @Query("DELETE FROM table")
    fun clear()
}
{{< /highlight >}}

### Database

- `entities`: entityの配列の型を指定する。
- `schema`: データベースのスキーマのバージョンを指定する。例えばテーブルの列を変えた場合は、ここのバージョンを上げる必要がある。
- `exportSchema`: スキーマの情報をどこかにエクスポートしてくれるっぽい。いらないので`false`

`@Volatile`をつけると、データをメモリに一時保管することがなくなるため、`INSTANCE`は常に最新のものを指すようになる。

`synchronized(obj) { ... }`で、`obj`をロックした上で`{ ... }`の処理を実行する。

`getInstance`はDatabaseのインスタンスを取得する。存在しなければ`Room.databaseBuilder`を利用してデータベースを再生成する。`fallbackToDestructiveMigration()`はいわゆるマイグレーションの方法を設定するメンバ関数の一つ。今回の場合は「データベーススキーマのバージョンが異なっていたら、全レコードを削除して作り直す」ことを意味している。

{{< highlight kotlin >}}
@Database(entities = [SleepNight::class], version = 1, exportSchema = false)
abstract class MyDatabase : RoomDatabase() {

    abstract val myDatabaseDao: MyDatabaseDao
    companion object {
        @Volatile
        private var INSTANCE: myDatabase? = null
        fun getInstance(context: Context): myDatabase {
            synchronized(this) {
                var instance = INSTANCE
                if (instance == null) {
                    instance = Room.databaseBuilder(
                            context.applicationContext,
                            myDatabase::class.java,
                            "my_database")
                            .fallbackToDestructiveMigration()
                            .build()
                }
                return instance
            }
        }
    }

}
{{< /highlight >}}

`Fragment`内でDAOを取得する場合は次のように書く。

{{< highlight kotlin >}}
val dataSource = SleepDatabase.getInstance(application).sleepDatabaseDao
{{< /highlight >}}

## Coroutine

ここは理解がかなり曖昧。

[ここ](https://codelabs.developers.google.com/codelabs/kotlin-android-training-coroutines-and-room/index.html?index=..%2F..android-kotlin-fundamentals#4)に書いてあることを簡単にまとめてみる。

ジョブとかディスパッチとかはOSの授業でやった覚えがあるけど、そのアナロジーで理解すれば良い？

- Job: 中断されうる作業の単位。`Job()`や`launch`によって作られる。後でやるが、例えばアプリ終了時などの、処理を中断しなければならないときに`cancel()`メンバ関数を利用する。
- Dispatcher: どのJobがどのスレッドで実行されるかを決定するもの。
- Scope: Coroutineが処理されるContextを定義するもの。Contextというのは、JobやDispatcherをまとめておくためのもの。Scopeの中でCoroutineが処理される。
- suspend: 中断されうる関数につける修飾子。コルーチンの中で関数を呼び出すために利用される。

この文で足し算が使われているのが謎。「`Main`スレッドで、`viewModelJob`を実行するようなスコープ」を定義していると理解すれば良さそう？
{{< highlight kotlin >}}
private val uiScope = CoroutineScope(Dispatchers.Main + viewModelJob)
{{< /highlight >}}

`withContext`とは、CoroutineのContextを切り替えるための関数。ここで行うのはデータベースでのIO処理なので`Dispatchers.IO`に切り替えているみたい。UIに関する処理はメインスレッドで行うみたいなので、`Dispatchers.Main`を利用する。

{{< highlight kotlin >}}
private fun initializeTonight() {
   uiScope.launch {
       tonight.value = getTonightFromDatabase()
   }
}
private suspend fun getTonightFromDatabase(): SleepNight? {
   return withContext(Dispatchers.IO) {
       var night = database.getTonight()
       if (night?.endTimeMilli != night?.startTimeMilli) {
           night = null
       }
       night
   }
}
{{</ highlight >}}

このパターンが多いらしい。

{{< highlight kotlin >}}
fun someWorkNeedsToBeDone {
   uiScope.launch {

        suspendFunction()

   }
}

suspend fun suspendFunction() {
   withContext(Dispatchers.IO) {
       longrunningWork()
   }
}
{{< /highlight >}}

## その他

`application.resources`でアプリ内のリソースにアクセスできるみたい。例えば`application.resources.getString(R.string.hello)`みたいにすると、`string.xml`内の`<string name="hello">...</string>`にアクセスできる。`application`の取得は次のように行う。

{{< highlight kotlin >}}
val application = requireNotNull(this.activity).application
{{< /highlight >}}

`Transformations.map`を用いると、`LiveData`の変化に応じて値が自動で変わってくれるようになる。例えば以下では、`tonight`が`null`になると`true`、`null`以外になると`false`に変わる。
{{< highlight kotlin >}}
val startButtonVisible = Transformations.map(tonight) {
    it == null
}
{{< /highlight >}}
