---
layout: post
title: CentOS6 "host" and "dig" commands are missing
date: 2014-05-20 20:39:37.00 +02:00
category: [CentOS]
---
Recently I configured a new machine with CentOS 6.5 on board and it turned out the *host* command was missing.
Here is a quick solution for that: <!--more-->
yum install bind-utils
{% highlight text %}
[robert@swordfish ~] yum install bind-utils
Loaded plugins: fastestmirror, keys, protectbase
Loading mirror speeds from cached hostfile
 * base: centosh2.centos.org
 * extras: mirror.nsc.liu.se
 * updates: mirror.nsc.liu.se
0 packages excluded due to repository protections
Setting up Install Process
Resolving Dependencies
--> Running transaction check
---> Package bind-utils.x86_64 32:9.8.2-0.23.rc1.el6_5.1 will be installed
...
--> Running transaction check
---> Package bind-libs.x86_64 32:9.8.2-0.23.rc1.el6_5.1 will be installed
--> Finished Dependency Resolution

Dependencies Resolved
...
Install       2 Package(s)

Total download size: 1.0 M
Installed size: 2.6 M
Is this ok [y/N]: y
Downloading Packages:
(1/2): bind-libs-9.8.2-0.23.rc1.el6_5.1.x86_64.rpm                                                           | 879 kB     00:00     
(2/2): bind-utils-9.8.2-0.23.rc1.el6_5.1.x86_64.rpm                                                          | 182 kB     00:00     

...

Complete!
[robert@swordfish ~] dig

; <<>> DiG 9.8.2rc1-RedHat-9.8.2-0.23.rc1.el6_5.1 <<>>
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 53593
;; flags: qr rd ra; QUERY: 1, ANSWER: 13, AUTHORITY: 0, ADDITIONAL: 0

;; QUESTION SECTION:
;.				IN	NS

;; ANSWER SECTION:
.			18308	IN	NS	a.root-servers.net.
.			18308	IN	NS	b.root-servers.net.
.			18308	IN	NS	c.root-servers.net.
.			18308	IN	NS	d.root-servers.net.
.			18308	IN	NS	e.root-servers.net.
.			18308	IN	NS	f.root-servers.net.
.			18308	IN	NS	g.root-servers.net.
.			18308	IN	NS	h.root-servers.net.
.			18308	IN	NS	i.root-servers.net.
.			18308	IN	NS	j.root-servers.net.
.			18308	IN	NS	k.root-servers.net.
.			18308	IN	NS	l.root-servers.net.
.			18308	IN	NS	m.root-servers.net.

;; Query time: 4 msec
;; SERVER: 8.8.8.8#53(8.8.8.8)
;; WHEN: Tue May 20 18:50:16 2014
;; MSG SIZE  rcvd: 228
{% endhighlight %}
Just to keep it in one place - I always forget which package provides it.
If you know where exactly the executable file is placed, you can use the `yum provides` command like this:

{% highlight text %}
$ yum provides /usr/bin/host
Loaded plugins: fastestmirror

...

32:bind-utils-9.8.2-0.17.rc1.el6_4.6.x86_64 : Utilities for querying DNS name servers
Repo        : base
Matched from:
Filename    : /usr/bin/host

32:bind-utils-9.8.2-0.23.rc1.el6_5.1.x86_64 : Utilities for querying DNS name servers
Repo        : updates
Matched from:
Filename    : /usr/bin/host

32:bind-utils-9.8.2-0.23.rc1.el6_5.1.x86_64 : Utilities for querying DNS name servers
Repo        : installed
Matched from:
Other       : Provides-match: /usr/bin/host


$ yum provides /usr/bin/dig
Loaded plugins: fastestmirror
Loading mirror speeds from cached hostfile
...
32:bind-utils-9.8.2-0.17.rc1.el6_4.6.x86_64 : Utilities for querying DNS name servers
Repo        : base
Matched from:
Filename    : /usr/bin/dig

32:bind-utils-9.8.2-0.23.rc1.el6_5.1.x86_64 : Utilities for querying DNS name servers
Repo        : updates
Matched from:
Filename    : /usr/bin/dig

32:bind-utils-9.8.2-0.23.rc1.el6_5.1.x86_64 : Utilities for querying DNS name servers
Repo        : installed
Matched from:
Other       : Provides-match: /usr/bin/dig
{% endhighlight %}
It will help you find most of the missing packages.


