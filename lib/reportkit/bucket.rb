module Reportkit
  class Bucket
    attr_reader :attributes, :columns, :root

    def initialize(root)
      @root = root
      @attributes = []
      @columns = []
    end

    def compare_relation
      # At the moment, a bucket has only a single relation.
      # Columns are compatible iff their attributes have the same relation.
      # We can relax this later on.
      @relation ||= attributes.empty? ? nil : attributes.first.relation
    end
    
    def compatible_with?(attribute)
      attribute.relation.singular? or attribute.relation == compare_relation # TODO: should compare loosely (table aliases)
    end
    
    def singular?
      columns.all? {|c| c.arel_attributes.all? {|a| a.relation.singular?}}
    end
    
    def include?(column)
      (column.arel_attributes - attributes).empty?
    end
    
    def add(attribute, column)
      @attributes << attribute
      @columns << column
      self
    end

    def merge(other)
      bucket = Bucket.new(root)
      (attributes + other.attributes).zip(columns + other.columns).each {|a,c| bucket.add(a, c)}
      bucket
    end
    
    def projections
      [root[root.primary_key], *attributes].uniq
    end

    def arel
      arel = root
      original_attributes = attributes
      @attributes = attributes.map do |att|
        att, arel = add_attribute_to_relation(att, arel)
        att
      end
      original_attributes.zip(attributes, columns) do |origatt, newatt, col|
        col.map_attributes! do |att|
          att == origatt ? newatt : att
        end
      end
      arel = arel.group(root[root.primary_key]) if arel.join?
      arel.project(*projections)
    end

    private

    def add_attribute_to_relation(att, relation)
      return att, relation if att.relation == relation || att.relation == root
      return att, att.relation if relation == root
      relation_joins = relation.join_hash
      aliased = {}
      new_att_relation = att.relation.replace_joins(relation_joins, aliased)
      if aliaz = aliased[att.original_relation]
        att = att.bind(aliaz)
      end
      return att, new_att_relation.replace(root, relation)
    end

  end
end