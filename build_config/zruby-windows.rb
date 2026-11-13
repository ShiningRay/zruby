# Windows/MinGW build profile for zruby.
# Only the static library and host mrbc are needed. Other bin tools include
# an interactive mirb/debugger that conflicts with MinGW's strndup headers.
MRuby::Build.new do |conf|
  conf.toolchain
  conf.gembox 'default'
  conf.gems.delete_if do |gem|
    gem.name.to_s.start_with?('mruby-bin-') && gem.name != 'mruby-bin-mrbc'
  end
end
