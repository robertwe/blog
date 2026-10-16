---
layout: post
title: 'Go: a request ID on every log line with log/slog, without passing a logger around'
date: 2026-10-16 14:00:00.00 +02:00
tag: ["Programming", "GoLang", "AWS", "Observability"]
category: GoLang
---

The single most useful field in a production log is the one that lets you pull every line belonging to one request.
Most Go codebases get there by threading a `*slog.Logger` through every function signature, or by stuffing the logger
into the context and fishing it out everywhere. There is a cleaner way that the `slog` design makes almost trivial:
a `Handler` that reads the request ID from the `context.Context` it is given. Then every call site is just
`slog.InfoContext(ctx, ...)`, and the ID appears on its own.
<!--more-->

## The idea in one paragraph

Every `slog` logging method has a `Context` variant, `slog.InfoContext(ctx, msg, attrs...)`, and the context is
passed down to the handler's `Handle(ctx, record)` method. The built-in handlers ignore it. Ours will not: it looks
for a request ID in the context and, if there is one, appends it to the record before delegating to the real handler.
Nobody downstream needs to know a logger exists beyond the standard package functions.

## The handler

```go
package logging

import (
	"context"
	"log/slog"
)

type ctxKey struct{}

// WithRequestID returns a context carrying the request id.
func WithRequestID(ctx context.Context, id string) context.Context {
	return context.WithValue(ctx, ctxKey{}, id)
}

// RequestID returns the request id stored in ctx, or "".
func RequestID(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}

// ctxHandler wraps another slog.Handler and adds request_id from the context.
type ctxHandler struct {
	slog.Handler
}

func NewHandler(inner slog.Handler) slog.Handler {
	return ctxHandler{Handler: inner}
}

func (h ctxHandler) Handle(ctx context.Context, r slog.Record) error {
	if id := RequestID(ctx); id != "" {
		r.AddAttrs(slog.String("request_id", id))
	}
	return h.Handler.Handle(ctx, r)
}

// WithAttrs and WithGroup must return the wrapper, not the inner handler,
// otherwise a logger.With(...) call silently drops the request id.
func (h ctxHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return ctxHandler{Handler: h.Handler.WithAttrs(attrs)}
}

func (h ctxHandler) WithGroup(name string) slog.Handler {
	return ctxHandler{Handler: h.Handler.WithGroup(name)}
}
```

The comment on `WithAttrs` and `WithGroup` is the one non-obvious thing. `slog.Handler` is an interface with those
two methods, and if you embed the inner handler and do not override them, `logger.With("component", "db")` returns
a logger whose handler is the *inner* one, and the request ID disappears for that logger only. That bug is quiet and
annoying to find. Override both, always.

Wire it up once in `main`:

```go
slog.SetDefault(slog.New(logging.NewHandler(
	slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}),
)))
```

## HTTP: a middleware that mints or forwards the ID

```go
func RequestIDMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			var b [16]byte
			rand.Read(b[:]) // crypto/rand; the error is always nil on supported platforms since Go 1.24
			id = hex.EncodeToString(b[:])
		}
		w.Header().Set("X-Request-ID", id)
		ctx := logging.WithRequestID(r.Context(), id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
```

Honouring an incoming `X-Request-ID` means a request that crosses three services keeps one ID across all three logs,
as long as each service forwards the header on outgoing calls. Returning it in the response means a user can read it
from their browser's network tab and paste it into a bug report, which is worth more than it sounds.

From here on, handlers and everything they call just do:

```go
func (s *Server) handleOrder(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	slog.InfoContext(ctx, "order received", "customer", custID)

	if err := s.store.Save(ctx, order); err != nil {
		slog.ErrorContext(ctx, "saving order", "err", err)
		http.Error(w, "internal error", 500)
		return
	}
}
```

`s.store.Save` receives the same `ctx`, logs with `slog.WarnContext(ctx, ...)` three packages deep, and the line comes
out with the same `request_id`. No logger parameter anywhere.

## Lambda: the ID already exists

In a Lambda function the context handed to your handler already carries the invocation's request ID. Pull it out and
drop it into our context once at the top:

```go
import "github.com/aws/aws-lambda-go/lambdacontext"

func handler(ctx context.Context, evt events.SQSEvent) error {
	if lc, ok := lambdacontext.FromContext(ctx); ok {
		ctx = logging.WithRequestID(ctx, lc.AwsRequestID)
	}
	slog.InfoContext(ctx, "batch received", "records", len(evt.Records))
	// ...
}
```

The nice side effect: that is the same ID CloudWatch prints in its own `START RequestId: ...` and `REPORT` lines, so
your structured lines and the runtime's lines correlate with no extra work.

## Reading it back in CloudWatch

Stdout from a Lambda or an ECS task lands in CloudWatch Logs as-is, one JSON object per line. Logs Insights parses
JSON automatically, so the query to follow one request is:

```
fields @timestamp, level, msg, err
| filter request_id = "4f1c0b2e9a7d4c3e8b6a5f0e1d2c3b4a"
| sort @timestamp asc
```

And the one you actually run on a bad day, "which requests errored in the last hour and how many lines did each
produce":

```
filter level = "ERROR"
| stats count() as lines, min(@timestamp) as first_seen by request_id
| sort first_seen desc
| limit 50
```

If you want this to work for ECS as well, use the `awslogs` log driver with no special format, JSON lines are enough.

## Two things to avoid

**Do not put the logger itself in the context.** It works, but every call site becomes `logger.FromContext(ctx).Info(...)`
and people forget, fall back to `slog.Info`, and the ID vanishes from exactly the lines you need. Putting only the
*ID* in the context and having the handler do the work means the plain `slog.InfoContext` is the right call everywhere.

**Do not forget the `Context` variants.** `slog.Info(msg)` passes `context.Background()` to the handler, so no ID.
A `go vet` style check for this does not exist in the standard tooling as far as I know; a `grep -rn 'slog\.\(Info\|Warn\|Error\|Debug\)('` in CI
is crude and effective.

The whole thing is forty lines, uses nothing outside the standard library and the Lambda SDK, and it is the first
thing I add to any new Go service now. Ten minutes once, and every incident afterwards starts with a request ID
instead of a timestamp and a guess.
