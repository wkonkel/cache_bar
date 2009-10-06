require 'test/unit'
require File.join(File.dirname(__FILE__), '../lib/cache_bar')
require File.join(File.dirname(__FILE__), '../lib/acts_as_cached')
require 'erb'

Object.send(:acts_as_cached)

class ActsAsCachedTest < Test::Unit::TestCase

  def setup
    CacheBar.singleton = CacheBar.new(:servers => '0.0.0.0', :namespace => Time.now.to_f)
  end

  def test_basic
    assert_raises(CacheBar::NotFound) { Integer.cache.get('a') }
    assert_equal Integer.cache.set('a', 'b'), 'b'
    assert_equal Integer.cache.get('a'), 'b'
    assert_raises(CacheBar::NotFound) { Hash.cache.get('a') }
  end

  # def test_erb
  #   assert_equal ERB.new("test<% cache('test') do %>test2<% end %>").result, 'testtest2'
  # end

end