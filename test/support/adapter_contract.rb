# frozen_string_literal: true

# Shared contract that every Indexer Adapter backend must satisfy (FR-M0-04). The including test class must implement
# `#build_adapter(index)` and provide the fixture index (see `IndexHelpers`).
module AdapterContract
  ANIMAL = "FixtureProject::Animal"
  DOG = "FixtureProject::Dog"
  GREETABLE = "FixtureProject::Greetable"
  ATTRIBUTE_SHAPES = "FixtureProject::AttributeShapes"

  def adapter
    @adapter ||= build_adapter(index)
  end

  def index
    @index ||= build_fixture_index
  end

  def test_method_definitions_include_location_comments_and_metadata
    definition = adapter.method_definitions(ANIMAL, "speak").first

    refute_nil definition
    assert_equal "speak", definition.name
    assert_equal ANIMAL, definition.owner
    assert_equal :method, definition.kind
    assert_equal :public, definition.visibility
    assert_includes definition.comments, "@param suffix [String]"
    assert_includes definition.comments, "@return [String]"
    assert_operator definition.location.start_line, :>, 0
    assert_match(/animals\.rb/, definition.uri.to_s)
  end

  def test_method_definitions_resolve_inherited_methods
    definitions = adapter.method_definitions(DOG, "speak")

    assert_equal [ANIMAL], definitions.map(&:owner)
  end

  def test_method_definitions_find_singleton_methods
    definitions = adapter.method_definitions(DOG, "species", singleton: true)

    assert_equal ["species"], definitions.map(&:name)
    assert_equal ["#{DOG}::<Class:Dog>"], definitions.map(&:owner)
    assert_empty adapter.method_definitions(DOG, "species")
  end

  def test_method_definitions_expose_visibility
    definition = adapter.method_definitions(ANIMAL, "secret").first

    refute_nil definition
    assert_equal :private, definition.visibility
  end

  def test_method_definitions_expose_parameters
    definition = adapter.method_definitions(ANIMAL, "signature").first

    refute_nil definition
    assert_equal(
      %i[required optional rest keyword keyword_optional options block],
      definition.parameters.map(&:name)
    )
    assert_equal(
      %i[required optional rest keyword keyword_optional keyword_rest block],
      definition.parameters.map(&:kind)
    )
  end

  def test_method_definitions_without_parameters_return_an_empty_list
    definition = adapter.method_definitions(DOG, "species", singleton: true).first
    reader = adapter.attribute_definitions(ANIMAL, "name").first

    refute_nil definition
    assert_empty definition.parameters
    assert_empty reader.parameters
  end

  def test_attribute_writers_expose_a_value_parameter
    writer = adapter.attribute_definitions(ANIMAL, "age").find { |definition| definition.name == "age=" }

    refute_nil writer
    assert_equal [::RubyLsp::Yard::Indexer::Parameter.new(:value, :required)], writer.parameters
  end

  def test_method_definitions_never_raise_for_unknown_names
    assert_empty adapter.method_definitions("No::Such", "method")
    assert_empty adapter.method_definitions(ANIMAL, "nope")
  end

  def test_attribute_definitions_return_readers_and_writers
    readers = adapter.attribute_definitions(ANIMAL, "name")
    accessors = adapter.attribute_definitions(ANIMAL, "age")

    assert_equal ["name"], readers.map(&:name)
    assert_equal [:attribute], readers.map(&:kind)
    assert_includes readers.first.comments, "@return [String]"

    assert_equal ["age", "age="], accessors.map(&:name)
  end

  def test_attribute_definitions_never_raise_for_unknown_attributes
    assert_empty adapter.attribute_definitions(ANIMAL, "nope")
    assert_empty adapter.attribute_definitions("No::Such", "name")
  end

  def test_methods_and_attributes_with_the_same_name_coexist
    method = adapter.method_definitions(ATTRIBUTE_SHAPES, "timeout").first
    writer = adapter.method_definitions(ATTRIBUTE_SHAPES, "timeout=").first

    refute_nil method
    assert_equal :method, method.kind
    assert_empty method.parameters
    refute_nil writer
    assert_equal "timeout=", writer.name
    assert_equal :attribute, writer.kind
    assert_equal ["timeout="], adapter.attribute_definitions(ATTRIBUTE_SHAPES, "timeout").map(&:name)
  end

  def test_writer_lookups_require_a_writer_definition
    assert_empty adapter.method_definitions(ATTRIBUTE_SHAPES, "reader_only=")
    assert_empty adapter.methods_of(ATTRIBUTE_SHAPES, prefix: "reader_only=")
  end

  def test_writer_only_attributes_have_no_reader_lookup
    assert_empty adapter.method_definitions(ATTRIBUTE_SHAPES, "writer_only")
    writer = adapter.method_definitions(ATTRIBUTE_SHAPES, "writer_only=").first

    refute_nil writer
    assert_equal "writer_only=", writer.name
    assert_equal [::RubyLsp::Yard::Indexer::Parameter.new(:value, :required)], writer.parameters
  end

  def test_aliases_are_reported_as_method_aliases
    definition = adapter.method_definitions(ATTRIBUTE_SHAPES, "timed_out").first

    refute_nil definition
    assert_equal :method_alias, definition.kind
  end

  def test_constant_definitions_return_namespaces_and_constants_with_comments
    definitions = adapter.constant_definitions(ANIMAL)
    klass = definitions.find { |definition| definition.kind == :class }

    refute_nil klass
    assert_equal ANIMAL, klass.name
    assert_includes klass.comments, "@!method self.build"

    constant = adapter.constant_definitions("FixtureProject::DEFAULT_NAME").first
    assert_equal :constant, constant.kind
    assert_includes constant.comments, "@return [String]"

    mod = adapter.constant_definitions(GREETABLE).first
    assert_equal :module, mod.kind
  end

  def test_constant_definitions_never_raise_for_unknown_names
    assert_empty adapter.constant_definitions("No::Such")
  end

  def test_resolve_constant_uses_the_given_nesting
    assert_equal DOG, adapter.resolve_constant("Dog", ["FixtureProject"])
    assert_equal "FixtureProject::Nested::Thing", adapter.resolve_constant("Nested::Thing", ["FixtureProject"])
    assert_equal "FixtureProject::DEFAULT_NAME", adapter.resolve_constant("DEFAULT_NAME", ["FixtureProject"])
    assert_equal DOG, adapter.resolve_constant("::FixtureProject::Dog", [])
  end

  def test_resolve_constant_returns_nil_when_unresolvable
    assert_nil adapter.resolve_constant("Nope", ["FixtureProject"])
    assert_nil adapter.resolve_constant("Dog", [])
  end

  def test_ancestors_are_linearized
    assert_equal [DOG, ANIMAL, GREETABLE], adapter.ancestors(DOG)
    assert_equal [ANIMAL, GREETABLE], adapter.ancestors(ANIMAL)
  end

  def test_ancestors_never_raise_for_unknown_names
    assert_empty adapter.ancestors("No::Such")
  end

  def test_methods_of_filters_by_prefix_and_owner
    assert_includes adapter.methods_of(DOG, prefix: "bar").map(&:name), "bark"
    assert_empty adapter.methods_of(ANIMAL, prefix: "bar")
    assert_includes adapter.methods_of(DOG).map(&:name), "speak"
  end

  def test_methods_of_finds_singleton_methods
    assert_includes adapter.methods_of(DOG, prefix: "spec", singleton: true).map(&:name), "species"
    assert_empty adapter.methods_of(DOG, prefix: "spec")
  end

  def test_definitions_expose_full_location_and_file_name
    definition = adapter.method_definitions(ANIMAL, "speak").first

    refute_nil definition
    refute_nil definition.full_location
    assert_equal "animals.rb", definition.file_name
    assert_operator definition.full_location.end_line, :>=, definition.location.start_line
  end

  def test_completion_candidates_omit_comments_and_expose_display_data
    candidate = adapter.completion_candidates(DOG, prefix: "bar").find { |definition| definition.name == "bark" }

    refute_nil candidate
    assert_nil candidate.comments
    assert_equal DOG, candidate.owner
    assert_equal :public, candidate.visibility
    assert_equal "animals.rb", candidate.file_name
    refute_nil candidate.full_location
  end

  def test_completion_candidates_find_singleton_methods
    candidates = adapter.completion_candidates(DOG, prefix: "spec", singleton: true)

    assert_includes candidates.map(&:name), "species"
    assert_empty adapter.completion_candidates(DOG, prefix: "spec")
  end

  def test_constant_candidates_filter_by_prefix_and_nesting
    candidates = adapter.constant_candidates("Doc", ["FixtureProject"])

    document = candidates.find { |definition| definition.name == "FixtureProject::Documented" }
    refute_nil document
    assert_nil document.comments
  end

  def test_constant_candidates_include_partial_paths_and_enclosing_scopes
    assert_includes(
      adapter.constant_candidates("Nested::Thi", ["FixtureProject"]).map(&:name),
      "FixtureProject::Nested::Thing"
    )
    assert_includes(
      adapter.constant_candidates("DEFAULT", ["FixtureProject", "Documented"]).map(&:name),
      "FixtureProject::DEFAULT_NAME"
    )
  end

  def test_constant_candidates_never_raise_for_unknown_names
    assert_empty adapter.constant_candidates("Zzz", ["No::Such"])
  end

  def test_on_change_notifies_subscribers
    received = []
    adapter.subscribe { |uris| received.concat(uris) }
    uri = fixture_uri("project/lib/animals.rb")

    adapter.on_change([uri])

    assert_equal [uri], received
  end
end
