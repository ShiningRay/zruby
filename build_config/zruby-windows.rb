# Windows/MinGW build profile for zruby.
# Skip the stdlib-io gembox (io/dir/socket) and CLI tools; the binding only
# needs the core language, math, metaprogramming and host mrbc.
MRuby::Build.new do |conf|
  conf.toolchain
  conf.gembox 'stdlib'
  conf.gembox 'stdlib-ext'
  conf.gembox 'math'
  conf.gembox 'metaprog'
  conf.gem :core => 'mruby-bin-mrbc'
end
