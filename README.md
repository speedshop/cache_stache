# CacheStache

[![CI](https://github.com/speedshop/cache_stache/actions/workflows/ci.yml/badge.svg)](https://github.com/speedshop/cache_stache/actions/workflows/ci.yml)

Have you ever had to work with a Redis cache provider which doesn't provide hitrate stats? It's a bummer. Use this gem!

CacheStache tracks cache hit rates for Rails apps. It counts how often your cache has data (hits) and how often it does not (misses). You can view these counts on a web page.

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

### Add Authentication

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
  # Redis connection for storing cache metrics.
  # Can be a String (URL), Proc, or Redis-compatible object.
  config.redis = ENV.fetch("CACHE_STACHE_REDIS_URL", ENV["REDIS_URL"])

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
| `redis` | `ENV["CACHE_STACHE_REDIS_URL"]` or `ENV["REDIS_URL"]` | Redis connection (String URL, Proc, or Redis object) |
| `redis_pool_size` | 5 | Size of the Redis connection pool |
| `bucket_seconds` | 5 minutes | Size of each time bucket |
| `retention_seconds` | 7 days | How long to keep data |
| `max_buckets` | 288 | Maximum number of buckets to query |
| `sample_rate` | 1.0 | Sample events |
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

## Limits

- Only cache reads are tracked. Writes and deletes are not.
- If you have two cache stores of the same type (redis, memcached, etc), their events will be mixed.
