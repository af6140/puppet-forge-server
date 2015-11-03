# -*- encoding: utf-8 -*-
#
# Copyright 2014 North Development AB
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

require 'json'
require 'digest/md5'
require 'uri'

module PuppetForgeServer::Backends
  class ProxyPulp < PuppetForgeServer::Backends::Proxy

    # Priority should be lower than v3 API proxies as v3 requires less API calls
    @@PRIORITY = 14
    @@FILE_PATH = '/api/v1/files'
    attr_reader :PRIORITY

    def initialize(url, cache_dir, http_client = PuppetForgeServer::Http::HttpClient.new)
      super(url, cache_dir, http_client, @@FILE_PATH)
      get_forge_repo()
    end

    def get_metadata(author, name, options = {})
      options = ({:with_checksum => true}).merge(options)
      query ="#{author}/#{name}"
      begin
        query_modules=get_module_json(query)
        get_modules(query_modules).select { |e| e['full_name'].match("#{query}") }, options)
      rescue => e
        @log.debug("#{self.class.name} failed querying metadata for '#{query}' with options #{options}")
        @log.debug("Error: #{e}")
        return nil
      end
    end

    def query_metadata(query, options = {})
      options = ({:with_checksum => true}).merge(options)
      begin
        query_modules=get_module_json(query)
        get_modules(query_modules).select { |e| e['full_name'].match("*#{query}*") }, options)
      rescue => e
        @log.debug("#{self.class.name} failed querying metadata for '#{query}' with options #{options}")
        @log.debug("Error: #{e}")
        return nil
      end
    end

    private
    def read_metadata(element, release)
      element['project_page'] = element['project_url']
      element['name'] = element['full_name'] ? element['full_name'].gsub('/', '-') : element['name']
      element['description'] = element['desc']
      element['version'] = release['version'] ? release['version'] : element['version']
      element['dependencies'] = release['dependencies'] ? release['dependencies'] : []
      %w(project_url full_name releases tag_list desc).each { |key| element.delete(key) }
      element
    end

    def parse_dependencies(metadata)
      metadata.dependencies = metadata.dependencies.dup.map do |dependency|
        PuppetForgeServer::Models::Dependency.new({:name => dependency[0], :version_requirement => dependency.length > 1 ? dependency[1] : nil})
      end.flatten
      metadata
    end

    def get_modules(modules, options)
      modules.map do |element|
        version = options['version'] ? "&version=#{options['version']}" : ''
        JSON.parse(get("/api/v1/releases.json?module=#{element['author']}/#{element['name']}#{version}")).values.first.map do |release|
          tags = element['tag_list'] ? element['tag_list'] : nil
          raw_metadata = read_metadata(element, release)
          PuppetForgeServer::Models::Module.new({
            :metadata => parse_dependencies(PuppetForgeServer::Models::Metadata.new(raw_metadata)),
            :checksum => options[:with_checksum] ? Digest::MD5.hexdigest(File.read(get_file_buffer(release['file']))) : nil,
            :path => "#{release['file']}".gsub(/^#{@@FILE_PATH}/, ''),
            :tags => tags
          })
        end
      end
    end

    def get_forge_id()
      @forge_id = URI(@url).path.split('/').last
    end
    def get_forge_host()
      uri=URI.parse(@url)
      @forge_host="http:://#{uri.host}:#{uri.port}"
    end
    def get_forge_repo()
      get_forge_id()
      get_forge_host
      @forge_repo_dir="#{@forge_host}/pulp/puppet/#{forge_id}"
    end

    def get_module_json(query)
      json_uri="#{@forge_repo_dir}/module.json"
      json_filtered=JSON.parse(get(json_uri)).select { |element| element['name'].match("#{query}") }
    end
  end
end
