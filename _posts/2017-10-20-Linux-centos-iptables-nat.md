---
layout: post
title: "防火墙之NAT表（附实验）"
description: "对SNAT,DNAT的功能进行介绍，并进行模拟实验"
categories: [centos6，centos7,service]
tags: [linux,iptables,nat]
redirect_from:
  - /2017/10/20/
---

### 一、背景介绍
在我们在利用私网主机去链接外网主机的时候，向路由器发送访问外网某个主机的请求，路由器收到后根据路由表会转发给外网目标主机，这个过程是没有问题的，但是当外网的目标主机向私网发送回应报文的时候，由于私网地址是无法在其路由中定义的，所以回应报文是无法到达私网主机的。这样就无法实现私网主机访问外网的要求，同理外网也是无法主动访问我们的内部私网的；NAT表就是为了解决这个问题，可以进行网络地址转换。
如下图：
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/1.png" width="900px"/>
</center>

### 二、NAT: network address translation
该表作用在PREROUTING，INPUT，OUTPUT，POSTROUTING，这四条链上
请求报文：修改源/目标IP，由NAT定义如何修改
响应报文：修改源/目标IP，根据跟踪机制自动实现
分为以下几种类型：
SNAT DNAT 

### 三、SNAT:source network address translation
#### 1.介绍：
作用在POSTROUTING, INPUT链上，让本地网络中的主机通过某一特定地址访问外部网络，实现地址伪装；之所以叫源网络地址转换，是根据请求报文的角度来定义的，转换的是请求报文中的源地址。
#### 2.具体流程：
私网地址的一个主机A，想要访问外网的一个服务器C，中间需要SNAT即B进行网络地址转换。首先主机A会将请求报文发经由B，B在收到以后，看到报文是发送给外网主机C的，会先将主机A的私网IP转换为B的公网IP（源地址转换），然后查询路由表，寻找路径将请求报文，发送给外网服务器C，C收到后会认为该请求报文是B发来的，源地址是B的公网IP，然后其构建响应报文，在响应报文中，源地址是C的IP,目标地址是B的地址，B在收到响应报文后，会将公网IP地址转换回主机A的私网地址，再查询路由，将回应报文发给私网主机A的IP地址。这样就实现了私网访问公网。
#### 3.地址转换表：
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E8%A1%A81.jpg" width="900px"/>
</center>

#### 4.通过PREROUTING链控制：
#### (1) 原因：
外网访问内网，真正的目标地址是内网地址，但是请求报文中目标地址是B。当请求到达B的时候，这时候是不能经过nat服务器上的路由，如果经过，由于还没有转换地址回目标内网地址，路由发现这个目标地址就是本机地址，就不会再转发给内网地址，因此要进行路由前控制。
#### (2) 语法和选项：
`iptables -t nat -A PREROUTING -d ExtIP -p tcp|udp --dport PORT -j DNAT --to-destination InterSeverIP[:PORT]` 
#### (3) 举例：
`iptables -t nat -A PREROUTING -s 0/0 -d 172.18.100.6 -p tcp --dport 22 -j DNAT --to-destination 10.0.1.22`
`iptables -t nat -A PREROUTING -s 0/0 -d 172.18.100.6 -p tcp --dport 80 -j DNAT --to-destination 10.0.1.22:8080`
#### 5.	MASQUERADE：动态IP，如拨号网络
#### (1) 简介
对于SNAT技术，默认是将源地址转换为了一个固定IP，这样在面对诸如拨号网络的动态IP就不适用，不可能每次都执行一次绑定IP，为了解决这个问题就出现了MASQUERADE技术，不绑定固定IP，直接绑定网卡。
#### (2) 语法和选项：
`iptables -t nat -A POSTROUTING -s LocalNET ! -d LocalNet -j MASQUERADE --to-ports port[-port]` 
#### (3) 举例：
`iptables -t nat -A POSTROUTING -s 10.0.1.0/24 ! – d 10.0.1.0/24 -j MASQUERADE`
>注：从上面命令可以看出，命令中并没有指定是哪个网卡，那怎么识别哪块网卡是我们需要的呢？解释这个之前，我们先看一个例子，假设有一天警察收到了一个钱包，这个是一位好心人捡来主动上交的，失主想找到捡到钱包的人，并奖励一辆马萨拉蒂，于是就拜托警察进行调查，经过缜密的调查，确定了三个人：你，我还有小明，警察确定是我们三人中的一个捡到了钱包，但是并不确定是哪一个；这时候，小明说那天他在忙着睡觉，我说那天我在忙着发呆，我和小明都有不在场的证据，最后警察确定了你就是那个捡到钱包的人，于是你得到了失主奖励的一辆马萨拉蒂。
>在这个例子中，我们不需要直接确定哪位捡到了钱包，而是用来排除法，应用到确定需要绑定的网卡上来，就是已知三个网卡（每个网卡是一个不同网段）里面必定有一个是我们需要的外网网卡，其中A和B都不是，那么C肯定就是了，所以我们在指定的时候不需要直接指定C，只需要指定A和B不是就行了，再具体点，就是指定A和B都是源，那么剩下的这个C那就肯定是用来替换源的网卡。
>于是如果有三个网段对应三个不同网段，那我们就要这样写：
>`iptables -t nat -A POSTROUTING -s LocalNETA，LocalNETB  -j MASQUERADE`

### 四、DNAT：destination network address translation
#### 1.介绍：
作用在 PREROUTING , OUTPUT 链上，把本地网络中的主机上的某服务开放给外部网络访问(发布服务和端口映射)，但隐藏真实IP。之所以称之为目标网络地址转换也是根据请求报文的角度来定义的，转换的是请求报文中的目标地址。
#### 2.具体流程：
私网内的主机A是一台web服务器，现在它向开放这个服务，让外网的主机C能够访问本服务。这时候就要用到DNAT，外网的主机C向B发送请求报文，B再转发给私网服务器A；首先，C构建请求报文，其中源地址是自己IP，目标地址是B，在B收到了C的请求报文后，会将请求报文中的目标地址，即B的公网地址，转换为私网地址A的IP，然后经由路由再发送给服务器A，这时候有个问题，B是怎么知道要将C的访问转发给A呢，如果在私网内还有一个ftp服务器D，B为什么不会将请求报文发给D呢？其实为了防止这种现象的产生，我们在配置的时候，已经指明了外网所有主机只要访问B的IP地址，加上某个端口的时候，例如2222，B就会自动识别将发送到该端口的请求报文发送给A，这样就实现了请求报文的转发。，服务器A收到请求报文后，会构建响应报文，其中目标地址是C的地址，源地址是自己A的IP，再经由B的时候，B会将回应报文中的源地址再度转换回B的公网地址，然后再经由路由发送给A，A一直打交道是B。这样就实现了让外网主机，访问私网服务。
#### 3.地址转换表：
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E8%A1%A82.jpg" width="900px"/>
</center>

#### 4.通过PREROUTING链控制：
#### (1) 原因：
外网访问内网，真正的目标地址是内网地址，但是请求报文中目标地址是B。当请求到达B的时候，这时候是不能经过nat服务器上的路由，如果经过，由于还没有转换地址回目标内网地址，路由发现这个目标地址就是本机地址，就不会再转发给内网地址，因此要进行路由前控制。
#### (2) 语法和选项：
`iptables -t nat -A PREROUTING -d ExtIP -p tcp|udp --dport PORT -j DNAT --to-destination InterSeverIP[:PORT]` 
#### (3) 举例：
`iptables -t nat -A PREROUTING -s 0/0 -d 172.18.100.6 -p tcp --dport 22 -j DNAT --to-destination 10.0.1.22`
`iptables -t nat -A PREROUTING -s 0/0 -d 172.18.100.6 -p tcp --dport 80 -j DNAT --to-destination 10.0.1.22:8080`

### PNAT：port nat，端口和IP都进行修改（针对的是内访问外）
#### 1.介绍
该技术针对的是SNAT出现问题的一种解决方法。在我们私网的主机访问外网的时候，除了IP之外还会随机打开一个端口，经由B的时候，SNAT只会转换IP不会转换端口，如果私网内有两台主机A和D的端口打开的一样是1111，就会出现这样一个问题，在经过B的SNAT转换去访问C的时候，C收到的两条来自相同IPB:1111的请求报文，它无法分辨这是来自两台不同的主机；为了解决这个问题就出现了PNAT技术，在B对源地址进行转换的时候同时转换端口，这样保证了C收到的请求报文不会出现相同IP加相同端口的情况，以便两调主机都能收到各自的回应报文，实现链接外网的要求。
#### 2.地址转换表
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/3.jpg" width="900px"/>
</center>

### 五、实验：实现SNAT和DNAT
#### 1.实验目的
通过一台主机B做SNAT和DNAT，分别实现内网主机A访问外网主机C，外网主机C访问内网主机A，并在最后实现REDIRECT功能。
#### 2.实验图示
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/2.png" width="900px"/>
</center>

#### 3.实验环境
#### (1) 第一台主机A，在内网，IP地址为192.168.65.69
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/3.png" width="900px"/>
</center>

##### (2) 第二台主机B，有两个网卡，一个链接内网，地址为192.168.65.68；一个链接外网，地址为172.18.65.68
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/4.png" width="900px"/>
</center>

#### (3) 第三台主机C，在外网，地址为172.18.65.74
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/5.png" width="900px"/>
</center>

#### 4.实现SNAT
#### (1) 为A主机配置路由表
A主机想要访问外网，那么其网关需要指向B主机的内网地址
{% highlight javascript linenos=table %}
[root@hostA ~]# ip route add default via 192.168.65.68 #指定网关
[root@hostA ~]# route -n #查看路由表
{% endhighlight %}

这时候主机A是可以ping通主机B的外网地址，但是无法ping通主机C
{% highlight javascript linenos=table %}
[root@hostA ~]# ping 172.18.65.68 #可以ping通
[root@hostA ~]# ping 172.18.65.74 #不可以ping通
{% endhighlight %}

>注：不需要为C机器配置路由。因为经过B的地址转换，私网IP转为了公网IP，而B的公网IP和C的IP同出一个网段，而且A看到的请求报文是来自B的公网IP，因此回应报文也是向B的公网IP发送。

#### (2) 在主机B开启路由，以及做SNAT策略
{% highlight javascript linenos=table %}
[root@hostB ~]# echo 1 > /eproc/sys/net/ipv4/ip_forward #开启B主机的路由转发功能
[root@hostB ~]# iptables -t nat -A POSTROUTING -s 192.168.0.0/16 -j SNAT --to-source 172.18.65.68 #在B主机加SNAT策略
{% endhighlight %}
#### (3) 在主机A上进行测验，在主机C上抓包，并测验
{% highlight javascript linenos=table %}
[root@hostA ~]# ping 172.18.65.74 #在主机A进行ping测验，正常是能够ping通的
[root@hostC ~]# tcpdump -i ens33 -nn icmp #在主机C上进行抓包，正常是可以看到源地址是B主机的IP
[root@hostC ~]# ping 192.168.65.69 #在C主机上测试，正常是能够ping通的
{% endhighlight %}

#### 5.实现DNAT
开始之前，因为DNAT一般应用于发布自己私网内某个服务器上的符，例如web服务，让外网能够进行访问，所以一般服务都要有一个端口来确定，所以我们要在内网主机A搭建httpd服务，我们将端口修改为8080端口，对应B进行替换的时候也要指定端口，由于客户在访问httpd服务的时候，浏览器会默认访问80端口，所以我们就指定，外网客户C在访问B的80端口时，B就将访问请求转扫A端口8080处理。

#### (1) 为主机A搭建web服务，并改端口为8080
{% highlight javascript linenos=table %}
[root@hostA ~]# yum -y install httpd #安装服务
[root@hostA ~]# echo “you had already got this web”  > /var/www/html/index.html #更改网站主页文件
[root@hostA ~]# vim /etc/httpd/conf/httpd.conf #修改http服务的端口，绑定到本主机地址上
Listen 192.168.56.69:8080
[root@hostA ~]# service httpd restart #重启服务
[root@hostA ~]# lsof -i  :8080 #查看8080端口是由哪个服务监听
[root@hostA ~]# ss -ntlp #这个命令也可以达到上面的效果
{% endhighlight %}

#### (2) 在主机B设置防火墙DNAT策略
{% highlight javascript linenos=table %}
[root@hostB ~]# iptables -t nat -A PREROUTING -s 0/0 -d 172.18.65.68 -p tcp --dport 80 -j DNAT --to-destination 192.168.65.69:8080 #在主机B上设置DNAT策略
{% endhighlight %}

#### (3) 在主机C上进行测试，并查看主机A的访问日志
{% highlight javascript linenos=table %}
[root@hostC ~]# curl 172.18.65.68:80 #在C主机上利用curl命令访问A主机，正常应该显示下面内容
you had already got this web
[root@hostA ~]# cat  /var/log/httpd/access_log #在A主机上查看访问日志，源地址正常应该是C的IP
{% endhighlight %}

>注：可以看到，和SNAT相同点在于，无论是私网访问外网，还是外网访问私网，外网主机C始终不知道自己真正打交道的私网主机A的真实IP，私网主机A就想是一个幕后老大，主机B就是其手下，帮其和外网主机C打交道，这样隐藏了其真实身份，保证了其安全性。

### 六、事后总结
DNAT的功能有点像调度器的作用，把不同外网请求调度给内网的不同服务器，但是其缺陷在于：当我们有多个web服务器的时候，DNAT不能实现对外部的访问请求分别调度给不同web服务器。在客户访问web服务器的时候，一般默认都是80端口，但是DNAT上的80端口只能对应内网的一个web服务器端口，不能绑定多个web服务器端口，这也就无法实现调度给不同web服务器的要求了。因此，DNAT技术并不适合作为调度器使用，LVS就可以解决这个问题，有机会我们在进行深度探讨。
NAT在防火墙上的实现其实非常简单，就两条命令，但是我们不能“好读书不求甚解”，应该认真理解其中的原理，不然就不算是一个合格的共产主义接班人了。本文写的只是本人自己的理解，其中的一些理解不能保证百分百正确，如果错误还请不吝赐教，让我们共同进步。