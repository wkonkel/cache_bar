class CacheBar::CacheStore < ActiveSupport::Cache::Store
  def read(key, options = {})
    log("read", key, options)
    CacheBar.pool.get(key)
  end

  def write(key, options = {})
    log("write", key, options)
    CacheBar.pool.set(key, options.merge(:ttl => options.delete(:expires_in)))
  end
  
  def delete(key, options = {})
    log("delete", key, options)
    CacheBar.pool.delete(key)
  end
  
  def delete_matched(key, options = {})
    super
    raise "Not supported"
  end
  
  def exist?(key, options = {})
    log("exist?", key, options)
    !read(key, options).nil?
  end
  
  def increment(key, amount = 1)
    log("incrementing", key, amount)
    CacheBar.pool.incr(key, amount)
  end
  
  def decrement(key, amount = 1)
    log("decrementing", key, amount)
    CacheBar.pool.decr(key, amount)
  end
end