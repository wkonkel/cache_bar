require 'benchmark'

require 'rubygems'
gem 'memcached'
require 'memcached'
c = Memcached.new('0.0.0.0')

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
