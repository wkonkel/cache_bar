require 'benchmark'

require File.join(File.dirname(__FILE__), '../lib/cache_bar')
c = CacheBar.new(:servers => '0.0.0.0')

5.times do 
  puts 'set: ' + Benchmark.realtime {
    10000.times do |i|
      c.set('test', 'testing 123')
    end
  }.to_s
end

5.times do 
  puts 'get: ' + Benchmark.realtime {
    10000.times do |i|
      c.get('test')
    end
  }.to_s
end
