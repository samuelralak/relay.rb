# frozen_string_literal: true

require "test_helper"

class BaseSerializerTest < ActiveSupport::TestCase
  class TestSerializer < BaseSerializer
    def serializable_hash
      { name: object[:name], value: object[:value] }
    end
  end

  # =========================================
  # Instance Methods
  # =========================================

  test "stores object and options" do
    serializer = TestSerializer.new({ name: "test" }, { extra: true })

    assert_equal({ name: "test" }, serializer.object)
    assert_equal({ extra: true }, serializer.options)
  end

  test "options defaults to empty hash" do
    serializer = TestSerializer.new({ name: "test" })
    assert_equal({}, serializer.options)
  end

  test "serialize returns hash for single object" do
    result = TestSerializer.new({ name: "test", value: 42 }).serialize
    assert_equal({ name: "test", value: 42 }, result)
  end

  test "serialize returns array for collections" do
    objects = [ { name: "a", value: 1 }, { name: "b", value: 2 } ]
    result = TestSerializer.new(objects).serialize

    assert_kind_of Array, result
    assert_equal 2, result.length
    assert_equal "a", result[0][:name]
  end

  test "serialize handles ActiveRecord::Relation" do
    result = Events::EventSerializer.new(Event.limit(2)).serialize

    assert_kind_of Array, result
    result.each { |item| assert item.key?(:id) }
  end

  test "to_json returns valid JSON string" do
    json = TestSerializer.new({ name: "test", value: 42 }).to_json
    parsed = JSON.parse(json)

    assert_equal "test", parsed["name"]
    assert_equal 42, parsed["value"]
  end

  # =========================================
  # Class Methods
  # =========================================

  test "self.serialize creates instance and serializes" do
    result = TestSerializer.serialize({ name: "test", value: 42 })
    assert_equal({ name: "test", value: 42 }, result)
  end

  test "self.serialize_collection maps over items" do
    result = TestSerializer.serialize_collection([ { name: "a", value: 1 }, { name: "b", value: 2 } ])

    assert_equal 2, result.length
    assert_equal "a", result[0][:name]
  end

  # =========================================
  # Abstract Method
  # =========================================

  test "serializable_hash raises NotImplementedError in base" do
    error = assert_raises(NotImplementedError) { BaseSerializer.new({}).serializable_hash }
    assert_includes error.message, "BaseSerializer"
  end

  # =========================================
  # Collection Detection
  # =========================================

  test "detects Array and Relation as collections" do
    assert_equal [], TestSerializer.new([]).serialize
    assert_kind_of Array, Events::EventSerializer.new(Event.where(kind: 1)).serialize
  end

  test "does not treat Hash as collection" do
    result = TestSerializer.new({ items: [ 1, 2, 3 ], name: "x", value: 1 }).serialize
    assert_kind_of Hash, result
  end
end
