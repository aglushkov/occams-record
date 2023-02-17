require 'bundler/setup'
require 'rake/testtask'

desc "Run all benchmarks"
task :bench do
  Rake::Task["bench:speed"].invoke
  Rake::Task["bench:memory"].invoke
end

namespace :bench do
  desc "Run performance benchmarks"
  task :speed => :environment do
    puts "OccamsRecord Speed Test\n\n"
    Benchmarks.each do |benchmark|
      puts benchmark.speed
    end
  end

  desc "Run memory benchmarks"
  task :memory => :environment do
    puts "OccamsRecord Memory Test\n\n"
    Benchmarks.each do |benchmark|
      puts benchmark.memory
    end
  end

  task :environment do
    $:.unshift File.join(File.dirname(__FILE__), "lib")
    require 'occams-record'
    require_relative './bench/seeds'
    require_relative './bench/marks'
  end
end

Rake::TestTask.new do |t|
  args = ARGV[1..-1]
  globs =
    if args.empty?
      ["test/**/*_test.rb"]
    else
      args.map { |x|
        if Dir.exist? x
          "#{x}/**/*_test.rb"
        elsif File.exist? x
          x
        end
      }.compact
    end

  t.libs << 'lib' << 'test'
  t.test_files = FileList[*globs]
  t.verbose = false
end
