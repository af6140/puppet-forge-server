require 'rake'
require 'rake/clean'
require 'rubygems'
require 'rspec/core/rake_task'
require 'bundler/gem_tasks'


CLEAN.include("pkg/", "tmp/")
CLOBBER.include("Gemfile.lock")
$LOAD_PATH.unshift(File.expand_path('../lib', __FILE__))


RSpec::Core::RakeTask.new(:spec) do |t|
  t.rspec_opts = ['--color', '--format', 'documentation']
  #t.pattern = 'spec/**/**_spec.rb'
end



task :default => [:build]

