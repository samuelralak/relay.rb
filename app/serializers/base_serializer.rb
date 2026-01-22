# frozen_string_literal: true

class BaseSerializer
  attr_reader :object, :options

  def initialize(object, options = {})
    @object = object
    @options = options
  end

  def serialize
    return serialize_collection if collection?

    serializable_hash
  end

  def to_json(*_args)
    serialize.to_json
  end

  class << self
    def serialize(object, options = {})
      new(object, options).serialize
    end

    def serialize_collection(collection, options = {})
      collection.map { |item| new(item, options).serializable_hash }
    end
  end

  def serializable_hash
    raise NotImplementedError, "#{self.class} must implement #serializable_hash"
  end

  private

  def collection?
    object.is_a?(Array) || object.is_a?(ActiveRecord::Relation)
  end

  def serialize_collection
    object.map { |item| self.class.new(item, options).serializable_hash }
  end
end
