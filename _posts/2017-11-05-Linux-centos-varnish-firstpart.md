---
layout: post
title: "Varnish的学习和总结(第一部分)"
description: "最近在学习varnish，就对自己的学习笔记进行了整理和分类，以便后来的复习和强化"
categories: [centos6,centos7,service]
tags: [linux,varnish]
redirect_from:
  - /2017/11/05/
---
## 一、基础知识

### 1.简单的网站架构 ###

在了解varnish之前，我们首先要搞清楚明白为什么需要用到反向代理服务器（缓存服务器），以及哪种架构会用到缓存服务器。下面是一个简单的网站架构：
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/网站简单架构.jpg" width="600px"/>
</center>
**调度服务器组**：负责将受到的请求调度到相应的后台服务器上，如lvs，nginx，haproxy <br/>
**缓存服务器组**：负责减轻后台服务器的压力，优化用户访问体验，如varnish <br/>
**静态处理服务器组**：负责处理静态页面请求，如apache，nginx <br/>
**动态处理服务器组**：负责处理动态页面请求，如php-fpm，tomcat <br/>
**数据库存储服务器组**：负责存储结构化和非结构化的数据，如mysql， Mariadb，mongodb <br/>
**分布式存储服务器组**：负责存储各种文件，如hadoop <br/>
**服务监控系统**：负责监控服务器器工作情况并进行通知，如zabbix，nagios <br/>
**文件配置系统**：监控服务器，并自动进行相关服务的文件配置 <br/>
**内容跟踪系统**：进行版本追踪，解决版本更新问题，如git <br/>
**搜索引擎系统**：根据算法负责数据和内容的查找 <br/>
**自动发布系统**： 自动灰度发布上线服务器 <br/>

由上图可知，我们的缓存服务器要架构在调度器和后台RS之间，前端的调度器调度将请求交给我们的缓存服务器，经由缓存服务器再交由后代服务器。那么为什么要这样架构呢？或者说这样架构有什么好处。这个问题就涉及了我们为什么要用到缓存服务器的问题。<br/>
一句话来说：因为程序的运行具有局部性，这种局部性表现在时间和空间两个方面：时间局部性，数据被访问过之后，可能很快会被再次访问到；空间局部性，数据被访问时，其周边的数据也有可能被访问到。缓存服务器的存在就是为了解决这种局部性带来的问题，时间局限性意味着刚刚被请求的资源会被立即重新请求甚至并发请求，这样我们的服务器要不断的进行IO操作，而空间局限性意味着一个资源相关的资源也会被同时请求，这意味着我们的服务器不仅要不断进行IO还要大量进行IO，服务器的压力可想而知。而增加缓存服务器不仅可以减轻我们后端服务器的压力，还可以增加客户的访问体验，提升用户体验。

### 2.两种缓存机制 ###

**(1)过期机制：**

以客户端处的缓存为例，服务器将数据回应给客户端，客户端会进行缓存，同时在返回的数据中表明有缓存有效时间，在这个时间内浏览器再请求同样的内容，会直接从本地缓存中读取而不会再请求服务器。如果在缓存有效时间内，服务器更新了这些数据，按照工作流程，浏览器再这个时间内还是会读取旧的内容，不过能够被缓存的一般重要性比较低，对用户体验影响不大。
根据过期机制的逻辑，会出现两个问题：
第一，缓存有效时间内的数据更新，客户端无法得知，影响用体验；
第二，缓存时间失效后，数据没更新过，客户端还是会重新请求服务器，给服务器造成了压力。
缓存在http首部中的表现：
Expires:Thu, 13 Aug 2026 02:05:12 GMT
在http1.0中使用，使用的是绝对时间，后面的是数字是指能缓存到什么时候，但是由于全球时区不同，会造成很大偏差
Cache-Control:max-age=315360000
在http1.1中引入该首部，加入相对时长，max-age后面的数字表示能缓存多少秒；引入控制选项，告诉缓存系统该如何缓存数据，privite表示只能在私有空间（浏览器）缓存，public在公共空间（缓存服务器）缓存，no-cache条件式缓存，每次缓存前都询问数据是否发生过改变，no-storage不允许缓存
如下：
{% highlight javascript linenos=table %}
	#请求报文用于通知缓存服务如何使用缓存响应请求：
	cache-request-directive = 
	"no-cache"，                        
	| "no-store"                         
	| "max-age" "=" delta-seconds        
	| "max-stale" [ "=" delta-seconds ]  
	| "min-fresh" "=" delta-seconds      
	| "no-transform"                    
	| "only-if-cached"                  
	| cache-extension  
	#响应报文用于通知缓存服务器如何存储上级服务器响应的内容：
	cache-response-directive =
	"public"                               
	| "private" [ "=" <"> 1#field-name <"> ] 
	| "no-cache" [ "=" <"> 1#field-name <"> ]，#可缓存，但响应给客户端之前需要revalidation，即必须发出条件式请求进行缓存有效性验正；
	| "no-store" ，#不允许存储响应内容于缓存中；                           
	| "no-transform"                        
	| "must-revalidate"                     
	| "proxy-revalidate"                  
	| "max-age" "=" delta-seconds  #最大缓存时长         
	| "s-maxage" "=" delta-seconds  #最大缓存时长，仅用于控制公共缓存时长
	| cache-extension
{% endhighlight %}

**(2)条件式请求机制：**

为了解决上述问题，就出现了条件式请求机制。客户端在请求数据的时候，会询问服务器，自己缓存的内容是否进行过修改，如果没有就继续使用缓存，如果修改了就请求新的数据。
**如何实现：**<br/>
第一种方法，`Last-Modified/If-Modified-Since`：基于文件的修改时间戳来判别；服务器回应给客户端数据的时候，也回应一个时间戳来标记文件，每次客户端请求服务器就对比时间戳，若果时间戳没变化，就证明数据没改变，客户端继续使用缓存，返回代码304；如果改变了就回应新的数据，返回代码200。在http中的首部：`Last-Modified:Wed, 03 Sep 2014 10:00:27 GMT` <br/>
第二种方法，Etag/If-None-Match：基于文件的校验码来判别；对回应的文件进行hash，取其值，每次客户端请求服务器就对比hash值，没变就使用缓存，变了就返回新数据。在http中的首部：`ETag:"1ec5-502264e2ae4c0"` <br/>

>注意：
条件式请求也存在问题，那就是每次服务器都要比较数据的时间戳或者hash值，虽然不用返回请求报文，但后台操作仍不可少，所以无形中加大了服务器压力。最好的办法是将两种机制结合起来使用：首先设置一个缓存有效期，在有效期内不对比不询问，直接使用缓存中的数据；超过有效期后再想服务器发送时间戳或者校验码让服务器进行对比，如果没变化就继续使用缓存，变化就返回新数据。（可以将缓存有效时间设置端一点，在减轻服务端一定压力的情况下，也让步于提升用户体验，二者取平衡）。

## 二、Varnish介绍

Varnish 是一款高性能且开源的反向代理服务器和 HTTP 加速器，其采用全新的软件体系机构，和现在的硬件体系紧密配合，与传统的 squid 相比，varnish 具有性能更高、速度更快、管理更加方便等诸多优点，很多大型的网站都开始尝试使用 varnish 来替换 squid，这些都促进 varnish 迅速发展起来。挪威的最大的在线报纸 Verdens Gang(vg.no) 使用 3 台 Varnish 代替了原来的 12 台 Squid，性能比以前更好，这是 Varnish 最成功的应用案例。

### 1.Varnish的程序架构 ###

varnish主要运行两个进程：Management进程和Child进程(也叫Cache进程)，组件shared memory log共享内存日志。如下图：
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/varnish程序架构.png" width="600px"/>
</center>

**(1)Management进程**
<br/>
主要实现应用新的配置、编译VCL、监控varnish、初始化varnish以及提供一个命令行接口等。Management进程会每隔几秒钟探测一下Child进程以判断其是否正常运行，如果在指定的时长内未得到Child进程的回应，Management将会重启此Child进程。

**(2)Child进程**
<br/>
包含多种类型的线程，常见的如：<br/>

- **Worker threads：**负责与客户端通信；child进程会为每个会话启动一个worker线程，因此，在高并发的场景中可能会出现数百个worker线程甚至更多。<br/>
- **Backend communication：**  与后端服务器交互；不一定会经常通讯，一旦缓存完成就很少再打扰后端服务器。<br/>
- **Acceptor线程：**接收新的连接请求并响应。<br/>
- **Expiry线程：**从缓存中清理过期内容。<br/>
- **Log/status：**记录日志和统计数据。<br/>
- **storage/hashing：**管理缓存存储。<br/>
- **object expiry：**缓存项过期清理线程。<br/>

**(3)shared memory log组件：**
<br/>
为了防止日志影响性能，方便与系统的其它部分进行交互，Child进程使用了可以通过文件系统接口进行访问的共享内存日志(shared memory log)，因此，如果某线程需要记录信息，其仅需要持有一个锁，而后向共享内存中的某内存区域写入数据，再释放持有的锁即可。而为了减少竞争，每个worker线程都使用了日志数据缓存。专门设置一个内存大小存储日志，大小一般为90M，内存空间用完就重新覆盖写入。存储两方面的内容：统计数据和日志记录。<br/>
varnish提供了多个不同的工具如varnishlog、varnishncsa或varnishstat等来分析共享内存日志中的信息并能够以指定的方式进行显示。<br/>
**统计数据：**此区域不断累加<br/>
**计数器：**例如接受多少了请求，处理过多少，命中了多少次，miss了多少次等等；<br/>
**日志区域：**此区域轮循使用<br/>
**日志记录：**包含一些有关日志的命令行工具<br/>
**查看工具如下：<br/>**

|-----------------+-------------------------------------------|
|     工具	      |          解释						      |
|-----------------|:-----------------------------------------:|
| varnishlog      |读取日志区域的日志内容			   		   	  |
| varnishstast    |读取统计区域的统计内容  				  	  |
| varnishhist     |查看日志历史数据          					  |
| varnishtop      |对统计数据进行排序显示         			      |
| varnishncsa     |兼容传统的日志显示方式（combind）		      |
|-----------------+-------------------------------------------|

**(4)补充知识：carnish的配置接口：VCL**
<br/>
Varnish Configuration Language, varnish配置语言，域类型配置语言，只能作用于某些固定的域。VCL用于让管理员定义缓存策略，而定义好的策略将由varnish的management进程分析、转换成C代码、编译成二进制程序并连接至child进程。<br/>
`vcl complier --> c complier --> shared object `

### 2.varnish的程序环境： ###

**(1)配置环境文件：**
{% highlight javascript linenos=table %}
	/etc/varnish/varnish.params： 
	配置varnish服务进程的工作特性，例如监听的地址和端口，最大可以接受多节并发，缓存机制等等；
	/etc/varnish/default.vcl：
	配置各Child/Cache线程的缓存策略；需要利用VCL语言进行配置。
{% endhighlight %}

**(2)主程序：**
{% highlight javascript linenos=table %}
	/usr/sbin/varnishd
	CLI interface命令行管理工具：
	/usr/bin/varnishadm
	Shared Memory Log交互工具：
	/usr/bin/varnishhist
	/usr/bin/varnishlog
	/usr/bin/varnishncsa
	/usr/bin/varnishstat
	/usr/bin/varnishtop  
{% endhighlight %}

**(3)测试工具程序**
{% highlight javascript linenos=table %}
	/usr/bin/varnishtest
{% endhighlight %}

**(4)VCL配置文件重载程序：**
{% highlight javascript linenos=table %}
	usr/sbin/varnish_reload_vcl;
	该工具可以实现让vcl语言直接实现两次编译成为可装载的模块
{% endhighlight %}

**(5)Systemd Unit File：**
{% highlight javascript linenos=table %}
	/usr/lib/systemd/system/varnish.service
	varnish服务单元
	/usr/lib/systemd/system/varnishlog.service
	/usr/lib/systemd/system/varnishncsa.service 
	日志的服务单元，启动该单元意味着可以将日志的存储策略从内存存储到硬盘，一般不建议开启，因为影响效率，日志功能并不是其主要功能。记录原始的nasa格式则启用varnishncsa.service，记录varnish特有的日志格式存储启用 varnishlog.service
{% endhighlight %}

### 3.缓存相关的HTTP首部 ###

HTTP协议提供了多个首部用以实现页面缓存及缓存失效的相关功能，这其中最常用的有：<br/>
**(1)Expires：**<br/>
用于指定某web对象的过期日期/时间，通常为GMT格式；一般不应该将此设定的未来过长的时间，一年的长度对大多场景来说足矣；其常用于为纯静态内容如JavaScripts样式表或图片指定缓存周期；<br/>
**(2)Cache-Control：**<br/>
用于定义所有的缓存机制都必须遵循的缓存指示，这些指示是一些特定的指令，包括public、private、no-cache(表示可以存储，但在重新验正其有效性之前不能用于响应客户端请求)、no-store、max-age、s-maxage以及must-revalidate等；Cache-Control中设定的时间会覆盖Expires中指定的时间；<br/>
**(3)Etag：**<br/>
响应首部，用于在响应报文中为某web资源定义版本标识符；<br/>
**(4)Last-Mofified：**<br/>
响应首部，用于回应客户端关于Last-Modified-Since或If-None-Match首部的请求，以通知客户端其请求的web对象最近的修改时间；<br/>
**(5)If-Modified-Since：**<br/>
条件式请求首部，如果在此首部指定的时间后其请求的web内容发生了更改，则服务器响应更改后的内容，否则，则响应304(not modified)；<br/>
**(6)If-None-Match：**<br/>
条件式请求首部；web服务器为某web内容定义了Etag首部，客户端请求时能获取并保存这个首部的值(即标签)；而后在后续的请求中会通过If-None-Match首部附加其认可的标签列表并让服务器端检验其原始内容是否有可以与此列表中的某标签匹配的标签；如果有，则响应304，否则，则返回原始内容；<br/>
**(7)Vary：**<br/>
响应首部，原始服务器根据请求来源的不同响应的可能会有所不同的首部，最常用的是Vary: Accept-Encoding，用于通知缓存机制其内容看起来可能不同于用户请求时Accept-Encoding-header首部标识的编码格式；<br/>
**(8)Age：**<br/>
缓存服务器可以发送的一个额外的响应首部，用于指定响应的有效期限；浏览器通常根据此首部决定内容的缓存时长；如果响应报文首部还使用了max-age指令，那么缓存的有效时长为“max-age减去Age”的结果；<br/>

## 三、Varnish的params

### 1.配置文件/etc/varnish/varnish.params
{% highlight javascript linenos=table %}
	# Varnish environment configuration description. This was derived from the old style sysconfig/defaults settings Set this to 1 to make systemd reload try to switch VCL without restart.
	RELOAD_VCL=1
	
	# Main configuration file. You probably want to change it.
	#定义varnish服务读取的vcl配置文件，可利用命令varnishd临时修改
	VARNISH_VCL_CONF=/etc/varnish/default.vcl 
	
	# Default address and port to bind to. Blank address means all IPv4 and IPv6 interfaces, otherwise specify a host name, an IPv4 dottedquad, or an IPv6 address in brackets.
	#定义监听的地址，不定义代表监听本机所有地址
	# VARNISH_LISTEN_ADDRESS=192.168.1.5 
	#定义服务监听的端口
	VARNISH_LISTEN_PORT=6081 
	
	# Admin interface listen address and port
	VARNISH_ADMIN_LISTEN_ADDRESS=127.0.0.1 #定义进行管理时的交互地址，默认本机地址，意味着只能在本机管理，当远程管理的时候需要监听一个其他端口
	VARNISH_ADMIN_LISTEN_PORT=6082 #定义进行管理的交互端口
	# Shared secret file for admin interface
	VARNISH_SECRET_FILE=/etc/varnish/secret #定义管理该服务时使用的秘钥文件，这项主要是为了远程管理的安全设置的，注意进行远程管理要将上面的监听地址进行修改。
	# Backend storage specification, see Storage Types in the varnishd(5) man page for details#定义varnish的缓存选项和大小；注：varnish的缓存是通过键值对实现的；
	VARNISH_STORAGE="malloc,256M" 
	
	# User and group for the varnishd worker processes
	VARNISH_USER=varnish #定义程序运行者
	VARNISH_GROUP=varnish #定义程序运行所属组
	# Other options, see the man page varnishd(1)
	#下面是一些运行时参数，通过DAEMON_OPTS进行定义，即在程序运行中也可以进行修改的参数，每一个参数都要通过-p指明；但一般不必要在此定义，但有一些特殊要求的，启动就让生效的；此外，要是希望定义以后不允许在运行中再进行修改的参数，可以加上-r指明，这样就保证了不能再程序运行期间进行修改。
	DAEMON_OPTS="-p thread_pool_min=5 -p thread_pool_max=500 -p thread_pool_timeout=300 -r hread_pool_min，thread_pool_max，thread_pool_timeout "
{% endhighlight %}

>注：niginx的缓存是将键放在内存中，值放在磁盘上，二者通过hash值进行映射，键本身被hash成了一个字符串，这个字符串中隐藏着值的路由信息（及文件存放的路径），请求到来与内存中的这个hash后的键进行匹配，成功则根据其中的路由找到值并返回。varnish的缓存存储方式分为三种：<br/>第一种是和niginx相似的键在内存，值在磁盘，即file模式，但需要注意的是varnish的file模式和niginx有不同之处，它是“黑盒”模式，我们只知道其以文件存储，但并不知道值在文件中是什么状态，而且这些值在重启后会丢失；<br/>第二种就是键值对都在内存中，即malloc（）方式，这样速度更快，需要注意的是malloc（）是串行的，只能一个个处理请求，varnish准确来说用的是jemalloc（），是并行的，只不过沿袭原来的写法；<br/>第三种是persistent，实验阶段，基于磁盘，为了避免上面两种值在重启会丢失的情况。内存在生产中是非常大的，但是注意也不能过大，内存会产生碎片，而且不像磁盘，这些碎片会严重影响内存的性能。

### 2.varnish的运行时参数（可调参数）###

Varnish有许多参数，虽然大多数场景中这些参数的默认值都可以工作得很好，然而特定的工作场景中要想有着更好的性能的表现，则需要调整某些参数。可以在管理接口中使用`param.show -l`命令查看这些参数，而使用`param.set`则能修改这些参数的值。然而，在命令行接口中进行的修改不会保存至任何位置，因此，重启varnish后这些设定会消失。此时，可以通过启动脚本使用-p选项在varnishd启动时为其设定参数的值。然而，除非特别需要对其进行修改，保持这些参数为默认值可以有效降低管理复杂度。(后面我们会对这些如何设置进行介绍)

### 3.线程模型(Trheading model) ###

varnish的child进程由多种不同的线程组成，分别用于完成不同的工作。
例如：

|------------------+----------------------------------------------|
|    线程	       |          解释						          |
|------------------|:--------------------------------------------:|
| cache-worker     |      每连接一个，用于处理请求			          |
| cache-main       |全局只有一个，用于启动cache				      |
| ban lurker       |一个，用于清理bans         			    	  |
| acceptor         |一个，用于接收新的连接请求        			      |
| epoll/kqueue     |数量可配置，默认为2，用于管理线程池		          | 
| expire           |一个，用于移除老化的内容	                      |
| backend poll     |每个后端服务器一个,用于检测后端服务器的健康状况    |
|------------------+----------------------------------------------|

>注：在配置varnish时，一般只需为关注cache-worker线程，而且也只能配置其线程池的数量，而除此之外的其它均非可配置参数。与此同时，线程池的数量也只能在流量较大的场景下才需要增加，而且经验表明其多于2个对提升性能并无益处。

### 4.线程相关的参数(Threading parameters) ###

varnish为每个连接使用一个线程，因此，其worker线程的最大数决定了varnish的并发响应能力。
下面是线程池相关的各参数及其配置：
{% highlight javascript linenos=table %}
	thread_pools               2 [pools]
	#Number of worker thread pools，启用的线程池数量，类似于nginx的work process，每个线程池可以处理多个并发请求，最好小于或等于CPU核心数量；
	thread_pool_max            5000[threads]
	#The maximum number of worker threads in each pool，每线程池的线程数；即每线程池的最大并发接受数
	thread_pool_min            100 [threads]
	#The minimum number of worker threads in each pool. 额外意义为“最大空闲线程数”，当处理完成，空闲线程会被减为此数
	thread_pool_add_delay      2 [milliseconds]
	#thread_pool_adWait at least this long after creating a thread.当请求到来，增加线程时的等待时间；避免刚增加请求就消失
	thread_threshold  2 [requests]
	#Wait this long after destroying a thread.当请求结束，删除线程时的等待时间；避免刚删除请求又大量涌入而来不及处理
	thread_pool_fail_delay     200 [milliseconds]
	thread_pool_purge_delay    1000 [milliseconds]
	thread_pool_stack          65536 [bytes]
	thread_pool_timeout        60 [seconds]
	#Thread idle threshold.  Threads in excess of thread_pool_min, which have been idle for at least this long, will be destroyed.线程池超时时长，超过这个时间开始杀空闲线程直至最少线程数
	thread_pool_workspace      16384 [bytes]
	thread_stats_rate          10 [requests]
{% endhighlight %}

在上面的参数中，其中最关键的当属`thread_pool_max`和`thread_pool_min`，它们分别用于定义每个线程池中的最大线程数和最少线程数。因此，在某个时刻，至少有`thread_pool_min`\* `thread_pools`个worker线程在运行，但至多不能超出`thread_pool_max`\*`thread_pools`个。根据需要，这两个参数的数量可以进行调整，varnishstat命令的n_wrk_queued可以显示当前varnish的线程数量是否足够，如果队列中始终有不少的线程等待运行，则可以适当调大thread_pool_max参数的值。但一般建议每台varnish服务器上最多运行的worker线程数不要超出5000个。<br/>
当某连接请求到达时，varnish选择一个线程池负责处理此请求。而如果此线程池中的线程数量已经达到最大值，新的请求将会被放置于队列中或被直接丢弃。默认线程池的数量为2，这对最繁忙的varnish服务器来说也已经足够。

### 5.Timer相关参数 ###
{% highlight javascript linenos=table %}
	send_timeout：
		Send timeout for client connections. If the HTTP response hasn't been transmitted in this many seconds the session is closed.
	timeout_idle：
		Idle timeout for client connections. 
	timeout_req： 
		Max time to receive clients request headers, measured from first non-white-space character to double CRNL.
	cli_timeout：
		Timeout for the childs replies to CLI requests from the mgt_param.
{% endhighlight %}
### 6.共享内存日志 ###
共享内存日志(shared memory log)通常被简称为shm-log，它用于记录日志相关的数据，大小为80M。varnish以轮转(round-robin)的方式使用其存储空间。一般不需要对shm-log做出更多的设定，但应该避免其产生I/O，这可以使用tmpfs实现，其方法为在/etc/fstab中设定一个挂载至/var/lib/varnish目录(或其它自定义的位置)临时文件系统即可。
