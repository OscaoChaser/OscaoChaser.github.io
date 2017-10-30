---
layout: post
title: "KeepAlived介绍以及实现主备lvs"
description: "对keepalived的功能进行介绍，并进行主备lvs实验"
categories: [centos6，centos7,service]
tags: [linux,keepalived,lvs]
redirect_from:
  - /2017/10/30/
---

### 一、KeepAlived简介

Keepalived 是一个基于VRRP协议来实现的LVS服务高可用方案，可以利用其来避免单点故障。一个LVS服务会有2台服务器运行Keepalived，一台为主服务器（MASTER），一台为备份服务器（BACKUP），但是对外表现为一个虚拟IP，主服务器会发送特定的消息给备份服务器，当备份服务器收不到这个消息的时候，即主服务器宕机的时候， 备份服务器就会接管虚拟IP，继续提供服务，从而保证了高可用性。

>注：<br/>
（1）apache在作为调度器VS时，第一无法实现对后端RS健康状态的检查，只能依赖ldirectord来提供这个功能；第二无法实现VS的HA，存在单点失败，只能依赖keepalived来提供这个功能，而且keepalived还可以代理ldirectord对后端的RS做健康性检查，以及实现IPVS策略。<br/>
（2）nginx在作为调度器VS的时候，可以实现对后端RS进行健康检查和调度，但是仍无法实现自身的HA，也需要依赖keepalived（脚本）实现这个要求。

#### 1.KeepAlived的功能

（1）vrrp协议完成地址流动<br/>
（2）为vip地址所在的节点生成ipvs规则(在配置文件中预先定义)<br/>
（3）为ipvs集群的各RS做健康状态检测<br/>
（4）基于脚本调用接口通过执行脚本完成脚本中定义的功能， 进而影响集群事务，以此支持nginx、haproxy等服务<br/>
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/1ha.png" width="700px"/>
</center>

#### 2.HA Cluster的配置准备

（1）各节点时间必须同步 ntp, chrony <br/>
可利用ntp服务保证时间同步：<br/>
首次，下载安装ntp包<br/>
`yum -y install ntp`<br/>
其次，先手动同步时间，避免差别过大<br/>
`ntpdate 172.18.0.1`（想要与其同步的IP,时间服务器的IP）<br/>
然后，配置ntp服务，选择指向的时间服务器<br/>
`vim  /etc/ntp.conf`将同步的IP指向172.18.0.1<br/>
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/2ha.png" width="600px"/>
</center>
最后，启动btp服务，并设置为开机启动<br/>
`systemctl start ntpd`<br/>
`systemctl enable ntpd`<br/>

>注：集群时间同步策略<br/>
VS与网络中提供时间的ntp服务器同步<br/>
RS与VS时间同步<br/>

(2)确保iptables及selinux不会成为阻碍 <br/>
(3)各节点之间可通过主机名互相通信（对KA并非必须）建议使用/etc/hosts文件实现<br/>
(4)节点之间的root用户可以基于密钥认证的ssh服务完成互相通信（对KA并非必须）<br/>
实现基于密钥认证：<br/>
首先，生成key<br/>
`ssh-keygen`<br/>
其次，传输key到其他主机<br/>
`cd  /root/.ssh`<br/>	
`ssh-copy-id -i id_rsa.pub  IP：`<br/>	    
最后，检查key是否成功传输<br/>
>注：
>如果是需要传输给大量的主机，最好使用execpt脚本实现key的传输

#### 3.keepalived安装配置文件

包名：keepalived<br/>
主配置文件：/etc/keepalived/keepalived.conf <br/>
主程序文件：/usr/sbin/keepalived <br/>
Unit File：/usr/lib/systemd/system/keepalived.service<br/>
Unit File的环境配置文件：/etc/sysconfig/keepalived<br/>
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/3ha.png" width="500px"/>
</center>

#### 4.配置文件的组成

一共分为三个部分<br/>
第一部分：全局配置GLOBAL CONFIGURATION<br/> 
	Global definitions <br/>
	Static routes/addresses <br/>
第二部分：虚拟路由设置VRRPD CONFIGURATION <br/>
	VRRP synchronization group(s)：vrrp同步组 <br/>
	VRRP instance(s)：即一个vrrp虚拟路由器 <br/>
第三部分：调度策略配置<br/>
	Virtual server group(s) <br/>
	Virtual server(s)：ipvs集群的vs和rs<br/>

#### 5.配置语法

（1）全局配置GLOBAL CONFIGURATION
{% highlight javascript linenos=table %}
global_defs {   #该函数定义全局配置
   notification_email {     #该函数代表的是如果keepalived发生诸如主备切换进行邮件通知
     acassen@firewall.loc   #通知邮件1
     failover@firewall.loc  #通知邮件2
     sysadmin@firewall.loc  #通知邮件3
   }
   notification_email_from Alexandre.Cassen@firewall.loc #定义邮件的发送方
   smtp_server 192.168.200.1        #定义发送邮件时的服务器地址
   smtp_connect_timeout 30          #定义链接邮件发送服务器的超时时间
   router_id LVS_DEVEL              #运行keepalived的节点标识（名字），不同服务器不同
   vrrp_mcast_group4 224.100.100.100  #定义多播地址，保证安全（同组地址应该相同）
}
{% endhighlight %}

（2）虚拟路由配置VRRPD CONFIGURATION 
{% highlight javascript linenos=table %}
vrrp_instance VI_1 {        #该函数表示定义虚拟路由
    state MASTER |BACKUP    #当前节点在此虚拟路由器上的初始状态；主还是备
    interface eth0          #绑定为当前虚拟路由器使用的物理接口 
    virtual_router_id 51    #当前虚拟路由器惟一标识，范围是0-255；标识相同代表属同组虚拟路由
    priority 254            #当前物理节点在此虚拟路由器中的优先级；范围1-254，优先级高的为主
    nopreempt               #设置为不抢占，这个配置只能设置在backup上，而且这个主机优先级要比另外一台高
    advert_int 1            #vrrp通告（组播）的时间间隔，默认1s
    authentication {        #该函数定义同组的路由（服务器）之间如何通信“暗号”
        auth_type PASS|AH   #定义认证机制，共享秘钥（pass用密码）
        auth_pass 1111      #定义认证密码（前八位有效）
    }
    virtual_ipaddress {     #该函数定义该路由组的虚拟IP
        192.168.200.16      #虚拟路由组的IP，可多个，语法“IP/NETMASK dev INTERFACE lable NAME” 
        192.168.200.17
        192.168.200.18
    }
    track interface {       #定义额外的监控，脸面任意一块网卡有问题都会进入故障（fault）状态（例如监控内外网网卡）
        eth0
        eth1
    }
}
{% endhighlight %}

（3）调度策略和服务器配置LVS CONFIGURATION
{% highlight javascript linenos=table %}
virtual_server 10.10.10.2 1358 {        #该函数定义IPVS策略
    delay_loop 6                        #检查后端服务器的时间间隔
    lb_algo rr|wrr|lc|wlc|lblc|sh|dh    #定义调度方法 
    lb_kind NAT|DR|TUN                  #定义集群的类型 
    persistence_timeout 50              #定义持久连接时长 
    protocol TCP                        #定义服务协议（仅支持TCP）
    sorry_server <IPADDR> <PORT>        #定义sorryserver的地址（可以设置为本机作为sorryserver）
    real_server <IPADDR> <PORT> {       #该函数定义后端RS的IP和PORT,以及其他信息
        weight 1                        #定义RS权重
        notify_up <STRING>|<QUOTED-STRING>   #RS上线通知脚本 
        notify_down <STRING>|<QUOTED-STRING> #RS下线通知脚本 
        HTTP_GET|SSL_GET|TCP_CHECK|SMTP_CHECK|MISC_CHECK {  #该函数定义当前主机的健康状态监测方法
            url {
                path <URL_PATH>         #定义要监控的URL
                status_code <INT>       #判断上述检测机制为健康状态的响应码 
                digest <STRING>         #判断为健康状态的响应的内容的校验(与检验状态码二者选一
            }
            connect_timeout 3           #定义连接请求的超时时长 
            nb_get_retry 3              #定义重试次数 
            delay_before_retry 3        #定义重试之前的延迟时长 
            connect_ip <IP ADDRESS>     #向当前RS哪个IP地址发起健康状态检测请求（建议网卡分离）
            connect_port <PORT>         #向当前RS的哪个PORT发起健康状态检测请求 
            bindto <IP ADDRESS>         #发出健康状态检测请求时使用的源地址 
            bind_port <PORT>            #发出健康状态检测请求时使用的源端口 
        }
    }
    real_server <IPADDR> <PORT> {
        .....
    }
}
{% endhighlight %}

#### 7.KeepAlived可实现的几种架构

（1）主备模式（A/B）<br/>
实现服务器的高可用，在同一个虚拟组中只有一个主路由器，其他皆为备用路由器，主路由器失败高优先路由器接手
（2）双主模式（A/A）<br/>
实现服务器的高可用，有两组不同的虚拟组，两台服务器都工作，且互为主备

### 二、KeepAlived的应用实验：实现双机热备中的主备模式

#### 1.实验目的：

通过keepalived模拟实现VS服务器的双机热备中的主备模式，并利用脚本自动发送主备切换通知，检测其高可用性

#### 2.实验环境：

（1）硬件：<br/>
五台主机，一台客户端，两台做VS，两台做RS<br/>
（2）软件：<br/>
VS需要安装keepalived<br/>
RS需要安装http服务<br/>

#### 3.实验架构：

<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/4ha.png" width="900px"/>
</center>

#### 4.表格展示：

<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/5ha.png" width="600px"/>
</center>
>注：为实验方便，所有主机同网段

#### 5.实验步骤

（1）各服务器时间同步，检查防火墙和selinux策略
{% highlight javascript linenos=table %}
[root@client ~]# ntpdate 172.18.0.1
[root@client ~]# setenforce 0
[root@client ~]# getenforce
[root@client ~]# service iptables stop 
[root@client ~]# iptables -vnL

[root@client ~]# ntpdate 172.18.0.1
[root@client ~]# setenforce 0
[root@client ~]# getenforce
[root@client ~]# service iptables stop 
[root@client ~]# iptables -vnL

[root@VS1 ~]#ntpdate 172.18.0.1
[root@VS1 ~]# setenforce 0
[root@VS1 ~]# getenforce
[root@VS1 ~]# iservice iptables stop 
[root@VS1 ~]# iptables -vnL

[root@VS2 ~]#ntpdate 172.18.0.1
[root@VS2 ~]# setenforce 0
[root@VS2 ~]# getenforce
[root@VS2 ~]# service iptables stop 
[root@VS2 ~]# iptables -vnL

[root@RS1 ~]# ntpdate 172.18.0.1
[root@RS1 ~]# setenforce 0
[root@RS1 ~]# getenforce
[root@RS1 ~]# service iptables stop 
[root@RS1 ~]# iptables -vnL

[root@RS2 ~]# ntpdate 172.18.0.1
[root@RS2 ~]# setenforce 0
[root@RS2 ~]# getenforce
[root@RS2 ~]# service iptables stop 
[root@RS2 ~]# iptables -vnL
{% endhighlight %}

>注：因为在同一网络，所以直接选择了与网关时间同步，手动同步后建议修改ntp的配置文件，并启动服务，让其自动生效；此外还要注意centos6和7命令略有不同，在实验中防火墙和selinux尽量关闭。

(2)在VS安装keepalived服务，在RS安装http服务并修改主页文件，进行测试
{% highlight javascript linenos=table %}
[root@VS1 ~]#yum -y install keepalived
[root@VS2 ~]#yum -y install keepalived

[root@RS1 ~]# echo "this RS1 web page" > /var/www/html/index.html
[root@RS1 ~]# service httpd  start
[root@RS1 ~]# ss -ntl

[root@VS2 ~]#  echo "this RS2 web page" > /var/www/html/index.html
[root@RS1 ~]# service httpd  start
[root@RS1 ~]# ss -ntl

[root@client ~]# curl 172.18.65.3
this RS1 web page
[root@client ~]# curl 172.18.65.4
this RS2 web page
{% endhighlight %}

(3)在VS上配置keepalived，准备通知脚本，VS1为主，VS2为备
{% highlight javascript linenos=table %}
[root@VS1 ~]#vim /etc/keepalived/keepalived.conf
#主调度服务器全局配置
global_defs {
        notification_email {
                root@localhost
        }
        notification_email_from keepalived@localhost
        smtp_server 127.0.0.1
        smtp_connect_timeout 30
        router_id VS1
        vrrp_mcast_group4 228.100.100.100
}
#主调度服务器虚拟VRRP配置
vrrp_instance VRRP {
        state MASTER
        interface ens33
        virtual_router_id 66
        priority 100
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass centos
        }
        virtual_ipaddress {
                172.18.65.2/16 dev ens33
        }
        notify_master "/etc/keepalived/notify.sh master"
        notify_backup "/etc/keepalived/notify.sh backup"
        notify_fault "/etc/keepalived/notify.sh fault"
}
#主调度服务器调度规则和主机设置
virtual_server 172.18.65.2 80 {
        delay_loop 1
        lb_algo wrr
        lb_kind DR
        protocol TCP
        sorry_server 127.0.0.1 80
        real_server 172.18.65.3 80 {
                weight 2
                HTTP_GET {
                        url {
                                path /
                                status_code 200
                        }
                connect_timeout 1
                nb_get_retry 3
                delay_before_retry 3
                }
        }
        real_server 172.18.65.4 80 {
                weight 1
                HTTP_GET {
                        url {
                                path /
                                status_code 200
                        }
                connect_timeout 1
                nb_get_retry 3
                delay_before_retry 3
                }
        }
}
{% endhighlight %}

{% highlight javascript linenos=table %}
[root@VS2 ~]#vim /etc/keepalived/keepalived.conf
#备调度服务器全局配置
global_defs {
        notification_email {
                root@localhost
        }
        notification_email_from keepalived@localhost
        smtp_server 127.0.0.1
        smtp_connect_timeout 30
        router_id VS1
        vrrp_mcast_group4 228.100.100.100
}
#备调度服务器虚拟VRRP设置
vrrp_instance VRRP {
        state BACKUP
        interface eth0
        virtual_router_id 66
        priority 90
        advert_int 1
        authentication {
                auth_type PASS
                auth_pass centos
        }
        virtual_ipaddress {
                172.18.65.2/16 dev eth0
        }
        notify_master "/etc/keepalived/notify.sh master"
        notify_backup "/etc/keepalived/notify.sh backup"
        notify_fault "/etc/keepalived/notify.sh fault"
}
#备调度服务器调度规则和主机设置
virtual_server 172.18.65.2 80 {
        delay_loop 1
        lb_algo wrr
        lb_kind DR
        protocol TCP
        sorry_server 127.0.0.1 80
        real_server 172.18.65.3 80 {
                weight 2
                HTTP_GET {
                        url {
                                path /
                                status_code 200
                        }
                connect_timeout 1
                nb_get_retry 3
                delay_before_retry 3
                }
        }
        real_server 172.18.65.4 80 {
                weight 1
                HTTP_GET {
                        url {
                                path /
                                status_code 200
                        }
                connect_timeout 1
                nb_get_retry 3
                delay_before_retry 3
                }
        }
}
{% endhighlight %}

{% highlight javascript linenos=table %}
#为VS1和VS2准备通知脚本
[root@VS1 ~]# vim notify.sh
#!/bin/bash 
# 
contact='root@localhost' 
notify() { 
    mailsubject="$(hostname) to be $1, vip floating" 
    mailbody="$(date +'%F %T'): vrrp transition, $(hostname) changed to be $1" 
    echo "$mailbody" | mail -s "$mailsubject" $contact 
} 
case $1 in 
master) 
    notify master 
    ;; 
backup) 
    notify backup 
    ;; 
fault) 
    notify fault 
    ;; 
*) 
    echo "Usage: $(basename $0) {master|backup|fault}" 
    exit 1 
    ;; 
esac
#拷贝至两个VS服务器的/etc/keepalived/目录下，并给予执行权限
[root@VS1 ~]# chmod +x /etc/keepalived/notify.sh 
[root@VS2 ~]# chmod +x /etc/keepalived/notify.sh
{% endhighlight %}

(4)利用脚本配置RS上的集群环境
{% highlight javascript linenos=table %}
#脚本如下
[root@VR1 ~]# vim  lvs_dr_rs.sh
#!/bin/bash
#
vip=172.18.65.2
mask='255.255.255.255'
dev=lo:1
rpm -q httpd &> /dev/null || yum -y install httpd &>/dev/null
service httpd start &> /dev/null && echo "The httpd Server is Ready!"
#echo "<h1>`hostname`</h1>" > /var/www/html/index.html

case $1 in
start)
    echo 1 > /proc/sys/net/ipv4/conf/all/arp_ignore
    echo 1 > /proc/sys/net/ipv4/conf/lo/arp_ignore
    echo 2 > /proc/sys/net/ipv4/conf/all/arp_announce
    echo 2 > /proc/sys/net/ipv4/conf/lo/arp_announce
    ifconfig $dev $vip netmask $mask broadcast $vip up
    #route add -host $vip dev $dev
    echo "The RS Server is Ready!"
    ;;
stop)
    ifconfig $dev down
    echo 0 > /proc/sys/net/ipv4/conf/all/arp_ignore
    echo 0 > /proc/sys/net/ipv4/conf/lo/arp_ignore
    echo 0 > /proc/sys/net/ipv4/conf/all/arp_announce
    echo 0 > /proc/sys/net/ipv4/conf/lo/arp_announce
    echo "The RS Server is Canceled!"
    ;;
*)
    echo "Usage: $(basename $0) start|stop"
    exit 1
    ;;
esac
{% endhighlight %}

{% highlight javascript linenos=table %}
#在两台RS服务器上执行改脚本
[root@RS1 app]# chmod +x lvs_dr_rs.sh
[root@RS1 app]# bash lvs_dr_rs.sh start
[root@VS2 app]# chmod +x lvs_dr_rs.sh
[root@VS2 app]# bash lvs_dr_rs.sh start
{% endhighlight %}

（5）在VS服务器启动keepalived，并检查策略，组播，测试是否正常工作
{% highlight javascript linenos=table %}
[root@VS1 ~]# service keepalived start
[root@VS1 ~]# ipvsadm -ln 
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  172.18.65.2:80 wrr
  -> 172.18.65.3:80               Route   2      0          0         
  -> 172.18.65.4:80               Route   1      0          0
[root@VS1 ~]# ip a
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 00:0c:29:05:58:f9 brd ff:ff:ff:ff:ff:ff
    inet 172.18.65.69/16 brd 172.18.255.255 scope global eth0
    inet6 fe80::20c:29ff:fe05:58f9/64 scope link 
       valid_lft forever preferred_lft forever
[root@VS2 ~]# tcpdump -i eth0 -nn host 228.100.100.100
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 65535 bytes
20:41:15.210067 IP 172.18.65.74 > 228.100.100.100: VRRPv2, Advertisement, vrid 66, prio 100, authtype simple, intvl 1s, length 20
20:41:16.211577 IP 172.18.65.74 > 228.100.100.100: VRRPv2, Advertisement, vrid 66, prio 100, authtype simple, intvl 1s, length 20
#从上面我们可以分析出：
	首先，配置的ipvs策略已经在主调度器生效，模式DR
	其次，VIP已经被配置到了主调度器VS1的eth0网卡
	最后，VS1在不断向外发送组播，宣告自己的vrid，优先级，认证方式，发送频率
总结：主调度器正常运行
	
[root@VS2 ~]# service keepalived start
[root@VS2 ~]# ipvsadm -ln
IP Virtual Server version 1.2.1 (size=4096)
Prot LocalAddress:Port Scheduler Flags
  -> RemoteAddress:Port           Forward Weight ActiveConn InActConn
TCP  172.18.65.2:80 wrr
  -> 172.18.65.3:80               Route   2      0          0         
  -> 172.18.65.4:80               Route   1      0          0 
#从上面我们可以分析出：
	首先，配置的ipvs策略已经在备调度器生效，模式DR
	其次，VIP并没有配置到备用服务器
	最后，VS2没有向外发送组播
总结：备调度器正常运行

[root@client ~]# for i in {1..12};do curl 172.18.65.2 ;done
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
#从上面我们可以分析出：
VS和RS正常工作，ipvs策略已经生效
{% endhighlight %}

（6）测试高可用是否生效
{% highlight javascript linenos=table %}
[root@VS1 ~]# service keepalived stop
[root@VS1 ~]#service keepalived status 
Redirecting to /bin/systemctl status keepalived.service
● keepalived.service - LVS and VRRP High Availability Monitor
   Loaded: loaded (/usr/lib/systemd/system/keepalived.service; disabled; vendor preset: disabled)
   Active: inactive (dead)
 
[root@VS2 ~]# mail
Heirloom Mail version 12.4 7/29/08.  Type ? for help.
"/var/spool/mail/root": 2 messages 1 new
    1 root                  Mon Oct 30 20:34  19/675   "VS2 to be backup, vip floati"
>N  2 root                  Mon Oct 30 20:56  18/664   "VS2 to be master, vip floati"
& 
Message  2:
From root@VS2.localdomain  Mon Oct 30 20:56:02 2017
Return-Path: <root@VS2.localdomain>
X-Original-To: root@localhost
Delivered-To: root@localhost.localdomain
Date: Mon, 30 Oct 2017 20:56:02 +0800
To: root@localhost.localdomain
Subject: VS2 to be master, vip floating
User-Agent: Heirloom mailx 12.4 7/29/08
Content-Type: text/plain; charset=us-ascii
From: root@VS2.localdomain (root)
Status: R
2017-10-30 20:56:02: vrrp transition, VS2 changed to be master

[root@VS2 ~]#ip a
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP qlen 1000
    link/ether 00:0c:29:05:58:f9 brd ff:ff:ff:ff:ff:ff
    inet 172.18.65.69/16 brd 172.18.255.255 scope global eth0
    inet 172.18.65.2/16 scope global secondary eth0
    inet6 fe80::20c:29ff:fe05:58f9/64 scope link 
       valid_lft forever preferred_lft forever

[root@VS2 ~]#tcpdump -i eth0 -nn host 228.100.100.100
tcpdump: verbose output suppressed, use -v or -vv for full protocol decode
listening on eth0, link-type EN10MB (Ethernet), capture size 65535 bytes
20:59:21.811031 IP 172.18.65.69 > 228.100.100.100: VRRPv2, Advertisement, vrid 66, prio 90, authtype simple, intvl 1s, length 20
20:59:22.811754 IP 172.18.65.69 > 228.100.100.100: VRRPv2, Advertisement, vrid 66, prio 90, authtype simple, intvl 1s, length 20

#我们关闭主调度器，让其失效，通过以上分析，我们可以得出下面的结论
	首先，通知脚本工作正常，已经通知VS2成为了主调度器
	其次，VIP已经被自动配置到了VS2的eth0网卡
	最后，VS2在不断向外发送组播，宣告自己的vrid，优先级，认证方式，发送频率
	
[root@client ~]# for i in {1..12};do curl 172.18.65.2 ;done
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
this RS1 web page
this RS1 web page
this RS2 web page
#我们在客户端进行测试，发现调度器工作正常
{% endhighlight %}

（7）测试健康检查和自动调度是否生效
{% highlight javascript linenos=table %}
[root@RS2 ~]# service httpd stop
[root@RS2 ~]# service httpd status
httpd is stopped

[root@VS2 ~]#mail
Heirloom Mail version 12.4 7/29/08.  Type ? for help.
"/var/spool/mail/root": 3 messages 1 new
    1 root                  Mon Oct 30 20:34  19/675   "VS2 to be backup, vip floati"
    2 root                  Mon Oct 30 20:56  19/675   "VS2 to be master, vip floati"
>N  3 keepalived@localhost  Mon Oct 30 21:05  17/642   "[VS2] Realserver [172.18.65."
& 
Message  3:
From keepalived@localhost.localdomain  Mon Oct 30 21:05:40 2017
Return-Path: <keepalived@localhost.localdomain>
X-Original-To: root@localhost
Delivered-To: root@localhost.localdomain
Date: Mon, 30 Oct 2017 13:05:40 +0000
From: keepalived@localhost.localdomain
Subject: [VS2] Realserver [172.18.65.4]:80 - DOWN
X-Mailer: Keepalived
To: root@localhost.localdomain
Status: R
=> CHECK failed on service : connection error <=

[root@client ~]# for i in {1..12} ;do curl 172.18.65.2 ;done
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page
this RS1 web page

[root@RS1 app]# service httpd stop
[root@RS1 app]# service httpd status
httpd is stopped

[root@VS2 ~]#mail
Heirloom Mail version 12.4 7/29/08.  Type ? for help.
"/var/spool/mail/root": 4 messages 1 new
    1 root                  Mon Oct 30 20:34  19/675   "VS2 to be backup, vip floati"
    2 root                  Mon Oct 30 20:56  19/675   "VS2 to be master, vip floati"
    3 keepalived@localhost  Mon Oct 30 21:05  18/653   "[VS2] Realserver [172.18.65."
>N  4 keepalived@localhost  Mon Oct 30 21:09  17/642   "[VS2] Realserver [172.18.65."
& 
Message  4:
From keepalived@localhost.localdomain  Mon Oct 30 21:09:18 2017
Return-Path: <keepalived@localhost.localdomain>
X-Original-To: root@localhost
Delivered-To: root@localhost.localdomain
Date: Mon, 30 Oct 2017 13:09:18 +0000
From: keepalived@localhost.localdomain
Subject: [VS2] Realserver [172.18.65.3]:80 - DOWN
X-Mailer: Keepalived
To: root@localhost.localdomain
Status: R
=> CHECK failed on service : connection error <=

[root@client ~]# for i in {1..12} ;do curl 172.18.65.2 ;done
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server
this sorry server

#从上面我们可以分析出
	首先，在我们停止RS2的web服务后，调度器接收到了邮件通知，证明对后端的健康行检查功能正常
	其次，在客户端访问测试，所有的请求被调度到了RS1，证明自动调度功能正常
	最后，我们把RS1页停止后，在客户端进行测试，所有请求发往了sorryserver，证明sorryserver工作正常
{% endhighlight %}
