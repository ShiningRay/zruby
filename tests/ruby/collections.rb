# Arrays, hashes, ranges and strings through the default gem set.

def assert(condition, message = "assertion failed")
  raise message unless condition
end

# Arrays.
array = [3, 1, 2]
assert(array[0] == 3, "array index")
assert(array[-1] == 2, "negative index")
assert(array[99].nil?, "out of bounds")
array[5] = 9
assert(array.length == 6, "array extension")
assert(array[4].nil?, "extension gap")
assert(array.include?(3), "include")
assert(array.index(1) == 1, "index")
assert([1, 2, 3].push(4) == [1, 2, 3, 4], "push")
assert([1, 2, 3].pop == 3, "pop")
assert([1, 2, 3].shift == 1, "shift")
assert([1, 2, 3].unshift(0) == [0, 1, 2, 3], "unshift")
assert([1, 2, 2, 3].uniq == [1, 2, 3], "uniq")
assert([1, [2, [3]]].flatten == [1, 2, 3], "flatten")
assert([3, 1, 2].sort == [1, 2, 3], "sort")
assert([1, 2, 3].select { |x| x % 2 == 1 } == [1, 3], "select")
assert([1, 2, 3].reject { |x| x % 2 == 1 } == [2], "reject")
assert([1, 2, 3].inject(0) { |sum, x| sum + x } == 6, "inject")
assert([1, 2, 3].map { |x| x * 3 } == [3, 6, 9], "map")
assert(["a", "b"].join("-") == "a-b", "join")

# Hashes with string, symbol and wide integer keys.
hash = { "a" => 1, b: 2, 1099511627776 => 3 }
assert(hash["a"] == 1, "string key")
assert(hash[:b] == 2, "symbol key")
assert(hash[1099511627776] == 3, "wide integer key")
assert(hash["missing"].nil?, "missing key")
hash["c"] = 4
assert(hash.length == 4, "hash insertion")
assert(hash.keys.length == 4, "hash keys")
assert(hash.values.length == 4, "hash values")
assert(hash.fetch("a") == 1, "fetch")
assert(hash.fetch("missing", 99) == 99, "fetch default")
hash.delete("c")
assert(!hash.has_key?("c"), "delete")

# Ranges.
assert((1..5).to_a == [1, 2, 3, 4, 5], "inclusive range")
assert((1...5).to_a == [1, 2, 3, 4], "exclusive range")
assert((1..5).include?(3), "range include")
assert((1..10).select { |x| x % 3 == 0 } == [3, 6, 9], "range select")

# Strings.
assert("hello world".split == ["hello", "world"], "split")
assert("a-b-c".tr("-", "_") == "a_b_c", "tr")
assert("pad".ljust(5, ".") == "pad..", "ljust")
assert("abc".upcase == "ABC", "upcase")
assert("ABC".downcase == "abc", "downcase")
assert("  x  ".strip == "x", "strip")
assert("abc"[1] == "b", "index")
assert("abc".chars == ["a", "b", "c"], "chars")
assert("abc".bytes.length == 3, "bytes")

if Object.const_defined?(:Set)
  set = Set.new([1, 2, 2, 3])
  assert(set.size == 3, "set dedup")
  set << 1
  assert(set.size == 3, "set idempotent add")
end

if [].respond_to?(:pack)
  assert([65, 66].pack("C*").unpack("C*") == [65, 66], "pack/unpack")
end
