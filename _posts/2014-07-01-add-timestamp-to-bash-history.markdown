---
layout: post
title: Add timestamp to Bash history
date: 2014-07-01 08:30:46.000000000 +02:00
tags: [bash,]
---
Sometimes there is a need to add a timestamp to bash history.
At my work I found it quite useful, especially when some other developers
have access to the same box or when you simply want to have an idea when a command from the history was executed. &nbsp;
This is how we can achieve this:
{% highlight bash %}
echo 'export HISTTIMEFORMAT="%d.%m.%y %T"' >> ~/.profile
{% endhighlight %}

(or `.bash_profile` if you use a RHEL based distro) and after that just re-login or reload your profile file.
Time formatting is exactly the same as for `strftime` - please check `man 3 strftime`.

Hint: reloading the profile can be done like this:
`. .profile` or `source .profile`


--
Cheers
Robert
