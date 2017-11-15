---
layout: post
title: "利用xtrabackup实现MySQL的备份和恢复"
description: "本篇介绍如何利用Percona提供的备份工具进行MySQL数据库的备份和恢复"
categories: [centos7,service]
tags: [linux,MySQL,Xrabackup]
redirect_from:
  - /2017/11/14/
---

### 前情提要：
在现代互联时代，随着大数据的到来，数据越来越成为人们津津乐道的事务。的确，对于一个企业来说，数据的重要性不言而喻，如果说把整个公司服务器的整体架构形容为一个人，那么数据库服务器无疑是这个架构中的心脏，为整个服务器架构提供着源源不断血液——数据。因此对于运维人员来说，数据信息的保护是我们的基本职责。
下面通过模拟实现了MySQL基于Innodb储存引擎的数据备份和恢复。
### 实验架构：
本次实验用到了两台服务器，一台作为数据服务器，一台作为备份服务器；而我们的目的在于实现：将数据服务器上的数据被分到远程的备份服务器并在备份服务器实现数据的恢复。基本架构如下：

|-----------------+-----------------+----------------|
| 服务器			  |	IP地址  	        |     主机名	     |
|-----------------|:----------------+---------------:|
| 数据服务器 node1 |172.18.65.71/16  |node1.oscao.com |
| 备份服务器 node2 |172.18.65.72/16  |node1.oscao.com |
|-----------------+-----------------+----------------|

### 实验准备：
#### 1.安装与配置MySQL

{% highlight javascript linenos=table %}
#分别在两台服务器上安装MySQL
[root@node1 ~]# yum -y install mariadb-server
[root@node2 ~]# yum -y install mariadb-server

#对两台服务器分别进行以下配置
[root@node1|2 ~]# vim /etc/my.cnf
log_bin=mysql_bin #开启二进制日志，设定二进制日志路径及前缀名
innodb_file_per_table = on #每表单独存放
skip_name_resolve = on #跳过名字解析

#安装备份工具Xtrabackup,利用在官网下载的rpm包进行安装,可能解决依赖需要配置epel源，建议阿里云
[root@node2 ~]# yum  install  ./percona-xtrabackup-24-2.4.8-1.el7.x86_64.rpm
[root@node2 ~]# yum  install  ./percona-xtrabackup-24-2.4.8-1.el7.x86_64.rpm

{% endhighlight %}

#### 2.同步时间
{% highlight javascript linenos=table %}
#同步时间非常重要，不然备份的数据无法恢复
[root@node1 ~]# ntpdate 172.18.0.1
14 Nov 08:56:19 ntpdate[55373]: step time server 172.18.0.1 offset -28801.414631 sec
[root@node2 ~]# ntpdate 172.18.0.1
14 Nov 08:56:34 ntpdate[42366]: step time server 172.18.0.1 offset -28800.844483 sec
{% endhighlight %}

#### 3.关闭防火墙和selinux
{% highlight javascript linenos=table %}
[root@node1 ~]# setenforce 0
[root@node1 ~]# systemctl stop firewalld
[root@node1 ~]# iptables -F

[root@node2 ~]# setenforce 0
[root@node2 ~]# systemctl stop firewalld
[root@node2 ~]# iptables -F
{% endhighlight %}

#### 4.模拟数据
为了尽量模拟真实场景，我们提前给**数据服务器**提供一些数据库和表，进行如下操作：
{% highlight javascript linenos=table %}
#创建数据库和表
[root@node1 ~]# mysql
MariaDB [(none)]> CREATE DATABASE hidb;
MariaDB [(none)]> CREATE TABLE hidb.students (id int UNSIGNED ,name VARCHAR(20),age tinyint,gender  ENUM('m','f'));

#批量插入数据
[root@node1 ~]# GENDER=('f' 'm')
[root@node1 ~]# for i in {1..1000}; do mysql -e "INSERT INTO hidb.students(id,name,age,gender) VALUES ($i,'stu$i','$[$RANDOM%80+18]','${GENDER[$[RANDOM%2]]}');"; done

#连入查看是否成功写入数据
[root@node1 ~]# mysql
MariaDB [(none)]> SELECT * FROM hidb.students;
+------+---------+------+--------+
| id   | name    | age  | gender |
+------+---------+------+--------+
|    1 | stu1    |   53 | m      |
|    2 | stu2    |   66 | m      |
|    3 | stu3    |   32 | f      |
|  ... | ...     |  ... | ...    |
|  999 | stu999  |   87 | m      |
| 1000 | stu1000 |   23 | m      |
+------+---------+------+--------+
{% endhighlight %}

#### 5.为备份服务器准备用户并授权

{% highlight javascript linenos=table %}
MariaDB [(none)]> CREATE USER 'bkpuser'@'172.18.65.%' IDENTIFIED BY '123456';
MariaDB [(none)]> GRANT RELOAD,LOCK TABLES,REPLICATION CLIENT ON *.* TO 'bkpuser'@'172.18.65.%';
MariaDB [(none)]> FLUSH PRIVILEGES;
#在备份服务器尝试是否能够登录
[root@node1 ~]# mysql -ubkpuser -h172.18.65.71 -p123456
{% endhighlight %}

### 实现全量+增量+binlog备份

#### 第一步，在数据服务器执行命令进行全量备份
{% highlight javascript linenos=table %}
#在数据服务器上执行命令,要确定最后出现‘completed OK!
[root@node1 ~]# innobackupex -ubkpuser -p123456 -H172.18.65.71  /app/data/ 
171115 09:53:01 innobackupex: Starting the backup operation

IMPORTANT: Please check that the backup run completes successfully.
           At the end of a successful backup run innobackupex
           prints "completed OK!".
......
xtrabackup: Transaction log of lsn (2012118) to (2012118) was copied.
171115 09:53:03 completed OK!

#将备份传入远程备份服务器
[root@node1 data]# scp -r 2017-11-15_09-53-01/ root@172.18.65.72:/app/data/

#在备份服务器上查看全量备份后的LSN编号
[root@node2 data]# cat 2017-11-15_09-53-01/xtrabackup_checkpoints
backup_type = full-backuped
from_lsn = 0
to_lsn = 2012118
last_lsn = 2012118
compact = 0
recover_binlog_info = 0
{% endhighlight %}

#### 第二步，在数据服务器进行数据修改,并进行第一次增量备份
{% highlight javascript linenos=table %}
#修改数据库内容
MariaDB [(none)]> ALTER TABLE hidb.students ADD major varchar(40) AFTER gender;
Query OK, 1000 rows affected (0.14 sec)                
Records: 1000  Duplicates: 0  Warnings: 0
MariaDB [(none)]> SELECT * FROM hidb.students;
+------+---------+------+--------+-------+
| id   | name    | age  | gender | major |
+------+---------+------+--------+-------+
|    1 | stu1    |   76 | f      | NULL  |
|    2 | stu2    |   31 | m      | NULL  |
|  ... | ......  |  ... | ...    | ...   |
|  999 | stu999  |   57 | f      | NULL  |
| 1000 | stu1000 |   88 | f      | NULL  |
+------+---------+------+--------+-------+
1000 rows in set (0.01 sec)

#进行第一次增量备份
[root@node1 ~]# innobackupex -ubkpuser -p123456 -H172.18.65.71 --incremental /app/data/increment-first/ --incremental-basedir=/app/data/2017-11-15_09-53-01
171115 09:59:13 innobackupex: Starting the backup operation

IMPORTANT: Please check that the backup run completes successfully.
           At the end of a successful backup run innobackupex
           prints "completed OK!".
......
xtrabackup: Transaction log of lsn (2108072) to (2108072) was copied.
171115 09:59:21 completed OK!

#将第一次增量备份传送到远程备份服务器
[root@node1 data]# scp -r increment-first/ root@172.18.65.72:/app/data/

#在备份服务器上查看第一次增量备份后的LSN编号
[root@node2 data]# [root@node2 data]# cat increment-first/2017-11-15_10-02-22/xtrabackup_checkpoints 
backup_type = incremental
from_lsn = 2012118
to_lsn = 2108072
last_lsn = 2108072
compact = 0
recover_binlog_info = 0

{% endhighlight %}
#### 第三步，在数据服务器进行数据修改,并进行第二次增量备份
{% highlight javascript linenos=table %}
#修改数据库内容
MariaDB [(none)]> UPDATE  hidb.students SET major='english' where id>900;
Query OK, 100 rows affected (0.13 sec)
Rows matched: 100  Changed: 100  Warnings: 0
MariaDB [(none)]> SELECT * FROM hidb.students WHERE id>898;
+------+---------+------+--------+---------+
| id   | name    | age  | gender | major   |
+------+---------+------+--------+---------+
|  899 | stu899  |   84 | m      | NULL    |
|  900 | stu900  |   73 | m      | NULL    |
|  901 | stu901  |   23 | m      | english |
|  902 | stu902  |   18 | m      | english |
|  ... | ......  |  ... | ...    | ...     |
| 1000 | stu1000 |   77 | f      | english |
+------+---------+------+--------+---------+
102 rows in set (0.00 sec)

#进行第二次增量备份
innobackupex -ubkpuser -p123456 -H172.18.65.71 --incremental /app/data/increment-second/ --incremental-basedir=/app/data/increment-first/2017-11-15_10-02-22/
171115 10:17:02 innobackupex: Starting the backup operation

IMPORTANT: Please check that the backup run completes successfully.
           At the end of a successful backup run innobackupex
           prints "completed OK!".
......
xtrabackup: Transaction log of lsn (2121903) to (2121903) was copied.
171115 10:17:05 completed OK!

#将第二次增量备份传送到远程备份服务器
[root@node1 data]# scp -r increment-second/ root@172.18.65.72:/app/data/

#在备份服务器上查看第二次增量备份后的LSN编号
[root@node2 data]# cat increment-second/2017-11-15_10-17-02/xtrabackup_checkpoints 
backup_type = incremental
from_lsn = 2108072
to_lsn = 2121903
last_lsn = 2121903
compact = 0
recover_binlog_info = 0

{% endhighlight %}

#### 第四步，模拟正在操作时，数据库崩溃

{% highlight javascript linenos=table %}
#在数据库修改数据
MariaDB [(none)]> UPDATE  hidb.students SET major='chinese' where id>998;
Query OK, 2 rows affected (0.02 sec)
Rows matched: 2  Changed: 2  Warnings: 0

MariaDB [(none)]> SELECT * FROM hidb.students WHERE id>996;
+------+---------+------+--------+---------+
| id   | name    | age  | gender | major   |
+------+---------+------+--------+---------+
|  997 | stu997  |   84 | f      | english |
|  998 | stu998  |   45 | m      | english |
|  999 | stu999  |   87 | m      | chinese |
| 1000 | stu1000 |   77 | f      | chinese |
+------+---------+------+--------+---------+
4 rows in set (0.00 sec)

#模拟此时数据库崩溃
[root@node1 ~]# cd /var/lib/mysql/ && rm -rf *

{% endhighlight %}

#### 第五步，备份准备
{% highlight javascript linenos=table %}
#在备份数据库查看第二次增量备份的二进制日志的名字和位置
[root@node2 data]# cat increment-second/2017-11-15_10-17-02/xtrabackup_checkpoints 
backup_type = incremental
from_lsn = 2108072
to_lsn = 2121903
last_lsn = 2121903
compact = 0
recover_binlog_info = 0

#将需要的二进制日志传送到备份服务器
[root@node1 ~]# scp /app/data/log/mysql_bin.000003  root@172.18.65.72:/app/data/
注：强烈建议将二进制日志与数据库分开存放，以保证数据库崩溃还能留存二进制日志便于恢复

#在备份数据库将备份进行合并
##进行全量备份的合并，不回滚日志
[root@node2 ~]# innobackupex --redo-only --apply-log /app/data/2017-11-15_09-53-01/

##进行第一次增量备份的合并，不回滚日志
[root@node2 ~]# innobackupex --redo-only --apply-log /app/data/2017-11-15_09-53-01/ --incremental-dir=/app/data/increment-first/2017-11-15_10-02-22/

##进行第二次增量备份的合并，不回滚日志
[root@node2 ~]# innobackupex --redo-only --apply-log /app/data/2017-11-15_09-53-01/ --incremental-dir=/app/data/increment-second/2017-11-15_10-17-02/

##提交并回滚日志，一旦提交并回滚就不能在使用了
[root@node2 ~]# innobackupex --apply-log /app/data/2017-11-15_09-53-01/

#查看合并并回滚后的LSN编号，如果和第二次增量备份中的一致说明已经合并成功
[root@node2 data]# cat 2017-11-15_09-53-01/xtrabackup_checkpoints 
backup_type = full-prepared
from_lsn = 0
to_lsn = 2121903
last_lsn = 2121903
compact = 0
recover_binlog_info = 0

#查看合并后的二进制日志及其位置
[root@node2 data]# cat 2017-11-15_09-53-01/xtrabackup_binlog_info 
mysql_bin.000003	226903

{% endhighlight %}

#### 第六步，将合并好的数据恢复到备份数据库
{% highlight javascript linenos=table %}
#为恢复准备一个完全干净的数据库
[root@node2 ~]# systemctl stop mariadb
[root@node2 ~]# rm -rf /var/lib/mysql/*

#恢复数据
[root@node2 ~]# innobackupex --copy-back /app/data/2017-11-15_09-53-01/

#修改恢复后数据的属主属组
[root@node2 ~]# chown -R  mysql:mysql  /var/lib/mysql/

#启动数据库
[root@node2 ~]# systemctl start mariadb.service

{% endhighlight %}

#### 第七步，使用二进制日志重放崩溃前的操作，实现最后修复
{% highlight javascript linenos=table %}
#关闭二进制日志记录功能
MariaDB [(none)]> set @@session.sql_log_bin=0;
Query OK, 0 rows affected (0.00 sec)

#重放二进制日志，回复最终数据
[root@node2 ~]# mysqlbinlog --start-position=226903 /app/data/mysql_bin.000003 > /app/data/log-bin.sql
[root@node2 ~]# mysql < /app/data/log-bin.sql

#查看数据库，数据是否一致
MariaDB [(none)]> SELECT * FROM hidb.students where id>996;
+------+---------+------+--------+---------+
| id   | name    | age  | gender | major   |
+------+---------+------+--------+---------+
|  997 | stu997  |   84 | f      | english |
|  998 | stu998  |   45 | m      | english |
|  999 | stu999  |   87 | m      | chinese |
| 1000 | stu1000 |   77 | f      | chinese |
+------+---------+------+--------+---------+
4 rows in set (0.00 sec)

#打开二进制日志记录功能
MariaDB [(none)]> set @@session.sql_log_bin=1;

{% endhighlight %}

#### 第八步，在备份服务器进行一次全量备份
{% highlight javascript linenos=table %}
#全量备份
[root@node2 ~]# innobackupex -ubkpuser -p123456 -H172.18.65.72 /app/data/all/
171115 11:04:46 innobackupex: Starting the backup operation

IMPORTANT: Please check that the backup run completes successfully.
           At the end of a successful backup run innobackupex
           prints "completed OK!".
......
xtrabackup: Transaction log of lsn (2123570) to (2123570) was copied.
171115 11:04:48 completed OK!

#查看备份的LSN
[root@node2 ~]# cat /app/data/all/2017-11-15_11-04-46/xtrabackup_checkpoints 
backup_type = full-backuped
from_lsn = 0
to_lsn = 2123570
last_lsn = 2123570
compact = 0
recover_binlog_info = 0
{% endhighlight %}

### 补充知识：将本机数据库利用压缩的方式全量备份到远程备份服务器
{% highlight javascript linenos=table %}
#备份时要确定最后出现‘completed OK!’,需要用到sshpass工具，配置epel源直接安装即可
#安装sshpass工具
[root@node1 ~]# yum -y install sshpass

#在数据服务器上执行命令
[root@node1 ~]# innobackupex -ubkpuser -p123456 -H172.18.65.71 --stream=tar ./ | gzip | sshpass -p '123456' ssh root@172.18.65.72  "cat - > /app/data/2017-11-15-fullbackup.tar.gz"
171115 08:58:09 innobackupex: Starting the backup operation

IMPORTANT: Please check that the backup run completes successfully.
           At the end of a successful backup run innobackupex
           prints "completed OK!".
......
171115 08:58:11 [00] Streaming <STDOUT>
171115 08:58:11 [00]        ...done
xtrabackup: Transaction log of lsn (2012116) to (2012116) was copied.
171115 08:58:11 completed OK!

#我们可以在备份服务器上查看到数据已经到达，且为压缩格式
[root@node2 ~]# ll /app/data
total 264
-rw-r--r-- 1 root root 269037 Nov 15 08:58 2017-11-15-fullbackup.tar.gz

#解压备份
[root@node2 data]# mkdir 2017-11-15-fullbackup && tar xvf 2017-11-15-fullbackup.tar.gz -C ./2017-11-15-fullbackup

{% endhighlight %}