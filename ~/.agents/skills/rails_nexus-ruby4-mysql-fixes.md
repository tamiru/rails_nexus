# RailsNexus: Ruby 4.0 + MySQL + Rails 8.1 Compatibility Fixes

## Context
rails_nexus is a Rails engine for error logging dashboard. When upgrading to Ruby 4.0, MySQL, and Rails 8.1, several compatibility issues arise.

## Issues & Fixes

### 1. Ruby 4.0: Inline `rescue` removed
Ruby 4.0 removed inline `rescue` modifier on complex expressions.

**Bad:**
```erb
<% data = JSON.parse(@exception.breadcrumbs) rescue [] %>
<% if @foo.respond_to?(:bar) rescue false %>
```

**Good:**
```erb
<% begin; data = JSON.parse(@exception.breadcrumbs); rescue => _e; data = []; end %>
<% begin; result = @foo.respond_to?(:bar); rescue => _e; result = false; end %>
```

### 2. Ruby 4.0: `GC::STATS` removed
Use `GC.stat` instead.

**Bad:** `GC::STATS[:total_allocated_objects]`
**Good:** `GC.stat[:total_allocated_objects]`

### 3. Ruby 4.0: `Range#duration` removed
Use `(range.last - range.first)` instead.

**Bad:** `@time_range.duration`
**Good:** `(@time_range.last - @time_range.first)`

### 4. MySQL: `EXTRACT(DAYOFWEEK FROM ...)` invalid
Use MySQL functions directly.

**Bad:** `.where("EXTRACT(DAYOFWEEK FROM created_at) = ?", 1)`
**Good:** `.where("DAYOFWEEK(created_at) = ?", 1)`

**Bad:** `.where("EXTRACT(HOUR FROM created_at) = ?", hour)`
**Good:** `.where("HOUR(created_at) = ?", hour)`

### 5. MySQL: `strftime()` is SQLite-only
Use `DATE_FORMAT()` for MySQL.

**Bad:** `.group("strftime('%Y-%m-%d %H:00', created_at)")`
**Good:** `.group("DATE_FORMAT(created_at, '%Y-%m-%d %H:00')")`

### 6. Kaminari/WillPaginate: Guard pagination methods
Not all projects use the same pagination gem. Guard calls.

**Bad:**
```erb
<%= @records.total_entries %>
<%= will_paginate @records %>
```

**Good:**
```erb
<%= @records.respond_to?(:total_entries) ? @records.total_entries : @records.length %>
<% if @records.respond_to?(:total_pages) && @records.total_pages > 1 %>
  <% if defined?(WillPaginate) %><%= will_paginate @records %><% end %>
<% end %>
```

### 7. JS: Don't use Ruby syntax in JavaScript files
**Bad (Ruby in JS):**
```js
snippet.lines.each do |line|
  bg = line[:highlighted] ? 'red' : 'blue'
end
```

**Good (proper JS):**
```js
snippet.lines.forEach((line) => {
  const bg = line.highlighted ? 'red' : 'blue'
})
```

### 8. Rails 8.1: `serialize` requires `coder:` keyword
**Bad:** `serialize :data, JSON`
**Good:** `serialize :data, coder: JSON`

### 9. Backtick interpolation in hash literal
Ruby 4.0 parser rejects backtick commands inside hash literals.

**Bad:**
```ruby
stats[:process] = {
  command: `ps -p #{Process.pid} -o args=`.strip
}
```

**Good:**
```ruby
cmd = `ps -p #{Process.pid} -o args=`.strip
stats[:process] = { command: cmd }
```

## Testing Checklist
After applying fixes:
1. `ruby -c` on all modified `.rb` files
2. `bundle exec rake test` passes
3. `yarn build` passes (no Ruby syntax in JS)
4. Verify all routes return expected status (403 with auth, 200 without)
5. Check `tail -20 log/development.log` for no 500 errors
