---
layout: post
title: Why you should not use kill -9
date: 2015-03-19 20:46:03.00 +02:00
tag: ["Linux"]
---

I recently found this advice given by _Randal Schwartz_.
I think most programmers have some idea who he is.
Anyway, if you have never had to touch Perl, here is the link to his [wiki page](https://en.wikipedia.org/wiki/Randal_L._Schwartz).

Here is the advice from Randal:

<!--more-->

```
No no no. Don't use kill -9.    
It doesn't give the process a chance to cleanly:    
1) shut down socket connections    
2) clean up temp files    
3) inform its children that it is going away    
4) reset its terminal characteristics    
and so on and so on and so on.    
Generally, send 15, and wait a second or two, and if that doesn't work, send 2, and if     
that doesn't work, send 1. If that doesn't, REMOVE THE BINARY because the program is    
badly behaved!    
Don't use kill -9. Don't bring out the combine harvester just to tidy up the flower pot.
```



In short:

  *  _15_ is _SIGTERM_ (terminate), 
  *  _2_ is _SIGINT_ (interrupt, ctrl-c), 
  *  _1_ is _SIGHUP_ (terminal hangup, often overloaded to keep a process running but reload the config)


For those who would like to have a full overview of all available signals, here is a snippet from `signal.h`:
{% highlight c %}
#define SIGHUP           1
#define SIGINT           2
#define SIGQUIT          3
#define SIGILL           4
#define SIGTRAP          5
#define SIGABRT          6
#define SIGIOT           6
#define SIGBUS           7
#define SIGFPE           8
#define SIGKILL          9
#define SIGUSR1         10
#define SIGSEGV         11
#define SIGUSR2         12
#define SIGPIPE         13
#define SIGALRM         14
#define SIGTERM         15
#define SIGSTKFLT       16
#define SIGCHLD         17
#define SIGCONT         18
#define SIGSTOP         19
#define SIGTSTP         20
#define SIGTTIN         21
#define SIGTTOU         22
#define SIGURG          23
#define SIGXCPU         24
#define SIGXFSZ         25
#define SIGVTALRM       26
#define SIGPROF         27
#define SIGWINCH        28
#define SIGIO           29
#define SIGPOLL         SIGIO
{% endhighlight %}


--robert
