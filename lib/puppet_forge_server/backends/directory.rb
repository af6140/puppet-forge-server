# -*- encoding: utf-8 -*-
#
# Copyright 2015 North Development AB
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'digest/md5'
require 'pathname'

module PuppetForgeServer::Backends
  class Directory
    include PuppetForgeServer::Utils::Archiver

    # Give highest priority to locally hosted modules
    @@PRIORITY = 0
    attr_reader :PRIORITY

    def initialize(url, readonly = false)
      @module_dir = url
      @log = PuppetForgeServer::Logger.get
      @readonly = readonly
    end

    def query_metadata(query, options = {})
      get_modules("*#{query}*.tar.gz", options)
    end

    def get_metadata(author, name, options = {})
      version = options[:version] ? options[:version] : '*'
      get_modules("#{author}-#{name}-#{version}.tar.gz", options)
    end

    def get_file_buffer(relative_path)
      path = Dir["#{@module_dir}/**/#{relative_path}"].first
      File.open(path, 'r') if path
    end

    def upload(file_data)
      return false if @readonly
      filename = File.join(@module_dir, file_data[:filename])
      return false if File.exist?(filename)
      File.open(filename, 'w') do |f|
        f.write(file_data[:tempfile].read)
      end
      true
    end

    private
    def read_metadata(archive_path)
      metadata_file = read_from_archive(archive_path, %r[^([^/]+/)?metadata\.json$])
      JSON.parse(metadata_file)
    rescue => error
      warn "Error reading from module archive #{archive_path}: #{error}"
      return nil
    end

    def normalize_metadata(metadata)
      metadata['name'] = metadata['name'].gsub('/', '-')
      metadata
    end

    def parse_dependencies(metadata)
      metadata.dependencies = metadata.dependencies.dup.map do |dependency|
        PuppetForgeServer::Models::Dependency.new({:name => dependency['name'], :version_requirement => dependency['version_requirement']})
      end.flatten
      metadata
    end

   def get_modules(file_name, options)
      options = ({:with_checksum => true}).merge(options)
      modules = []
      Dir["#{@module_dir}/**/#{file_name}"].each do |path|
        metadata_raw = read_metadata(path)
        if metadata_raw
          modules <<
            PuppetForgeServer::Models::Module.new({
            :metadata => parse_dependencies(PuppetForgeServer::Models::Metadata.new(normalize_metadata(metadata_raw))),
            :checksum => options[:with_checksum] == true ? Digest::MD5.file(path).hexdigest : nil,
            :path => "/#{File.basename(path)}",
            :private => ! @readonly
          })
        else
          @log.error "Failed reading metadata from #{path}"
        end
      end
      modules
    end
  end
end
