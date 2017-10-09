---
layout: post
title:  "磁盘分区相关知识"
date:   2017-7-2 18:34:10 +0700
categories: [linux, disk]
---

# **磁盘分区相关知识** #
>使用磁盘分区的过程
设备识别→设备分区→创建文件系统→标记文件系统→在/etc/fstab文件中创建条目→挂载新的文件系统

>分区不是必须的，但是分区是必要的:
优化I/O性能 
实现磁盘空间配额限制 
提高修复速度 
隔离系统和程序 
安装多个OS 
采用不同文件系统

>不重启激活新添加的磁盘：echo "- - -" > /sys/class/scsi_host/host0/scan

## MBR分区（Master Boot Record）
>使用32位表示扇区 数，分区不超过512*2^32=2TB
>
0磁道0扇区（成为mbr）：512bytes 

>446bytes: boot loader （其他分区的第一个扇区也会余出446，但是是空的不存储引导数据）

>64bytes：分区表 记录分区名 分区地址 其中16bytes标识一个分区 所以最多只能划分四个分区 4个主分区；3主分区+1扩展(N个逻辑分区)
 
>2bytes: 55AA 标识位 表示有分区的意思

新磁盘未分区的mbr全部为零 没有分区表 查看分区前512字节
`hexdump -C -n 512 /dev/sda`
![](http://wx4.sinaimg.cn/mw690/9e44f588gy1fiqgucruixj211y0o7dwv.jpg)
分区结构图
![](http://wx4.sinaimg.cn/mw690/9e44f588gy1fiqgy2vcksj20rs0gs407.jpg)
## GPT分区（Globals Unique Identifiers）
>支持128个分区，使用64位 支持8Z（ 512Byte/block ）或者64Z （ 4096Byte/block）
>
>使用128位UUID(Universally Unique Identifier) 表示磁盘 和分区 GPT分区表自动备份在头和尾两份，并有CRC校验位 

>UEFI (统一扩展固件接口)硬件支持GPT，使操作系统启动（BIOS本身不支持GPT分区的，只能利用UEFI技术 才能启动系统UEFI+GPT=BIOS+MBR）

GPT分区结构图
![](http://wx2.sinaimg.cn/mw690/9e44f588gy1fiqgufcpccj20ri0lyjsr.jpg)

## 创建分区
>列出块设备 lsblk 

>创建分区使用：
fdisk 创建MBR分区
gdisk 创建GPT分区 
parted 高级分区操作(二者都可以)
partprobe－重新设置内存中的内核分区表版本

### parted
直接输入以交互式方式进行分区操作
Parted /dev/sdb

也可以使用非交互式进行分区操作

用法：parted [选项]... [设备 [命令 [参数]...]...] 
parted /dev/sdb mklabel gpt|msdos 

指定用分区方式（即格式化分区）

![](http://wx1.sinaimg.cn/mw690/9e44f588gy1fiqguhtuoej20hz02l0t7.jpg)

parted /dev/sdb print 显示分区表

![](http://wx4.sinaimg.cn/mw690/9e44f588gy1fiqguh8893j20l508sjtn.jpg)

parted /dev/sdb mkpart primary 1 200 （默认M）创建分区
parted /dev/sdb rm 1 
删除磁盘分区 按照编号删除
parted -l 显示磁盘分区信息
![](http://wx3.sinaimg.cn/mw690/9e44f588gy1fiqgugno60j20qu0o6n3m.jpg)

GPT和MBR分区没有必要进行转换，一但转换内部信息会被破坏，因为二者分区的结构不同
![](http://wx1.sinaimg.cn/mw690/9e44f588gy1fiqgujq6khj20ys03gdgy.jpg)
#### 延伸：

对于MBR分区来说，若0磁道0扇区的mbr被破坏（即前512字节），会造成严重后果，机器无法启动。
![](http://wx2.sinaimg.cn/mw690/9e44f588gy1fiqguig872j20m3030dga.jpg)

利用lsblk仍可以看到分区信息，fdisk看不到，因为分区表一份在磁盘一份在内存，二者是不同步的。
如何恢复？

*  可以将512字节分区表提前备份到本地和其他主机

![](http://wx4.sinaimg.cn/mw690/9e44f588gy1fiqgufy32vj20im03tmxs.jpg)

* 当磁盘的mbr分区表被破坏后，当没有重启，可以利用本地备份的分区表恢复

![](http://wx2.sinaimg.cn/mw690/9e44f588gy1fiqguduxpzj20l207r403.jpg)

### gdisk和fdisk（交互式和非交互）

>gfisk /dev/sdb 类fdisk 的GPT分区工具 

>交互：
fdisk /dev/sdb  管理分区

>非交互：
fdisk -l [-u] [device...] 查看分区 
子命令： 
p 分区列表 
t 更改分区类型 
n 创建新分区 
d 删除分区 
v 校验分区 
u 转换单位 

Centos7默认以扇区为单位，可以选择以柱面为单位

![](http://wx2.sinaimg.cn/mw690/9e44f588gy1fiqguj64pdj20qi0d0ae5.jpg)

## 同步分区

>fdisk -l /dev/磁盘名 查看磁盘真实分区信息

>lsblk 或者cat /proc/partations 
查看内存中分区表

>通过以上两个命令可以看分区时不是已经同步

### 不同步解决办法
*	centos6 通知内核重新读取硬盘分区表 
	
	新增分区后用 
	partx -a /dev/DEVICE  
	kpartx -a /dev/DEVICE -f: force 

	删除分区后用 partx -d --nr M-N /dev/DEVICE 

* CentOS 5、7知内核重新读取硬盘分区表 

	使用partprobe [/dev/DEVICE]

### 一旦新增和删除分区，一定要记得同步分区表


PS:LINUX小白 敬请指教



