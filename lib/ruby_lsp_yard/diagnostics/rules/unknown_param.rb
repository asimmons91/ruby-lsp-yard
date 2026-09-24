# frozen_string_literal: true

require "prism"

require_relative "base"

module RubyLsp
  module Yard
    module Diagnostics
      module Rules
        # YARD/UnknownParam (warning): a `@param` names a parameter the method does not have. FR-M1-05 keeps these
        # tags in the signature store precisely so this rule can report them. Destructured parameters
        # (`def m((a, b))`) contribute their inner names so valid tags are not reported.
        class UnknownParam < Base
          class << self
            def key
              "YARD/UnknownParam"
            end

            def default_severity
              :warning
            end

            def check(target, context)
              return [] unless target.documented? && target.def_node?

              names = parameter_names(target.node).map { |name| normalize_name(name) }
              target.raw_doc.params.filter_map do |tag|
                next if names.include?(normalize_name(tag.name))

                diagnostic(
                  "`@param #{tag.name}` does not match any parameter of `#{target.name}`",
                  range: context.tag_range(target, "@param #{tag.name}"),
                  target: target,
                  data: {param: tag.name}
                )
              end
            end

            private

            def parameter_names(def_node)
              parameters = def_node&.parameters
              return [] unless parameters

              names = []
              [
                *parameters.requireds,
                *parameters.optionals,
                parameters.rest,
                *parameters.posts,
                *parameters.keywords,
                parameters.keyword_rest,
                parameters.block
              ].each { |node| collect_name(node, names) }
              names
            end

            def collect_name(node, names)
              case node
              when nil
                nil
              when Prism::MultiTargetNode
                node.lefts.each { |child| collect_name(child, names) }
                collect_name(node.rest, names)
                node.rights.each { |child| collect_name(child, names) }
              else
                name = node.respond_to?(:name) ? node.name : nil
                names << name.to_s if name && !name.to_s.empty?
              end
            end
          end
        end
      end
    end
  end
end
