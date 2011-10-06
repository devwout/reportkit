module Reportkit
    
  class Table
    include Enumerable
    
    attr_reader :columns, :level
    
    def initialize(data, columns, level=0)
      @data = data
      @columns = columns
      @level = level
      raise 'data incompatible with columns' if data.first and data.first.length != columns.length
    end
    
    def each(&block)
      @data.each(&block)
    end
    
    def traverse(&block)
      block.call(self)
    end
    
    # Yield data, column for each cell in +row+ (Array)
    def each_with_column(row, &block)
      row.zip(columns).each(&block)
    end
    
    def aggregate(aggregate)
      aggregate.reduce(aggregate.map(self))
    end
    
    # Return a collection of groups/tables (reportables) that can be rendered.
    def to_collection
      [self]
    end
    
    def group?
      false
    end
    
    def kind
      'data'
    end
  end
  
  class Grouping
    attr_reader :columns, :attributes, :column, :aggregates
    
    def initialize(child, column, aggregates=[])
      @child = child
      @column = column
      @columns = child.columns - [column]
      @attributes = child.attributes
      @aggregates = aggregates
    end
    
    def group(data, cols=columns, level=0)
      cur = []
      curkey = nil
      groups = []
      data.each do |row|
        key = column.group_key_for_row(row, attributes)
        if key == curkey
          cur << row
        else
          groups << create_group(cur, cols, level) unless cur.empty?
          cur = [row]
          curkey = key
        end
      end
      # Add the last group
      groups << create_group(cur, cols, level) unless cur.empty?
      groups
    end
    
    private
    
    def create_group(data, cols, level)
      Group.new(
        column.format(column.value_for_row(data.first, attributes)),
        @child.group(data, cols, level+1),
        cols,
        level,
        aggregates)
    end

  end
  
  class ColumnDefinition
    attr_reader :name, :type, :args
    
    def initialize(name, *args)
      @name = name.to_sym
      @type = case args.first
        when Class then args.shift
        when Symbol then Columns.const_get(args.shift.to_s.camelize)
        else Column
        end
      @args = args
    end
    
    def new(options={})
      col = type.new(name, *args)
      col.options = options
      col
    end
  end
  
  class Column
    attr_reader :name, :arel_attributes
    attr_accessor :options
    
    def initialize(name, arel_attribute, *other_attributes)
      idx = 0
      @name = name.to_sym
      @arel_attributes = other_attributes.unshift(arel_attribute).map! do |a| 
        a && a.aggregation?? a.as("#{name}_#{idx+=1}") : a
      end.freeze
      @first_attribute = arel_attribute
    end
    
    alias :sort_attributes :arel_attributes
    
    def human_name
      @human_name ||= I18n.t("#{@first_attribute.relation.name.singularize}.#{name}", 
        :scope => [:activerecord, :attributes], 
        :default => [:"shared.#{name}", name.to_s])
    end
    
    def option(*path)
      path.inject(options) {|r,p| r && r[p]}
    end
    
    def map_attributes!(&block)
      @arel_attributes = @arel_attributes.map(&block)
    end
    
    def kind
      @kind ||= if self.class == Column
        @arel_attributes.first.class.name.demodulize.underscore
      else
        self.class.name.demodulize.underscore
      end
    end
    
    def value_for_row(row, attributes)
      @arel_attributes_index ||= @arel_attributes.map do |a| 
        [a, (attributes.index(a) or raise "Attribute not found: #{a.name}")]
      end
      value(*@arel_attributes_index.map {|a,i| a.type_cast(row[i])})
    end
    
    def group_key_for_row(row, attributes)
      # TODO: maybe add method group_attributes and take all casted values from these by default?
      value_for_row(row, attributes)
    end
    
    def value(*data)
      data.first
    end
    
    def format(value)
      value
    end
  end
  
  class Group
    include Enumerable
    
    attr_reader :name, :columns, :level, :aggregates
    
    def initialize(name, data, columns, level=0, aggregates=[])
      @name = name
      @data = data
      @columns = columns
      @level = level
      @aggregates = aggregates
      @aggregates_cache = {}
    end
    
    # Enumerate subgroups and tables.
    def each(&block)
      @data.each(&block)
    end
    
    # Traverse all subgroups and tables recursively.
    # Yields self, recursive subgroups & tables, summary.
    def traverse(&block)
      block.call(self)
      each {|data| data.traverse(&block)}
      block.call(summary)
    end
    
    def aggregate(aggregate)
      @aggregates_cache[aggregate] ||= aggregate.reduce(map {|d| d.aggregate(aggregate)})
    end
    
    def summary
      SummaryTable.new(self, columns, level)
    end
    
    def to_collection
      self
    end
    
    def group?
      true
    end
    
    def kind
      'group'
    end
  end
  
  class SummaryTable < Table
    def initialize(group, columns, level)
      row = columns.map do |col|
        if agg = group.aggregates.detect {|a| a.column == col}
          group.aggregate(agg)
        end
      end
      super([row], columns, level)
    end
    def kind
      'summary'
    end
  end
  
  class Aggregate
    attr_reader :column
    
    def initialize(column)
      @column = column
    end
    
    # Map the table to reducable values. Default implementation returns the column values.
    def map(table)
      @idx ||= table.columns.index(column)
      table.map {|row| row[@idx]} # Could maybe optimize by returning an Enumerable
    end
    
    # Aggregate mapped values into a single value.
    # The function needs to be idempotent, so reduce([reduce(vals)]) == reduce(vals)
    def reduce(values)
      raise NotImplementedError, 'subclass responsability'
    end
    
    class Sum < Aggregate
      def reduce(values)
        values.compact.reduce(:+)
      end
    end
    
    class Count < Aggregate
      def map(table)
        table.length
      end
      def reduce(counts)
        counts.reduce(:+)
      end
    end
    
    class Concat < Aggregate
      def reduce(values)
        values.compact.join(', ')
      end
    end
  end
end