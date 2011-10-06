module Reportkit
  class Report
    attr_reader :model, :columns, :filter, :order, :base_conditions, :options
    
    # Raised when sorting on multiple columns that cannot be fetched in a single query.
    class InvalidOrderError < StandardError ; end
    
    def initialize(model, columns, options)
      @model = model
      @columns = columns.map {|name| model.column_named(name, options)}
      @options = options
    end
    
    def filter=(arel)
      return unless arel
      unless arel.is_a? Arel::Relation
        raise TypeError, 'filter should be an arel relation'
      end
      @filter = arel
    end
    
    def base
      (filter || model.arel_table).where(base_conditions)
    end
    
    def base_conditions=(arel)
      return unless arel
      unless arel.is_a? Arel::Predicates::Predicate
        raise TypeError, 'base_conditions should be an arel predicate'
      end
      @base_conditions = arel
    end
    
    def order=(orderings)
      @order = orderings.map do |col, dir|
        col = col.to_sym
        if c = columns.detect {|column| column.name == col}
          [c, dir == :desc ? :desc : :asc]
        end
      end.compact
    end
    
    def limit_offset(limit, offset=0)
      return unless limit
      @limit = limit.to_i
      @offset = offset.to_i
    end
    
    def table
      @table ||= begin
        root = model.arel_table
        
        buckets = BucketList.new(root)
        buckets.bucketize(columns)
        buckets.consolidate((order || []).map {|col, dir| col}) or raise InvalidOrderError
        
        arel = buckets.main.arel
        if base.join?
          ids = base.project(root[model.primary_key]).call.array.flatten.uniq
          arel = arel.where(root[model.primary_key].in(ids))
          @count = ids.length
          return @table = Reportkit::Table.new([], columns) if ids.empty?
        else
          arel = arel.where(*base.wheres)
        end
        orderings = []
        if order
          orderings = order.map {|col, dir| col.sort_attributes.map {|att| att.send(dir)}}.flatten
          arel = arel.order(*orderings)
        end
        arel = arel.take(@limit) if @limit
        arel = arel.skip(@offset) if @offset
        arel = arel.group(*idx_group_attrs(root, orderings, root[model.primary_key])) if arel.join?
        data = arel.call.array
        @count ||= @offset.to_i + data.length unless @limit and data.length >= @limit.to_i
        
        projections = buckets.execute_and_join(data)
        
        data.map! {|row| columns.map {|col| col.value_for_row(row, projections)}}
        Reportkit::Table.new(data, columns)
      end
    end
    
    def count
      @count ||= base.project(model.arel_table[model.primary_key].count(true)).call.first.tuple.first.to_i
    end
    
    def to_ext
      cnames = table.columns.map {|c| c.name}
      {
        'version' => 1,
        'results' => count,
        'records' => table.map {|row| Hash[cnames.zip(row)]}
      }
    end
    
    private
    
    # Return the attributes of the shortest index that contains all columns in +orderings+.
    def idx_group_attrs(table, orderings, grouping)
      if orderings.empty? or orderings.any? {|o| o.relation != table} or orderings.map {|o| o.class}.uniq.length != 1
        [grouping]
      else
        order_class = orderings.first.class
        orderings = orderings.map {|o| o.attribute}
        idx = indexes_for_table(table).select {|atts| atts[0...orderings.length] == orderings}
        ((idx.min {|a, b| a.length <=> b.length} || []) + [grouping]).map {|a| order_class.new(a)}
      end
    end
    
    def indexes_for_table(table)
      (@@indexes_for_table ||= {})[table.name] ||= table.engine.indexes(table.name).map {|idx| idx.columns.map {|c| table[c]}}
    end
  end
end