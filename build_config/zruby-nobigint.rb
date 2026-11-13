# mruby profile for zruby's non-BigInt hash regression test.
MRuby::Build.new do |conf|
  conf.toolchain
  conf.gembox 'stdlib'
  conf.gembox 'stdlib-ext'
  conf.gembox 'metaprog'
  conf.gem :core => 'mruby-bin-mrbc'
end
