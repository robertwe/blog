---
layout: post
title: 'I turned this blog into a terminal window (and threw out the theme while I was at it)'
date: 2026-10-16 10:30:00.00 +02:00
tag: ["Meta", "CSS", "Jekyll", "Web"]
category: Meta
---

So, new look. If you were here before you probably remember a white page with a serif font that looked like every
other Jekyll blog from 2016 - because that is exactly what it was. I have wanted something that looks like the thing
I stare at all day for a long time, and last evening I finally did it. This is a short note on how, mostly because
I ended up deleting more than I added, and that part surprised me.
<!--more-->

## How it started

I did not start from a design. I started from a complaint: the old theme pulled in a Google font, Font Awesome
(the whole 30 KB of it, for three icons in the footer) and a theme gem I had not updated in years. For a blog that
is ninety percent text and HCL snippets. Every time I touched it I had the feeling I was maintaining someone else's
furniture.

Then the "make it look like a console" idea came back, and I decided the two problems have one solution: rip out the
theme, write the layouts myself, and keep only what I can read in one sitting.

I was lazy about it, in the good way. I had Claude Code throw together three static mockups - a green-on-black retro
one with scanlines, a dark "modern terminal" one, and a man-page style light one - opened them side by side and
picked. The retro one was the most fun and the least readable. The man page was the most readable and did not look
like a terminal at all. The middle one won, with the scanlines stolen from the retro one because I liked them too much
to let go.

## What is actually there now

Six layout files in `_layouts/`, two tiny includes, one CSS file. No framework, no JavaScript in the theme, no web
fonts - it uses whatever monospace and sans fonts your system already has. The icons became words. Turns out "GitHub"
written as a word is perfectly understandable.

The whole page sits in a fake window, about 128 characters wide, which is roughly how wide I keep my real terminal:

```css
.win{position:relative;max-width:128ch;margin:0 auto;background:#1e1e2e;
     border-radius:10px;border:1px solid #313244;box-shadow:0 20px 60px rgba(0,0,0,.5);overflow:hidden}
.bar{background:#313244;padding:.55rem 1rem;display:flex;align-items:center;gap:.45rem}
.bar i{width:12px;height:12px;border-radius:50%}
.bar i:nth-child(1){background:#f38ba8}.bar i:nth-child(2){background:#f9e2af}.bar i:nth-child(3){background:#a6e3a1}
```

The three dots in the title bar are three empty `<i>` tags with a background colour. I was half expecting to need an
SVG for that, nope.

Colours are [Catppuccin Mocha](https://catppuccin.com/). Not a deep decision - it is everywhere already, it is easy on
the eyes, and giscus has a theme with the same name, so the comments box below the posts does not look like someone
glued a white sticker on a dark screen.

## The prompt thing

Every page is a sequence of fake commands and their "output". The prompt is a Jekyll include, I pass it the directory
and the command:

```html
{% raw %}<div class="p"><span class="arrow">➜</span> <span class="h">robert@notes</span>
<span class="d">{{ include.cwd }}</span> <span class="g">git:(</span><span class="arrow">master</span><span class="g">)</span>
<span class="c">{{ include.cmd }}</span></div>{% endraw %}
```

The front page pretends to run `ls -t posts/ | head -n 5 | xargs head -n 3`, a post is `glow something.md`, the
archive is `ls -lt`, a tag page is `grep -l "tag: AWS" *.md`. Yes, it is a gag. But it is a gag that also tells you
where on the site you are, so I am keeping it.

## Blinking cursor and scanlines, no JS

I was sure the cursor would need a few lines of JavaScript. It does not, it is a pseudo-element with a one-step
animation. Same for the scanlines, that is a repeating gradient painted over the window. The important bit is
`pointer-events: none`, otherwise you cannot select text through it - I learned that one the hard way, about thirty
seconds after adding it.

```css
.cur::after{content:"▋";animation:bl 1.1s steps(1) infinite}
@keyframes bl{50%{opacity:0}}
@media(prefers-reduced-motion:reduce){.cur::after{animation:none}}

.win::after{content:"";position:absolute;inset:0;pointer-events:none;
  background:repeating-linear-gradient(0deg,rgba(0,0,0,.12) 0 1px,transparent 1px 3px)}
```

The `prefers-reduced-motion` line is there because a blinking thing in the corner is cute for me and genuinely
unpleasant for some people. One line, do it.

## The one real decision: not everything is monospace

This is the part I went back and forth on. A page that is 100% monospace looks the most like a terminal. It is also
tiring to read once a post goes past a few hundred words, and some of mine go well past that. So I split it: anything
that is "UI" - prompts, nav, titles, headings, code - is monospace, and the body text of a post is a normal sans font,
slightly bigger. Headings keep a `##` in front of them, drawn by CSS, so they still look like markdown in a terminal:

```css
.post .body{font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;font-size:1.03rem;line-height:1.7}
.post .body h2{font-family:ui-monospace,Menlo,Consolas,monospace;color:#cba6f7}
.post .body h2::before{content:"## ";color:#6c7086}
```

If you are reading this on the site, you are looking at the result. If it bugs you, tell me, the mono-everything
version is one CSS rule away.

## A small confession

The theme has no JavaScript, but the page does. Google Analytics is still here, the comments are giscus (so that is an
iframe plus a script on post pages), and the contact form still has reCAPTCHA in front of it. Same three third parties
as before, I just moved the furniture around them. I did briefly have "no JS, no cookies" in the footer, noticed it was
a lie, and took it out. Whether to actually go cookie-free is a question for another evening.

## Was it worth it

Byte-wise, not dramatically: the stylesheet went from about 10 KB to about 7, and the font and icon downloads went
to zero. The site was never heavy. What I got rid of is moving parts. There is no theme gem to keep compatible with
Jekyll anymore, no CDN link that can rot, nothing to update. Seventy lines of CSS, and I know what every one of them
does. For a blog I post to a couple of times a year, that is the right amount of frontend to own.
