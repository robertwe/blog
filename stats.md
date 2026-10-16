---
layout: page
comments: false
title: GitHub and Wakatime stats
permalink: /stats/
---

### GitHub contributions chart:

<a href="https://github.com/{{ site.github_username }}">
  <img src="https://ghchart.rshah.org/{{ site.github_username }}" alt="{{ site.github_username }}'s Github chart" />
</a>
<br /><br />
### Wakatime stats:
{% for chart in site.wakatime.charts %}
<figure>
  <img src="https://wakatime.com/@{{ site.wakatime.username }}/{{ chart }}.svg" alt="Wakatime chart" />
</figure>
{% endfor %}
