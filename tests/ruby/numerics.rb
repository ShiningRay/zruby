# Numeric edge cases and Math, executed through VM.evalWithOptions.

def assert(condition, message = "assertion failed")
  raise message unless condition
end

assert(1 + 2 == 3, "addition")
assert(2 ** 10 == 1024, "power")
assert(10.divmod(3) == [3, 1], "divmod")
assert(7 % 3 == 1, "modulo")
assert(-7 / 2 == -4, "floor division")
assert(3.0 / 2 == 1.5, "float division")

# Word-boxed integers and values outside the small inline range.
assert((1 << 62).to_s == "4611686018427387904", "shift beyond small fixnum")
assert(9223372036854775807 > 0, "max i64 literal")
assert(2 ** 100 > 0, "big integer power")
assert((1 << 62) + 1 - 1 == (1 << 62), "wide integer arithmetic")

# Floats and special values.
assert(0.1 + 0.2 - 0.3 < 1e-9, "float precision")
assert(1.0.round == 1, "round")
assert(2.5.to_i == 2, "to_i truncates")
assert(1e300 * 1e300 == Float::INFINITY, "positive infinity")
assert((-1.0 / 0.0) < 0, "negative infinity")
assert(Float::NAN.nan?, "nan")

# Math module.
assert(Math.sqrt(144.0) == 12.0, "sqrt")
assert(Math.sin(0) == 0.0, "sin")
assert(Math::PI > 3.14 && Math::PI < 3.15, "PI")
assert(Math.hypot(3, 4) == 5.0, "hypot")

# Bit operations.
assert((0b1010 & 0b0110) == 0b0010, "and")
assert((0b1010 | 0b0110) == 0b1110, "or")
assert((0b1010 ^ 0b0110) == 0b1100, "xor")
assert((~0) == -1, "invert")

# Conversions and formatting.
assert("42".to_i == 42, "string to_i")
assert("3.5".to_f == 3.5, "string to_f")
assert(255.to_s(16) == "ff", "to_s base")
assert(sprintf("%05.2f", 3.14159) == "03.14", "sprintf float")
assert(sprintf("%s=%d", "n", 42) == "n=42", "sprintf mixed")
