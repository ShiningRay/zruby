# Default-gem smoke tests: Struct, Set, Fiber, Enumerator, Time, Random,
# eval, pack and GC.

def assert(condition, message = "assertion failed")
  raise message unless condition
end

assert(sprintf("%05.2f", 3.14159) == "03.14", "sprintf")

if Object.const_defined?(:Struct)
  Point = Struct.new(:x, :y) do
    def magnitude
      Math.sqrt(x * x + y * y)
    end
  end
  point = Point.new(3, 4)
  assert(point.magnitude == 5.0, "struct method")
end

if Object.const_defined?(:Set)
  set = Set.new([1, 2, 2, 3])
  assert(set.size == 3, "set")
end

if Object.const_defined?(:Fiber)
  values = []
  fiber = Fiber.new do
    values << 1
    Fiber.yield
    values << 2
  end
  fiber.resume
  fiber.resume
  assert(values == [1, 2], "fiber")
end

if Kernel.respond_to?(:eval)
  assert(eval("40 + 2") == 42, "eval builtin")
end

if Object.const_defined?(:Enumerator)
  enum = [1, 2, 3].each
  assert(enum.next == 1, "enumerator next")
end

if Object.const_defined?(:Time)
  assert(Time.now.year >= 2000, "time year")
end

if Object.const_defined?(:Random)
  assert(Random.rand(10) >= 0 && Random.rand(10) < 10, "random range")
end

if [].respond_to?(:pack)
  assert([65, 66].pack("C*").unpack("C*") == [65, 66], "pack/unpack")
end

if Object.const_defined?(:JSON)
  assert(JSON.parse('{"a":1}')["a"] == 1, "json parse")
  assert(JSON.generate({"a" => 1}) == '{"a":1}', "json generate")
end

GC.start
assert(true, "gc")
