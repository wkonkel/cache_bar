require 'test/unit'
require File.join(File.dirname(__FILE__), '../lib/cache_bar')

class CacheBarTest < Test::Unit::TestCase

  def test_server_no_port
    assert_get_set_delete(CacheBar.new(:servers => '0.0.0.0', :namespace => Time.now.to_f))
  end
  
  def test_server_with_port
    assert_get_set_delete(CacheBar.new(:servers => '0.0.0.0:11211', :namespace => Time.now.to_f))
  end
  
  def test_multiple_servers
    assert_get_set_delete(CacheBar.new(:servers => ['0.0.0.0', '0.0.0.0'], :namespace => Time.now.to_f))
  end
  
  def test_bogus_server
    client = CacheBar.new(:servers => '255.255.255.255', :namespace => Time.now.to_f)
    assert_raises(CacheBar::ConnectionError) { client.get('test') }
    assert_raises(CacheBar::ConnectionError) { client.set('test', 'test') }
    assert_raises(CacheBar::ConnectionError) { client.add('test', 'test') }
    assert_raises(CacheBar::ConnectionError) { client.delete('add') }
  end
  
  def test_simple_get_and_set_with_brackets
    with_default_cache do |cache|
      assert_nil cache['test']
      assert_equal 'this is a test', (cache['test'] = 'this is a test')
      assert_equal 'this is a test', cache['test']
    end
  end
  
  def test_encoding_and_marshaling
    with_default_cache do |cache| 
      assert_get_set_delete(cache, nil)
      assert_get_set_delete(cache, true)
      assert_get_set_delete(cache, false)
      assert_get_set_delete(cache, 5)
      assert_get_set_delete(cache, "5")
      assert_get_set_delete(cache, 'test string')
      assert_get_set_delete(cache, 'uʍop ǝpısdn ǝɹɐ ʇɐɥʇ sƃuıɥʇ')
      assert_get_set_delete(cache, [1,2,3,[4,5]])
      assert_get_set_delete(cache, { :a => 1, 'b' => 2 })
    end
  end
  
  def test_delete_missing_key
    with_default_cache do |cache|
      assert_raises(CacheBar::NotFound) { cache.delete('test') }
    end
  end
  
  def test_add_raises
    with_default_cache do |cache|
      assert_equal 'test string', cache.add('test', 'test string')
      assert_equal 'test string', cache.get('test')
      assert_raises(CacheBar::NotStored) { cache.add('test', 'test string') }
    end
  end
  
  def test_not_founds_raises
    with_default_cache do |cache| 
      assert_raises(CacheBar::NotFound) { cache.get('test') }
      assert_raises(CacheBar::NotFound) { cache.gets('test') }
    end      
  end

  def test_gets_and_cas
    with_default_cache do |cache|
      assert_equal 'test string', cache.add('test', 'test string')
      value, cas = cache.gets('test')
      assert 'test string', value
  
      assert_equal 'test string2', cache.set('test', 'test string2')
      value, cas2 = cache.gets('test')
      assert 'test string2', value
      
      assert cas2 > cas
      
      assert_raises(CacheBar::NotStored) { cache.cas('test', 'test string 3', cas) }
      assert_equal 'test string 3', cache.cas('test', 'test string 3', cas2)
    end
  end
  
  def test_append_and_prepend
    with_default_cache do |cache|
      cache.set('test', 'aaa')
      cache.append('test', 'bbb')
      cache.prepend('test', 'ccc')
      assert_equal 'cccaaabbb', cache.get('test')
    end
  end

  def test_replace
    with_default_cache do |cache|
      assert_raises(CacheBar::NotStored) { cache.replace('test', 'aaa') }
      assert_equal cache.set('test', 'bbb'), 'bbb'
      assert_equal cache.replace('test', 'ccc'), 'ccc'
      assert_equal cache.get('test', 'ccc'), 'ccc'
    end
  end
  
  def test_get_or_set
    with_default_cache do |cache|
      assert_equal 'test', cache.gos('test') { 'test' }
      assert_equal 'test', cache.get('test')
      cache.set('test', 'test2')
      assert_equal 'test2', cache.gos('test') { 'test' }
    end
  end

  def test_get_multi
    with_default_cache do |cache|
      assert_equal 'test1', cache.set('test1', 'test1')
      assert_equal 'test2', cache.set('test2', 'test2')
      results = cache.get_multi('test1', 'test2')
      assert_equal results['test1'], 'test1'
      assert_equal results['test2'], 'test2'
    end
  end

  def test_ttl
    with_default_cache do |cache|
      cache.set('test', 'test', :ttl => 1)
      assert_equal 'test', cache.get('test')
      sleep(1.1)
      assert_raises(CacheBar::NotFound) { cache.get('test') }
    end
  end
  
  def test_stats
    with_default_cache do |cache|
      assert cache.stats['0.0.0.0'][:curr_connections]
    end
  end

protected

  def assert_get_set_delete(cache, value='test string')
    assert_raises(CacheBar::NotFound) { cache.get('test') }
    assert_equal value, cache.set('test', value)
    assert_equal value, cache.get('test')
    assert_equal true, cache.delete('test')
    assert_raises(CacheBar::NotFound) { cache.get('test') }
  end

  def with_default_cache
    yield CacheBar.new(:servers => '0.0.0.0', :namespace => Time.now.to_f)
  end

end

