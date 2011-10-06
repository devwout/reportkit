require 'activerecord'

class ActiveRecord::Base
  class << self
    # Glue between Filterkit and Reportkit, to avoid creating type classes twice.
    class PropertyColumn < Reportkit::Column
      attr_reader :property
      
      MAPPING = {
        Arel::Attributes::Time => Reportkit::Columns::Time,
        Arel::Attributes::Date => Reportkit::Columns::Date,
        Arel::Attributes::Boolean => Reportkit::Columns::Boolean,
        Arel::Attributes::Decimal => Reportkit::Columns::Decimal,
        Arel::Attributes::Float => Reportkit::Columns::Decimal
      }
      
      def self.new(name, property)
        if type = MAPPING[property.type]
          type.new(name, property.attribute)
        else
          super
        end
      end

      def initialize(name, property)
        @property = property
        super(name, property.attribute)
      end

      def value(v)
        property.type.value(v)
      end

      # TODO: define custom group_key_for row for grouping efficiency?
    end
    
    def define_columns(&block)
      (@reportkit_column_definitions ||= []) << block
    end
    
    # name, [type], [relation], *arel_attributes
    # When +relation+ is given, all attributes are bound to the relation.
    #   column :phone_number, PhoneColumn, arel(:phonenumbers), Phonenumber[:prefix], Phonenumber[:number]
    def column(name, *args)
      if relation = args.detect {|arg| arg.is_a? Arel::Relation}
        args.delete(relation)
        args.map! {|arg| arg.is_a?(Arel::Attribute) ? relation[arg] : arg}
      end
      args.push(arel_table[name]) unless args.any? {|arg| arg.is_a? Arel::Attribute}
      report_columns[name.to_sym] = Reportkit::ColumnDefinition.new(name, *args.compact)
    end

    def report_columns
      @reportkit_columns ||= {}
    end

    def column_named(name, options={})
      @reportkit_column_definitions.shift.call until @reportkit_column_definitions.blank?
      (report_columns[name.to_sym] || default_column_named(name)).new(options)
    end

    def default_column_named(name)
      path = name.is_a?(Array) ? name : name.to_s.split('/')
      Reportkit::ColumnDefinition.new(name, PropertyColumn, Filterkit::PropertyPath.new(self, path))
    end
  end
end