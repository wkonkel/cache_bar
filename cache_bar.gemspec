Gem::Specification.new do |s|
  s.name     = "cache_bar"
  s.version  = "0.0.1"
  s.date     = "2009-10-06"
  s.summary  = "A pure ruby memcached client."
  s.email    = "wkonkel@gmail.com"
  s.homepage = "http://github.com/wkonkel/cache_bar"
  s.description = "A pure ruby memcached client."
  s.has_rdoc = false
  s.authors  = ["Warren Konkel"]
  s.files    = Dir.glob('**/*') - Dir.glob('test/*.rb')
  s.test_files = Dir.glob('test/*.rb')
end