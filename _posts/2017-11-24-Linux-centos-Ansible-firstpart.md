---
layout: post
title: "自动化运维工具Ansible(第一部分)"
description: "本篇介绍自动化运维工具Ansible相关知识"
categories: [centos7,service]
tags: [linux,Ansible]
redirect_from:
  - /2017/11/24/
---
### 一.Ansible简介
Ansible is a radically simple IT automation engine that automates cloud provisioning, configuration management, application deployment, intra-service orchestration, and many other IT needs.<br/>
Ansible是一个非常容易上手的自动化IT工具，可以实现自动化云配置，系统配置管理，应用部署，内部服务流程配置等众多IT需求。

#### 1.Ansible具有以下特点

**(1)EFFICIENT ARCHITECTURE 高效的体系结构 模块化**
<br/>
- Ansible通过连接到节点并推出一些名为“Ansible模块”的小程序。这些程序被编写成系统所需状态的资源模型。然后Ansible执行这些模块（默认情况下通过SSH），并在完成后删除它们。
- 模块库可以驻留在任何机器上，并且不需要服务器，守护进程或数据库。

**(2)SSH KEYS ARE YOUR FRIENDS  支持SSH免秘链接 而非agent**
<br/>
- 支持密码，但SSH密钥与ssh-agent是使用Ansible的最佳方式之一。
- Ansible的“authorized_key”模块是一个很好的方法，可以用来控制哪些机器可以访问哪些主机。其他选项，如kerberos或身份管理系统，也可以使用。

**(3)MANAGE  INVENTORY IN SIMPLE TEXT FILES 通过主机清单进行管理**
<br/>
- 默认情况下，Ansible使用一个非常简单的INI文件来表示它管理的机器，这个文件将所有的被管理机器放在你自己选择的组中。如下：

{% highlight javascript linenos=table %}
[webservers]
www1.example.com
www2.example.com

[dbservers]
db0.example.com
db1.example.com
{% endhighlight %}

**(4)PLAYBOOKS: A SIMPLE+POWERFUL AUTOMATION LANGUAGE 使用playbook实现配置**
<br/>
**(5)Idempotence 幂等性**
- 幂等（idempotent、idempotence）是一个数学与计算机学概念，常见于抽象代数中。 在编程中，一个幂等操作的特点是其任意多次执行所产生的影响均与一次执行的影响相同。 幂等函数，或幂等方法，是指可以使用相同参数重复执行，并能获得相同结果的函数。
- Ansible的幂等性是通过一系列参数来实现的

#### 2.Ansible的结构体系

<Center>
<img src="http://oy4e0m51m.bkt.clouddn.com/%E7%BB%93%E6%9E%84%E4%BD%93%E7%B3%BB.png" width="900px"/>
</Center>

>注：Ansible与其他主机的连接控制，是通过SSH连接的，模板语言是jinjia2，模块语言是yaml。

### 二.Ansible的安装配置

#### 1.安装选择

Ansible有两个个yum仓库提供，一个是extra仓库，提供的是2.4版本，一个是epel仓库，提供的是2.2版本。推荐配置阿里云的镜像：
<br/>
- Base源：
https://mirrors.aliyun.com/centos/7.4.1708/os/x86_64/
- Epel源：
https://mirrors.aliyun.com/epel/7/x86_64/
- Extra源：
https://mirrors.aliyun.com/centos/7.4.1708/extras/x86_64/

#### 2.工作流程

没有守护进程，是一个命令行工具；需要先定义它能够管理的主机，然后在playbook写好配置，在命令行将其推入其管理的主机，根据playbook中的定义进行配置。

#### 3.配置文件

- /etc/ansible/ansible.cfg ：工具配置文件
- /etc/ansible/hosts  ：主机清单
- playbook：可以自己定义但结尾要是.yml或者.yaml，直接引用即可

#### 4.命令行语法

{% highlight javascript linenos=table %}
#语法
ansible  <host-pattern> [options] -f FORKS -C -u USERNAME -c CONNECTION
#选项
HOST-PATTERN:指定管理hosts中定义的那类主机，all 表示所有
	ansible dbservs --list-hosts:看在hosts中定义的某个组中的主机信息
	ansible all -m ping :测试hosts定义的所有主机的状态是否在线
-m:指定想要加载的模块，不指定默认模块是command
	ansibl all -m yum -a 'yum install -y httpd':在所有主机安装httpd
-a:指定想要模块加载的参数，对应模块中支持的各种功能
	ansible all -a 'ip a':查看所有主机的IP地址
-f:指定一批管理几台主机，默认为5个
{% endhighlight %}

#### 5.主机清单配置语法

{% highlight javascript linenos=table %}
[web]
172.18.65.74
172.18.65.75

[db]
172.18.65.72
172.18.65.73
{% endhighlight %}

#### 6.playbook配置语法

所谓的playbook就是将配置写在文本文件中，然后根据其进行配置管理的主机，不用再将每项设置通过命令行一次一次实现。

{% highlight javascript linenos=table %}
- hosts: web
  remote_user: root
  tasks:
  - name: install tomcat
    yum: name=java-1.8.0-openjdk,tomcat,tomcat-admin-webapps,tomcat-webapps,tomcat-docs-webapp state=installed

  - name: start tomcat service
    service: name=tomcat state=started

  - name: configure tomcat


- hosts: db
  remote_user: root
  tasks:
  - name: install redis
    yum: name=redis state=installed

  - name: start redis service
    service: name=redis state=started

{% endhighlight %}

### 三.Ansible的常见模块
Ansible是通过模块来发挥作用的，每个模块都代表者一类功能，模块内还有不同的参数，这些参数的组合实现模块功能的完整发挥。

{% highlight javascript linenos=table %}
#获取模块列表
ansible-doc  -l
#查看某模块支持的参数
ansible-doc -s MOD_NAME 
{% endhighlight %}

#### 1.command模块
Executes a command on a remote node;在远程主机运行用户给定的命令
<br/>
(1)参数：
- chdir：执行命令前，切换目录
- creates=/PATH/TO/SOMEFILE_OR_DIR:如果此处给定的文件或者目录存在，就不执行命令执行，没有才会执行。例如只有目录未被创建过才创建。为了保证幂等性
- removes=/PATH/TO/SOMEFILE_OR_DIR:如果此处给定的文件或者目录存在，就执行命令执行，没有不会有任何影响。例如只有用户或者文件存在才执行。为了保证幂等性

(2)示例：
{% highlight javascript linenos=table %}
#切换至目录app在执行命令
[root@node1 ~]# ansible db -a 'ls -l  chdir=/app/'
172.18.65.73 | SUCCESS | rc=0 >>
total 0
-rw-r--r-- 1 root root 0 Nov 25 02:40 test.txt

172.18.65.72 | SUCCESS | rc=0 >>
total 0
drwxr-x---. 6 root root 134 Nov 15 11:04 data
-rw-r--r--  1 root root   0 Nov 25 02:40 test.txt
{% endhighlight %}

#### 2.shell模块
Executes a command on a remote node;在远程主机在shell进程下运行命令，支持shell特性，如管道等
<br/>
(1)参数：
- chdir：执行命令前，切换目录
- creates=/PATH/TO/SOMEFILE_OR_DIR:如果此处给定的文件或者目录存在，就不执行命令 例如只有目录未被创建过才创建
- removes=/PATH/TO/SOMEFILE_OR_DIR:如果此处给定的文件或者目录存在，就执行命令 例如只有用户或者文件存在才删除
- executable=/PATH/TO/SHELL:指定运行命令时的shell类型，默认是bash

(2)示例：
{% highlight javascript linenos=table %}
#为节点的root账号改密码
[root@node1 ~]# ansible db -m shell -a 'echo 123456 | passwd --stdin root'
172.18.65.72 | SUCCESS | rc=0 >>
Changing password for user root.
passwd: all authentication tokens updated successfully.

172.18.65.73 | SUCCESS | rc=0 >>
Changing password for user root.
passwd: all authentication tokens updated successfully.
{% endhighlight %}

#### 3.user模块
Manage user accounts;管理用户账号
<br/>
(1)	参数：
- name= 指定要管理的用户名，这个是必要参数
- system= 指定是系统用户，无法为已存在的用户指定 yes/no 布尔型参数
- password= 指定用户密码
- createhome=是否创建家目录，默认创建
- uid= 指定UID
- shell= 指定shell，默认bash
- group= 指定主组
- groups= 指定多个属组
- comment= 指定描述性信息
- home= 指定家目录路径，默认在/home/下
- generate_ssh_key= 是否创建秘钥 用yes/no 布尔型参数

(2)示例：
{% highlight javascript linenos=table %}
#创建用户并指定密码
[root@node1 ~]# ansible db -m user -a 'name=hhy password=123456'
172.18.65.73 | SUCCESS => {
    "append": false, 
    "changed": true, 
    "comment": "hhy", 
    "failed": false, 
    "group": 1000, 
    "home": "/home/hhy", 
    "move_home": false, 
    "name": "hhy", 
    "password": "NOT_LOGGING_PASSWORD", 
    "shell": "/bin/bash", 
    "state": "present", 
    "uid": 1000
}
172.18.65.72 | SUCCESS => {
    "append": false, 
    "changed": true, 
    "comment": "hhy", 
    "failed": false, 
    "group": 1000, 
    "home": "/home/hhy", 
    "move_home": false, 
    "name": "hhy", 
    "password": "NOT_LOGGING_PASSWORD", 
    "shell": "/bin/bash", 
    "state": "present", 
    "uid": 1000
}
{% endhighlight %}

#### 4.group模块
Add or remove groups;创建或者删除组
<br/>
(1)参数：
- name= 指定组名 该参数必要
- state= 指定要进行的操作 不指定默认创建
- 	present 创建 
- 	absent 删除
- system= 指定为系统组 yes/no 布尔型参数
- gid= 指定组ID

(2)示例：
{% highlight javascript linenos=table %}
#删除组HHY
[root@node1 ~]# ansible db -m group -a 'name=HHY state=absent'
172.18.65.72 | SUCCESS => {
    "changed": true, 
    "failed": false, 
    "name": "HHY", 
    "state": "absent"
}
172.18.65.73 | SUCCESS => {
    "changed": true, 
    "failed": false, 
    "name": "HHY", 
    "state": "absent"
}
{% endhighlight %}

#### 5.copy模块
Copies files to remote locations；复制本机文件或者目录到远程主机
<br/>
(1)参数：
- src= 本机的文件或目录 *dest=复制到目标主机的某目录或文件
- content= 给定内容 *dest=复制到目标主机成为某文件，或者修改某文件中的内容
- owner：指定属主
- group,：指定属组
- mode ：指定权限  数字形式如0664
- decrypt：传输过程加密(盐)
>注：
源是目录那目标一定是目录，源是文件目标也一定是文件，目标不指定那么就会自动根据源文件属性进行创建

(2)示例：
{% highlight javascript linenos=table %}
#复制文件到节点目录
[root@node1 ~]# cat test.txt 
this a test file
[root@node1 ~]# ansible db -m copy -a "src=test.txt dest=/app/"
172.18.65.73 | SUCCESS => {
    "changed": true, 
    "checksum": "6737bd76a24373b1af8e7a48e82aa720259fa591", 
    "dest": "/app/test.txt", 
    "failed": false, 
    "gid": 0, 
    "group": "root", 
    "md5sum": "700d41ee96135e627b5fb2d3cf072ae2", 
    "mode": "0644", 
    "owner": "root", 
    "size": 17, 
    "src": "/root/.ansible/tmp/ansible-tmp-1511599180.28-210311421334528/source", 
    "state": "file", 
    "uid": 0
}
172.18.65.72 | SUCCESS => {
    "changed": true, 
    "checksum": "6737bd76a24373b1af8e7a48e82aa720259fa591", 
    "dest": "/app/test.txt", 
    "failed": false, 
    "gid": 0, 
    "group": "root", 
    "md5sum": "700d41ee96135e627b5fb2d3cf072ae2", 
    "mode": "0644", 
    "owner": "root", 
    "size": 17, 
    "src": "/root/.ansible/tmp/ansible-tmp-1511599180.25-250588166814325/source", 
    "state": "file", 
    "uid": 0
}

#复制目录到节点目录（注意目录内的文件会被一同复制）
[root@node1 ~]# mkdir test
[root@node1 ~]# mv test.txt  ./test
[root@node1 ~]# cat test/test.txt 
this a test file
[root@node1 ~]# ansible db -m copy -a "src=./test dest=/app/"
172.18.65.72 | SUCCESS => {
    "changed": true, 
    "checksum": "6737bd76a24373b1af8e7a48e82aa720259fa591", 
    "dest": "/app/test/test.txt", 
    "failed": false, 
    "gid": 0, 
    "group": "root", 
    "md5sum": "700d41ee96135e627b5fb2d3cf072ae2", 
    "mode": "0644", 
    "owner": "root", 
    "size": 17, 
    "src": "/root/.ansible/tmp/ansible-tmp-1511599299.22-160454501440973/source", 
    "state": "file", 
    "uid": 0
}
172.18.65.73 | SUCCESS => {
    "changed": true, 
    "checksum": "6737bd76a24373b1af8e7a48e82aa720259fa591", 
    "dest": "/app/test/test.txt", 
    "failed": false, 
    "gid": 0, 
    "group": "root", 
    "md5sum": "700d41ee96135e627b5fb2d3cf072ae2", 
    "mode": "0644", 
    "owner": "root", 
    "size": 17, 
    "src": "/root/.ansible/tmp/ansible-tmp-1511599299.23-225014256124769/source", 
    "state": "file", 
    "uid": 0
}
[root@node1 ~]# ansible db -a "cat /app/test/test.txt"
172.18.65.73 | SUCCESS | rc=0 >>
this a test file

172.18.65.72 | SUCCESS | rc=0 >>
this a test file
{% endhighlight %}

#### 6.file模块
Sets attributes of files；设定远程主机文件的属性
<br/>
(1)一般用法：
- 创建链接文件：*path=  src=需要链接的原文件  state=link
- 修改属性：path=  owner= group=  mode=权限 
- 创建目录：path=   state=directory 
- 创建空文件：path=  state=touch

(2)state的可用值：
- absent：删除
- link：软链接
- hard：硬链接
- touch：创建文件
- directory：创建目录
- file：修改文件(默认)  

#### 7.fetch模块
Fetches a file from remote nodes；从远程主机得到文件
<br/>
- dest= 将得到的文件存放到何处
- src= 出何处得到文件

#### 8.get_url模块
Downloads files from HTTP, HTTPS, or FTP to node；通过HTTP，HTTPS,FTP下载文件到节点
- url= 指明下载的URL
- dest=指明下载的存放路径

#### 9.corn模块
Manage cron.d and crontab entries；制定计划任务
(1)参数：
- minute=# 指定分钟
- day= # 指定天
- month= # 指定月 
- weekday=# 指定周
- hour= # 指定小时
- job= #指定工作
- user= #指明创建该任务的身份(默认是SSH链接的身份)
- name= #给任务命名，方便调用
- disabled=#禁用任务(即注释)
- reboot= #只要系统重启，该任务就会执行
- cron_file= #指明cron的文件(即读取文件中的设置到计划任务)
- state=指明任务进行何种操作
- 	present：创建
- 	absent：删除

(2)示例：
{% highlight javascript linenos=table %}
#设定每五分钟同步一次时间
[root@node1 ~]# ansible db -m cron -a "name='time sync' job='/usr/sbin/ntpdate 172.18.0.1 &> /dev/null' minute='*/5' "
172.18.65.73 | SUCCESS => {
    "changed": true, 
    "envs": [], 
    "failed": false, 
    "jobs": [
        "time sync"
    ]
}
172.18.65.72 | SUCCESS => {
    "changed": true, 
    "envs": [], 
    "failed": false, 
    "jobs": [
        "time sync"
    ]
}
#可以查看到任务已经添加
[root@node2 app]# crontab -l
#Ansible: time sync
*/5 * * * * /usr/sbin/ntpdate 172.18.0.1 &> /dev/null
{% endhighlight %}

#### 10.yum模块
Manages packages with the `yum' package manager;管理应用程序

- name= 指定程序包名称，可以带版本号；
- state= 指定要进行什么操作
- 	present, latest，installed 都表示安装
- 	absent，removed 都表示删除
- disablerepo：#临时禁用某个仓库
- enablerepo：#临时启用某个仓库

>注：其他包管理工具有apt(debian)，zypper(suse)，dnf(dedorea),rpm，dpkg...

#### 11.service模块
Manage services;管理服务
<br/>
- name=指定服务名
- state=指定进行何种操作
- 	started 启动
- 	stopped 停止
- 	restarted 重启
- 	reloaded 重读
- enabled=是否开机自起 true/false
- runlevel= 若开机自启动，可选择在何种运行级别自起

#### 12.haproxy模块
Enable, disable, and set weights for HAProxy backend servers using socket command;通过haproxy管理后端主机
<br/>
- backend：haproxy后端服务器组的名称
- host：必需，指明要进行管理的后端服务器
- state：设置后端主机的模式
- 	disabled：禁用
- 	enable：启用
- drain：当state=disabled时使用，不再接受新的请求，保留已经建立连接的请求，知道连接超时或者关闭
- shutdown_sessions：当state=disabled时使用，立即关闭所有链接
- weight：设置后端主机的权重

