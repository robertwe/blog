---
layout: post
title: 'IPtables returns an error : security raw nat mangle filter FAILED'
date: 2014-06-28 12:13:09.00 +02:00

---
After setting up my new "linode" on linode.com I started configuring the firewall (iptables).
After writing down all my rules I tried to restart iptables, but got output like this:

{% highlight bash %}

$ service iptables restart
iptables: Flushing firewall rules:                         [  OK  ]
iptables: Setting chains to policy ACCEPT: security raw nat[FAILED]filter
iptables: Unloading modules:                               [  OK  ]
iptables: Applying firewall rules:                         [  OK  ]
{% endhighlight %}
<!--more-->
After a quick research (Google) I found an answer for that:
[here is the link](http://www.hostvirtual.com/kb/6383/IPtables-returns-an-error--security-raw-nat-mangle-filter-FAILED.html)

Looks like you need to add this patch to the iptables init script:

{% highlight bash %}
echo -n $"${IPTABLES}: Setting chains to policy $policy: "
ret=0
for i in $tables; do
    echo -n "$i "
    case "$i" in
+       security)
+           $IPTABLES -t filter -P INPUT $policy \
+               && $IPTABLES -t filter -P OUTPUT $policy \
+               && $IPTABLES -t filter -P FORWARD $policy \
+               || let ret+=1
+           ;;
        raw)
            $IPTABLES -t raw -P PREROUTING $policy \
                && $IPTABLES -t raw -P OUTPUT $policy \
                || let ret+=1
            ;;
{% endhighlight %}


Looks like this is a known bug in CentOS 6 in virtualized environments.


--robert

