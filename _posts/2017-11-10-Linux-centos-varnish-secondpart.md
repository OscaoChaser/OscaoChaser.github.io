---
layout: post
title: "Varnish的学习和总结(第二部分)"
description: "本篇介绍Varnish余下的两部分"
categories: [centos6，centos7,service]
tags: [linux,varnish]
redirect_from:
  - /2017/11/10/
---

## 一、Varnish的vcl ##
Varnish Configuration Language (VCL)是varnish配置缓存策略的工具，它是一种基于“域”(domain specific)的简单编程语言，它支持有限的算术运算和逻辑运算操作、允许使用正则表达式进行字符串匹配、允许用户使用set自定义变量、支持if判断语句，也有内置的函数和变量等。使用VCL编写的缓存策略通常保存至.vcl文件中，其需要编译成二进制的格式后才能由varnish调用。事实上，整个缓存策略就是由几个特定的子例程如vcl_recv、vcl_fetch等组成，它们分别在不同的位置(或时间)执行，如果没有事先为某个位置自定义子例程，varnish将会执行默认的定义。
<br/>
VCL策略在启用前，会由management进程将其转换为C代码，而后再由gcc编译器将C代码编译成二进制程序。编译完成后，management负责将其连接至varnish实例，即child进程。正是由于编译工作在child进程之外完成，它避免了装载错误格式VCL的风险。因此，varnish修改配置的开销非常小，其可以同时保有几份尚在引用的旧版本配置，也能够让新的配置即刻生效。编译后的旧版本配置通常在varnish重启时才会被丢弃，如果需要手动清理，则可以使用varnishadm的vcl.discard命令完成。
<br/>
VCL用于让管理员定义缓存策略，而定义好的策略将由varnish的management进程分析、转换成C代码、编译成二进制程序并连接至child进程。varnish内部有几个所谓的状态(state)，在这些状态上可以附加通过VCL定义的策略以完成相应的缓存处理机制，因此VCL也经常被称作“域专用”**语言或状态引擎**，“域专用”指的是有些数据仅出现于特定的状态中，**“域”既有面对客户端的“状态引擎”，也有面对服务端的“状态引擎”**。

### 1.VCL语法 ###
配置文件/etc/varnish/default.vcl是varnish默认使用的vcl文件，其中的语法就是vcl语言。VCL的设计参考了C和Perl语言，因此，对有着C或Perl编程经验者来说，其非常易于理解。
**(1)基本语法说明如下：**
<br/>
- //、#或/* comment */用于注释
- sub $name {} 定义函数；每一个子历程以sub开头，配置段以{}括起来，每一个语句以分号结尾
- 不支持循环，有内置变量，不同变量有其固定使用位置
- 每一个语句结束都要使用终止语句return{}表明进入的下一个状态引擎，没有返回值
- 域专用的语言，Domain-specific
- 操作符：=(赋值)、==(等值比较)、~(模式匹配)、!(取反)、&&(逻辑与)、\|\|(逻辑或)

**(2)三类基本写法**
<br/>
{% highlight javascript linenos=table %}
	sub subroutine {
		...
	}
					
	if CONDITION {
		...
	} else {        
		...
	}
		
	return(),hash_data()
{% endhighlight %}

>注：
	VCL的函数不接受参数并且没有返回值，因此，其并非真正意义上的函数，这也限定了VCL内部的数据传递只能隐藏在HTTP首部内部进行。VCL的return语句用于将控制权从VCL状态引擎返回给Varnish，而非默认函数，这就是为什么VCL只有终止语句而没有返回值的原因。同时，对于每个“域”来说，可以定义一个或多个终止语句，以告诉Varnish下一步采取何种操作，如查询缓存或不查询缓存等。

### 2.VCL的状态引擎 ###
varnish开始处理一个请求时，首先需要分析HTTP请求本身，比如从首部获取请求方法、验正其是否为一个合法的HTT请求等。当这些基本分析结束后就需要做出第一个决策，即varnish是否从缓存中查找请求的资源。这个决定的实现则需要由VCL来完成，简单来说，要由vcl_recv方法来完成。如果管理员没有自定义vcl_recv函数，varnish将会执行默认的vcl_recv函数。然而，即便管理员自定义了vcl_recv，但如果没有为自定义的vcl_recv函数指定其终止操作(terminating)，其仍将执行默认的vcl_recv函数。事实上，varnish官方强烈建议让varnish执行默认的vcl_recv以便处理自定义vcl_recv函数中的可能出现的漏洞。
对于VCL的有限状态机来说有以下要求：<br/>
- 每一个请求都会独立的被处理
- 请求彼此之间没有什么关系
- 状态彼此啊建有关联性，但是是隔离的
- 利用return()，来确定状态之间是怎么联系的
- 内建的状态引擎是一直存在的，而且会被附加在自定义的的状态引擎之后

**(1)各种状态引擎介绍：**
<br/>
- vcl_recv	用于接收和处理请求，当请求到达并成功接收后被调用，通过判断请求的数据来决定如何处理请求。仅处理可以识别http方法，且只缓存get和head的方法，不缓存用户特有的数据（根据客户端的请求作出的缓存策略）
- vcl_fetce	在从后端主机更新缓存并且获取内容后调用该方法，接着，通过判断获取的内容来决定是否将内容放入缓存，还是直接返回给客户端。
- vcl_pipe	此函数在进入pipe模式时被调用，用于将请求直接传递至后端主机，在请求和返回的内容没有改变的情况下，将不变的内容返回给客户端，直到这个链接关闭
- vcl_hash	定义hash生成时的数据来源，hash该数据后当成键与内存中的键匹配，从内得到缓存数据。
- vcl_pass	此函数在进入pass模式时被调用，用于将请求直接传递至后端主机，后端主机应答数据后送给客户端，但不进行任何缓存，在当前连接下每次都返回的内容。
- vcl_hit	在执行lookup指令后，如果在缓存中找到了请求的内容，将自动调用该函数。
- vcl_miss	在执行lookup指令后，如果没有在缓存中找到请求的内容时自动调用该方法，此函数可以用于判断是否需要从后端服务器取内容。
- vcl_deliver 	将用户请求的内容响应给客户端时用到的方法；
- vcl_error	在varnish端合成错误响应时的缓存策略

**(2)状态引擎工作图示**
<br/>
<center>
<img src="http://oy4e0m51m.bkt.clouddn.com/状态引擎工作图示.png" width="900px"/>
</center>

**(3)vcl_recv介绍**
<br/>
vcl_recv是在Varnish完成对请求报文的解码为基本数据结构后第一个要执行的子例程，它通常有四个主要用途：
- 修改客户端数据以减少缓存对象差异性；比如删除URL中的www.等字符；
- 基于客户端数据选用缓存策略；比如仅缓存特定的URL请求、不缓存POST请求等；
- 为某web应用程序执行URL重写规则； 
- 挑选合适的后端Web服务器；
		
可以使用下面的终止语句，即通过return()向Varnish返回的指示操作：
- pass：绕过缓存，即不从缓存中查询内容或不将内容存储至缓存中；
- pipe：不对客户端进行检查或做出任何操作，而是在客户端与后端服务器之间建立专用“管道”，并直接将数据在二者之间进行传送；此时，keep-alive连接中后续传送的数据也都将通过此管道进行直接传送，并不会出现在任何日志中；
- lookup：在缓存中查找用户请求的对象，如果缓存中没有其请求的对象，后续操作很可能会将其请求的对象进行缓存；
- error：由Varnish自己合成一个响应报文，一般是响应一个错误类信息、重定向类信息或负载均衡器返回的后端web服务器健康状态检查类信息；
		
vcl_recv也可以通过精巧的策略完成一定意义上的安全功能，以将某些特定的攻击扼杀于摇篮中。同时，它也可以检查出一些拼写类的错误并将其进行修正等。<br/>
		
Varnish默认的vcl_recv专门设计用来实现安全的缓存策略，它主要完成两种功能：
- 仅处理可以识别的HTTP方法，并且只缓存GET和HEAD方法；
- 不缓存任何用户特有的数据；
		
安全起见，一般在自定义的vcl_recv中不要使用return()终止语句，而是再由默认vcl_recv进行处理，并由其做出相应的处理决策。<br/>

下面是一个自定义的使用示例：

{% highlight javascript linenos=table %}
	sub vcl_recv {
		if (req.http.User-Agent ~ "iPad" ||
			req.http.User-Agent ~ "iPhone" ||
			req.http.User-Agent ~ "Android") {
				set req.http.X-Device = "mobile";
		} else {
				set req.http.X-Device = "desktop";
		}
	}	
	#此例中的VCL创建一个X-Device请求首部，其值可能为mobile或desktop，于是web服务器可以基于此完成不同类型的响应，以提高用户体验。
{% endhighlight %}

vcl_recv的默认配置：
{% highlight javascript linenos=table %}
	sub vcl_recv {
	    if (req.method == "PRI") { #表示请求报文中的方法不是"PRI"就进行以下操作
	        /* We do not support SPDY or HTTP/2.0 */ #注释
	        return (synth(405)); #返回即进入下一个状态synth（405），表示返回给客户端405响应码
	    }
	    if (req.method != "GET" && #表示如果请求方法不是GET
	    req.method != "HEAD" && #而且请求方法不是HEAD
	    req.method != "PUT" && #...
	    req.method != "POST" && #...
	    req.method != "TRACE" && #...
	    req.method != "OPTIONS" && #...
	    req.method != "DELETE") { #而且请求方法不是DELETE
	        /* Non-RFC2616 or CONNECT which is weird. */
	        return (pipe); #就进入下一个状态pipe，及管道传递给后台服务端
	    }
	    #上面的例子是指从客户端发来的请求不是本缓存服务器能够识别的方法，因此要通过pipe（四层代理）直接传递给后台服务器处理
	    if (req.method != "GET" && req.method != "HEAD") {
	        /* We only deal with GET and HEAD by default */
	        return (pass);
	    }
	    #上面的例子是指从客户端发来的请求连GET和HEAD都不是，但是缓存代理服务器一般自身能够处理的就是GET和HEAD方法，这两个都不是，那就要调入pass，直接让其自己去和后台服务器交互
	    if (req.http.Authorization || req.http.Cookie) {
	        /* Not cacheable by default */
	        return (pass);
	    }
	        return (hash);
	    }
	    #上面的例子是指，如果请求报文中的首部是Authorization或者Cookie，就直接返回pass，直接让其去与后端服务器交互；原因在于这两项的请求首部，标识该请求中包含使用者的私人信息，而缓存代理服务器一般只缓存公共数据而不会缓存私有数据，因此让其直接与后台服务器进行交互。
	}
	#上面的这个sub域，是面向客户端的一个域，处理的是从客户端来的请求
{% endhighlight %}

**(4)vcl_fetch介绍**
如前面所述，相对于vcl_recv是根据客户端的请求作出缓存决策来说，vcl_fetch则是根据服务器端的响应作出缓存决策。在任何VCL状态引擎中返回的pass操作都将由vcl_fetch进行后续处理。vcl_fetch中有许多可用的内置变量，比如最常用的用于定义某对象缓存时长的beresp.ttl变量。<br/>
通过return()返回给varnish的操作指示有：
- deliver：缓存此对象，并将其发送给客户端(经由vcl_deliver)；
- hit_for_pass：不缓存此对象，但可以导致后续对此对象的请求直接送达到vcl_pass进行处理；
- restart：重启整个VCL，并增加重启计数；超出max_restarts限定的最大重启次数后将会返回错误信息；
- error code [reason]：返回指定的错误代码给客户端并丢弃此请求；
默认的vcl_fetch放弃了缓存任何使用了Set-Cookie首部的响应。

### 3.VCL的内置函数 ###
VCL提供了几个函数来实现字符串的修改，添加bans，重启VCL状态引擎以及将控制权转回Varnish等。
{% highlight javascript linenos=table %}
	regsub(str,regex,sub) 查找替换
		#这两个用于基于正则表达式搜索指定的字符串并将其替换为指定的字符串；但regsuball()可以将str中能够被regex匹配到的字符串统统替换为sub，regsub()只替换一次；
	regsuball(str,regex,sub) 
		#全局替换
	ban（boolean expression）：
		#清除匹配的所有缓存
	ban_url(regex)：
		#Bans所有其URL能够由regex匹配的缓存对象；
	purge()：
		#从缓存中挑选出某对象以及其相关变种一并删除，这可以通过HTTP协议的PURGE方法完成；
	hash_data(str)：
		#表示对那些内容做hash计算，一般是将某些字符串当键的时候使用
	return()：
		#当某VCL域运行结束时将控制权返回给Varnish，并指示Varnish如何进行后续的动作；其可以返回的指令包括：lookup、pass、pipe、hit_for_pass、fetch、deliver和hash等；但某特定域可能仅能返回某些特定的指令，而非前面列出的全部指令；
	synthetic（str）：
		#表示要合成哪些内容，一般用于合成响应报文
	return(restart)：
		#重新运行整个VCL，即重新从vcl_recv开始进行处理；每一次重启都会增加req.restarts变量中的值，而max_restarts参数则用于限定最大重启次数。
{% endhighlight %}

举例：定义变量
{% highlight javascript linenos=table %}
	#obj.hits是内建变量，用于保存某缓存项的从缓存中命中的次数；

	if (obj.hits>0) {
	    set resp.http.X-Cache = "HIT via " + server.ip;
	} else {
	    set resp.http.X-Cache = "MISS from " + server.ip;
	}

	#解释：如果当前请求是在缓存中命中的，那么內建变量obj.hits一定是大于零的，此时用set定义变量 resp.http.X-Cache值为由本缓存服务器（IP）HIT，否则就定义该变量为从本缓存服务器MISS。该变量可以使用在状态引擎vcl_deliver中，表示在响应报文中添加该http首部。
{% endhighlight %}

### 5.VCL变量类型 ###
Varnish作为一个“掮客”，面向两端服务，一个是面向客户端接收和发送请求，另外一个是面向后方BE（RS）接收和发送请求。<br/>
如下图：

<img src="http://oy4e0m51m.bkt.clouddn.com/varnish作用.png" width="700px"/>


变量有自己的应用状态引擎范围，如下表：
其中R表示该变量可读，W表示可修改

<img src="http://oy4e0m51m.bkt.clouddn.com/变量范围.png" width="700px"/>


**(1)內建变量：  **    <br/>  
- req.*：request，表示由客户端发来的请求报文相关；
- bereq.*：由varnish发往BE主机的httpd请求相关；
- beresp.*：由BE主机响应给varnish的响应报文相关；
- resp.*：由varnish响应给client相关；
- obj.*：存储在缓存空间中的缓存对象的属性；只读

常用內建变量：

|-------------------------+-------------------------------------------|
|类别      |          解释						      |
|-------------------------|:-----------------------------------------:|
| bereq.method      |读取日志区域的日志内容			   				  |
| bereq.url    |读取统计区域的统计内容  				  				  |
| bereq.proto     |查看日志历史数据          							  |
| bereq.backend      |对统计数据进行排序显示         					  |
| req.http.Cookie      |读取日志区域的日志内容			   		 	  	  |
| req.http.User-Agent   |读取统计区域的统计内容  				  	  |
| req.http.Referer    |查看日志历史数据          					  |
| beresp.status        |响应的状态码                        |
| reresp..proto    |协议版本          					  |
| beresp.backend.name    |协议版本         					  |
| beresp.ttl    |BE主机响应的内容的余下的可缓存时长       		  |
| obj.hits        |此对象从缓存中命中的次数                      |
| obj.ttl        |对象的ttl值                                |
| server.ip        |varnish主机的IP                                |
| server.hostname        |varnish主机的Hostname                 |
| client.ip        |发请求至varnish主机的客户端IP                 |
|-----------------+-------------------------------------------|

**(2)用户自定义变量：** <br/>
可以使用set自定义变量，利用unset取消自定义，这里不再赘述。

**(3)相关变量的示例**<br/>
示例1：强制对接收到有关客户登录和管理私人信息的请求不检查缓存而直接交由后端服务器处理（之所以不检查，原因在于本来该项内容就不应该也没有该缓存）其中：~表示正则匹配，（？i）表示忽略大小写，^/表示锚定URI的开头，不包含主机名和端口，（login\|admin）表示URI中如果包含login或者admin这两个字符则匹配，return（pass）表示将以上匹配的内容直接pass交由后端服务器进行处理：

{% highlight javascript linenos=table %}
	vcl_recv {
        if (req.url ~ "(?i)^/(login|admin)") {
            return(pass);
        }
    }
{% endhighlight %}

示例2：对于特定类型的资源，例如公开的图片等，取消其私有标识，并强行设定其可以由varnish缓存的时长； 定义在vcl_backend_response中，例如在一些电商网站中，用户的请求是一个图片，如用户头像等，但是类似这些图片信息虽然被归类为用户的私有数据，但实际上缓存并不侵犯其隐私，而且对图片缓存是可以大大提升他访问速度的。beresp.http.cache-control!~ "s-maxage"表示是后端服务器的缓存控制中没有"s-maxage"这一项（该项是定义公共缓存时长），意思是后端服务器没有告诉我们该项应该缓存，意味着此项默认是不缓存的；bereq.url ~ "(?i)\.(jpg\|jpeg\|png\|gif\|css\|js)$"该项表示对Varniash向后端服务器发送的请求URL中以.(jpg\|jpeg\|png\|gif\|css\|js)格式结尾的匹配；unset beresp.http.Set-Cookie 是取消后端服务器回应报文中设置的cookie信息，因为带此项的一般表示后端服务器认为这些数据是用户私人信息，不让缓存，实际是可以缓存的，因此要unset取消（想要设置cookie，后端服务器必须支持此种设定）；set beresp.ttl = 3600s表示设置匹配的内容缓存时长为3600s；

{% highlight javascript linenos=table %}
    if (beresp.http.cache-control !~ "s-maxage") {
        if (bereq.url ~ "(?i)\.(jpg|jpeg|png|gif|css|js)$") {
            unset beresp.http.Set-Cookie;
            set beresp.ttl = 3600s;
        }
    }
{% endhighlight %}

示例3：本例的意思是，给后端服务器发送真正的客户端IP地址。req.restart表示客户端请求重启的次数，这也就意味着进行了URL重写，例如301和302重定向，等待时间过长重新排队等，req.restarts == 0表示如果不是重启的请求；req.http.X-Fowarded-For此项表示如果存在Fowarded-For这个首部（有这个变量代表这个请求是代理服务器发来的请求，变量中包含的是真正客户端的地址）；set req.http.X-Forwarded-For = req.http.X-Forwarded-For + "," + client.ip表示如果上面条件匹配就将此变量重设，增加内容为“client.ip”,该变量意思为客户端，这就是这个报文的源地址（对于本缓存服务器来说，客户端其实是前一个代理服务器，所以client.ip的真正含义是代理服务器的地址，真正的客户端IP是req.http.X-Forwarded-For的值）；set req.http.X-Forwarded-For = client.ip该项表示如果不匹配条件，即报文中不存在req.http.X-Fowarded-For这项（意味着中间没有经过代理服务器，发送这个报文的就是真正的客户端），就将该变量设置为client.ip（即客户端ip）；是要进行定义在vcl_recv中；

{% highlight javascript linenos=table %}
    if (req.restarts == 0) {
        if (req.http.X-Fowarded-For) {
            set req.http.X-Forwarded-For = req.http.X-Forwarded-For + "," + client.ip;
        } else {
            set req.http.X-Forwarded-For = client.ip;
        }
    } 	#注意：要想使上面的设置生效，即可以读取X-Forwarded-For这个值（即显示客户端IP），需要在后端服务器进行设置日志格式如下：	vim  /etc/httpd/conf/httpd.con	LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" \"%{X-Forwarded-For}i\"" varnish	CustomLog logs/access_log varnish		#然后在进行动态观察，并进行访问就可以看到客户端IP	tail -F /var/log/httpd/access_log	curl varnishserver:port{% endhighlight %}### 6.缓存对象修剪 ###**(1)简单介绍**<br/>提高缓存命中率的最有效途径之一是增加缓存对象的生存时间(TTL)，但是这也可能会带来副作用，比如缓存的内容在到达为其指定的有效期之间已经失效，这意味着后端服务器的内容已经改变，但是varnish中缓存的仍然是旧的内容，因为定义的缓存时长太长，客户端一直获取的的是换粗内的旧内容。因此，手动检验缓存对象的有效性或者刷新缓存是缓存很有可能成为服务器管理员的日常工作之一，但是，Varnish为完成这类的任务提供了三种途径：HTTP 修剪(HTTP purging)、禁用某类缓存对象(banning)和强制缓存未命令(forced cache misses)。<br/>例如：增加缓存时长{% highlight javascript linenos=table %}	#接收后台服务器的回应报文的时候，检查其中的URL中是否结尾请求的是图片信息，如果是就取消后台服务器设置的不缓存此项（一般后台服务器有需要会设置），然后缓存这些数据时间为7200s	sub vcl_backend_response {}	    if (bereq.url ~ "(?i)\.(jpg|png|jpeg|gif)$”) {	        unset beresp.http.Set-Cookie;	        set beresp.ttl = 7200s;	    }	}{% endhighlight %}访问后会进行缓存<img src="http://oy4e0m51m.bkt.clouddn.com/访问后会进行缓存.png" width="700px"/>这时候就会出现问题，因为即使在浏览器进行强制刷新，也是无法请求到后台服务器的，这时候后台服务器数据要是进行了更新，客户端是无法得到最新数据的。这时候缓存对象的修剪就成为了必要。>注:在具体执行某清理工作时，需要事先确定如下问题：
- 仅需要检验一个特定的缓存对象，还是多个？
- 目的是释放内存空间，还是仅替换缓存的内容？
- 是不是需要很长时间才能完成内容替换？- 这类操作是个日常工作，还是仅此一次的特殊需求？

**(2)purge移除单个缓存对象**
<br/>
purge用于清理缓存中的某特定对象及其变种(variants)，因此，在有着明确要修剪的缓存对象时可以使用此种方式。HTTP协议的PURGE方法可以实现purge功能，不过，其仅能用于vcl_hit和vcl_miss中，它会释放内存工作并移除指定缓存对象的所有Vary:-变种，并等待下一个针对此内容的客户端请求到达时刷新此内容。另外，其一般要与return(restart)一起使用。<br/>
使用purge移除缓存，意味着临时移除当前的缓存，等客户端再进行请求的时候，就会自动编程MISS,从而实现去后端服务器请求新的内容。但是执行purge操作是危险的，因为如果任何人都可以使用，那就意味着有人恶意清除我们所有的缓存，那后段服务器就会崩溃，所以要设置访问控制，限制只有规定的IP才能够使用purge清除缓存。
<br/>
首先：定义purge操作（一般这是默认的vcl，但仍可以重复设置）
{% highlight javascript linenos=table %}
	#定义purge操作，即进入该子历程的请求，其对应的在缓存服务的资源会被清除，使其请求能够传入后台服务器获得新的资源
	sub vcl_purge {
	    return (synth(200,"Purged"));
	}
{% endhighlight %}
其次：设置访问控制，规定只有固定的IP才可以发送purge请求
{% highlight javascript linenos=table %}
	#下面首先设置了一个acl，再让子历程调用该acl，子历程时定义收报文请求，表示如果请求方法种有purge就查看其IP是否符合acl定义的IP和网段，如果符合就让该请求进入下一个子历程purge，如果不符合就给客户端返回405和权限禁止提示。
	acl purgers {
	    "127.0.0.0"/8;
	    "172.18.65.74";
	sub vcl_recv {
	    if (req.method == "PURGE") {
	        if (!client.ip ~ purgers) {
	            return(synth(405,"Purging not allowed for " + client.ip));
	        }
	    return(purge);
	    }
	}
{% endhighlight %}
最后，在不同主机进行检测
{% highlight javascript linenos=table %}
	curl -X PURGE http://172.18.65.74/111.jpg
{% endhighlight %}

**(3)强制缓存未命中**<br/>
在vcl_recv中使用return(pass)能够强制到上游服务器取得请求的内容，但这也会导致无法将其缓存。使用purge会移除旧的缓存对象，但如果上游服务器宕机而无法取得新版本的内容时，此内容将无法再响应给客户端。使用req.has_always_miss=ture，可以让Varnish在缓存中搜寻相应的内容但却总是回应“未命中”，于是vcl_miss将后续地负责启动vcl_fetch从上游服务器取得新内容，并以新内容缓存覆盖旧内容。此时，如果上游服务器宕机或未响应，旧的内容将保持原状，并能够继续服务于那些未使用req.has_always_miss=true的客户端，直到其过期失效或由其它方法移除。

**(4)Banning批量清除缓存对象**
ban()是一种从已缓存对象中过滤(filter)出某此特定的对象并将其移除的缓存内容刷新机制，不过，它并不阻止新的内容进入缓存或响应于请求,也就是使用ban可以批量清除匹配到的缓存。<br/>
在Varnish中，ban的实现是指将一个ban添加至ban列表(ban-list)中，这可以通过命令行接口或VCL实现，它们的使用语法是相同的。ban本身就是一个或多个VCL风格的语句，它会在Varnish从缓存哈希(cache hash)中查找某缓存对象时对搜寻的对象进行比较测试，因此，一个ban语句就是类似匹配所有“以/downloads开头的URL”，或“响应首部中包含nginx的对象”。例如：<br/>
`ban req.http.host == "magedu.com" && req.url ~ "\.gif$"`<br/>
定义好的所有ban语句会生成一个ban列表(ban-list)，新添加的ban语句会被放置在列表的首部。缓存中的所有对象在响应给客户端之前都会被ban列表检查至少一次，检查完成后将会为每个缓存创建一个指向与其匹配的ban语句的指针。Varnish在从缓存中获取对象时，总是会检查此缓存对象的指针是否指向了ban列表的首部。如果没有指向ban列表的首部，其将对使用所有的新添加的ban语句对此缓存对象进行测试，如果没有任何ban语句能够匹配，则更新ban列表。
<br/>
对ban这种实现方式持反对意见有有之，持赞成意见者亦有之。反对意见主要有两种，一是ban不会释放内存，缓存对象仅在有客户端访问时被测试一次；二是如果缓存对象曾经被访问到，但却很少被再次访问时ban列表将会变得非常大。赞成的意见则主要集中在ban可以让Varnish在恒定的时间内完成向ban列表添加ban的操作，例如在有着数百万个缓存对象的场景中，添加一个ban也只需要在恒定的时间内即可完成。<br/>

ban的两种实现方式：<br>
- 第一在varnishadm命令行中（建议）<br/>
例如：将所有jpg和png结尾的缓存全部清除<br>
`ban req.url ~ (?i).(jpg|png)$`<br/>
- 第二在配置文件中写入<br/>
{% highlight javascript linenos=table %}
	sub vcl_recv {
		if (req.method == "BAN") {
		ban("req.http.host == " + req.http.host + " && req.url == " + req.url);
		} 
	} 
{% endhighlight %}
>注：如果有必要，要进行访问限制，指定的IP才能使用该命令

### 7.使用多个后端主机 ###
对于网站架构来说，动态资源和静态资源是需要分开存储的，有各自不同的服务器；静态资源有css，js，html，txt以及jpg，jpeg，png，gif等，对于前面的静态资源一般会经常发生变化，而后面的静态资源都是一些图片，他们很少会发生什么变化，因此一般也会分开存放；由此，网站的后端服务器可以是分为两类，第一类存储静态资源中的图片，另一类存储静态资源中经常会发生变化的css，js，html，txt以及动态资源如jsp文件。
<br/>
对于一个网站页面来说，其中的资源包括很多URL这些URL可能代表静态也可能代表动态，那么我们的缓存服务器在资源未命中的时候就要将不同请求发往不同的后端服务器，这时候就需要设置多个后端主机。<br/>
例如：有两台后端服务器，一台提供图片服务images，一台提供除图片外的其他服务appsrv.
{% highlight javascript linenos=table %}
	backend images {
	    .host = "172.18.65.69";
	    .port = "80";
	}
		
	backend appsrv {
	    .host = "172.18.65.70";
	    .port = "80";
	}
		
	sub vcl_recv {  
	    if (req.url ~ "(?i)\.（jpg|jpeg|png|gif）$") {
	        set req.backend_hint = images;
	    } else {
	        set req.backend_hint = appsrv;
	    }   
	}
{% endhighlight %}

###8.使用负载均衡功能###

我们知道，varnish面对的后端服务器不可能是一个，可能是多个，例如图片服务器可能有多个做集群，这时候我们的图片请求未命中的时候，varnish就需要进行调度，做负载均衡，而varnish使用这个功能需要加一个特殊的模块，而且一定要在调度配置前使用，表明调用该模块。对于varnish来说，只有两种调度算法，因为本身就是缓存服务器，只有很少MISS请求才会备调度，调度方法为随机和轮询（round_roubin）。
<br/>
两个特殊的引擎：
- vcl_init：在处理任何请求之前要执行的vcl代码：主要用于初始化VMODs；
- vcl_fini：所有的请求都已经结束，在vcl配置被丢弃时调用；主要用于清理VMODs；
示例：
{% highlight javascript linenos=table %}
	import directors;    # load the directors指明导入调度模块
		
	backend server1 {
	    .host = 
	    .port = 
	}
	backend server2 {
	    .host = 
	    .port = 
	}
	
	sub vcl_init {
	    new GROUP_NAME = directors.round_robin(); #表示新建一个组，组名自定义，调度算法是轮询
	    GROUP_NAME.add_backend(server1);
	    GROUP_NAME.add_backend(server2);
	}
	
	sub vcl_recv { 
	    set req.backend_hint = GROUP_NAME.backend(); #表示接受请求发送到组
	}
	#注意：我们是可以定义多个组的，每个组都可以做条件限制，响应不同的请求，这里指定医疗一个，如果有多个需要在sub vcl_recv中指明条件的组名
{% endhighlight %}

### 9.实现会话绑定 ###
对于一些动态内容的请求，可能缓存服务器不需要进行缓存，但是仍需要进行调度，列如将jsp请求调度到后端的tomcat服务器上，这时候就需要会话绑定来实现将固定的请求调度到固定的后端服务器上，使用session sticky的方法，此中可以通过源IP进行绑定或者通过cookie进行绑定，后者要比前者颗粒度细，更加精确；varnish可以通过hashURL实现后者。<br/>
示例：
{% highlight javascript linenos=table %}
	import directors;    # load the directors导入模块
	backend server1 {
	    .host = 
	    .port = 
	}
	backend server2 {
	    .host = 
	    .port = 
	}
	sub vcl_init {
	        new h = directors.hash();
	        h.add_backend(one, 1);   // backend 'one' with weight '1'
	        h.add_backend(two, 1);   // backend 'two' with weight '1'
	    }
	
	sub vcl_recv {
	    set req.backend_hint = h.backend(req.http.cookie);
	}
	#基于cookie的session sticky
{% endhighlight %}

### 10.检测后端主机的健康状态 ###

健康监测可以分应用层检测和传输层检测，检测的级别越高消耗的资源越多；传输层检测如果是tcp检测就向对应的socket发送握手请求，对方只要响应第二次即可，如果是udp直接发送一个请求报文只要对方响应即可，一般是tcp方式；<br/>
Varnish可以检测后端主机的健康状态，在判定后端主机失效时能自动将其从可用后端主机列表中移除，而一旦其重新变得可用还可以自动将其设定为可用。为了避免误判，Varnish在探测后端主机的健康状态发生转变时(比如某次探测时某后端主机突然成为不可用状态)，通常需要连续执行几次探测均为新状态才将其标记为转换后的状态。<br/>
每个后端服务器当前探测的健康状态探测方法通过.probe进行设定，其结果可由req.backend.healthy变量获取，也可通过varnishlog中的Backend_health查看或varnishadm的debug.health查看。<br/>
示例：
{% highlight javascript linenos=table %}
	backend BE_NAME {   #BE_NAME为检测的后端服务器设置名字
		.host =         #主机名，如www.oscao.com
		.port =         #检测端口
		.probe = {      #设置相关的检测指令
			.url=       #检测时要请求的URL，默认为”/"
			.timeout=   #检测超时时长，超时视为失败
			.interval=  #探测请求的发送周期，默认为5秒
			.window=    #设定在判定后端主机健康状态时基于最近多少次的探测进行，默认是8
			.threshold= #在.window中指定的次数中，至少有多少次是成功的才判定后端主机正健康运行；默认是3；
		}
	}

	probe check {
		.url = "/.healthcheck.html";
		.window = 5;
		.threshold = 4;
		.interval = 2s;
		.timeout = 1s;
	}
		
	backend default {
		.host = "10.1.0.68";
		.port = "80";
		.probe = check;
	}
		
	backend appsrv {
		.host = "10.1.0.69";
		.port = "80";
		.probe = check;
	}
{% endhighlight %}

**(1).probe中的探测指令常用的有：**
<br/>
- .url：探测后端主机健康状态时请求的URL，默认为“/”；
- .request: 探测后端主机健康状态时所请求内容的详细格式，定义后，它会替换.url指定的探测方式；
- .window：设定在判定后端主机健康状态时基于最近多少次的探测进行，默认是8；
- .threshold：在.window中指定的次数中，至少有多少次是成功的才判定后端主机正健康运行；默认是3；
- .initial：Varnish启动时对后端主机至少需要多少次的成功探测，默认同.threshold；
- .expected_response：期望后端主机响应的状态码，默认为200；
- .interval：探测请求的发送周期，默认为5秒；
- .timeout：每次探测请求的过期时长，默认为2秒
- .max_connections:每一个后端主机的最大并发链接数

**(2)手动设定后端主机的健康状况**
<br/>
我们可以在命令行设置后端主机的状况，有三种方式，通过这种方法可以实现灰度发布
- sick	管理down; 灰度发布；一旦设置down，varnish就不会再向其调度
- healthy	管理up；一旦设置为up，就断后端服务器失败，也会一直调度
- auto	让varnish自己进行检测，确定是否调度

举例:<br/>
`backend.list`显示后端主机及其状态<br/>
`backend.set.health picsrv sick` 标记为down<br/>
`backend.set.health picsrv health` 标记为up<br/>
`backend.set.health picsrv auto` 标记为自动检测<br/>

## 二、Varnish的相关命令 ##

### 1.varnishd命令：###

**作用：**<br/>
- 用来临时配置varnish服务，等同于/etc/varnish/varnish.prarams,只不过是临时生效<br/>

**选项：**<br/>
{% highlight javascript linenos=table %}
-a address[:port][,address[:port][...]，指定提供服务的地址和端口，可指定多个，默认为6081端口； 
-T address[:port]，指定进行管理交互时所用地址和端口，默认为6082端口；
-s [name=]type[,options]，定义缓存存储机制；
-u user；指定程序运行者
-g group；指定程序所属组
-f config：指定读取VCL配置文件；
-F：运行于前台；
-p param=value：设定运行参数及其值； 可重复使用多次；
-r param[,param...]: 设定指定的参数为只读状态，永久生效要写在文件中； 
{% endhighlight %}

### 2.varnishadm命令： ###

**作用：**<br/>
对varnish服务进行管理的工具，可以相关理数据库一样链接varnish进行管理，即建立一个 CLI 的连接。使用 -T  和 -S 参数。 如果给出了要执行的命令，varnishadm 会传输命令和返回运行的结果到标准输出。 如果没有给出要执行的命令，varnish 会给你一个 CLI 接口，可以在 CLI 接口上输入命令和返回结果。<br/>
**选项**<br/>
{% highlight javascript linenos=table %}
-S /etc/varnish/secret  确定一个认证的安全文件，默认为/etc/varnish/secret
-T [ADDRESS:]PORT 连接到管理接口的地址和端口
-t timeout 定义链接的超时时间
{% endhighlight %}
**内置参数：**<br/>
{% highlight javascript linenos=table %}
	配置文件相关：	
	vcl.list		查看vcl配置文件的列表
	vcl.use <NAME>	使用编译的配置文件，指明自定义版本名称
	vcl.load <NAME >	重新编译加载vcl配置，需要指明自定义版本名称，和需要编译的文件name.vcl位置
	vcl.show		显示指定的配置文件详细信息，指明自定义版本名称
	vcl.discard		手动清理版本，否则旧版本配置信息会在varnish重启后丢弃
	运行时参数相关：	
	param.show -l		查看varnish主进程的运行选项参数
	param.set 		在运行时设定主进程的运行参数
	缓存存储相关：	
	storage.list		查看缓存存储机制
	后端服务器相关：	
	backend.list		查看后端服务器列表及状态
	其他相关：	
	ping		判断后端服务器的状态，正常回应pong
	status		查看进行的运行状态
	panic.show		如果某个子进程曾经panic过，可以使用这个命令查看（panic代表服务曾经崩溃过）
	ban [&& ]…. 	手动清除缓存
	ban.list 	列出清除缓存的规则列表，由上一个参数定义
{% endhighlight %}

### 3.日志相关 ###

**(1)varnishstat**
<br/>
Varnish Cache statistics 动态显示缓存统计数据<br/>
选项：
{% highlight javascript linenos=table %}
	-1 	查看一次
	-1 -f FILED_NAME 	指定参数名称，查看指定参数
	-l	可用于-f选项指定的字段名称列表；
{% endhighlight %}

>注：<br/>
MAIN.cache_hit  缓存命中数量（重要关注参数）<br/>
MAIN.cache_miss 缓存未命中数量（重要关注参数）<br/>

举例：
{% highlight javascript linenos=table %}
	varnishstat -1 -f MAIN.cache_hit -f MAIN.cache_miss
		显示指定参数的当前统计数据；
	varnishstat -l -f MAIN -f MEMPOOL
		列出指定配置段的每个参数的意义；
{% endhighlight %}

**(2)varnishtop** <br/> 
Varnish log entry ranking 按照速率排序动态显示日志数据<br/>
参数：
{% highlight javascript linenos=table %}
	-1 	显示一次 
	-i taglist	可以同时使用多个-i选项，也可以一个选项跟上多个标签；包含列表，只显示指定的标签；白名单
	-I <[taglist:]regex> 	正则白名单
	-x taglist：	排除列表，显示指定以外的标签；黑名单
	-X  <[taglist:]regex> 	正则黑名单
{% endhighlight %}

举例：
{% highlight javascript linenos=table %}
	#varnishtop -i RespHeader,RespStatus 
		只显示RespHeader和RespStatus的内容
	#varnishtop -x RespHeader,RespStatus 
		除RespHeader和RespStatus以外的内容都显示
{% endhighlight %}

**(3)varnishlog** 
Display Varnish logs 实时显示日志，只显示新生成的<br/>
里面分为了后端服务器请求和回应、对客户端的请求和回复以及当前会话三个部分<br/>

**(4)varnishncsa ** <br/>
Display Varnish logs in Apache / NCSA combined log format 传统日志显示模式<br/>

**总结：**
由日志系统介绍可知（参考varnish的shared memory log组件），日志信息是不可以永久记录的，想持久记录信息，将其记录到文件内，需要启动varnishlog和或varnishncs服务。<br/>
`service varnishlog start`；在/var/log/下会生成日志varnishlog.log<br/><br/>
<img src="http://oy4e0m51m.bkt.clouddn.com/日志1.png" width="700px"/>

`service varnishncs start`；在/var/log/下会生成日志varnishncs.log<br/><br/>
<img src="http://oy4e0m51m.bkt.clouddn.com/日志2.png" width="700px"/>
>注意开启后可能会影响性能，尽可能设置过滤非必要信息，非必要不要开启日志记录服务，而且两个服务选择一个开启即可。因为缓存服务器并不是日志服务器，主要功能在于缓存，记录日志会消耗IO。




