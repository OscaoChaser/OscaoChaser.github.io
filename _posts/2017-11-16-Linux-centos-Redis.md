---
layout: post
title: "Redis的Replication,Sential和Cluster"
description: "本篇介绍分布式存储Redis的复制，高可用和集群并进行试验操作"
categories: [centos7,service]
tags: [linux,Redis,Replication,Sential,Cluster]
redirect_from:
  - /2017/11/16/
---

### 前情提要
Redis是一个开源的、基于内存和数据结构存储的工具，通常用于当做非关系型数据库、缓存、消息队列（中间件）。它支持的数据结构诸如strings、hashes、lists、set、sorted sets  with range queries, bitmaps, hyperloglogs和空间索引。Redis拥有內建的复制，Lua脚本，LRU算法，事务，持久存储，高可用和集群。可以说是一个非常强大的工具了。
<br/>
本文将从Redis的复制，高可用和集群三方面对其进行介绍，并简单介绍一下非关系型数据库的BASE。

### 非关系型数据库的BASE
在了解非关系型数据库的BASE特点之前，我们先来回顾一下关系型数据库事务的ACID特点。

#### 1.关系型数据的ACID
事务(Transaction)，一般是指要做的或所做的事情。在计算机术语中是指访问并可能更新数据库中各种数据项的一个程序执行单元(unit)。在计算机术语中，事务通常就是指数据库事务。<br/>
当一个事务被提交给了DBMS（数据库管理系统），则DBMS需要确保该事务中的所有操作都成功完成且其结果被永久保存在数据库中，如果事务中有的操作没有成功完成，则事务中的所有操作都需要被回滚，回到事务执行前的状态（要么全执行，要么全都不执行）;同时，该事务对数据库或者其他事务的执行无影响，所有的事务都好像在独立的运行。<br/>
并非任意的对数据库的操作序列都是数据库事务。事务应该具有4个属性：
-  原子性(Atomicity) ：事务作为一个整体被执行，包含在其中的对数据库的操作要么全部被执行，要么都不执行。
-  一致性(Consistency) ：事务应确保数据库的状态从一个一致状态转变为另一个一致状态。一致状态的含义是数据库中的数据应满足完整性约束。
-  隔离性(Isolation) ：多个事务并发执行时，一个事务的执行不应影响其他事务的执行；锁机制。
-  持久性(Durability) ：一个事务一旦提交，他对数据库的修改应该永久保存在数据库中。

事务必须要满足上述四个特点，而关系型数据库对事务的支持，使得对于安全性能很高的数据访问要求得以实现。

#### 2.非关系行数据库的BASE
在了解BASE之前我们先要了解一下ACP，所谓的ACP即Consistency(一致性),Availability(可用性),Tolerance of network Partition(分区容忍性),具体解释如下：

|-----------------+------------------------------------------|
| 特性		      |  要求									 |
|-----------------|:----------------------------------------:|
| C:一致性 		  | 要求多个数据节点上的数据一致；				 |
| A:可用性 	  	  | 要求用户发出请求后的有限时间范围内返回结果；	 |
| P:分区容忍性 	  | 要求网络发生分区后，服务依然可用；			 |
|-----------------+------------------------------------------|

CAP理论是用来描述分布式系统特性的；2000年，在PODC(Principle of Distributed Computing)会议上由Brewer所提出，该理论认为一个分布式系统不可能同时满足C、A、P三个特性，最多可同时满足其中两者；对大型网站，可用性与分区容忍性优先级要高于数据一致性，一般会尽量朝着 AP 的方向设计，然后通过其它手段保证对于一致性的商务需求。
<br/>
而BASE则是在ACP基础上演化而来的，有趣的是ACID的中文意思为酸，而BASE则是碱，二者真是相爱相杀，生生不息 -_-''。下面是BASE的相关解释：
- BA：Basically Available，即基本可用，这和ACID的高可用要求完全相反；
- S：Soft state，软状态/柔性事务，即状态可以在一个时间窗口内是不同步的，意味着异步是允许的；
- E：Eventually consistency，最终一致性，无论其过程如何，取得的最终数据必须是一致的；
复习过ACID，了解过BASE后，我们再来实现一下Redis的复制，高可用和集群，这些功能都是其內建的功能哦。

>注：有趣的地方在于，非关系型数据库NoSQL，指的并不是数据库中的数据没有任何关系，如何没有关系就不可能对数据进行操作了；所谓的非关系型数据库NoSQL是指Not Only SQL，即不仅仅是SQL，翻译为超级数据库比较合适，估计第一次进行中文命名的人也没有想到当年随意起的名字会给后来初学者带来困扰吧。哈哈~~

### 实验准备
在开始这三个实验之前，我们需要进行以下准备
####　三台主机
配置如下：

|-----------------+-----------------+----------------|
| 服务器			  |	IP地址  	        |     主机名	     |
|-----------------|:----------------+---------------:|
|  node1 	 	  |172.18.65.71/16  |node1.oscao.com |
|  node2		  |172.18.65.72/16  |node2.oscao.com |
|  node3		  |172.18.65.73/16  |node3.oscao.com |
|-----------------+-----------------+----------------|

#### 安装Redis

{% highlight javascript linenos=table %}
[root@node1 ~]# yum -y install redis
[root@node2 ~]# yum -y install redis
[root@node3 ~]# yum -y install redis
{% endhighlight %}

#### 同步时间

{% highlight javascript linenos=table %}
[root@node1 ~]# ntpdate 172.18.0.1
15 Nov 22:38:33 ntpdate[3084]: step time server 172.18.0.1 offset -28799.765126 sec
[root@node2 ~]# ntpdate 172.18.0.1
15 Nov 22:38:59 ntpdate[3137]: step time server 172.18.0.1 offset -28799.772499 sec
[root@node3 ~]# ntpdate 172.18.0.1
15 Nov 22:39:02 ntpdate[1487]: step time server 172.18.0.1 offset -28799.409097 sec
{% endhighlight %}

#### 实现互相之间基于非对称密钥的登录

{% highlight javascript linenos=table %}
#在node1生成秘钥对
[root@node1 ~]# ssh-keygen -t rsa -P '' 
Generating public/private rsa key pair.
Enter file in which to save the key (/root/.ssh/id_rsa): 
Your identification has been saved in /root/.ssh/id_rsa.
Your public key has been saved in /root/.ssh/id_rsa.pub.
The key fingerprint is:
SHA256:dQ6k6aKMLrVvXIG8ZyuJLpqay7cNWp19snjPGeSWkdo root@node1.oscao.com
The key's randomart image is:
+---[RSA 2048]----+
|          .      |
|         +       |
|   . .  o o .    |
|    o .. ..+     |
|     ...S+  .    |
|  .oo.*.= o      |
| ..*oB = E       |
|++=.B o.* o      |
|OB++o+...+       |
+----[SHA256]-----+

#将秘钥对分别copy至其他主机，实现三台主机用同一对公钥和私钥
[root@node1 ~]# for i in 72 73; do ssh-copy-id -i /root/.ssh/id_rsa.pub root@172.18.65.$i;done
/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/root/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
root@172.18.65.72's password: 

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'root@172.18.65.72'"
and check to make sure that only the key(s) you wanted were added.

/usr/bin/ssh-copy-id: INFO: Source of key(s) to be installed: "/root/.ssh/id_rsa.pub"
/usr/bin/ssh-copy-id: INFO: attempting to log in with the new key(s), to filter out any that are already installed
/usr/bin/ssh-copy-id: INFO: 1 key(s) remain to be installed -- if you are prompted now it is to install the new keys
root@172.18.65.73's password: 

Number of key(s) added: 1

Now try logging into the machine, with:   "ssh 'root@172.18.65.73'"
and check to make sure that only the key(s) you wanted were added.

#手动验证互相登录
[root@node1 ~]# ssh root@172.18.65.72
Last login: Sat Nov 18 16:28:09 2017 from 172.18.65.108
[root@node2 ~]# 

[root@node1 ~]# ssh root@172.18.65.73
Last login: Sat Nov 18 16:28:11 2017 from 172.18.65.108
[root@node3 ~]# 

{% endhighlight %}

### Redis的Replication实验

#### 3.实验架构
<img src="http://oy4e0m51m.bkt.clouddn.com/redis%E4%B8%BB%E4%BB%8E%E5%A4%8D%E5%88%B6.png" width="700px"/>

一台作为主节点，另两台台作为从节点来同步复制主节点的数据。配置如下：

|-----------------+-----------------+----------------|
| 服务器			  |	IP地址  	        |     主机名	     |
|-----------------|:----------------+---------------:|
| 主节点 node1 	  |172.18.65.71/16  |node1.oscao.com |
| 从节点 node2	  |172.18.65.72/16  |node2.oscao.com |
| 从节点 node3	  |172.18.65.73/16  |node3.oscao.com |
|-----------------+-----------------+----------------|

#### 2.实验步骤

####第一步，配置主节点

{% highlight javascript linenos=table %}
#配置主节点相关信息
[root@node1 ~]# vim /etc/redis.conf 
requirepass 123456 #为主节点设定密码
bind 0.0.0.0 #设置监听地址
port 6379 #设置监听端口
[root@node1 ~]# systemctl start redis

#为主节点写入部分数据
127.0.0.1:6379> SELECT 15
OK
127.0.0.1:6379[15]> SADD anmial tiger dog cat bear lion deer monkey
(integer) 7
127.0.0.1:6379[15]> SMEMBERS anmial
1) "tiger"
2) "dog"
3) "bear"
4) "monkey"
5) "deer"
6) "cat"
7) "lion"
{% endhighlight %}

>注：Redis主从复制的实现有两种方式。第一种即RDB(snapshotting)，在第一次进行主从复制的时候直接快照主节点的状态，不进行任何修改，传给从节点进行恢复，随后主节点发生的任何变化都会同步到从节点,这种不必要经过先保存在磁盘上成为文件再进行传输，对网络依赖较大；第二种即AOF(Append Only File)，把主节点进行的各种操作保存成文件，再发送给从节点，在从节点完成‘重放’，恢复数据。

#### 第二步，配置从节点
配置从节点的方法有两种，第一种是直接在配置文件中写入参数，然后再启动Redis；第二种是在Redis命令行界面进行操作；我们选择第二种

{% highlight javascript linenos=table %}
#配置从节点1
[root@node2 ~]# systemctl start redis
[root@node2 ~]# redis-cli
127.0.0.1:6379> SLAVEOF 172.18.65.71 6379 #指明主节点的地址和端口
OK
127.0.0.1:6379> CONFIG SET masterauth 123456 #指明主节点的认证密码
OK
127.0.0.1:6379> CONFIG SET requirepass 123456 #为从节点设定密码
OK
127.0.0.1:6379> CONFIG REWRITE #将配置写入配置文件
OK

#配置bind和port是不支持在命令行修改的，要在配置文件中修改
[root@node2 ~]# vim /etc/redis.conf 
bind 0.0.0.0 
port 6379 
[root@node2 ~]# systemctl restart redis

#查看从节点1的Replication的信息
127.0.0.1:6379[15]> INFO Replication
# Replication
role:slave
master_host:172.18.65.71
master_port:6379
master_link_status:up
master_last_io_seconds_ago:1
master_sync_in_progress:0
slave_repl_offset:3115
slave_priority:100
slave_read_only:1
connected_slaves:0
master_repl_offset:0
repl_backlog_active:0
repl_backlog_size:1048576
repl_backlog_first_byte_offset:0
repl_backlog_histlen:0

#查看数据是否同步
127.0.0.1:6379> SELECT 15
OK
127.0.0.1:6379[15]> SMEMBERS anmial
1) "tiger"
2) "cat"
3) "dog"
4) "deer"
5) "bear"
6) "lion"
7) "monkey"

#配置从节点2的方法和上述一样，此处不再赘述

#最终在主节点上查看一下Replication信息
127.0.0.1:6379[15]> INFO Replication
# Replication
role:master
connected_slaves:2
slave0:ip=172.18.65.72,port=6379,state=online,offset=3437,lag=1
slave1:ip=172.18.65.73,port=6379,state=online,offset=3437,lag=1
master_repl_offset:3437
repl_backlog_active:1
repl_backlog_size:1048576
repl_backlog_first_byte_offset:2
repl_backlog_histlen:3436

{% endhighlight %}

### Redis的Sentinel实验
上面的实验实现了主从复制，当主节点的数据发生变化时，从节点的数据就会随之更新，但是这时候的主节点存在单点失败的问题，万一主节点出了故障，那整个服务就会无法使用，如何保证主节点的高可用性呢?Redis自身提供给了我们一个sentinel工具来实现这个需求。
<br/>
Sentinel主要完成三个功能：监控、通知、自动故障转移，它只监督主节点，当主节点失败，提拔一个从节点为主，以保证主节点的高可用。
<br/>
Sentinel通过流言协议来判定主节点是否失败，它本身也是一个集群，在其集群内多数sentinel认为主节点失败，主节点就会被确定为不可用。这个过程通过投票机制来实现，规定超过半数的票数为真，这就要求集群内有投票权的sentinel数量必须为奇数。
<br/>
由于Sentinel也是一个独立的服务，监听在不同的端口，因此我们在实验时没有必要进行单独再列出三个主机作为其集群，我们把Redis主从复制的三台主机设置为Sentinel集群即可。

#### 1.实验架构：
<img src="http://oy4e0m51m.bkt.clouddn.com/2017-11-16_154045.png" width="700px"/>

在上个Replication实验的基础上，再搭建Sentinel集群，配置如下：

|-----------------+-----------------+----------------|
| 服务器			  |	IP地址  	        |     主机名	     |
|-----------------|:----------------+---------------:|
| sentinel1 node1 |172.18.65.71/16  |node1.oscao.com |
| sentinel2 node2 |172.18.65.72/16  |node2.oscao.com |
| sentinel3 node3 |172.18.65.73/16  |node3.oscao.com |
|-----------------+-----------------+----------------|

#### 2.实验步骤

#### 第一步，配置sentinel

{% highlight javascript linenos=table %}

#配置主节点上的sentinel1
[root@node1 ~]# vim /etc/redis-sentinel.conf
bind 0.0.0.0 #指定监听的IP；监听本地所有地址
port 26379 #通过26379来监控6379
sentinel monitor myreplication 172.18.65.71 6379 2 #指定监控的集群主节点地址，端口和至少有两个节点同时判定主节点故障时，才认为其真的故障(因为Sentinel集群有三个)
sentinel auth-pass myreplication 123456 #指定的监控的复制集群的的密码
sentinel down-after-milliseconds myreplication 5000 #监控到指定的集群的主节点异常状态持续多久方才将标记为“故障”
sentinel parallel-syncs myreplication 2 #在主节点（故障）转移过程中，新主节点能够被从节点并行请求同步的数量
sentinel failover-timeout myreplication 180000 #必须在此指定的时长内完成故障转移操作，否则，将视为故障转移操作失败。

#将该配置文件给所有的sentinel集群中的主机各提供一份，这里用scp直接覆盖
[root@node1 ~]# scp /etc/redis-sentinel.conf  root@172.18.65.72:/etc/
[root@node1 ~]# scp /etc/redis-sentinel.conf  root@172.18.65.73:/etc/

{% endhighlight %}

#### 第二步，启动sentinel的集群，并检查状态

{% highlight javascript linenos=table %}
[root@node1 ~]# systemctl start redis-sentinel.service
[root@node1 ~]# lsof -i :26379
COMMAND    PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
redis-sen 5047 redis    4u  IPv6  58043      0t0  TCP *:26379 (LISTEN)
redis-sen 5047 redis    5u  IPv4  58044      0t0  TCP *:26379 (LISTEN)

[root@node2 ~]# systemctl start redis-sentinel.service 
[root@node2 ~]# lsof -i :26379
COMMAND    PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
redis-sen 5112 redis    4u  IPv6  62690      0t0  TCP *:26379 (LISTEN)
redis-sen 5112 redis    5u  IPv4  62691      0t0  TCP *:26379 (LISTEN)

[root@node3 ~]# systemctl start redis-sentinel.service 
[root@node3 ~]# lsof -i :26379
COMMAND    PID  USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
redis-sen 3435 redis    4u  IPv6  44966      0t0  TCP *:26379 (LISTEN)
redis-sen 3435 redis    5u  IPv4  44967      0t0  TCP *:26379 (LISTEN)

#通过sentinel的客户端工具查看监控状况(连接集群内的任意sentinel皆可)
[root@node1 ~]# redis-cli -h 172.18.65.71 -p 26379
172.18.65.71:26379> SENTINEL masters #查看集群内主节点信息
1)  1) "name" #集群名
    2) "myreplication"
    3) "ip" #主节点地址
    4) "172.18.65.71"
    5) "port" #端口
    6) "6379"
    7) "runid"
    8) "342aca2b26ed8716711c9b199f52c08a722f59fc"
    9) "flags" #标记，可以看到是主节点
   10) "master"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "928"
   19) "last-ping-reply"
   20) "928"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "7769"
   25) "role-reported"
   26) "master"
   27) "role-reported-time"
   28) "88133"
   29) "config-epoch"
   30) "0"
   31) "num-slaves" #有几个从节点
   32) "2"
   33) "num-other-sentinels" #有几台sentinel
   34) "2"
   35) "quorum" #sentinel的投票生效最低限制
   36) "2"
   37) "failover-timeout" #多长时间转移无法完成为失败
   38) "180000"
   39) "parallel-syncs" #主节点转移时可以并行将数据同步给多少台从节点
   40) "2"

172.18.65.71:26379> SENTINEL slaves myreplication #查看集群内的从节点信息
1)  1) "name" #第一个从节点
    2) "172.18.65.72:6379"
    3) "ip" 
    4) "172.18.65.72"
    5) "port"
    6) "6379"
    7) "runid"
    8) "291dd98a0666a2f10e3ca617d2ebf8481d5594a1"
    9) "flags"
   10) "slave"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "485"
   19) "last-ping-reply"
   20) "485"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "4669"
   25) "role-reported"
   26) "slave"
   27) "role-reported-time"
   28) "265667"
   29) "master-link-down-time"
   30) "0"
   31) "master-link-status"
   32) "ok"
   33) "master-host"
   34) "172.18.65.71"
   35) "master-port"
   36) "6379"
   37) "slave-priority"
   38) "100"
   39) "slave-repl-offset"
   40) "195780"
2)  1) "name" #第二个从节点
    2) "172.18.65.73:6379"
    3) "ip"
    4) "172.18.65.73"
    5) "port"
    6) "6379"
    7) "runid"
    8) "ae2da26524f91c61d4c5fa246304f53351400fb4"
    9) "flags"
   10) "slave"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "485"
   19) "last-ping-reply"
   20) "485"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "4669"
   25) "role-reported"
   26) "slave"
   27) "role-reported-time"
   28) "265667"
   29) "master-link-down-time"
   30) "0"
   31) "master-link-status"
   32) "ok"
   33) "master-host"
   34) "172.18.65.71"
   35) "master-port"
   36) "6379"
   37) "slave-priority"
   38) "100"
   39) "slave-repl-offset"
   40) "195780"

172.18.65.71:26379> SENTINEL get-master-addr-by-name myreplication #查看集群内的主节点的地址与端口
1) "172.18.65.71"
2) "6379"

{% endhighlight %}

####　第三步，模拟主节点失败，查看转移情况

{% highlight javascript linenos=table %}
＃关闭主节点，模拟失败
[root@node1 ~]# systemctl stop redis

＃查看集群中的信息
[root@node1 ~]# redis-cli -h 172.18.65.71 -p 26379
172.18.65.71:26379> SENTINEL masters　#查看监控的集群信息
1)  1) "name"
    2) "myreplication"
    3) "ip"
    4) "172.18.65.73"
    5) "port"
    6) "6379"
    7) "runid"
    8) "ae2da26524f91c61d4c5fa246304f53351400fb4"
    9) "flags"
   10) "master"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "150"
   19) "last-ping-reply"
   20) "150"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "3725"
   25) "role-reported"
   26) "master"
   27) "role-reported-time"
   28) "466874"
   29) "config-epoch"
   30) "2"
   31) "num-slaves"
   32) "2"
   33) "num-other-sentinels"
   34) "2"
   35) "quorum"
   36) "2"
   37) "failover-timeout"
   38) "180000"
   39) "parallel-syncs"
   40) "2"
172.18.65.71:26379> SENTINEL slaves myreplication #查看从节点信息
1)  1) "name"
    2) "172.18.65.72:6379"
    3) "ip"
    4) "172.18.65.72"
    5) "port"
    6) "6379"
    7) "runid"
    8) "291dd98a0666a2f10e3ca617d2ebf8481d5594a1"
    9) "flags"
   10) "slave"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "214"
   19) "last-ping-reply"
   20) "214"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "5854"
   25) "role-reported"
   26) "slave"
   27) "role-reported-time"
   28) "450348"
   29) "master-link-down-time"
   30) "0"
   31) "master-link-status"
   32) "ok"
   33) "master-host"
   34) "172.18.65.73"
   35) "master-port"
   36) "6379"
   37) "slave-priority"
   38) "100"
   39) "slave-repl-offset"
   40) "629489"
2)  1) "name"
    2) "172.18.65.71:6379"
    3) "ip"
    4) "172.18.65.71"
    5) "port"
    6) "6379"
    7) "runid"
    8) "342aca2b26ed8716711c9b199f52c08a722f59fc"
    9) "flags"
   10) "s_down,slave,disconnected" #可以看到原来的主节点成为了从节点，但是状态是不可用
   11) "link-pending-commands"
   12) "2"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "243349"
   17) "last-ok-ping-reply"
   18) "244075"
   19) "last-ping-reply"
   20) "244075"
   21) "s-down-time"
   22) "238324"
   23) "down-after-milliseconds"
   24) "5000"
   25) "info-refresh"
   26) "244366"
   27) "role-reported"
   28) "slave"
   29) "role-reported-time"
   30) "470433"
   31) "master-link-down-time"
   32) "1510825669000"
   33) "master-link-status"
   34) "err"
   35) "master-host"
   36) "172.18.65.73"
   37) "master-port"
   38) "6379"
   39) "slave-priority"
   40) "100"
   41) "slave-repl-offset"
   42) "1"
172.18.65.71:26379> SENTINEL get-master-addr-by-name myreplication #查看该集群的主节点地址和端口，可以看到已经转移
1) "172.18.65.73"
2) "6379"

{% endhighlight %}

####　第四步，修复失败的节点，重新上线
{% highlight javascript linenos=table %}
#修改node1的redis配置文件
[root@node1 ~]# vim /etc/redis.conf
slaveof 172.18.65.73 6375 #设定自己的主节点地址和端口
masterauth 123456 #指定自己的主节点认证密码

#重新上线
[root@node1 ~]# systemctl start redis

#查看是否恢复
[root@node1 ~]# redis-cli -h 172.18.65.72 -p 26379
172.18.65.72:26379> SENTINEL masters
1)  1) "name"
    2) "myreplication"
    3) "ip"
    4) "172.18.65.73"
    5) "port"
    6) "6379"
    7) "runid"
    8) "ae2da26524f91c61d4c5fa246304f53351400fb4"
    9) "flags"
   10) "master"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "737"
   19) "last-ping-reply"
   20) "737"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "5205"
   25) "role-reported"
   26) "master"
   27) "role-reported-time"
   28) "1041884"
   29) "config-epoch"
   30) "2"
   31) "num-slaves"
   32) "2"
   33) "num-other-sentinels"
   34) "2"
   35) "quorum"
   36) "2"
   37) "failover-timeout"
   38) "180000"
   39) "parallel-syncs"
   40) "2"
172.18.65.72:26379> SENTINEL slaves myreplication
1)  1) "name"
    2) "172.18.65.71:6379"
    3) "ip"
    4) "172.18.65.71"
    5) "port"
    6) "6379"
    7) "runid"
    8) "a158cc85d39560375835e656af74b23d9d02def0"
    9) "flags"
   10) "slave"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "805"
   19) "last-ping-reply"
   20) "805"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "6302"
   25) "role-reported"
   26) "slave"
   27) "role-reported-time"
   28) "1048535"
   29) "master-link-down-time"
   30) "0"
   31) "master-link-status" #可以看到已经恢复，且成为了从节点
   32) "ok"
   33) "master-host"
   34) "172.18.65.73"
   35) "master-port"
   36) "6379"
   37) "slave-priority"
   38) "100"
   39) "slave-repl-offset"
   40) "751581"
2)  1) "name"
    2) "172.18.65.72:6379"
    3) "ip"
    4) "172.18.65.72"
    5) "port"
    6) "6379"
    7) "runid"
    8) "291dd98a0666a2f10e3ca617d2ebf8481d5594a1"
    9) "flags"
   10) "slave"
   11) "link-pending-commands"
   12) "0"
   13) "link-refcount"
   14) "1"
   15) "last-ping-sent"
   16) "0"
   17) "last-ok-ping-reply"
   18) "141"
   19) "last-ping-reply"
   20) "141"
   21) "down-after-milliseconds"
   22) "5000"
   23) "info-refresh"
   24) "1821"
   25) "role-reported"
   26) "slave"
   27) "role-reported-time"
   28) "1038489"
   29) "master-link-down-time"
   30) "0"
   31) "master-link-status"
   32) "ok"
   33) "master-host"
   34) "172.18.65.73"
   35) "master-port"
   36) "6379"
   37) "slave-priority"
   38) "100"
   39) "slave-repl-offset"
   40) "752445"
172.18.65.72:26379> SENTINEL get-master-addr-by-name myreplication
1) "172.18.65.73"
2) "6379"

{% endhighlight %}

### Redis的Cluster实验
通过上述两个实验，我们实现了主从复制，保护了数据；实现了主节点的可高用。但是，我们仍然面临两个问题：第一，读写分离；但读写操作过多，Redis可能无法承受而崩溃，我们该如何将读写分给不同的服务器，让每个服务器只承担单独的读或者写功能，以实现减轻Redis读写压力，增加高可用的目的；第二，写操作的水平扩展，就算实现了读写分离，但写操作如果只能被单个服务器承受，就有可能出现无法承受而崩溃的情况，此时我们该怎么将写操作分摊给其他不同服务器，来实现减轻其压力，增加其可用性的目的呢？
<br/>
为了解决上述问题，有很多第三方扩展框架解决方案，例如：<br/>
- Twemproxy：Twitter提供的企业级方案,利用代理分片机制；。优点为稳定，毕竟是企业级解决方案；当然缺点更突出，例如无法解决单点失败，需要依赖第三方软件Keepalived，无法平滑横向扩展，分片机制引入了更多的来回读取操作增大了延迟，单核模式，无法充分利用多核...不出意料，该套解决方案已经被其“亲爸爸”——Twitter所抛弃，已经不再使用。
- Codis：豌豆荚提供的解决方案，也是利用的代理分片机制，基于GO语言研发(又一次感受到了Golang的魅力)。该方案优点突出：非常稳定(企业级方案不稳定不行-_-''),数据自动平衡，性能优异，比Twemproxy快一倍，可以使用多核，配置简单，没有协调机制没有主从复制，有便于管理的后台界面；但其也有自己的缺点：和Twemproxy一样，引入代理分片机制导致了更多的来回次数而造成了高延迟，需要第三方软件的协调机制，如Zookeerper及Etcd，不支持主从复制，需要另外实现，采用了Proxy的方案，必然带来了单机性能的损失，大概会损失40%。
- Cerberus：由芒果TV所研发(没错，就是马桶台！)。优点在于：数据自动平衡，本身实现了Redis的Smart Client，支持读写分离功能；缺点为：依赖Redis 3.0或者更高版本(估测现在已经不算是缺点了)，也是代理分片机制，所以会造成延迟增加，没有后台界面，最重要的是，其稳定性还有待检测。
- Redis Cluster：Redis官方所提供的的解决方案，需要Redis 3.0以上版本。优点在于：无中心的P2P Gossip分散式模式，更少的来回次数降低了延迟，自动与多个Redis节点进行分片，不需要第三方软件的支持其协调机制；缺点在于：需要智能客户端(这个貌似很伤)，Redis客户端必须要支持该架构，较Codis需要更多的维护精力，最后它的稳定性也需要时间检测。

无论怎么样，有很多手段可以解决问题，下面就利用Redis官方提供的Redis Cluster来实现一下，当然在开始之前，我们要注意以下几点：
- Redis Cluster是无中心节点的模式，没有主从节点之说。
- Redis Cluster是分片式存储，每个节点存储一部分，新增节点需要手动把各节点的一部分分片分过去。
- Redis Cluster不会在片级进行冗余和副本，只能给每个节点做一个从节点，不过可以利用多实例互为主从(但是在实际生产环境中没必要这样做)。
- Redis Cluster需要智能客户端，在请求的节点失败时，会自动寻找其他节点。

#### 1.实验架构
<img src="http://oy4e0m51m.bkt.clouddn.com/Cluster.png" width="700px"/>

仍然以三台主机为例，配置如下：

|-----------------+-----------------+----------------|
| 服务器			  |	IP地址  	        |     主机名	     |
|-----------------|:----------------+---------------:|
|  node1		  |172.18.65.71/16  |node1.oscao.com |
|  node2 		  |172.18.65.72/16  |node2.oscao.com |
|  node3 		  |172.18.65.73/16  |node3.oscao.com |
|-----------------+-----------------+----------------|

#### 2.实验步骤

#### 第一步，因为没有所谓的Replication和Sentinel，需要初始化环境

{% highlight javascript linenos=table %}
#关闭Sentinel服务
[root@node1 ~]# systemctl stop redis-sentinel.service 
[root@node2 ~]# systemctl stop redis-sentinel.service 
[root@node3 ~]# systemctl stop redis-sentinel.service 

#关闭主从复制功能
[root@node1 ~]# vim /etc/redis.conf
#masterauth 123456 #关闭密码认证功能
#slaveof 172.18.65.73 6379 #关闭主从复制

#传给其他节点各一份，覆盖原来的配置
[root@node1 ~]# scp /etc/redis.conf  root@172.18.65.72:/etc/redis.conf
redis.conf                                                         100%   46KB  21.3MB/s   00:00    
[root@node1 ~]# scp /etc/redis.conf  root@172.18.65.73:/etc/redis.conf
redis.conf                                                         100%   46KB  31.8MB/s   00:00

#重启各节点的Redis
[root@node1 ~]# systemctl restart redis
[root@node2 ~]# systemctl restart redis
[root@node2 ~]# systemctl restart redis

{% endhighlight %}

#### 第二步，启用集群功能

{% highlight javascript linenos=table %}
#配置文件
[root@node1 ~]# vim /etc/redis.conf
port 7000 #修改端口
bind 172.18.65.71 #修改绑定的IP；其他node1和node2分别为72和73
cluster-enabled yes #开启集群配置
cluster-config-file nodes-6379.conf #集群节点集群信息配置文件,每个节点都有一个,由redis生成和更新,配置时避免名称冲突
cluster-node-timeout 15000 #集群节点互连超时的阈值，单位毫秒
appendonly yes #开启aof存储方式，默认是RDB模式。

#重启服务
[root@node1 ~]# systemctl restart redis
[root@node2 ~]# systemctl restart redis
[root@node2 ~]# systemctl restart redis

#查看集群状态
[root@node1 ~]# redis-cli -h 172.18.65.71 -p 7000 CLUSTER INFO
cluster_state:fail #可以看到集群现在的状态是失败的，原因在于没有分配slots
cluster_slots_assigned:0
cluster_slots_ok:0
cluster_slots_pfail:0
cluster_slots_fail:0
cluster_known_nodes:1
cluster_size:0
cluster_current_epoch:0
cluster_my_epoch:0
cluster_stats_messages_sent:0
cluster_stats_messages_received:0

#为每个节点配置slots(尽量平均分配)
##node1配置5462个槽片，范围是0-5461
[root@node1 ~]# redis-cli -h 172.18.65.71 -p 7000 CLUSTER ADDSLOTS {0..5461}
OK
[root@node1 ~]# redis-cli -h 172.18.65.71 -p 7000 CLUSTER NODES
e8e9a9cea100eed1fe89cacb7433512b9532ec11 :7000 myself,master - 0 0 0 connected 0-5461

##node2配置5462个槽片，范围是5462-10923
[root@node2 ~]# redis-cli -h 172.18.65.72 -p 7000 CLUSTER ADDSLOTS {5462..10923}
OK
[root@node2 ~]# redis-cli -h 172.18.65.72 -p 7000 CLUSTER NODES
1c314a26d6df160b51909d212f9c909ccbd4a521 :7000 myself,master - 0 0 0 connected 5462-10923

##node2配置5462个槽片，范围是10923-16383
[root@node3 ~]# redis-cli -h 172.18.65.73 -p 7000 CLUSTER ADDSLOTS {10924..16383}
OK
[root@node3 ~]# redis-cli -h 172.18.65.73 -p 7000 CLUSTER NODES
1709c85889e16896f248f8d28c39d3d7666379c9 :7000 myself,master - 0 0 0 connected 10924-16383

#设置各节点联通
[root@node1 ~]# redis-cli  -h 172.18.65.71 -p 7000 CLUSTER MEET 172.18.65.72 7000
OK
[root@node1 ~]# redis-cli  -h 172.18.65.71 -p 7000 CLUSTER MEET 172.18.65.73 7000
OK

#查看集群状态
[root@node1 ~]# redis-cli  -h 172.18.65.71 -p 7000 CLUSTER INFO
cluster_state:ok #集群成功
cluster_slots_assigned:16384 #集群内总槽片
cluster_slots_ok:16384 #集群内可用的总槽片
cluster_slots_pfail:0 
cluster_slots_fail:0
cluster_known_nodes:3 #集群内的节点
cluster_size:3 
cluster_current_epoch:2
cluster_my_epoch:0
cluster_stats_messages_sent:50
cluster_stats_messages_received:50

{% endhighlight %}


