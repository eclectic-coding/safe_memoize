# SafeMemoize

Thread-safe memoization for Ruby that correctly handles `nil` and `false` values.

## The Problem

Ruby's common memoization pattern breaks with falsy values:

```ruby
def user
  @user ||= find_user  # Re-runs find_user every time it returns nil!
end
```

SafeMemoize uses `Hash#key?` to distinguish "not yet cached" from "cached nil/false", so your methods are only computed once regardless of return value.

## Features

- Correctly memoizes `nil` and `false` return values
- Caches per unique arguments (positional and keyword)
- Thread-safe via double-check locking
- Zero runtime dependencies
- Simple `prepend` + `memoize` API
- Block arguments bypass cache (blocks aren't comparable)

## Installation

Add to your Gemfile:

```ruby
gem "safe_memoize"
```

Then run:

```bash
bundle install
```

Or install directly:

```bash
gem install safe_memoize
```

## Usage

### Basic memoization

```ruby
class UserService
  prepend SafeMemoize

  def current_user
    # This expensive lookup runs only once
    User.find_by(session_id: session_id)
  end
  memoize :current_user
end
```

### With arguments

Results are cached per unique argument combination:

```ruby
class Calculator
  prepend SafeMemoize

  def compute(x, y)
    sleep(2)
    x + y
  end
  memoize :compute
end

calc = Calculator.new
calc.compute(1, 2)  # computes and caches
calc.compute(1, 2)  # returns cached result
calc.compute(3, 4)  # computes and caches (different args)
```

### Nil and false safety

```ruby
class Config
  prepend SafeMemoize

  def enabled?
    # Only called once, even though it returns false
    ENV["FEATURE_FLAG"] == "true"
  end
  memoize :enabled?
end
```

### Cache reset

```ruby
obj = MyService.new
obj.reset_memo(:current_user)  # Clears cache for one method
obj.reset_all_memos            # Clears all memoized values
```

## How It Works

SafeMemoize uses Ruby's `prepend` mechanism. When you call `memoize :method_name`, it creates an anonymous module with a wrapper method and prepends it onto your class. The wrapper calls `super` to invoke the original method and stores the result in a per-instance hash. Thread safety is achieved with a per-instance `Mutex` using double-check locking.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rspec` to run the tests. You can also run `bin/console` for an interactive prompt.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/eclectic-coding/safe_memoize.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
