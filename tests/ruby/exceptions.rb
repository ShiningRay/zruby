# Exception control flow, rescue/ensure/retry and error classes.

def assert(condition, message = "assertion failed")
  raise message unless condition
end

class ZigError < StandardError
end

begin
  raise ZigError, "custom"
rescue ZigError => error
  assert(error.message == "custom", "custom message")
  assert(error.is_a?(StandardError), "custom hierarchy")
else
  raise "unreachable else"
ensure
  $ensured = true
end
assert($ensured, "ensure ran")

# Retry once.
attempts = 0
begin
  attempts += 1
  raise "retry me" if attempts < 2
rescue
  retry
end
assert(attempts == 2, "retry")

# Ensure runs on return.
def zig_ensure_return
  return 42
ensure
  $ensured_return = true
end
assert(zig_ensure_return == 42, "return value")
assert($ensured_return, "ensure on return")

# Re-raise preserves the active exception.
begin
  begin
    raise ArgumentError, "inner"
  rescue => original
    # mruby 4.0's bare `raise` does not re-raise the active exception;
    # pass the captured exception explicitly.
    raise original
  end
rescue ArgumentError => error
  assert(error.message == "inner", "re-raise")
end

# Nested rescue replaces the exception.
begin
  begin
    raise "first"
  rescue
    raise "second"
  end
rescue => error
  assert(error.message == "second", "nested rescue")
end

# Standard error classes.
begin
  1 / 0
rescue ZeroDivisionError
  assert(true, "zero division")
end

begin
  nil.not_a_method
rescue NoMethodError
  assert(true, "no method")
end

begin
  Integer("not-a-number")
rescue ArgumentError
  assert(true, "integer conversion")
end

# Catch/throw if available.
if Kernel.respond_to?(:catch)
  result = catch(:zig_throw) do
    throw :zig_throw, 42
  end
  assert(result == 42, "catch/throw")
end
