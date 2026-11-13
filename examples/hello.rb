# Evaluated by examples/embed.zig.

def greet(name)
  "Hello, #{name}, from mruby #{RUBY_VERSION}"
end

def ruby_sum(a, b)
  a + b
end

# Calls a function implemented in Zig and exposed as Zig.square.
Zig.square(7)
