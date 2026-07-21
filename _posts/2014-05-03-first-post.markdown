---
layout: post
title: first post
date: 2014-05-03 22:40:03.00 +02:00
tag: ["First Post"]
---
#### Let's write it down.
To be honest, I don't remember when I actually started thinking about writing down most of the solutions I found on the internet or implemented myself.
I realized that from time to time I go back to solutions, code snippets or config files I created or modified to fulfill some specific requirements. It's good if I wrote it down somewhere, put it on [Gist](https://gist.github.com/robertwe) or [Pastebin](http://pastebin.com/), but what if I did not?
Let's say I just configured Nginx as a load balancer and, for example, after a year or so I need to make something exactly the same or at least similar. What then? I need to go through the Nginx documentation again or start searching on Google. Sure, in some cases I remember exactly how I solved a specific problem, but when it was some time ago then...
This is the reason why I decided to create this simple blog. I hope it won't evolve in any unpredictable way. You can think about this blog as my notebook. If somebody else finds my notes useful/helpful - even better. Let's make this World better.

Have a great day.


*P.S. As you probably noticed, I'm not a native speaker, so in case you find some mistakes in my posts (probably more than one), please let me know ASAP.*

<script type="text/javascript" async
  src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-MML-AM_CHTML">
</script>


| RAM | vCPU | Price (€) |
|:---:|:----:|:---------:|
|  1G |   1  |     5     |
|  2G |   2  |     10    |
|  4G |   4  |     30    |
|  8G |   6  |     60    |
| 12G |   8  |    120    |
| 16G |  10  |    160    |
| 24G |  12  |    240    |
| 32G |  16  |    320    |

<hr />


### Our universe (in SI units):

$$
\begin{align*}
  \frac{\partial\mathcal{D}}{\partial t} \quad & = \quad \nabla\times\mathcal{H},   & \quad \text{(Faraday's law)} \\[5pt]
  \frac{\partial\mathcal{B}}{\partial t} \quad & = \quad -\nabla\times\mathcal{E},  & \quad \text{(Ampère's circuital law)}   \\[5pt]
  \nabla\cdot\mathcal{B}                 \quad & = \quad 0,                         & \quad \text{(Gauss's law for magnetism)}   \\[5pt]
  \nabla\cdot\mathcal{D}                 \quad & = \quad 0.                         & \quad \text{(Coulomb's Law)}
  \end{align*}
$$

<hr />

$$
\begin{align*}
  & \phi(x,y) = \phi \left(\sum_{i=1}^n x_ie_i, \sum_{j=1}^n y_je_j \right)
  = \sum_{i=1}^n \sum_{j=1}^n x_i y_j \phi(e_i, e_j) = \\
  & (x_1, \ldots, x_n) \left( \begin{array}{ccc}
      \phi(e_1, e_1) & \cdots & \phi(e_1, e_n) \\
      \vdots & \ddots & \vdots \\
      \phi(e_n, e_1) & \cdots & \phi(e_n, e_n)
    \end{array} \right)
  \left( \begin{array}{c}
      y_1 \\
      \vdots \\
      y_n
    \end{array} \right)
\end{align*}
$$
<hr />
$$
\begin{array}{c|lcr}
n & \text{Left} & \text{Center} & \text{Right} \\
\hline
1 & 0.24 & 1 & 125 \\
2 & -1 & 189 & -8 \\
3 & -20 & 2000 & 1+10i
\end{array}
$$

{% highlight ruby %}
def show
  @widget = Widget(params[:id])
  respond_to do |format|
    format.html # show.html.erb
    format.json { render json: @widget }
  end
end
{% endhighlight %}


{% highlight go %}
package interfaces
import (
	"io"
	"os"
)

//PipeExample function
func PipeExample() error {
	r, w := io.Pipe()

	go func() {
		w.Write([]byte("test\n"))
		w.Close()
	}()

	if _, err := io.Copy(os.Stdout, r); err != nil {
		return err
	}
	return nil
}
{% endhighlight %}

{% highlight go %}
package interfaces

import (
	"fmt"
	"io"
	"os"
)

// Copy data from std in to std out
func Copy(in io.ReadSeeker, out io.Writer) error {
	w := io.MultiWriter(out, os.Stdout)
	if _, err := io.Copy(w, in); err != nil {
		return err
	}
	in.Seek(0, 0)
	buf := make([]byte, 64)
	if _, err := io.CopyBuffer(w, in, buf); err != nil {
		return err
	}

	fmt.Println()
	return nil
}
{% endhighlight %}
--robert
