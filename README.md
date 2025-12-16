# CacheStache

[![CI](https://github.com/speedshop/cache_stache/actions/workflows/ci.yml/badge.svg)](https://github.com/speedshop/cache_stache/actions/workflows/ci.yml)

CacheStache tracks cache hit rates for Rails apps. It counts how often your cache has data (hits) and how often it does not (misses). You can view these counts on a web page.

A higher hit rate means your app finds data in the cache more often. This means fewer slow calls to your database or other services. CacheStache helps you see this rate over time and spot problems.

## Features

- Listens to cache events from Rails
- Groups counts into time buckets (default: 5 minutes)
- Keeps data for a set time (default: 7 days)
- Tracks custom groups of cache keys (called "keyspaces")
- Stores metrics in Redis
- Includes a web page to view stats

## Requirements

- Ruby 3.1+
- Rails 7.0+
- Redis

## Quick Start

1. Run the install command:

   ```bash
   rails generate cache_stache:install
   ```

   This creates a file at `config/initializers/cache_stache.rb`.

2. Edit the file to set your options and keyspaces.

3. Add the web page to `config/routes.rb`:

   ```ruby
   require "cache_stache/web"
   mount CacheStache::Web, at: "/cache-stache"
   ```

4. Restart Rails and go to `/cache-stache`.

### Add a Password (Optional)

You can add a password to the web page:

```ruby
require "cache_stache/web"

CacheStache::Web.use Rack::Auth::Basic do |user, pass|
  ActiveSupport::SecurityUtils.secure_compare(user, ENV["CACHE_STACHE_USER"]) &&
    ActiveSupport::SecurityUtils.secure_compare(pass, ENV["CACHE_STACHE_PASS"])
end

mount CacheStache::Web, at: "/cache-stache"
```

## Settings

All settings go in `config/initializers/cache_stache.rb`:

```ruby
CacheStache.configure do |config|
  # Redis connection for storing cache metrics
  # Falls back to ENV["REDIS_URL"] if not set
  config.redis_url = ENV.fetch("CACHE_STACHE_REDIS_URL", ENV["REDIS_URL"])

  # Time bucket size
  config.bucket_seconds = 5.minutes

  # How long to keep data
  config.retention_seconds = 7.days

  # Sample rate (not yet active)
  config.sample_rate = 1.0

  # Turn off in tests
  config.enabled = !Rails.env.test?

  # Wait until after response to write (needs Puma)
  config.use_rack_after_reply = false

  # Track groups of cache keys
  config.keyspace :profiles do
    label "Profile Fragments"
    match /^profile:/
  end

  config.keyspace :search do
    label "Search Results"
    match %r{/search/}
  end
end
```

### Setting List

| Setting | Default | What it does |
|---------|---------|--------------|
| `redis_url` | `ENV["CACHE_STACHE_REDIS_URL"]` or `ENV["REDIS_URL"]` | Redis connection URL |
| `redis_pool_size` | 5 | Size of the Redis connection pool |
| `bucket_seconds` | 5 minutes | Size of each time bucket |
| `retention_seconds` | 7 days | How long to keep data |
| `max_buckets` | 288 | Maximum number of buckets to query |
| `sample_rate` | 1.0 | Not yet active |
| `enabled` | true | Turn tracking on or off |
| `use_rack_after_reply` | false | Wait to write until after response |

### Keyspaces

Keyspaces let you group cache keys by name pattern. Each has a name, a label, and a regex:

```ruby
config.keyspace :views do
  label "View Fragments"
  match /views\//
end

config.keyspace :models do
  label "Model Cache"
  match %r{/(community|unit|lease)/}
end
```

A cache key can match more than one keyspace.

## Web Page

The web page shows:

- Total hit rate
- Hit rate for each keyspace
- Current settings
- Size of stored data

Time windows: 5m, 15m, 1h (default), 6h, 1d, 1w.

Click a keyspace name to see more detail.

## How It Works

```
Rails.cache.fetch(...)
  -> Rails sends an event
  -> CacheStache counts it
  -> CacheStache stores the count
  -> Web page shows the counts
```

1. **Counting**: CacheStache listens for cache events. It skips its own cache calls.

2. **Buckets**: Times are rounded down to `bucket_seconds`. Each event adds to hit or miss counts.

3. **Storage**: Counts are stored with keys like `cache_stache:v1:production:1234567890`. Each bucket expires after `retention_seconds`.

4. **Reading**: The web page reads all buckets and adds them up.

## Query Stats in Code

You can get stats from Ruby code:

```ruby
query = CacheStache::StatsQuery.new(window: 1.hour)
results = query.execute

results[:overall][:hit_rate_percent]  # => 85.5
results[:overall][:hits]              # => 1234
results[:overall][:misses]            # => 210
results[:keyspaces][:profiles][:hit_rate_percent]  # => 92.1
```

## Test Data

Make fake data with:

```bash
rails runner lib/cache_stache/bin/test_day_simulation.rb
```

This makes 24 hours of fake cache events. Then go to `/cache-stache` to see it.

## Limits

- The `sample_rate` setting does nothing yet.
- Only cache reads are tracked. Writes and deletes are not.
- If you have two cache stores of the same type, their events will be mixed.

## Files

```
lib/cache_stache/
├── app/               # Web page views and code
├── bin/               # Test scripts
├── config/            # Routes
├── lib/               # Gem/engine Ruby code
│   ├── cache_stache.rb
│   ├── cache_stache/
│   └── generators/
├── Gemfile            # Standalone bundler entrypoint
├── cache_stache.gemspec
├── Rakefile
├── spec/              # Tests
├── tasks/             # Rake tasks
```

## Running Specs (Standalone)

CacheStache can be tested independently from the host Rails app:

```bash
cd lib/cache_stache
bundle install
bundle exec rspec
```

From the host app root, you can also run the engine suite without `cd`:

```bash
BUNDLE_GEMFILE=lib/cache_stache/Gemfile bundle exec rspec --options lib/cache_stache/.rspec lib/cache_stache/spec
```

## Run Tests

```bash
cd lib/cache_stache
bundle exec rspec
```

Tests are in `lib/cache_stache/spec/`. They do not need Redis.
