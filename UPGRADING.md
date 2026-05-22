# Upgrading to SafeMemoize 1.0.0

This guide covers every behavioral change introduced across the 0.x series that could affect code written against an earlier release. Work through the sections that apply to your starting version.

---

## Summary of breaking changes

| Change | Introduced | Impact |
|---|---|---|
| Ruby 3.2 dropped | v0.5.0 | High if still on Ruby 3.2 |
| TTL clock starts at first call, not definition | v0.6.0 | Medium — affects TTL precision |
| `memo_keys`/`memo_values` shape for custom keys | v0.6.1 | Low — only if inspecting key metadata |
| `memoize` raises at definition time for undefined methods | v0.8.0 | Medium — affects dynamic class construction |
| Argument mutation no longer corrupts cache | v0.8.0 | Low — was silent bug; may surface latent test issues |
| Hook exceptions no longer propagate | v0.8.0 | Medium — only if catching hook exceptions |
| `memoized?` / introspection methods now respect custom keys | v1.0.0 | Low — bug fix; only if using custom keys |
| `reset_memo` with args and `memo_refresh` respect custom keys | v1.0.0 | Low — bug fix; only if using custom keys |

---

## Upgrading from 0.1.x or 0.2.x

Follow every section below in order.

## Upgrading from 0.3.x – 0.4.x

Follow sections starting from [Ruby 3.2 dropped](#ruby-32-dropped-v050).

## Upgrading from 0.5.x

Follow sections starting from [TTL clock fix](#ttl-clock-now-starts-at-first-call-v060).

## Upgrading from 0.6.x

Follow sections starting from [memoize on undefined methods](#memoize-on-an-undefined-method-raises-at-definition-time-v080).

## Upgrading from 0.7.x – 0.9.x

Follow sections starting from [custom key introspection fix](#introspection-methods-now-respect-custom-keys-v100).

---

## Ruby 3.2 dropped (v0.5.0)

**Impact:** High — the gem will not install on Ruby 3.2.

Ruby 3.2 reached end-of-life and was removed from the supported matrix in v0.5.0. The gemspec now enforces `ruby >= 3.3.0`.

**Migration:** Upgrade to Ruby 3.3 or later before updating the gem.

---

## TTL clock now starts at first call, not definition (v0.6.0)

**Impact:** Medium — affects how long entries actually live in the cache.

Before v0.6.0, the TTL countdown began when `memoize :method, ttl: N` was evaluated (class load time). If a class was loaded 30 seconds before the first call, entries would expire 30 seconds earlier than expected.

From v0.6.0 onwards, the clock starts on the first cache write — the entry lives for exactly `ttl` seconds after it is populated.

**Migration:** No code change required. Entries now live for the duration you specified. If you intentionally set very short TTLs and relied on the early-start behaviour (unlikely), reduce your TTL value accordingly.

---

## `memo_keys`/`memo_values` shape change for custom-keyed entries (v0.6.1)

**Impact:** Low — only affects code that reads the hashes returned by these methods.

Before v0.6.1, entries stored via `memoize_with_custom_key` were surfaced in `memo_keys` and `memo_values` as:

```ruby
{ args: <the_custom_key>, kwargs: nil }
```

From v0.6.1 onwards they are correctly surfaced as:

```ruby
{ custom_key: <the_custom_key> }
```

**Migration:** If your code inspects the hash returned by `memo_keys` or `memo_values` and checks for an `:args` key to detect custom-keyed entries, update it to check for `:custom_key` instead:

```ruby
# Before
entry[:args] # custom key was smuggled here

# After
entry[:custom_key] # explicit field
entry[:args]       # only present for default-keyed entries
```

---

## `memoize` on an undefined method raises at definition time (v0.8.0)

**Impact:** Medium — affects any code that calls `memoize` before the method is defined,
or that dynamically defines methods after `memoize` is called.

Before v0.8.0, calling `memoize :missing_method` silently succeeded at class load time. The error only appeared at runtime when the memoized wrapper tried to call `super` and found nothing to call.

From v0.8.0 onwards, `memoize` raises `ArgumentError` immediately if the named method does not exist at the time of the call.

**Migration:** Ensure `memoize` is always called *after* the method it wraps:

```ruby
# Wrong — memoize called before def (raises ArgumentError in v0.8.0+)
memoize :compute
def compute = expensive_work

# Correct
def compute = expensive_work
memoize :compute
```

If you use `Module#prepend` or `include` to add methods dynamically, make sure `memoize` is called after the module is prepended/included:

```ruby
include MyMethods   # defines :compute
memoize :compute    # now safe
```

---

## Argument mutation no longer corrupts the cache (v0.8.0)

**Impact:** Low — this was a silent bug. Existing code is unlikely to rely on it, but test suites that mutate arguments after a call and expect a cache miss may need updating.

Before v0.8.0, mutable cache keys (arrays, hashes, strings passed as arguments) were stored by reference. Mutating an argument after a call could cause the cache to behave unpredictably — sometimes missing on identical arguments, sometimes returning stale values.

From v0.8.0 onwards, argument arrays, hashes, and strings are deep-frozen into an independent copy when the cache key is built. Callers can mutate their arguments after a call without affecting the cache.

**Migration:** No migration required for production code. If a test mutates arguments after a memoized call and expects a cache miss, the test was relying on the buggy behaviour — update it to use distinct argument values instead.

---

## Hook exceptions no longer propagate to callers (v0.8.0)

**Impact:** Medium — only affects code that wraps memoized calls in `rescue` to catch errors raised by hooks.

Before v0.8.0, an exception raised inside an `on_memo_hit`, `on_memo_miss`, `on_memo_store`, `on_memo_expire`, or `on_memo_evict` hook would propagate through the memoized method call and be visible to the caller.

From v0.8.0 onwards, hook exceptions are isolated. By default a `[SafeMemoize] Hook error in <type>: <message>` warning is written to `$stderr` and execution continues normally.

**Migration:** If you need hook exceptions to propagate (e.g. in a strict test environment), configure `on_hook_error` to re-raise:

```ruby
SafeMemoize.configure do |c|
  c.on_hook_error = ->(error, hook_type, cache_key) { raise error }
end
```

Or to route them to your error tracker without raising:

```ruby
SafeMemoize.configure do |c|
  c.on_hook_error = ->(error, _type, _key) { Bugsnag.notify(error) }
end
```

---

## Introspection methods now respect custom keys (v1.0.0)

**Impact:** Low — only affects code that uses `memoize_with_custom_key` or the `key:` option together with any of the introspection methods listed below.

Before v1.0.0, the following methods looked up cache entries using the *default* key (derived from raw arguments) rather than the *custom* key generator. This meant they always returned incorrect results when a custom key was active:

- `memoized?`
- `memo_ttl_remaining`
- `memo_touch`
- `memo_age`
- `memo_stale?`

From v1.0.0 onwards, all five methods correctly call `compute_cache_key`, which checks for a custom key generator first.

**Migration:** No code change required — the methods now return correct results. If your code had workarounds that bypassed these methods (e.g. manually inspecting `memo_keys` to determine if an entry existed), you can simplify them to use `memoized?` directly.

---

## `reset_memo` with args and `memo_refresh` respect custom keys (v1.0.0)

**Impact:** Low — only affects code that uses custom keys and calls `reset_memo` with specific arguments, or calls `memo_refresh`.

Before v1.0.0, `reset_memo(:method, *args)` with explicit arguments built a default key from raw args to match entries. When the method used a custom key generator, no entry was found and nothing was cleared. `memo_refresh` inherited the same flaw — the old entry survived and `refresh` returned the cached (stale) value instead of recomputing.

From v1.0.0 onwards, both methods resolve the cache key through `compute_cache_key`.

**Migration:** No code change required — the methods now behave correctly. Note that `reset_memo(:method)` with *no* arguments still clears all entries for the method regardless of key format; this behaviour is unchanged.

---

## New stable API

All symbols listed in the README `## Public API and versioning guarantee` section are now covered by [Semantic Versioning](https://semver.org/) from v1.0.0 onwards. Breaking changes to any of those symbols require a major version bump.

Opt-in extensions (`SafeMemoize::Rails`, `SafeMemoize::Adapters::StatsD`, `SafeMemoize::Adapters::OpenTelemetry`) are available but are *not* included in the v1.0.0 semver guarantee; they will be stabilised in a subsequent minor release.