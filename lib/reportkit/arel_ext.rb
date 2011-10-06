module Arel
  module Recursion::BaseCase
    def join_hash(*) {} end
    def replace_joins(*) self end
    def singular? ; true ; end
  end
  
  class Join
    def join_hash(hash={})
      relation1.join_hash(hash)
      (hash[relation2.name] ||= []) << self
      hash
    end
    
    def replace_joins(join_hash, aliased={})
      relation1 = self.relation1.replace_joins(join_hash, aliased)
      aliased_predicates = predicates.map {|p| aliased.inject(p) {|result, (orig, replace)| result.replace(orig, replace)}}
      if other_joins = join_hash[relation2.name]
        if other_join = other_joins.find {|j| j.predicates.to_sql == aliased_predicates.map {|p| p.replace(relation2, j.relation2)}.to_sql}
          aliased[relation2] = other_join.relation2
          relation1
        elsif relation2.is_a? Arel::Alias
          self.class.new(relation1, relation2, *aliased_predicates)
        else
          aliaz = relation2.alias
          aliased[relation2] = aliaz
          self.class.new(relation1, aliaz, *aliased_predicates.map {|p| p.replace(relation2, aliaz)})
        end
      else
        self.class.new(relation1, relation2, *aliased_predicates)
      end
    end
    
    def singular?
      @singular ||= relation1.singular? and predicates_singular?
    end
    
    private
    
    def predicates_singular?
      attributes = predicates.map {|p| p.join_attributes_for(relation2).map {|a| a.name.to_s}}.flatten.to_set
      indexes_for_table(relation2).any? {|i| i.subset? attributes}
    end
    
    def indexes_for_table(table)
      # TODO: indexed columns should be NOT NULL.
      # TODO: Table#primary_key only works when the key is singular. Maybe in the future, fetch the indexes ourselves?
      # TODO: share this cache with Report cache, in a Singleton?
      (@@indexes_for_table ||= {})[table.name] ||= 
        table.engine.indexes(table.name).select {|i| i.unique}.map {|i| i.columns.to_set}.push([table.primary_key].to_set)
    end
  end
  
  class Compound
    delegate :join_hash, :singular?, :to => :relation
  end
  
  # TODO: maybe take a hash mapping as an argument for replace, so we can replace everything at once?
  module Predicates
    class Predicate
      def replace_operand(operand, old_relation, new_relation)
        if operand.class.name =~ /^Arel\:\:/
          operand.replace(old_relation, new_relation)
        else
          operand
        end
      end
      
      def join_attributes_for(relation)
        []
      end
    end
    class Polyadic
      def replace(old_relation, new_relation)
        self.class.new(predicates.map {|p| p.replace(old_relation, new_relation)})
      end
    end
    class Unary
      def replace(old_relation, new_relation)
        self.class.new(replace_operand(operand, old_relation, new_relation))
      end
    end
    class Binary
      def replace(old_relation, new_relation)
        self.class.new(
          replace_operand(operand1, old_relation, new_relation), 
          replace_operand(operand2, old_relation, new_relation))
      end
    end
    class And
      def join_attributes_for(relation)
        operand1.join_attributes_for(relation) + operand2.join_attributes_for(relation)
      end
    end
    class Equality
      def join_attributes_for(relation)
        attributes.select {|a| relation[a]}
      end
    end
  end
  
  class Attribute
    def replace(old_relation, new_relation)
      if original_relation == old_relation # TODO: what about lexical aliases?
        bind(new_relation)
      else
        self
      end
    end
    
    # Patched compare function for attribute not to take the ancestor into account.
    # The ancestor of an attribute does not matter, what matters is the relation
    # that will be used to convert it to sql and scope it.
    def ==(other)
      Attribute === other && 
      !(Expression === other) &&
      relation == other.relation && 
      name == other.name && 
      self.alias == other.alias && 
      original_relation == other.original_relation
    end
    
    # Patched type_cast because compare function changed. Use equal? instead of == for comparison.
    def type_cast(value)
      if root.equal?(self)
        raise NotImplementedError, "#type_cast should be implemented in a subclass."
      else
        root.type_cast(value)
      end
    end
    
    # Bugfix: unaliased attributes should preferably bind to unaliased relationships.
    # We compare attribute matches in how much their history differs now, instead of
    # how much history they have in common.
    def /(other)
      other ? (history & other.history).length - (history | other.history).length : 0
    end
  end
  
  class Header
    # Backwards compatible arel optimization. A lot less elegant, but reduces memory allocation significantly.
    # Arel used select { ... }.max, which requires a new array to be allocated each time
    def find_by_attribute(attr)
      max = nil
      each do |a|
        if !a.is_a?(Value) && a.root == attr.root
          if max.nil? or (a.original_attribute / attr) > (max.original_attribute / attr)
            max = a
          end
        end
      end
      max
    end
  end
  
  class Expression
    delegate :original_relation, :to => :attribute
    
    def ==(other)
      self.class === other && attribute == other.attribute && self.alias == other.alias
    end
  end
  
  class Sql::Christener
    # Arel BUGFIX: Consistent naming for Alias objects.
    #  Since formatters are not passed around everywhere, the same christener
    #  is not used for the entire query. We already have object_id that is unique however...
    def name_for(relation)
      name = relation.table_alias || relation.name
      relation.is_a?(Alias) ? "#{name}_#{relation.object_id}" : name
    end
  end
  
  class Sql::GroupClause
    def ordering(ordering)
      "#{attribute(ordering.attribute)} #{ordering.direction_sql}"
    end
  end
  
  class Sql::OrderClause
    # Patch to allow ordering on aggregations.
    def ordering(ordering)
      if ordering.attribute.aggregation?
        # TODO: ordering on a GROUP_CONCAT column is a fail, the column values themselves are in random order.
        #   Need an order by clause in the GROUP_CONCAT function itself, the only way to do it right.
        "#{ordering.attribute.alias || (ordering.attribute.function_sql.to_s.downcase+'_id')} #{ordering.direction_sql}"
      else
        # Default impementation in arel
        "#{quote_table_name(name_for(ordering.attribute.original_relation))}.#{quote_column_name(ordering.attribute.name)} #{ordering.direction_sql}"
      end
    end
  end
  
  class Sql::SelectClause
    def infix_operation(operation)
      # operator.attributes.map {|att| att.to_sql(self)}.join(operator.operator_name) +
      '((' + operation.attribute.to_sql(self) + ') ' + operation.operator_name + ' (' + operation.attribute2.to_sql(self) + '))' +
      (operation.alias ? " AS #{quote_column_name(operation.alias)}" : '')
    end
    
    def polyadic_expression(expression)
      "#{expression.function_sql}(#{([expression.attribute].concat(expression.expressions)).map {|x| x.to_sql(self)}.join(',')})" +
      (expression.alias ? "AS #{quote_column_name(expression.alias)}" : "")
    end
    
    # Patched so that expressions without an alias do not get "AS functionname_id" appended.
    # Needed to use the result of the expression afterwards, like sum(total_price) - sum(amount)
    def expression(expression)
      if expression.function_sql == "DISTINCT"
        "#{expression.function_sql} #{expression.attribute.to_sql(self)}" +
        (expression.alias ? " AS #{quote_column_name(expression.alias)}" : '')
      else
        "#{expression.function_sql}(#{expression.attribute.to_sql(self)})" +
        (expression.alias ? " AS #{quote_column_name(expression.alias)}" : "")
      end
    end
    
    def group_concat(expression)
      if expression.ordering
        "#{expression.function_sql}(#{expression.attribute.to_sql(self)} ORDER BY #{expression.ordering.to_sql(Sql::OrderClause.new(expression.relation))})"
      else
        "#{expression.function_sql}(#{expression.attribute.to_sql(self)})"
      end + (expression.alias ? " AS #{quote_column_name(expression.alias)}" : '')
    end
    
    def value(value)
      value.to_sql(self)
    end
    
    def scalar(value)
      quote(value)
    end
  end
  
  # Extra aggregate functions.
  class GroupConcat < Expression
    attr_reader :ordering
    
    def initialize(attribute, aliaz=nil, ancestor=nil, ordering=nil)
      super(attribute, aliaz, ancestor)
      @ordering = ordering
      @ordering = @ordering.asc if @ordering and not @ordering.is_a?(Ordering)
    end
    
    def bind(new_relation)
      new_relation == relation ? self : self.class.new(attribute.bind(new_relation), @alias, self, @ordering)
    end
    
    def as(aliaz)
      self.class.new(attribute, aliaz, self, ordering)
    end
    
    def to_sql(formatter = Sql::SelectClause.new(relation))
      formatter.group_concat(self)
    end
    
    def function_sql ; 'GROUP_CONCAT' ; end
  end
  
  class PolyadicExpression < Expression
    attr_reader :expressions
    
    def initialize(attribute, aliaz=nil, ancestor=nil, *expressions)
      super(attribute, aliaz, ancestor)
      @expressions = expressions
    end
    
    def bind(new_relation)
      new_relation == relation ? self : self.class.new(attribute.bind(new_relation), @alias, self, *@expressions.map {|e| e.bind(new_relation)})
    end
    
    def as(aliaz)
      self.class.new(attribute, aliaz, self, *@expressions)
    end
    
    def to_sql(formatter = Sql::SelectClause.new(relation))
      formatter.polyadic_expression(self)
    end
    
    def function_sql ; raise NotImplementedError, 'subclass responsibility' ; end
  end
  
  class Concat < PolyadicExpression
    def function_sql ; 'CONCAT' ; end
  end
  
  class Coalesce < PolyadicExpression
    def function_sql ; 'COALESCE' ; end
  end
  
  class Timediff < PolyadicExpression
    def function_sql ; 'TIMEDIFF' ; end
  end
  
  class TimeToSec < Expression
    def function_sql ; 'TIME_TO_SEC' ; end
  end
  
  class InfixOperation < Expression
    attr_reader :attribute2
    
    def initialize(attribute, aliaz=nil, ancestor=nil, attribute2=nil)
      @attribute2 = attribute2
      raise 'attribute2 cannot be nil' unless @attribute2
      super(attribute, aliaz, ancestor)
    end
    
    def bind(new_relation)
      # TODO: should bind attribute2 when appropriate (when aliasing the original relation)
      new_relation == relation ? self : self.class.new(attribute.bind(new_relation), @alias, self, attribute2)
    end
    
    def as(aliaz)
      self.class.new(attribute, aliaz, self, attribute2)
    end
    
    def to_sql(formatter = Sql::SelectClause.new(relation))
      formatter.infix_operation self
    end
  end
  
  class Product < InfixOperation
    def operator_name ; '*' ; end
  end
  
  class Division < InfixOperation
    def operator_name ; '/' ; end
  end
  
  class Addition < InfixOperation
    def operator_name ; '+' ; end
  end
  
  class Substraction < InfixOperation
    def operator_name ; '-' ; end
  end
  
  class Attribute
    module Expressions
      def group_concat(distinct = false, order = nil)
        distinct ? Distinct.new(self).group_concat(false, order) : GroupConcat.new(self, nil, nil, order)
      end
      
      def concat(*expressions)
        Concat.new(self, nil, nil, *expressions)
      end
      
      def coalesce(*expressions)
        Coalesce.new(self, nil, nil, *expressions)
      end
      
      def timediff(attribute)
        Timediff.new(self, nil, nil, attribute)
      end
      
      def time_to_sec
        TimeToSec.new(self, nil, nil)
      end
      
      def *(attribute)
        Product.new(self, nil, nil, attribute)
      end
      
      def div(attribute) # The / operator is already in use for attributes.
        Division.new(self, nil, nil, attribute)
      end
      
      def +(attribute)
        Addition.new(self, nil, nil, attribute)
      end
      
      def -(attribute)
        Substraction.new(self, nil, nil, attribute)
      end
    end
  end
  
  class Value
    include Attribute::Expressions
    
    alias :original_relation :relation
  end
  
  class Expression
    def type_cast(value)
      value # Temporary. How to know the type of the returned value of an expression? Mostly numerics...
    end
  end
end