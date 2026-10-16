---
layout: post
title: 'This blog now looks like a terminal - and weighs 7 KB of CSS'
date: 2026-10-16 10:30:00.00 +02:00
tag: ["Meta", "CSS", "Jekyll", "Web"]
category: Meta
---

If you have been here before you noticed: the serif font and the white background are gone, the blog now renders inside
a terminal window with a zsh prompt. This post is the short write-up of how, because the interesting part is not the
look, it is what was removed to get there. No CSS framework, no JavaScript for the theme, no web fonts, one 7 KB
stylesheet. Still Jekyll, still static files on Firebase Hosting.
<!--more-->

## What went out

The old setup was the `jekyll-whiteglass` theme plus Font Awesome 4.7 for three footer icons plus a Google font. That is
a 10 KB stylesheet, a 30 KB icon CSS file with a font behind it, and a third-party font request on every page view -
for a blog that is 95% text and code blocks.

Now: the theme gem is gone, the layouts live in the repo (`_layouts/`, six files, none longer than a screen), and the
whole look is one hand-written CSS file. Fonts are the system monospace and system sans stacks, so zero font downloads.
Icons are words. Nobody has ever been confused by the word "GitHub".

## The window

The frame is one `div` with a title bar. The three dots are three empty `<i>` elements coloured red, yellow and green.
The whole page is `max-width: 106ch` and centred, which is roughly what a comfortable terminal window is.

```css
.win{position:relative;max-width:106ch;margin:0 auto;background:#1e1e2e;
     border-radius:10px;border:1px solid #313244;box-shadow:0 20px 60px rgba(0,0,0,.5);overflow:hidden}
.bar{background:#313244;padding:.55rem 1rem;display:flex;align-items:center;gap:.45rem}
.bar i{width:12px;height:12px;border-radius:50%}
.bar i:nth-child(1){background:#f38ba8}.bar i:nth-child(2){background:#f9e2af}.bar i:nth-child(3){background:#a6e3a1}
```

The colours are [Catppuccin Mocha](https://catppuccin.com/), because it is a palette most terminal emulators and editors
already ship, and because giscus has a matching theme, so the comment box does not look like a white sticker on a dark page.

## The prompt

Every "section" of a page is a fake command followed by its output. The prompt is a Jekyll include with two
parameters, the working directory and the command:

```html
{% raw %}<div class="p"><span class="arrow">➜</span> <span class="h">robert@notes</span>
<span class="d">{{ include.cwd }}</span> <span class="g">git:(</span><span class="arrow">master</span><span class="g">)</span>
<span class="c">{{ include.cmd }}</span></div>{% endraw %}
```

The home page is `ls -t posts/ | head -n 5 | xargs head -n 3`, a post is `glow <slug>.md`, the archive is `ls -lt`, a
tag page is `grep -l "tag: AWS" *.md`. It is a joke, but it is a joke that also tells you where you are.

## The cursor and the scanlines - CSS only

The blinking block at the bottom is a pseudo-element with a one-step animation. The scanlines are a repeating gradient
laid over the window with `pointer-events: none`, so it never gets in the way of selecting text.

```css
.cur::after{content:"▋";animation:bl 1.1s steps(1) infinite}
@keyframes bl{50%{opacity:0}}
@media(prefers-reduced-motion:reduce){.cur::after{animation:none}}

.win::after{content:"";position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(0deg,rgba(0,0,0,.12) 0 1px,transparent 1px 3px)}
```

The `prefers-reduced-motion` line is two seconds of work and it is the difference between a nice touch and a page that
some people cannot read.

## Monospace where it is UI, sans where it is prose

This was the one design decision that took some thought. A 100% monospace page looks the most like a terminal and is
the hardest thing to read for two thousand words. So the chrome - prompts, nav, titles, headings, code - is monospace,
and the post body is the system sans font at a slightly larger size. Headings keep the terminal feeling with a
`##` prefix drawn by CSS:

```css
.post .body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:1.03rem;line-height:1.7}
.post .body h2{font-family:ui-monospace,Menlo,Consolas,monospace;color:#cba6f7}
.post .body h2::before{content:"## ";color:#6c7086}
```

## What did not change, honestly

The theme has zero JavaScript, but the page is not script-free. Google Analytics is still there, giscus loads on post
pages for comments, and the contact form still uses reCAPTCHA. Those are the same three third parties the old design
had, I just did not pretend otherwise in the footer. Dropping them is a separate decision for a separate day.

## Numbers

| | before | after |
|---|---|---|
| stylesheet | 10.6 KB | 7.2 KB |
| icon font CSS | 30 KB + font file | 0 |
| web font requests | 1 | 0 |
| theme JavaScript | 0 | 0 |

Not a dramatic saving in bytes, the site was already light. The win is in moving parts: no theme gem to keep in sync
with Jekyll, no CDN that can go away, nothing to update. The whole design is 70 lines of CSS I can read in one sitting,
which is exactly the amount of frontend I want to own.
