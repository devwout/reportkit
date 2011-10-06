module Reportkit
  class BucketList
    attr_reader :root, :buckets
    
    def initialize(root)
      @root = root
      @buckets = [Bucket.new(root)]
      @buckets.first.add(root[root.primary_key], Column.new(root.primary_key, root[root.primary_key]))
    end
    
    def main
      buckets.first
    end
    
    def other_buckets
      buckets[1..-1]
    end
    
    def bucketize(columns)
      columns.each do |column|
        column.arel_attributes.each do |att|
          if bucket = buckets.detect {|b| b.compatible_with? att}
            bucket.add(att, column)
          else
            buckets.push(Bucket.new(root).add(att, column))
          end
        end
      end
    end
    
    def consolidate(order_columns)
      if buckets.length > 1
        order_buckets = (order_columns || []).map {|col| buckets.detect {|b| b.include? col}}.uniq - [buckets.first]
        to_merge = case order_buckets.length
          when 0 then buckets[1]
          when 1 then order_buckets.first
          else return nil
          end
        buckets.delete(to_merge)
        buckets[0] = buckets[0].merge(to_merge)
      end
      true
    end
    
    def execute_and_join(data)
      projections = main.projections
      return projections if buckets.length < 2 or data.empty?
      hash = Hash[data.map {|row| [row[0].to_i, row]}]
      pks = hash.keys
      other_buckets.each do |bucket|
        bdata = bucket.arel.where(root[root.primary_key].in(pks)).call.array
        bdata.each do |row|
          if r = hash[row[0].to_i] and r.length == projections.length
            r.concat(row)
          end
        end
        projections.concat(bucket.projections)
      end
      projections
    end
  end
end