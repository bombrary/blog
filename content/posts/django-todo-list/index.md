---
title: "Djangoの勉強でTodoリストを作る"
date: 2019-11-15T08:26:41+09:00
tags: ["Django", "Python", "Programming", "Todoリスト"]
categories: ["Python", "Programming"]
---

# Djangoの勉強でTodoリストを作る

## どんなTodoリストを作るか

- Todoの登録
  - 情報は短いテキストだけ
- Todoをリスト表示
- Todoをクリックすると削除

## サイトの作成

適当なディレクトリで次のコマンドを実行すると、`mysite`というディレクトリが作られる。以降は`mysite`ディレクトリで作業する。

```txt
$ django-admin startproject mysite
```

## アプリの作成

`mysite`ディレクトリにて以下のコマンドを実行すると、`todo_list`というディレクトリが作られる。ここに実際のアプリの処理を記述していく。:w

```txt
$ python3 manage.py startapp todo_list
```

続いて`mysite/settings.py`を開いて、`INSTALL_APPS`を以下の記述にする。`'todo_list.apps.TodoListConfig'`を追加しただけ。これはデータベース作成やテンプレート作成のために、djangoがtodo_listのディレクトリを教えているっぽい。`Todo_listConfig`かと思ったが違うらしい(エラーで「TodoListConfigだよ」と教えてくれた。優しい)。

{{< highlight  python3 >}}
INSTALLED_APPS = [
    'todo_list.apps.TodoListConfig',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]
{{< /highlight >}}

## viewの作成

`mysite/todo_list/views.py`を編集する。とりあえずviewが動くかどうかだけ確認したいので、レスポンスは適当な文字列にする。


{{< highlight python3 >}}
from django.shortcuts import render

# Create your views here.

def index(request):
    return HttpResponse('Hello')
{{< /highlight >}}

## urlの設定

まず`mysite/mysite/urls.py`の設定をする。`urls.py`とは「どんなurlにアクセスされたらどんなviewに処理を任せるか」を記述したものっぽい。ここでは、`todo_list/`で始まるurlだったら`todo_list/urls.py`に処理を任せるように書いている。

{{< highlight python3 >}}
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path('todo_list/', include('todo_list.urls')),
    path('admin/', admin.site.urls),
]
{{< /highlight >}}

ということで`mysite/todo_list/urls.py`の設定をする。恐らく存在しないので新しく作成する。`todo_list/`以降に何も指定されなかったら表示を`views.py`の`index`関数に任せるように書いている。

{{< highlight python3 >}}
from django.urls import path

from . import views

app_name = 'todo_list'
urlpatterns = [
    path('', views.index, name='index'),
]
{{< /highlight >}}

## 動かしてみる

```
$ python3 manage.py runserver
```

ブラウザを起動して`localhost:8000/todo_list/`にアクセスすると`Hello`の文字列だけ表示されたページに飛ぶ。期待通りに動いている。

## Model作成

`Todo`の内容を保存しておくためのデータベースが必要である。Djangoでは、データベースのテーブル要素をModelとして定義する。

`mysite/todo_list/model.py`の内容を以下のように編集する。今回扱うのはただのテキストだけなので、`models.CharField`しか用意しない。ただし、内部的には`text`だけでなく`id`変数も追加される。これはテーブルの要素を識別するためのもので、後で削除機能を実装する時に利用する。

{{< highlight python3 >}}
from django.db import models

# Create your models here.

class Todo(models.Model):
    text = models.CharField(max_length = 500)
{{< /highlight >}}

テーブルを自動作成するためにマイグレーションという作業が必要らしいので、それをやる。`Ctrl+C`でサーバーを終了した後、次の2コマンドを実行。
```
$ python3 manage.py makemigrations
$ python3 manage.py migrate
```
終わったらサーバーを再起動する。

## Templates作成

`mysite/todo_list/templates/todo_list/index.html`を作成し、内容を以下の通りにする。ディレクトリも適当に作成する。`todo_list/templates/todo_list`というディレクトリ構成が気持ち悪いが、名前空間云々の理由で仕方ない([参考](https://docs.djangoproject.com/ja/2.2/intro/tutorial03/#s-write-views-that-actually-do-something))。

{{< highlight html >}}
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>Todo List</title>
  </head>
  <body>
    <h1>Todo List</h1>
  </body>
</html>
{{< /highlight >}}

`mysite/todo_list/views.py`を編集する。

{{< highlight python3 >}}
from django.shortcuts import render
from django.http import HttpResponse

# Create your views here.

def index(request):
    return render(request, 'todo_list/index.html', {})
{{< /highlight >}}

## モデルが表示できるようにする

`mysite/todo_list/models.py`の`Todo`クラスをインポートして、`Todo.objects.all()`でTodoの全要素が取得できるらしい。この情報をrenderに渡すと、前項で作ったTemplateでそれが利用できるようになる。

{{< highlight python3 >}}
from django.shortcuts import render
from django.http import HttpResponse

from .models import Todo

# Create your views here.

def index(request):
    todos = Todo.objects.all()
    print(todos)
    return render(request, 'todo_list/index.html', {todos: todos})
{{< /highlight >}}

ということで`mysite/todo_list/templates/todo_list/index.html`を編集する。djangoのtemplate構文を利用して、`for-in`文が書ける。便利。

{{< highlight html >}}
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>Todo List</title>
  </head>
  <body>
    <h1>Todo List</h1>
    <ul>
      {% for todo in todos %}
      <li>{{ todo }}</li>
      {% endfor %}
    </ul>
  </body>
</html>
{{< /highlight >}}

しかしTodoにまだ何も要素が追加されていないので、表示されない。

## Todo追加と削除機能を追加

テキストエリアでEnterが押された時に`todo_list/add`にアクセスするようにする。`Todo`のテーブルに要素を追加する処理を書くつもり。また、Todoリストの各要素がクリックされた時に`todo_list/[TodoのId]/remove`にアクセスするようにする。ここでは`Todo`のテーブルから要素を削除する処理を書くつもり。

とりあえず外見だけ作ろう。`mysite/todo_list/templates/todo_list/index.html`を編集する。

`{% url 'todo_list:name' %}`を用いると、`urls.py`に書かれている`name`と照合してurlを生成してくれる。`{% csrf_token %}`はセキュリティ対策のために用いられるものらしいけど、この辺はまだ詳しくない。`{% url 'todo_list:name' todo.id %}`については`urls.py`にて説明する。

{{< highlight html >}}
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <title>Todo List</title>
  </head>
  <body>
    <h1>Todo List</h1>
    <form action="{% url 'todo_list:add' %}" method="post">
      {% csrf_token %}
      <input type="text" name="text" placeholder="What will you do?">
    </form>
    <ul>
      {% for todo in todos %}
      <li><a href="{% url 'todo_list:remove' todo.id %}">{{ todo.text }}</a></li>
      {% endfor %}
    </ul>
  </body>
</html>
{{< /highlight >}}

`mysite/todo_list/urls.py`を編集する。`<int:todo_id>`は特殊な文法で、ここには何かしらの整数が入る。この`todo_id`は``views.py`の引数として指定する。また`index.html`で書いていた`{% url 'todo_list:remove` todo.id %}`の`todo.id`に当たる数字がここに入って、`todo_list/[todo.idの値]/remove`というurlに解釈される。

{{< highlight python3 >}}
from django.urls import path

from . import views

app_name = 'todo_list'
urlpatterns = [
    path('', views.index, name='index'),
    path('add/', views.add, name='add'),
    path('<int:todo_id>/remove/', views.remove, name='remove'),
]
{{< /highlight >}}


`mysite/todo_list/views.py`を編集する。

`add`ビューではテーブルに要素を追加する。フォーム要素から`request.POST[name]`で、form部品の情報を取得できる。ここでのnameとは、form部品のname属性である。

`remove`ビューでは引数に`todo_id`を指定している。これは`urls.py`で指定していた`<int:todo_id>`と同じものである。`get_object_or_404`でTodoテーブルから`id==todo_id`となるものを探し出し、もし見つからなかったら`404`ページを表示する。`pk`というのはおそらく`primary key`の略で、デフォルトでは`id`が主キーになっているのだろう。

{{< highlight python3 >}}
from django.shortcuts import render, get_object_or_404
from django.http import HttpResponse, HttpResponseRedirect
from django.urls import reverse

from .models import Todo

# Create your views here.

def index(request):
    todos = Todo.objects.all()
    return render(request, 'todo_list/index.html', {'todos': todos})

def add(request):
    todo = Todo(text=request.POST['text'])
    todo.save()
    return HttpResponseRedirect(reverse('todo_list:index', args=()))

def remove(request, todo_id):
    todo = get_object_or_404(Todo, pk=todo_id)
    todo.delete()
    return HttpResponseRedirect(reverse('todo_list:index', args=()))
{{< /highlight >}}


これでまともなTodoリストができた。
{{< figure src="./01.png" width="50%" >}}

## スタイルの変更
せっかくなのでCSSでかっこいいUIにしたい。ということで編集する。

`mysite/todo_list/templates/todo_list/index.html`を編集する。`{% load static %}`で、`static`ディレクトリ以下をデータの探索対象に含めてくれるっぽい？`{% static 'todo_list/style.css' %}`は`/todo_list/style.css`と解釈されるっぽい。

{{< highlight html >}}
{% load static %}
<!DOCTYPE html>
<html lang="ja">
  <head>
    <meta charset="utf-8">
    <link rel="stylesheet" type="text/css" href="{% static 'todo_list/style.css' %}">
    <title>Todo List</title>
  </head>
  <body>
    <div class="wrapper">
      <h1>Todo List</h1>
      <form action="{% url 'todo_list:add' %}" method="post">
        {% csrf_token %}
        <input type="text" name="text" placeholder="What will you do?">
      </form>
      <ul>
        {% for todo in todos %}
        <li><a href="{% url 'todo_list:remove' todo.id %}">{{ todo.text }}</a></li>
        {% endfor %}
      </ul>
    </div>
  </body>
</html>
{{< /highlight >}}

HTML上で`todo_list/style.css`と解釈されているファイルは、実際には`mysite/todo_list/static/todo_list/style.css`に置かれている。ということでそれを作成し、内容を以下のようにする。

{{< highlight css >}}
* {
  box-sizing: border-box;
}
body {
  padding: 10px 30%;
  font-family: sans-serif;
  background-color: #eee;
}
.wrapper {
  padding: 20px 50px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background-color: #fff;
  border-radius: 10px;
  box-shadow: 5px 5px 5px rgba(0, 0, 0, 0.4);
}
h1 {
  color: #333;
}

form {
  width: 100%;
}

input[type="text"] {
  height: 40px;
  width: 100%;
  padding: 0 0 0 10px;
  font-size: 1.2em;
  outline: none;
  border: none;
  border-bottom: 3px dotted #ccc;
  color: #555;
}

ul {
  width: 100%;
  margin: 0;
  padding: 0;
  list-style-type: none;
}

li {
  width: 100%;
  padding: 0 0 0 10px;
  margin: 0;
  height: 40px;
  line-height: 40px;
}

li:first-child {
  margin-top: 20px;
}

li a {
  text-decoration: none;
  font-size: 1.5em;
  color: #555;
}
{{< /highlight >}}

`$ python3 manage.py runserver`でサーバーを再起動した方が良いかもしれない。そうするとCSSが反映されている。ここでは`style.css`の完成形を一気に見せてしまったが、実際には、Webページ上での表示を確認しながらCSSを作っていくことになるだろう。

{{< figure src="./02.png" >}}


## 参考

[Django Tutorial](https://docs.djangoproject.com/ja/2.2/intro/)
