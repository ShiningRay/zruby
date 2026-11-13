# mruby profile for zruby's no-boxing ABI test.
MRuby::Build.new do |conf|
  conf.toolchain
  conf.gembox 'stdlib'
  conf.gembox 'stdlib-ext'
  conf.gembox 'math'
  conf.gembox 'metaprog'
  conf.gem :core => 'mruby-bin-mrbc'
  conf.cc.defines << 'MRB_NO_BOXING'
  conf.cc.defines << 'MRB_INT64'
end
