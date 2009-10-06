Object.class_eval do
  def self.acts_as_cached(options={})
    self.class_inheritable_hash :acts_as_cached_options
    self.acts_as_cached_options = options

    class_eval do
      def cache(*params, &block)
        params.push({}) unless params.last.is_a?(Hash)
        params.last.merge!(:erb => self) if defined?(ActionView::Base) && self.is_a?(ActionView::Base)
        self.class.cache(*params, &block)
      end
      
      def self.cache(key=nil, options={}, &block)
        proxy_object = CacheBar.pool.with_options(:namespace => self.name)
        if key && block
          begin
            value = proxy_object.get(key, options)
          rescue CacheBar::NotFound
            value = options[:erb] ? options[:erb].capture(&block) : block.call
            proxy_object.set(key, value, options)
          end
          
          options[:erb] ? options[:erb].concat(value) && nil : value
        else
          proxy_object
        end
      end
      
      # def self.method_missing_with_cache_bar(method, *params, &block)
      #   # find
      # end
      # alias_method_chain :method_missing, :cache_bar
    end
  end
end

# hooks into rails
ActionView::Base.send(:acts_as_cached)
ActionController::Base.send(:acts_as_cached)
