---
layout: post
title: Add new key to APT AKA tell APT to trust given key
date: 2015-04-30 08:00:03.00 +02:00
tag: ["Linux"]
---

On one of my desktop boxes I recently got this message when I wanted to update it via `apt`:

```
Fetched 1448 B in 8s (180 B/s)
Reading package lists... Done
W: An error occurred during the signature verification. The repository is not updated and the previous index files will be used.
GPG error: http://xxxxxxx ./ Release: The following signatures couldn't be verified because
the public key is not available: NO_PUBKEY 0000000000
```

<!--more-->

The solution is very straightforward, but let's write it down here since I always forget how to do it.
Here it is:

```
gpg --keyserver subkeys.pgp.net --recv-keys keyId
gpg -a --export keyId | sudo apt-key add -
```
Of course you will need to replace `keyId` with the real GPG key which is missing/unknown to APT.

Additional resources - [SecureApt Debian wiki page](https://wiki.debian.org/SecureApt)

--robert
