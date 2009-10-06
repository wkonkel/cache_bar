require 'cache_bar'
require 'cache_bar/cache_store'
require 'acts_as_cached'

config.cache_store = CacheBar::CacheStore.new
config.after_initialize do
  ActionView::Base.send(:acts_as_cached)
  ActionController::Base.send(:acts_as_cached)
  #ActiveRecord::Base.send(:acts_as_cached)
end