---
layout: post
title: Hosting migration
date: 2014-06-28 11:52:36.00 +02:00
tags: hosting
---
I recently noticed I actually spend a lot of money on hosting and server resources I'm not using at all.
Such a waste. After a small research I decided to move all my Droplets from [DigitalOcean.com](https://www.digitalocean.com/)
to its competitor - [linode.com](https://www.linode.com). I also hosted 2 sites on a separate hosting - elastichost.com -
which is also rather expensive.
So in the end I sat down and calculated how many resources I need and how many resources I actually pay for.
At the beginning I thought that maybe the best solution would be to move everything to a dedicated machine at [OVH](ovh.de) or
maybe [Hetzner](hetzner.de), but in both cases the cost is ~50-70€ per month minimum. Quite a lot I think, especially when my
sites do not have significant traffic. <!--more-->
I was definitely searching for something like **digitalocean.com** (DO).

#### DigitalOcean has a very reasonable price and offers a bunch of features I was looking for, but:

  -  when somebody tries to flood (DDoS) your droplet you are actually on your own (they do not offer any type of protection).
     Support in this case also seems to be powerless, no matter if this is a targeted attack or just a ricochet. One of my
     clients got such a case and, to be honest, I was really disappointed when I was not able to get any help from the DO Support Team,
  -  when your site/droplet catches some significant traffic, DO has poor performance. Yes, I know what I'm talking about.
     And I'm not talking here about 30Mb/s traffic. I even upgraded my droplet from 2G MEM to 8G MEM and it did not help much - I/O
     was still on a low level (but still, DO looks better than most VPS hosting companies),
  -  it's a pity they do not offer some more extensive monitoring out of the box.


#### So why Linode:

  -  for the same price I can get a more powerful virtual machine and more disk space,
  -  looks like they have better I/O performance (I will try to provide some stats to prove that),
  -  quick and helpful support - don't get me wrong, DO support is also damn quick, but Linode support seems to be more techie oriented,
  -  better monitoring out of the box - "Longview".


In general I don't think DO is bad, I think it's simply suited for other purposes, like test or dev environments.

After the migration, performance increased significantly.
It was quite visible, especially on my Redmine instance and other RoR based apps.



Peace \o/.
