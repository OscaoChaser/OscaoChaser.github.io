---
layout: post
title: "利用Github配合Jekyll搭建自己的博客网站"
description: "利用git和jekyll搭建自己的静态网站"
categories: [blog,service]
tags: [blog]
redirect_from:
  - /2017/1/28/
---

### 博客目的
之前一直想整理一下自己搭建博客网站的过程，但是一直没有时间，最近由于重新装了电脑系统，又买了一个新的域名，需要重新绑定域名，就顺便将自己搭建博客网站的过程重新整理一下。

### 搭建准备
利用Github+Jekyll模板来搭建网站的过程非常简单，大概的原理如下图：

<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%8D%9A%E5%AE%A2%E6%9E%B6%E6%9E%84.png" width="900px"/>
</Center>

1. 我们的网站想要展示给别人需要以下几个东东：首先要有一个服务器来存放我们网站上的代码，这个服务器的功能由Github来帮我们实现；其次我们需要一个域名能让别人在浏览器输入后访问到我们的网站，这个提供“路径”的功能，需要我们去阿里云购买；最后我们的网站需要一个模板来展示给别人，就像QQ空间里的皮肤一样，这个功能需要Jekyll来帮我们实现。
2. 而准备以上三样东西需要我们在一个环境中进行，这个环境需要我们下载三样东西，第一为Gitbash，第二为Ruby，第三是Jekyll。

### 具体步骤
下面，我们就一步一步来实现整个博客网站的搭建。

#### 第一步，在Ｇithub上创建仓库
在Github创建并登录后，按照官方指导，创建一个自己的仓库，这里我以自己的仓库OscaoChaser.github.io为例：

1，进入自己的个人主页，点击新建仓库
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%88%9B%E5%BB%BA%E4%BB%93%E5%BA%93%E7%AC%AC%E4%B8%80%E6%AD%A5.jpg" width="900px"/>
</Center>
2，给自己的仓库命名，并创建(注意要以github.io结尾)
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%88%9B%E5%BB%BA%E4%BB%93%E5%BA%93%E7%AC%AC%E4%BA%8C%E6%AD%A5.jpg" width="900px"/>
</Center>
这时候，我们就已经把仓库创建完成了，是不是特别简单，但是只有仓库还不行，我们还有两步，第一是申请一个域名，让别人可以通过域名访问到我们的网站(仓库)，第二就是我们要为仓库添加内容，让别在访问后可以看到我们的博客。

#### 第二步，在阿里云申请一个属于自己的域名
注册一个阿里云账号，登录后按照一下步骤进行域名申请：

1，注册账号并登陆，选择域名购买服务
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E6%B3%A8%E5%86%8C%E5%9F%9F%E5%90%8D%E7%AC%AC%E4%B8%80%E6%AD%A5.jpg" width="900px"/>
</Center>
2，选一个自己喜欢的域名并进行购买
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E6%B3%A8%E5%86%8C%E5%9F%9F%E5%90%8D%E7%AC%AC%E4%BA%8C%E6%AD%A5.jpg" width="900px"/>
</Center>
3，购买完成后进入控制台，开始配置我们的域名
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%9F%9F%E5%90%8D%E7%94%B3%E8%AF%B7%E7%AC%AC%E4%B8%89%E6%AD%A5.jpg" width="900px"/>
</Center>
4，选择为购买的域名配置解析
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%9F%9F%E5%90%8D%E7%94%B3%E8%AF%B7%E7%AC%AC%E5%9B%9B%E6%AD%A5.jpg" width="900px"/>
</Center>
5，配置要求如下
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E6%B3%A8%E5%86%8C%E5%9F%9F%E5%90%8D%E7%AC%AC%E4%BA%94%E6%AD%A5.jpg" width="900px"/>
</Center>

这时候，我们的域名申请工作就已经完成了，但是我们只在这里指明了仓库，同样的我们要在仓库配置界面，设置仓库是可以被访问的，这就像男女搞对象一样，男女双方都同意才能构建链接。

6，回到我们的仓库界面，开始配置
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%9F%9F%E5%90%8D%E7%94%B3%E8%AF%B7%E7%AC%AC%E5%85%AD%E6%AD%A5.jpg" width="900px"/>
</Center>
7，绑定我们的域名
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E5%9F%9F%E5%90%8D%E7%94%B3%E8%AF%B7%E7%AC%AC%E4%B8%83%E6%AD%A5.jpg" width="900px"/>
</Center>

#### 第三步，下载一个喜欢的Jekyll模板
我们域名和仓库都已经搞好了，剩下的就是为我们的仓库添加内容了，我们可以在这个网站下载很多Jekyll主题:[https://jekyllthemes.io/](https://jekyllthemes.io/ "点击下载Jekyll主题")，
下载完成后是一个zip格式的压缩文件，我们需要解压配置一下

1，将下载的zip文件解压到自己目录下，这里我解压到了自己的C盘

2，解压后将解压后的目录改名为我们Github的仓库名OsacoChaser.github.io，如下:
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E4%B8%8B%E8%BD%BD%E6%A8%A1%E6%9D%BF.jpg" width="900px"/>
</Center>


这里我们已经配置好了模板，但是我们还需要将这些在本地安装好的内容，推送到我们的Github上存下来，这样别人可以通过我们绑定的域名`www.ailinux.tech`访问到我们的网站。

#### 第四步，下载安装Gitbash，Ruby
Git的下载网址为:[http://gitforwindows.org/](http://gitforwindows.org/ "点击进入Gitbash下载界面") 


Ruby的下载网址为:[http://railsinstaller.org/en](http://railsinstaller.org/en "点击进入Ruby下载界面")

下载直接进行安装即可，这个过程非常简单，在这里就不再赘述！安装完成后，我们需要进入我们的OscaoChaser.github.io目录

1，进入目录后右键选择`git bash here`
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E4%B8%8B%E8%BD%BD%E5%AE%89%E8%A3%85git%E7%AC%AC%E4%B8%80%E6%AD%A5.jpg" width="900px"/>
</Center>
2，在命令行界面进行以下操作
 {% highlight javascript linenos=table %}
$ ruby -version  #查看一下ruby是否安装
ruby 2.3.3p222 (2016-11-21 revision 56859) [i386-mingw32]
$ bundle install #安装Jekyll环境，这个过程很慢，耐心等待
Fetching gem metadata from https://rubygems.org/...........
Fetching version metadata from https://rubygems.org/..
Fetching dependency metadata from https://rubygems.org/.
Resolving dependencies...
Fetching rake 10.5.0
Installing rake 10.5.0
Using public_suffix 3.0.1
Using bundler 1.15.3
Using colorator 1.1.0
Using ffi 1.9.18 (x86-mingw32)
Using forwardable-extended 2.6.0
Using rb-fsevent 0.10.2
Using ruby_dep 1.5.0
Using kramdown 1.16.2
Using liquid 4.0.0
Using mercenary 0.3.6
Fetching rouge 1.11.1
Installing rouge 1.11.1
Using safe_yaml 1.0.4
Using addressable 2.5.2
Using rb-inotify 0.9.10
Using pathutil 0.16.1
Using sass-listen 4.0.0
Using listen 3.1.5
Fetching sass 3.5.5
Installing sass 3.5.5
Fetching jekyll-watch 1.5.1
Installing jekyll-watch 1.5.1
Using jekyll-sass-converter 1.5.1
Fetching jekyll 3.5.2
Installing jekyll 3.5.2
Fetching jekyll-feed 0.9.2
Installing jekyll-feed 0.9.2
Fetching jekyll-redirect-from 0.12.1
Installing jekyll-redirect-from 0.12.1
Fetching jekyll-seo-tag 2.4.0
Installing jekyll-seo-tag 2.4.0
Fetching jekyll-sitemap 1.2.0
Installing jekyll-sitemap 1.2.0
Using simple-texture 0.2.2 from source at `.`
Bundle complete! 3 Gemfile dependencies, 27 gems now installed.
Use `bundle info [gemname]` to see where a bundled gem is installed.
{% endhighlight %}

3，在浏览器输入`localhost:4000`访问我们的本地博客
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E6%BC%94%E7%A4%BA%E8%AE%BF%E9%97%AE%E5%8D%9A%E5%AE%A2.gif" width="900px"/>
</Center>

#### 第五步，修改并提交我们的博客
我们的博客需要在读懂的目录下，根据固定的格式要求来进行书写，书写完成后还需要提交到我们的仓库才能让别人通过域名访问到，具体步骤如下：

1，进入固定的目录C:\OscaoChaser.github.io\_posts
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E4%BF%AE%E6%94%B9%E5%8D%9A%E5%AE%A2%E7%AC%AC%E4%B8%80%E6%AD%A5.jpg" width="900px"/>
</Center>

2，按照固定的格式修改我们的博客
<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E4%BF%AE%E6%94%B9%E5%8D%9A%E5%AE%A2%E7%AC%AC%E4%BA%8C%E6%AD%A5.jpg" width="900px"/>
</Center>

3，修改完成后，提交我们的博客到Github仓库
我们需要进入到目录:\OscaoChaser.github.io，然后右键`git
 bash here`进入gitbash界面，进行如下操作:
{% highlight javascript linenos=table %}

{% endhighlight %}


