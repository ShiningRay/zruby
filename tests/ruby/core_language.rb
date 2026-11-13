# Core language smoke suite, executed through VM.evalWithOptions.
# Any raise fails the corresponding Zig test.

def assert(condition, message = "assertion failed")
  raise message unless condition
end

# Scalar literals and operators.
assert(1 + 2 == 3, "addition")
assert(2 ** 10 == 1024, "power")
assert(7 / 2 == 3, "integer division")
assert(-7 / 2 == -4, "floor division")
assert(7 % 3 == 1, "modulo")
assert(0.1 + 0.2 > 0.29, "float precision")
assert(nil.nil?, "nil")
assert(true && !false, "booleans")

# Strings and symbols.
assert("hello world".split == ["hello", "world"], "split")
assert("a-b-c".tr("-", "_") == "a_b_c", "tr")
assert("pad".ljust(5, ".") == "pad..", "ljust")
assert("abc"[1] == "b", "string index")
assert(("a" + "b") == "ab", "string concatenation")
assert(:alpha.to_s == "alpha", "symbol to_s")
assert("alpha".to_sym == :alpha, "string to_sym")

# Arrays, hashes and ranges.
assert([1, 2, 3].map { |x| x * 2 } == [2, 4, 6], "map")
assert([1, 2, 3].select { |x| x % 2 == 1 } == [1, 3], "select")
assert([1, 2, 3].inject(0) { |sum, x| sum + x } == 6, "inject")
assert([3, 1, 2].sort == [1, 2, 3], "sort")
assert([[1, 2], [3]].flatten == [1, 2, 3], "flatten")
assert([1, 2, 2].uniq == [1, 2], "uniq")
assert({ a: 1, b: 2 }.map { |key, value| "#{key}#{value}" }.sort == ["a1", "b2"], "hash map")
assert({ a: 1 }[:a] == 1, "hash lookup")
assert((1..5).to_a == [1, 2, 3, 4, 5], "range to_a")
assert((1..5).include?(3), "range include")
assert((1..5).select { |x| x % 2 == 1 } == [1, 3, 5], "range select")

# Classes, inheritance, modules and accessors.
class Animal
  attr_accessor :name

  def initialize(name)
    @name = name
  end

  def speak
    "..."
  end
end

class Dog < Animal
  def speak
    "woof"
  end
end

module Greeter
  def greet
    "hi #{@name}"
  end
end

class TalkingDog < Dog
  include Greeter

  def speak
    super.upcase + "!"
  end
end

dog = TalkingDog.new("rex")
assert(dog.is_a?(Animal), "inheritance")
assert(dog.name == "rex", "attr reader")
dog.name = "zig"
assert(dog.name == "zig", "attr writer")
assert(dog.speak == "WOOF!", "super and interpolation")
assert(dog.greet == "hi zig", "module mixin")

# Blocks, procs and lambdas.
sum = 0
[1, 2, 3].each { |value| sum += value }
assert(sum == 6, "each block")
double = ->(value) { value * 2 }
assert(double.call(21) == 42, "lambda")
values = [1, 2, 3].map(&:to_s)
assert(values == ["1", "2", "3"], "symbol to proc")

# Exceptions, rescue and ensure.
ensured = false
begin
  raise ArgumentError, "nope"
rescue ArgumentError => error
  assert(error.message == "nope", "exception message")
else
  raise "should not reach else"
ensure
  ensured = true
end
assert(ensured, "ensure ran")

# Struct, Set and Fiber are part of the default gem set.
if Object.const_defined?(:Struct)
  Point = Struct.new(:x, :y)
  point = Point.new(3, 4)
  assert(point.x == 3 && point.y == 4, "struct")
  assert(point.to_a == [3, 4], "struct to_a")
end

if Object.const_defined?(:Set)
  set = Set.new([1, 2, 2, 3])
  assert(set.size == 3, "set dedup")
  set << 1
  assert(set.size == 3, "set idempotent add")
end

if Object.const_defined?(:Fiber)
  fiber_values = []
  fiber = Fiber.new do
    fiber_values << 1
    Fiber.yield
    fiber_values << 2
  end
  fiber.resume
  fiber.resume
  assert(fiber_values == [1, 2], "fiber")
end

if Kernel.respond_to?(:eval)
  assert(eval("1 + 1") == 2, "eval")
end

if Object.const_defined?(:Time)
  assert(Time.now.year >= 2000, "time")
end

if Object.const_defined?(:Random)
  assert(Random.rand(10) >= 0 && Random.rand(10) < 10, "random")
end

GC.start
assert(true, "gc ran")
