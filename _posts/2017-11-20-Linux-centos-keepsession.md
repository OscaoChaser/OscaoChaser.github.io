---
layout: post
title: "Keep Session的三种方式以及模拟实现"
description: "本篇介绍三种保持会话的方式，以及用Memcached当做会话服务器，实现会话保持"
categories: [centos7,service]
tags: [linux,Nginx,Tomcat,Memcached,Keep Session]
redirect_from:
  - /2017/11/20/
---

### 一.前情提要
在开始会话保持之前，我们要首先了解为什么要进行会话保持，或者说，会话保持的意义何在。其实，在实际生活中，电商网站常常面临这样的要求：相同客户的用户身份认证方面或者商品交易方面的交互信息，需要通过相同服务器去处理，而不能被分别调度到不同服务器；这是因为，如果进行了调度，那么可能有关用户的交易信息就会不完整，这会导致交易完全无法进行。我么将来自相同客户端的请求，转发至后端相同的服务器进行处理这个称之为会话保持。因此，实现会话保持，是一个重要的需求。

### 二.实现会话保持的方式

在不断的发展过程中，产生了众多解决会话保持问题的方案，在了解这三种方式之前，我们先看一下一个简单的网站构建拓扑。

<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E7%AE%80%E5%8D%95%E7%BD%91%E7%AB%99%E6%9E%B6%E6%9E%84.png" width="700px"/>
</Center>

根据不同的设置，实现会话保持分为以下三类：
- (1)**在调度器上进行设置**，将相同的会话发送到后端的相同动态服务器上；称之为会话粘滞(session sticky);会话粘滞根据实现方式不同，又分为基于源地址和基于Cookie两类。其中，调度器有Hapoxy，Httpd和Nginx等。
但该方案不常用，基于源地址会发生源地址IP变化而导致会话无法保持的情况出现，基于Cookie会出现后端服务器宕机会话无法保持的情况出现。
- (2)**在动态服务器上进行设置**，将所有的会话信息保持在所有的动态服务器上；称之为会话集群(session cluster)。其中，动态服务器有php-fpm和Tomcat等。
该方案也不常用，虽然解决了上述两个问题，但是当会话信息非常多的时候，由于集群内每个服务器都要拥有所有的会话信息，这严重耗费了资源。
- (3)**单独设置会话保持服务器**，将来自相同请求的会话单独存储；称之为会话服务器(session server)。其中，会话服务器有Redis和Memcached等。
该方案常用，解决了上述所有问题，但需要注意的是，该方案强依赖会话服务器，最好设置会话服务器的集群。

### 三.会话保持实验
我们直接模拟第三种方式，即设置单独的会话服务器来实现会话保持

#### 1.实验目的

通过设置单独的会话服务器来实现会话保持；其中调度器可以将会话请求调度到任意动态服务器，后端会话服务器为动态服务器提供会话信息存储以及实现保持；而且动态服务器和后端会话服务器不会产生单点失败。

#### 2.实验架构

<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E4%BC%9A%E8%AF%9D%E6%9C%8D%E5%8A%A1%E5%99%A8%E6%9E%B6%E6%9E%84.png" width="900px"/>
</Center>

#### 3.实验准备

|-----------------------------+-----------------+----------------|
| 服务器			              |	IP地址  	        |     主机名	     |
|-----------------------------|:----------------+---------------:|
| 前端调度器 Httpd node1 	  |172.18.65.71/16  |www.oscao.com   |
| 会话服务器 Memcached-n1 node2|172.18.65.72/16  |node2.oscao.com |
| 会话服务器 Memcached-n2 node3|172.18.65.73/16  |node3.oscao.com |
| 动态服务器 TomcatA node4     |172.18.65.74/16  |node4.oscao.com |
| 动态服务器 TomcatB node5     |172.18.65.75/16  |node5.oscao.com |
|-----------------------------+-----------------+----------------|

#### 4.实验步骤

#### 第一步，实验准备

{% highlight javascript linenos=table %}
#安装需要软件
##在node1安装httpd
[root@node1 ~]# yum -y install httpd
##在node2和node3安装Memcached
[root@node2 ~]# yum -y install memcached
[root@node3 ~]# yum -y install memcached
##在node4和node5安装Tomcat
[root@node4 ~]# yum -y install tomcat tomcat-webapps #tomcat-webapps是网页测试包
[root@node5 ~]# yum -y install tomcat tomcat-webapps


#下载实现会话保持需要的jar包，并放在/usr/share/java/tomcat目录下
##会话管理器包
memcached-session-manager-2.1.1.jar
memcached-session-manager-tc7-2.1.1.jar
##流式化工具包
asm-5.2.jar
kryo-4.0.1.jar
minlog-1.3.0.jar
objenesis-2.6.jar
kryo-serializers-0.42.jar
msm-kryo-serializer-2.1.1.jar
reflectasm-1.11.3.jar
reflectasm-1.11.3-shaded.jar
##通信包
spymemcached-2.12.3.jar
##下载地址
https://github.com/magro/memcached-session-manager/wiki/SetupAndConfiguration


#为两台Tomcat主机提供测试页面
##TomcatA,node4
[root@node4 ~]# mkdir -pv /var/lib/tomcat/webapps/tomcat/{classes,WEB-INF,META-INF}
[root@node4 ~]# vim /var/lib/tomcat/webapps/tomcat/index.jsp
        <%@ page language="java" %>
        <html>
            <head><title>TomcatA</title></head>
            <body>
                <h1><font color="red">TomcatA.oscao.com</font></h1>
                <table align="centre" border="1">
                    <tr>
            <td>Session ID</td>
                    <% session.setAttribute("oscao.com","oscao.com"); %>
            <td><%= session.getId() %></td>
                    </tr>
                    <tr>
            <td>Created on</td>
            <td><%= session.getCreationTime() %></td>
                    </tr>
                </table>
            </body>
        </html>

##TomcatB,node5
[root@node5 ~]# mkdir -pv /var/lib/tomcat/webapps/tomcat/{classes,WEB-INF,META-INF}
[root@node5 ~]# vim /var/lib/tomcat/webapps/tomcat/index.jsp
        <%@ page language="java" %>
        <html>
            <head><title>TomcatB</title></head>
                <body>
                <h1><font color="blue">TomcatB.oscao.com</font></h1>
                <table align="centre" border="1">
                    <tr>
            <td>Session ID</td>
                    <% session.setAttribute("oscao.com","oscao.com"); %>
            <td><%= session.getId() %></td>
                    </tr>
                    <tr>
            <td>Created on</td>
            <td><%= session.getCreationTime() %></td>
                    </tr>
                </table>
                </body>
        </html>


#同步各个服务器时间
[root@node1 ~]# ntpdate 172.18.0.1
[root@node2 ~]# ntpdate 172.18.0.1
[root@node3 ~]# ntpdate 172.18.0.1
[root@node4 ~]# ntpdate 172.18.0.1
[root@node5 ~]# ntpdate 172.18.0.1


#关闭各服务器的防火墙和Selinux(所有主机)
[root@node1 ~]# systemctl stop firewalled
[root@node1 ~]# iptables -F
[root@node1 ~]# setenforce 0

{% endhighlight %}

#### 第二步，配置调度器Httpd

{% highlight javascript linenos=table %}
[root@node1 ~]# vim /etc/httpd/conf.d/proxy.conf
#设置调度策略
	<proxy balancer://tcsrvs>
		BalancerMember http://172.18.65.74:8080 loadfactor=1 #权重
		BalancerMember http://172.18.65.75:8080 loadfactor=1
		ProxySet lbmethod=byrequests #调度算法权重轮询
	</Proxy>
#设置调度服务器
	<VirtualHost *:80> #调度服务器监听所有IP，端口是80
		ServerName www.oscao.com #调度服务器的主机名
		ProxyVia On #在后端服务器发给客户端的响应报文中添加Via首部，首部内容为Via:www.oscao.com
		ProxyRequests Off #正向代理关闭
		ProxyPreserveHost On #保留客户端请求的HOST:主机名，可以让后端的主机名为这个主机名的主机回应该请求；这在后端服务器有多个虚拟主机的时候有用，让客户端请求的虚拟主机回应。
		<Proxy *> #反代所有请求
			Require all granted 
		</Proxy>
		ProxyPass / balancer://tcsrvs/ #将对本主机根的请求，代理至www.oscao.com:80,而不是本机的根响应请求
		ProxyPassReverse / balancer://tcsrvs/ #在发生重定向的时候，保留客户端请求信息，不会再向客户端发送重定向的主机地址，以免让客户端再次重新请求
		<Location /> #允许对根的访问
			Require all granted
		</Location>
	</VirtualHost> 

{% endhighlight %}

#### 第三步，配置动态服务器Tomcat

{% highlight javascript linenos=table %}
#配置Tomcat，在host中定义(node4和node5都要定义)
[root@node4|5 ~]# vim /etc/httpd/conf.d/proxy.conf
	<Context path="/tomcat" docBase="/var/lib/tomcat/webapps/tomcat" reloadable="true">
	    <Manager className="de.javakaffee.web.msm.MemcachedBackupSessionManager"
	        memcachedNodes="n1:172.18.65.72:11211,n2:172.18.65.73:11211"
	        failoverNodes="n1" #备用节点是n1，即n2(node3)是主节点
	        requestUriIgnorePattern=".*\.(ico|png|gif|jpg|css|js)$"
	        transcoderFactoryClass="de.javakaffee.web.msm.serializer.kryo.KryoTranscoderFactory"/>
	</Context>

{% endhighlight %}

#### 第四步，开启Memcached，进行网页测试

<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/memcached%E4%BC%9A%E8%AF%9D%E4%BF%9D%E6%8C%81%E6%B5%8B%E8%AF%95.gif" width="1000px"/>
</Center>

### 四.总结

利用Memcached作为会话缓存的优缺点：

#### 1.优点
- 基于K/V的内存存储，效率和性能优异。
- 使用的协议简单，文本协议和二进制协议两种。
- 预先分块存储，有效避免了内存碎片对服务性能的影响。

- 数据储存在内存，一旦宕机，数据就会丢失，需要做集群。
- 无法实现数据长久存储，即存储在磁盘上，这点不如Redis。
- 其K/V存储只支持存储可流式化数据（可序列化数据）。
- 提供的是旁挂式缓存服务，不能自己选择怎么存储，依赖智能客户端。只能是半分布式。

