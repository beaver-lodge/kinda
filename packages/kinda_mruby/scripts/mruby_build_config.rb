MRuby::Build.new do |conf|
  toolchain = ENV.fetch('KINDA_MRUBY_TOOLCHAIN', 'gcc').to_sym
  conf.toolchain toolchain
  conf.cc.flags << '-fPIC' unless toolchain == :visualcpp
  conf.cc.defines << 'MRB_NO_DEFAULT_RO_DATA_P'
  conf.cc.defines << 'MRB_WORD_BOXING'
  conf.cc.defines << 'MRB_INT64'
  conf.gembox 'default'
end
