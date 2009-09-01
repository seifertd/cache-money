module Cash
  module Accessor
    def self.included(a_module)
      a_module.module_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module ClassMethods
      def fetch(keys, options = {}, &block)
        #puts "IN FETCH, KEYS: #{keys.inspect}, OPTIONS: #{options.inspect}, BLOCK: #{block.inspect}"
        case keys
        when Array
          keys = keys.collect { |key| cache_key(key) }
          #puts "KEYS ARE ARRAY #{keys.inspect}"
          hits = repository.get_multi(keys)
          #puts "HITS: #{hits.keys.inspect}"
          if (missed_keys = keys - hits.keys).any?
            #puts "MISSED KEYS: #{missed_keys.inspect}"
            missed_values = block.call(missed_keys)
            #puts "MISSED VALUES: #{missed_values.inspect}"
            # Stuff the newly hit stuff into the cache? Dubious?
            key_to_value = missed_keys.zip(Array(missed_values)).to_hash
            key_to_value.each do |new_key, new_val|
              #puts "CALLING SET #{new_key.inspect} => #{new_val.inspect}"
              repository.set(new_key, new_val, options[:ttl] || 0, options[:raw])
            end
            hits.merge!(key_to_value)
          end
          hits
        else
          repository.get(cache_key(keys), options[:raw]) || (block ? block.call : nil)
        end
      end

      def get(keys, options = {}, &block)
        #puts "IN GET, KEYS: #{keys.inspect}, OPTIONS: #{options.inspect}"
        case keys
        when Array
          fetch(keys, options, &block)
        else
          fetch(keys, options) do
            if block_given?
              add(keys, result = yield(keys), options)
              result
            end
          end
        end
      end

      def add(key, value, options = {})
        if repository.add(cache_key(key), value, options[:ttl] || 0, options[:raw]) == "NOT_STORED\r\n"
          yield
        end
      end

      def set(key, value, options = {})
        repository.set(cache_key(key), value, options[:ttl] || 0, options[:raw])
      end

      def incr(key, delta = 1, ttl = 0)
        repository.incr(cache_key = cache_key(key), delta) || begin
          repository.add(cache_key, (result = yield).to_s, ttl, true) { repository.incr(cache_key) }
          result
        end
      end

      def decr(key, delta = 1, ttl = 0)
        repository.decr(cache_key = cache_key(key), delta) || begin
          repository.add(cache_key, (result = yield).to_s, ttl, true) { repository.decr(cache_key) }
          result
        end
      end

      def expire(key)
        repository.delete(cache_key(key))
      end

      def cache_key(key)
        "#{name}:#{cache_config.version}/#{key.to_s.gsub(' ', '+')}"
      end
    end

    module InstanceMethods
      def expire
        self.class.expire(id)
      end
    end
  end
end
