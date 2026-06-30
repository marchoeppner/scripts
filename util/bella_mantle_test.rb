require 'matrix'
require 'benchmark'
require 'optparse'
require 'ostruct'

class MantelTest
  def self.run(matrix_a, matrix_b, permutations = 999, method = :pearson)
    raise "Matrices must be the same size" unless matrix_a.row_size == matrix_b.row_size
    
    vec_a = extract_lower_triangle(matrix_a)
    vec_b = extract_lower_triangle(matrix_b)
    
    observed_r = calculate_correlation(vec_a, vec_b, method)
    
    # Permutation test
    count_more_extreme = 0
    permutations.times do
      permuted_vec_b = vec_b.shuffle
      perm_r = calculate_correlation(vec_a, permuted_vec_b, method)
      count_more_extreme += 1 if perm_r.abs >= observed_r.abs
    end
    
    p_value = (count_more_extreme + 1.0) / (permutations + 1.0)
    
    { observed_r: observed_r, p_value: p_value }
  end

  def self.extract_lower_triangle(matrix)
    # Extract only strictly lower triangular elements
    (0...matrix.row_size).each_with_object([]) do |i, arr|
      (0...i).each do |j|
        arr << matrix[i, j]
      end
    end
  end

  def self.calculate_correlation(vec_a, vec_b, method)
    # Simple Pearson correlation
    mean_a = vec_a.sum.to_f / vec_a.size
    mean_b = vec_b.sum.to_f / vec_b.size
    
    numerator = vec_a.zip(vec_b).map { |a, b| (a - mean_a) * (b - mean_b) }.sum
    denominator = Math.sqrt(vec_a.map { |a| (a - mean_a)**2 }.sum * vec_b.map { |b| (b - mean_b)**2 }.sum)
    
    denominator.zero? ? 0.0 : numerator / denominator
  end
end

### Get the script arguments and open relevant files
options = OpenStruct.new()
opts = OptionParser.new()
opts.on("-b","--bella", "=BELLA","Bella file") {|argument| options.bella = argument }
opts.on("-c","--chewie", "=CHEWIE","Chewie file") {|argument| options.chewie = argument }
opts.on("-o","--outfile", "=OUTFILE","Output file") {|argument| options.outfile = argument }
opts.on("-h","--help","Display the usage information") {
    puts opts
    exit
}

opts.parse! 

matrix_bella = []
matrix_chewie = []

bella_lines = IO.readlines(options.bella)
header = bella_lines.shift

bella_lines.each do |line|
  elements = line.strip.split("\t")[1..-1].map{|e| e.to_f.round(0)}
  matrix_bella.append(elements)
end

chewie_lines = IO.readlines(options.chewie).sort
chewie_lines.each do |line|
  elements = line.strip.split(" ")[1..-1].map{|e| e.to_f.round(0)}
  matrix_chewie.append(elements)
end

# Example usage:
m1 = Matrix[[0, 1, 2], [1, 0, 3], [2, 3, 0]]
m2 = Matrix[[0, 1, 2], [1, 0, 3], [2, 3, 0]]

#m1 = Matrix[matrix_bella]
#m2 = Matrix[matrix_chewie]

puts MantelTest.run(m1, m2, 999)
# puts MantelTest.run(m1, m2, 999)