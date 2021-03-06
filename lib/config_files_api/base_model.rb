module ConfigFilesApi
  # A base class for models. Represents a configuration file as an object
  # with domain-specific attributes/methods. For persistent storage,
  # use load and save,
  # Non-responsibilities: actual storage and parsing (both delegated).
  # There is no caching involved.
  class BaseModel
    # @param parser [.parse, .serialize] parser that can convert object to
    #   string and vice versa. It have to provide methods
    #   `string #serialize(object)` and `object #parse(string)`.
    #   For example see {ConfigFilesApi::AugeasParser}
    # @param file_path [String] expected path passed to file_handler
    # @param file_handler [.read, .write] object, that can read/write string.
    #   It have to provide methods `string read(string)` and
    #   `write(string, string)`. For example see {ConfigFilesApi::MemoryFile}
    def initialize(parser, file_path, file_handler: File)
      @file_handler = file_handler
      @parser = parser
      @file_path = file_path
      @loaded = false
    end

    def save(changes_only: false)
      merge_changes if changes_only
      @file_handler.write(@file_path, @parser.serialize(data))
    end

    def load
      self.data = @parser.parse(@file_handler.read(@file_path))
      @loaded = true
    end

    # powerfull method that sets any value in config. It try to be
    # smart to at first modify existing value, then replace commented out code
    # and if even that doesn't work, then append it at the end
    # @note prefer to use specialized methods of children
    def generic_set(key, value)
      modify(key, value) || uncomment(key, value) || add_new(key, value)
    end

    # powerfull method that gets unformatted any value in config.
    # @note prefer to use specialized methods of children
    def generic_get(key)
      data[key]
    end

    # rubocop:disable Style/TrivialAccessors
    # Returns if configuration was already loaded
    def loaded?
      @loaded
    end

  protected

    # generates accessors for trivial key-value attributes
    def self.attributes(attrs)
      attrs.each_pair do |key, value|
        define_method(key) do
          generic_get(value)
        end

        define_method(:"#{key.to_s}=") do |target|
          generic_set(value, target)
        end
      end
    end
    private_class_method :attributes

    attr_accessor :data

    def merge_changes
      new_data = data.dup
      read
      # TODO: recursive merge
      data.merge(new_data)
    end

    def modify(key, value)
      # if already set, just change value
      return false unless data[key]

      data[key] = value
      true
    end

    def uncomment(key, value)
      # Try to find if it is commented out, so we can replace line
      matcher = Matcher.new(
        collection:    "#comment",
        value_matcher: /(\s|^)#{key}\s*=/
      )
      return false unless  data.data.any?(&matcher)

      data.add(key, value, ReplacePlacer.new(matcher))
      true
    end

    def add_new(key, value)
      data.add(key, value)
    end
  end

  # Representing boolean value switcher in default grub configuration file.
  # Allows easy switching and questioning for boolean value, even if
  # represented by text in config file
  class BooleanValue
    def initialize(name, model, true_value: "true", false_value: "false")
      @name = name
      @model = model
      @true_value = true_value
      @false_value = false_value
    end

    def enable
      @model.generic_set(@name, @true_value)
    end

    def disable
      @model.generic_set(@name, @false_value)
    end

    def enabled?
      return nil unless data

      data == @true_value
    end

    def disabled?
      return nil unless data

      data != @true_value
    end

    def defined?
      !data.nil?
    end

    # sets boolean value, recommend to use for generic boolean setter.
    # for constants prefer to use enable/disable
    def value=(value)
      @model.generic_set(@name, value ? @true_value : @false_value)
    end

  private

    def data
      @model.generic_get(@name)
    end
  end
end
