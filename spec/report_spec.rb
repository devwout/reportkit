require File.join(File.dirname(__FILE__), 'spec_helper')

describe Report do
  before(:all) do
    @p = %w[Jan Piet Joris Korneel Dieter].map {|n| Person.create!(:first_name => n)}
    @c = %w[BMW Mercedes Audi Volkswagen].map {|n| Company.create!(:name => n)}
    @q1 = Quote.create!(:company => @c.first, :contact => @p[0], :responsible => @p[1], :description => 'q1')
    @q2 = Quote.create!(:company => @c.first, :contact => @p[2], :responsible => @p[0], :description => 'q2')
    @q3 = Quote.create!(:company => @c.first, :contact => @p[3], :responsible => @p[2], :description => 'q3', :deleted_at => Time.now)
    @q4 = Quote.create!(:company => @c[2], :contact => @p[3], :responsible => @p[3], :description => 'q4')
    @c[0].people = [@p[0], @p[1]]
    @c[1].people = [@p[2]]
    @c[2].people = [@p[2], @p[3], @p[4]]
  end
  
  let(:rp) { Report.new(Quote, %w[id], {}) }
  
  it 'raises a TypeError when assigning a filter that is not an Arel::Relation' do
    lambda { rp.filter = 'test' }.should raise_error(TypeError)
    lambda { rp.filter = Quote.arel_table[:id].eq(1) }.should raise_error(TypeError)
    lambda { rp.filter = Quote.arel_table.where(Quote.arel_table[:id].eq(1)) }.should_not raise_error
  end
  
  it 'raises a TypeError when assigning base conditions that are not an arel Predicate' do
    lambda { rp.base_conditions = 'test' }.should raise_error(TypeError)
    lambda { rp.base_conditions = Quote.arel_table.where(Quote.arel_table[:id].eq(1)) }.should raise_error(TypeError)
    lambda { rp.base_conditions = Quote.arel_table[:id].eq(1) }.should_not raise_error
  end
  
  it 'creates a table with the given columns' do
    r = Report.new(Quote, %w[id description], {})
    r.count.should == 4
    r.table.to_a.should == [[@q1.id, 'q1'], [@q2.id, 'q2'], [@q3.id, 'q3'], [@q4.id, 'q4']]
  end
  
  it 'uses a limit when set, but count everything' do
    rp.limit_offset(1)
    rp.count.should == 4
    rp.table.to_a.should == [[@q1.id]]
  end
  
  it 'uses a limit and an offset when set, but count everything' do
    rp.limit_offset(2, 1)
    rp.count.should == 4
    rp.table.to_a.should == [[@q2.id], [@q3.id]]
  end
  
  it 'only includes rows in the table that satisfy the base conditions' do
    r = Report.new(Quote, %w[id], {})
    r.base_conditions = Quote.arel_table[:deleted_at].eq(nil)
    r.count.should == 3
    r.table.to_a.should == [[@q1.id], [@q2.id], [@q4.id]]
  end
  
  it 'only includes rows in the table that satisfy the filter' do
    r = Report.new(Quote, %w[id], {})
    r.filter = Quote.arel_table.where(Quote.arel_table[:contact_id].eq(@p[3].id))
    r.count.should == 2
    r.table.to_a.should == [[@q3.id], [@q4.id]]
  end
  
  it 'only includes rows in the table that satisfy both base conditions and filter' do
    r = Report.new(Quote, %w[id], {})
    r.base_conditions = Quote.arel_table[:deleted_at].eq(nil)
    r.filter = Quote.arel_table.where(Quote.arel_table[:contact_id].eq(@p[3].id))
    r.count.should == 1
    r.table.to_a.should == [[@q4.id]]
  end
  
  it 'filters rows on columns from related tables' do
    r = Report.new(Quote, %w[id], {})
    r.filter = Quote.arel(:contact).where(Person.arel_table[:first_name].eq('Korneel'))
    r.count.should == 2
    r.table.to_a.should == [[@q3.id], [@q4.id]]
  end
  
  it 'creates a table with related columns' do
    r = Report.new(Quote, %w[id responsible/first_name], {})
    r.count.should == 4
    r.table.to_a.should == [[@q1.id, 'Piet'], [@q2.id, 'Jan'], [@q3.id, 'Joris'], [@q4.id, 'Korneel']]
  end
  
  it 'creates a table with different related columns coming from the same sql table' do
    r = Report.new(Quote, %w[id responsible/first_name contact/first_name], {})
    r.count.should == 4
    r.table.to_a.should == [[@q1.id, 'Piet', 'Jan'], [@q2.id, 'Jan', 'Joris'], [@q3.id, 'Joris', 'Korneel'], [@q4.id, 'Korneel', 'Korneel']]
  end
  
  it 'orders the results on the given orderings, ascending by default' do
    r = Report.new(Quote, %w[id responsible/first_name], {})
    r.order = ['responsible/first_name']
    r.count.should == 4
    r.table.to_a.should == [[@q2.id, "Jan"], [@q3.id, "Joris"], [@q4.id, "Korneel"], [@q1.id, "Piet"]]
  end
  
  it 'orders the results descending when asked' do
    r = Report.new(Quote, %w[id responsible/first_name], {})
    r.order = [['responsible/first_name', :desc]]
    r.count.should == 4
    r.table.to_a.should == [[@q1.id, "Piet"], [@q4.id, "Korneel"], [@q3.id, "Joris"], [@q2.id, "Jan"]]
  end
  
  it 'orders the results on multiple columns' do
    r = Report.new(Quote, %w[id company/name responsible/first_name], {})
    r.order = [['company/name'], ['responsible/first_name', :desc]]
    r.count.should == 4
    r.table.to_a.should == [[@q4.id, "Audi", "Korneel"], [@q1.id, "BMW", "Piet"], [@q3.id, "BMW", "Joris"], [@q2.id, "BMW", "Jan"]]
  end
  
  # TODO: also include the sort columns and map their sort_attributes
  xit 'joins in related columns for ordering that are not in the result set' do
    r = Report.new(Quote, %w[id], {})
    r.order = [['company/name']]
    r.count.should == 4
    r.table.to_a.should == [[@q4.id], [@q1.id], [@q2.id], [@q3.id]]
  end
  
  it 'allows aggregates as column attributes' do
    r = Report.new(Company, %w[id people_count], {})
    r.count.should == 4
    r.table.to_a.should == [[1, 2], [2, 1], [3, 3], [4, 0]]
  end
  
  it 'allows sorting on aggregate columns' do
    r = Report.new(Company, %w[id people_count], {})
    r.order = [['people_count', :desc]]
    r.count.should == 4
    r.table.to_a.should == [[3, 3], [1, 2], [2, 1], [4, 0]]
  end
  
  it 'allows multiple aggregates on the same column' do
    r = Report.new(Company, %w[id people_count people_sum people/id], {})
    r.count.should == 4
    query_count do
      r.table.to_a.should == [[1, 2, 3, 1], [2, 1, 3, 3], [3, 3, 12, 3], [4, 0, nil, nil]]
    end.should == 2 # TODO: should == 1
  end
  
  it 'separates incompatible aggregates into multiple queries' do
    r = Report.new(Company, %w[name people_count quote_count], {})
    r.count.should == 4
    r.table.to_a.should == [["BMW", 2.0, 3.0], ["Mercedes", 1.0, 0.0], ["Audi", 3.0, 1.0], ["Volkswagen", 0.0, 0.0]]
  end
  
  it 'allows sorting on a separated aggregate' do
    r = Report.new(Company, %w[name people_count quote_count], {})
    r.order = ['people_count']
    r.table.to_a.should == [["Volkswagen", 0.0, 0.0], ["Mercedes", 1.0, 0.0], ["BMW", 2.0, 3.0], ["Audi", 3.0, 1.0]]
    r = Report.new(Company, %w[name people_count quote_count], {})
    r.order = [['quote_count', :desc]]
    r.table.to_a.should == [["BMW", 2.0, 3.0], ["Audi", 3.0, 1.0], ["Mercedes", 1.0, 0.0], ["Volkswagen", 0.0, 0.0]]
  end
  
  it 'allows sorting on a combination of a separated aggregate and another column' do
    r = Report.new(Company, %w[name people_count quote_count], {})
    r.order = [['quote_count', :desc], ['name', :desc]]
    query_count do
      r.table.to_a.should == [["BMW", 2.0, 3.0], ["Audi", 3.0, 1.0], ["Volkswagen", 0.0, 0.0], ["Mercedes", 1.0, 0.0]]
    end.should == 2
  end
  
  it 'raises an error when sorting on two aggregates that are fetched in separate queries' do
    r = Report.new(Company, %w[name people_count quote_count], {})
    r.order = [['quote_count'], ['people_count']]
    lambda { r.table }.should raise_error(Reportkit::Report::InvalidOrderError)
  end
  
  it 'allows joining the same table with an alias in the column definition' do
    r = Report.new(Company, %w[id related_count], {})
    r.table.to_a.should == [[1, 1], [2, 2], [3, 2], [4, 0]]
  end
  
  it 'allows getting aggregates from multiple tables without including a column of the base table' do
    r = Report.new(Company, %w[people_count quote_count], {})
    query_count do
      r.table.to_a.should == [[2.0, 3.0], [1.0, 0.0], [3.0, 1.0], [0.0, 0.0]]
    end.should == 2
  end
  
  it 'allows sorting on a separated aggregate without including a column of the base table' do
    r = Report.new(Company, %w[people_count quote_count], {})
    r.order = [['quote_count', :desc]]
    query_count do
      r.table.to_a.should == [[2.0, 3.0], [3.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    end.should == 2
  end
  
  # spec doesn't work as expected
  # it 'does not include joins twice with conditions that are bound to different but equal relations' do
  #   join = Relationship.arel.outer_join(Person.arel).on(Relationship.arel[:person_id].eq(Person.arel[:id]))
  #   Company.column :difficult1, Company.arel.outer_join(join).on(join[:company_id].eq(Company.arel[:id]))[Person.arel[:id]]
  #   Company.column :difficult2, Company.arel.outer_join(join).on(Relationship.arel[:company_id].eq(Company.arel[:id]))[Person.arel[:id]]
  #   r = Report.new(Company, %w[difficult1 difficult2], {})
  #   query_count do
  #     lambda { r.table.to_a }.should_not raise_error
  #   end.should == 1
  # end
  
  # PERFORMANCE SPECS
  
  it 'caches the count' do
    r = Report.new(Company, %w[id], {})
    query_count do
      2.times { r.count.should == 4 }
    end.should == 1
  end
  
  it 'caches the table' do
    r = Report.new(Company, %w[id], {})
    query_count do
      2.times { r.table }
    end.should == 1
  end
  
  it 'derives the count when all rows are selected' do
    r = Report.new(Company, %w[id], {})
    query_count { r.table }.should == 1
    query_count { r.count.should == 4 }.should == 0
  end
  
  it 'derives the count when all rows are selected with filter and base conditions' do
    r = Report.new(Quote, %w[id], {})
    r.base_conditions = Quote.arel_table[:deleted_at].eq(nil)
    r.filter = Quote.arel_table.where(Quote.arel_table[:contact_id].eq(@p[3].id))
    query_count { r.table }.should == 1
    query_count { r.count.should == 1 }.should == 0
  end
  
  it 'derives the count when a (join) filter executed first, even when a limit is in effect' do
    r = Report.new(Company, %w[id], {})
    r.filter = Company.arel(:quotes).where(Quote.arel_table[:deleted_at].eq(nil))
    r.limit_offset(1)
    query_count { r.table }.should == 2
    query_count { r.count.should == 4 }.should == 0
  end
  
  it 'does not perform the extra queries when there are no results in the first query' do
    r = Report.new(Company, %w[id people_count quote_count], {})
    r.base_conditions = Company.arel_table[:id].eq(nil)
    query_count { r.table }.should == 1
  end
  
  it 'does not perform the main query when the filter returns no results' do
    r = Report.new(Company, %[id], {})
    r.filter = Company.arel(:quotes).where(Quote.arel_table[:deleted_at].eq(-1))
    query_count do
      2.times { r.table.to_a.should == [] }
      r.count.should == 0
    end.should == 1
  end
  
  it 'optimizes GROUP BY statements iff an index exists for the sort attributes' do
    r = Report.new(Company, %w[id name relationships/id], {})
    r.order = [['name']]
    query_count { r.table }.should == 1
    @queries.last.should include("GROUP BY  `companies`.`name` ASC, `companies`.`alpha` ASC, `companies`.`id` ASC ORDER BY  `companies`.`name` ASC")
    r = Report.new(Company, %w[id name relationships/id], {})
    r.order = [['name', :desc]]
    query_count { r.table }.should == 1
    @queries.last.should include("GROUP BY  `companies`.`name` DESC, `companies`.`alpha` DESC, `companies`.`id` DESC ORDER BY  `companies`.`name` DESC")
    r = Report.new(Company, %w[id name relationships/id updated_at], {})
    r.order = [['updated_at']]
    query_count { r.table }.should == 1
    @queries.last.should include("GROUP BY  `companies`.`id` ASC ORDER BY  `companies`.`updated_at` ASC")
  end
    
  def query_count
    cnt = 0
    @queries = queries = []
    k = ActiveRecord::ConnectionAdapters::MysqlAdapter
    k.send(:alias_method, :orig_select_rows, :select_rows)
    begin
      k.send(:define_method, :select_rows) do |*args|
        cnt += 1
        queries << args.first
        send(:orig_select_rows, *args)
      end
      yield
      cnt
    ensure
      k.send(:alias_method, :select_rows, :orig_select_rows)
    end
  end
  
end